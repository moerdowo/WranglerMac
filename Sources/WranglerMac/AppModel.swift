import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var binaryAvailable = false
    var version: String = "—"
    var whoamiOutput: String = ""
    var checkingEnvironment = true

    /// Whether the app-bundled Node + wrangler runtime is being used.
    var usingBundledRuntime = false
    /// Human-readable bundled runtime versions, e.g. "node v24.18.0 · wrangler 4.110.0".
    var bundledRuntimeInfo: String?

    /// Project directory used for `dev` / `deploy` / `tail` (they read wrangler.toml).
    var projectDir: String {
        didSet { UserDefaults.standard.set(projectDir, forKey: "projectDir") }
    }

    /// Custom wrangler path (absolute, or "npx").
    var wranglerPath: String {
        didSet { UserDefaults.standard.set(wranglerPath, forKey: "wranglerPath") }
    }

    /// The account ID used for Cloudflare API calls (Workers list). Defaults to
    /// the first account from whoami.
    var selectedAccountID: String? {
        didSet { UserDefaults.standard.set(selectedAccountID, forKey: "selectedAccountID") }
    }

    var accounts: [WhoAmIInfo.CFAccount] { WhoAmIInfo.parse(whoamiOutput).accounts }

    var activeAccountID: String? {
        selectedAccountID ?? accounts.first?.accountID
    }

    /// Return a non-expired OAuth token, refreshing via `wrangler whoami` if needed.
    func freshToken() async -> String? {
        if let info = CloudflareAPI.tokenInfo(), !info.expired { return info.token }
        _ = await exec(["whoami"]) // forces wrangler to refresh the access token
        return CloudflareAPI.tokenInfo()?.token
    }

    private(set) var console: [ConsoleEntry] = []

    init() {
        projectDir = UserDefaults.standard.string(forKey: "projectDir") ?? ""
        wranglerPath = UserDefaults.standard.string(forKey: "wranglerPath") ?? ""
        selectedAccountID = UserDefaults.standard.string(forKey: "selectedAccountID")
    }

    private func loadBundledRuntimeInfo() {
        let hasOverride = !wranglerPath.trimmingCharacters(in: .whitespaces).isEmpty
        usingBundledRuntime = !hasOverride && WranglerCLI.shared.bundledRuntime != nil
        guard let res = Bundle.main.resourceURL else { bundledRuntimeInfo = nil; return }
        let url = res.appendingPathComponent("Runtime/runtime.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            bundledRuntimeInfo = nil; return
        }
        if let node = obj["node"], let wr = obj["wrangler"] {
            bundledRuntimeInfo = "node \(node) · wrangler \(wr)"
        }
    }

    /// Run a wrangler command, record it in the console, and return the result
    /// (a synthetic failure result if the process couldn't be launched).
    @discardableResult
    func exec(_ args: [String], stdin: String? = nil) async -> CLIResult {
        do {
            let r = try await WranglerCLI.shared.run(args, cwd: projectDir.nilIfEmpty, stdin: stdin)
            record(r)
            return r
        } catch {
            let r = CLIResult(command: "wrangler " + args.joined(separator: " "),
                              exitCode: -1, stdout: "", stderr: error.localizedDescription)
            record(r)
            return r
        }
    }

    func record(_ r: CLIResult) {
        let out = r.stderr.isEmpty ? r.stdout : (r.stdout + (r.stdout.isEmpty ? "" : "\n") + r.stderr)
        console.insert(ConsoleEntry(command: r.command, output: out, ok: r.ok, date: Date()), at: 0)
        if console.count > 200 { console.removeLast(console.count - 200) }
    }

    func refreshEnvironment() async {
        checkingEnvironment = true
        defer { checkingEnvironment = false }
        loadBundledRuntimeInfo()
        binaryAvailable = await WranglerCLI.shared.isAvailable
        guard binaryAvailable else { version = "not found"; return }
        do {
            let r = try await WranglerCLI.shared.run(["--version"])
            record(r)
            version = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? r.stderr
        } catch {
            version = "unknown"
        }
        await refreshWhoami()
    }

    func refreshWhoami() async {
        guard binaryAvailable else { return }
        do {
            let r = try await WranglerCLI.shared.run(["whoami"])
            record(r)
            whoamiOutput = r.ok ? r.stdout : (r.stderr.nilIfEmpty ?? r.stdout)
        } catch {
            whoamiOutput = error.localizedDescription
        }
    }

    func login() async {
        guard binaryAvailable else { return }
        if let r = try? await WranglerCLI.shared.run(["login"]) { record(r) }
        await refreshWhoami()
    }

    func logout() async {
        guard binaryAvailable else { return }
        if let r = try? await WranglerCLI.shared.run(["logout"]) { record(r) }
        await refreshWhoami()
    }
}
