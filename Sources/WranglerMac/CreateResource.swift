import SwiftUI

/// The kinds of resources that can be created from the app.
enum ResourceKind {
    case kv, d1, r2, queue, worker

    var title: String {
        switch self {
        case .kv: return "New KV Namespace"
        case .d1: return "New D1 Database"
        case .r2: return "New R2 Bucket"
        case .queue: return "New Queue"
        case .worker: return "New Worker"
        }
    }
    var icon: String {
        switch self {
        case .kv: return "tablecells"
        case .d1: return "cylinder.split.1x2"
        case .r2: return "externaldrive.fill"
        case .queue: return "tray.full.fill"
        case .worker: return "bolt.fill"
        }
    }
    var tint: Color {
        switch self {
        case .kv: return Color(hex: 0x2AA79B)
        case .d1: return Color(hex: 0x7C5CFC)
        case .r2: return Color(hex: 0xF6821F)
        case .queue: return Color(hex: 0x3A7BD5)
        case .worker: return Color(hex: 0xF6821F)
        }
    }
    var placeholder: String {
        switch self {
        case .kv: return "MY_NAMESPACE"
        case .d1: return "my-database"
        case .r2: return "my-bucket"
        case .queue: return "my-queue"
        case .worker: return "my-worker"
        }
    }
    var help: String {
        switch self {
        case .kv: return "A title for the namespace, e.g. SESSIONS."
        case .d1: return "Lowercase name with hyphens, e.g. app-db."
        case .r2: return "Lowercase, hyphens allowed. Must be globally unique in your account."
        case .queue: return "Lowercase name with hyphens."
        case .worker: return "Deploys a minimal starter Worker you can iterate on."
        }
    }
    var supportsLocation: Bool { self == .d1 || self == .r2 }

    func createArgs(name: String, location: String) -> [String] {
        switch self {
        case .kv:    return ["kv", "namespace", "create", name]
        case .d1:    return ["d1", "create", name] + (location.isEmpty ? [] : ["--location", location])
        case .r2:    return ["r2", "bucket", "create", name] + (location.isEmpty ? [] : ["--location", location])
        case .queue: return ["queues", "create", name]
        case .worker: return [] // handled via scaffold + deploy
        }
    }
}

/// Cloudflare location hints for D1/R2.
private let locations: [(value: String, label: String)] = [
    ("", "Automatic"),
    ("wnam", "Western North America"),
    ("enam", "Eastern North America"),
    ("weur", "Western Europe"),
    ("eeur", "Eastern Europe"),
    ("apac", "Asia-Pacific"),
    ("oc", "Oceania"),
]

enum WorkerTemplate: String, CaseIterable, Identifiable {
    case hello = "HTTP handler"
    case scheduled = "Scheduled"
    var id: String { rawValue }
    func code(name: String) -> String {
        switch self {
        case .hello:
            return """
            export default {
              async fetch(request, env, ctx) {
                return new Response("Hello from \(name)! 👋");
              },
            };
            """
        case .scheduled:
            return """
            export default {
              async scheduled(event, env, ctx) {
                console.log("\(name) cron ran at", new Date().toISOString());
              },
              async fetch(request) {
                return new Response("\(name) is running.");
              },
            };
            """
        }
    }
}

struct CreateResourceSheet: View {
    @Environment(AppModel.self) private var model
    let kind: ResourceKind
    var onDone: (Bool) -> Void

    @State private var name = ""
    @State private var location = ""
    @State private var template: WorkerTemplate = .hello
    @State private var busy = false
    @State private var done = false
    @State private var success = false
    @State private var output = ""
    @State private var error: String?
    @State private var handle: StreamHandle?

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if done {
                resultView
            } else {
                form
                if busy { deployLog }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            footer
        }
        .padding(20)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [kind.tint.opacity(0.95), kind.tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: kind.icon).foregroundStyle(.white).font(.title3))
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.title3).bold()
                Text(kind.help).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(kind.placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(busy)
                .onSubmit { if !trimmed.isEmpty { Task { await create() } } }

            if kind.supportsLocation {
                HStack {
                    Text("Location").foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    Picker("", selection: $location) {
                        ForEach(locations, id: \.value) { Text($0.label).tag($0.value) }
                    }.labelsHidden()
                }
            }
            if kind == .worker {
                HStack {
                    Text("Template").foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                    Picker("", selection: $template) {
                        ForEach(WorkerTemplate.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented)
                }
            }
        }
    }

    private var deployLog: some View {
        ScrollView {
            Text(output.isEmpty ? "Working…" : output)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 90)
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(success ? "Created \(trimmed)" : "Couldn’t create \(trimmed)",
                  systemImage: success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(success ? .green : .red)
            if !output.isEmpty {
                ScrollView {
                    Text(output).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            if done {
                Button("Done") { onDone(success) }.buttonStyle(.borderedProminent)
            } else {
                Button("Cancel") { handle?.terminate(); onDone(false) }
                Button {
                    Task { await create() }
                } label: {
                    if busy { Text("Creating…") } else { Label("Create", systemImage: "plus") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmed.isEmpty || busy)
            }
        }
    }

    // MARK: Create

    private func create() async {
        let n = trimmed
        guard !n.isEmpty else { return }
        busy = true; error = nil; output = ""

        if kind == .worker {
            do {
                let script = try scaffoldWorker(name: n, template: template)
                handle = try WranglerCLI.shared.streamSync(
                    ["deploy", script.path, "--name", n, "--compatibility-date", "2025-06-01"],
                    onLine: { line in Task { @MainActor in appendLog(line) } },
                    onEnd: { code in Task { @MainActor in
                        busy = false; handle = nil; done = true; success = (code == 0)
                        if code != 0 && error == nil { error = "Deploy exited with code \(code)." }
                    } })
            } catch {
                busy = false; self.error = error.localizedDescription
            }
            return
        }

        let args = kind.createArgs(name: n, location: location)
        let r = await model.exec(args)
        busy = false; done = true; success = r.ok
        output = stripANSI(r.ok ? r.stdout : (r.stderr.nilIfEmpty ?? r.stdout))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !r.ok { error = "wrangler reported an error." }
    }

    @MainActor private func appendLog(_ line: String) {
        let c = stripANSI(line)
        if !c.trimmingCharacters(in: .whitespaces).isEmpty {
            output += (output.isEmpty ? "" : "\n") + c
        }
    }

    private func scaffoldWorker(name: String, template: WorkerTemplate) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WranglerMac-worker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("worker.js")
        try template.code(name: name).write(to: script, atomically: true, encoding: .utf8)
        return script
    }
}
