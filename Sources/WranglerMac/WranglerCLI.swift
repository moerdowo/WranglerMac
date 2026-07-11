import Foundation

/// Result of a completed (non-streaming) wrangler invocation.
struct CLIResult {
    let command: String
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { exitCode == 0 }
}

enum CLIError: LocalizedError {
    case binaryNotFound
    case failed(CLIResult)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "The `wrangler` executable could not be found. Set its path in Settings, or install it with `npm i -g wrangler`."
        case .failed(let r):
            let msg = r.stderr.isEmpty ? r.stdout : r.stderr
            return "`\(r.command)` exited with code \(r.exitCode).\n\(msg)"
        }
    }
}

/// Thin wrapper around the local `wrangler` binary. We shell out and (where
/// supported) decode `--json` output rather than reimplementing the Cloudflare
/// API, so we inherit wrangler's auth, config resolution, and forward-compat.
actor WranglerCLI {
    static let shared = WranglerCLI()

    /// User-overridable absolute path (or `npx`) persisted in UserDefaults.
    private nonisolated var overridePath: String? {
        UserDefaults.standard.string(forKey: "wranglerPath")?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    /// Location of the app-bundled Node + wrangler runtime, if present.
    nonisolated var bundledRuntime: (node: String, wranglerJS: String)? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let base = res.appendingPathComponent("Runtime")
        let node = base.appendingPathComponent("bin/node").path
        let js = base.appendingPathComponent("node_modules/wrangler/bin/wrangler.js").path
        guard FileManager.default.fileExists(atPath: node),
              FileManager.default.fileExists(atPath: js) else { return nil }
        return (node, js)
    }

    /// Resolve how to invoke wrangler. Returns (launchPath, leadingArgs).
    private nonisolated func resolveInvocation() -> (String, [String])? {
        // 1. Explicit override always wins (lets power users point at their own).
        if let p = overridePath {
            if p == "npx" { return npxInvocation() }
            if FileManager.default.isExecutableFile(atPath: p) { return (p, []) }
        }
        // 2. App-bundled runtime — the default, so everything works out of the box.
        if let rt = bundledRuntime {
            ensureExecutable(rt.node)
            return (rt.node, [rt.wranglerJS])
        }
        // 3. Common global install locations.
        let candidates = [
            "/opt/homebrew/bin/wrangler",
            "/usr/local/bin/wrangler",
            "\(NSHomeDirectory())/.npm-global/bin/wrangler",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return (c, [])
        }
        // 3. Ask a login shell (picks up nvm / fnm / volta PATHs).
        if let found = whichViaLoginShell(), FileManager.default.isExecutableFile(atPath: found) {
            return (found, [])
        }
        // 4. Fall back to npx if node is around.
        return npxInvocation()
    }

    /// Resolve the working directory for a command. Wrangler reads/writes
    /// `./.wrangler/cache`, so when there's no project directory we run inside a
    /// writable app-owned folder rather than the launch cwd (which is `/` when
    /// opened from Finder).
    private nonisolated func effectiveCWD(_ cwd: String?) -> String {
        if let cwd, !cwd.isEmpty { return cwd }
        let fm = FileManager.default
        let base = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("WranglerMac/work", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }

    /// Ensure a bundled binary carries the executable bit (defensive — the copy
    /// build phase normally preserves it).
    private nonisolated func ensureExecutable(_ path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path), !fm.isExecutableFile(atPath: path) else { return }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private nonisolated func npxInvocation() -> (String, [String])? {
        for npx in ["/opt/homebrew/bin/npx", "/usr/local/bin/npx"] {
            if FileManager.default.isExecutableFile(atPath: npx) { return (npx, ["--yes", "wrangler"]) }
        }
        if let npx = whichViaLoginShell(binary: "npx") { return (npx, ["--yes", "wrangler"]) }
        return nil
    }

    private nonisolated func whichViaLoginShell(binary: String = "wrangler") -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lic", "command -v \(binary)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let s = String(decoding: data, as: UTF8.self)
                .split(separator: "\n").last.map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return s?.nilIfEmpty
        } catch { return nil }
    }

    var isAvailable: Bool { resolveInvocation() != nil }

    /// Human-readable command string for the console/audit log.
    private func displayCommand(_ args: [String]) -> String {
        "wrangler " + args.joined(separator: " ")
    }

    /// Run wrangler to completion in an optional working directory. If `stdin`
    /// is provided it is written to the process's standard input (used by
    /// `secret put`, which reads the secret value from stdin).
    @discardableResult
    func run(_ args: [String], cwd: String? = nil, stdin: String? = nil) async throws -> CLIResult {
        guard let (launch, lead) = resolveInvocation() else { throw CLIError.binaryNotFound }
        let display = displayCommand(args)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = lead + args
        p.currentDirectoryURL = URL(fileURLWithPath: effectiveCWD(cwd))

        var env = ProcessInfo.processInfo.environment
        env["WRANGLER_SEND_METRICS"] = "false"
        env["NO_COLOR"] = "1"
        env["CI"] = "1" // suppress interactive prompts
        p.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        let inPipe = stdin != nil ? Pipe() : nil
        if let inPipe { p.standardInput = inPipe }

        return try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { proc in
                let o = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let e = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: CLIResult(command: display, exitCode: proc.terminationStatus, stdout: o, stderr: e))
            }
            do {
                try p.run()
                if let inPipe, let stdin {
                    inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                    try? inPipe.fileHandleForWriting.close()
                }
            } catch { cont.resume(throwing: error) }
        }
    }

    /// Run and decode JSON stdout into `T`. Tolerates a `wrangler`-style banner
    /// preceding the JSON by scanning for the first `[` or `{`.
    func runJSON<T: Decodable>(_ args: [String], as type: T.Type, cwd: String? = nil) async throws -> T {
        var a = args
        if !a.contains("--json") { a.append("--json") }
        let r = try await run(a, cwd: cwd)
        guard r.ok else { throw CLIError.failed(r) }
        let data = Self.extractJSON(from: r.stdout)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func extractJSON(from s: String) -> Data {
        guard let start = s.firstIndex(where: { $0 == "[" || $0 == "{" }) else {
            return Data(s.utf8)
        }
        return Data(s[start...].utf8)
    }

    /// Streaming invocation (e.g. `tail`, `dev`). Emits lines via `onLine`,
    /// returns a handle whose `terminate()` stops the process. Nonisolated so
    /// callers can start it synchronously from the UI.
    nonisolated func streamSync(_ args: [String], cwd: String? = nil,
                                onLine: @escaping @Sendable (String) -> Void,
                                onEnd: @escaping @Sendable (Int32) -> Void) throws -> StreamHandle {
        guard let (launch, lead) = resolveInvocation() else { throw CLIError.binaryNotFound }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = lead + args
        p.currentDirectoryURL = URL(fileURLWithPath: effectiveCWD(cwd))

        var env = ProcessInfo.processInfo.environment
        env["WRANGLER_SEND_METRICS"] = "false"
        env["NO_COLOR"] = "1"
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                onLine(String(line))
            }
        }
        p.terminationHandler = { proc in
            handle.readabilityHandler = nil
            onEnd(proc.terminationStatus)
        }
        try p.run()
        return StreamHandle(process: p)
    }
}

/// Handle to a running streaming process.
final class StreamHandle: @unchecked Sendable {
    private let process: Process
    init(process: Process) { self.process = process }
    var isRunning: Bool { process.isRunning }
    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
