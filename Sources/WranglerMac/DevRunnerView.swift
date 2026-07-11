import SwiftUI
import AppKit

/// Tier 1.4 — a managed `wrangler dev` runner: start/stop the local server,
/// stream its output, and surface the ready URL.
struct DevRunnerView: View {
    @Environment(AppModel.self) private var model
    @State private var port = "8787"
    @State private var lines: [String] = []
    @State private var handle: StreamHandle?
    @State private var running = false
    @State private var readyURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            logBody
        }
        .navigationTitle("Dev Server")
        .onDisappear { stop() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(model.projectDir.isEmpty ? "No project selected" : model.projectDir)
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(model.projectDir.isEmpty ? .secondary : .primary)
                Button("Choose…") { chooseDir() }.controlSize(.small)
                Spacer()
            }
            HStack(spacing: 10) {
                Text("Port").foregroundStyle(.secondary)
                TextField("8787", text: $port).frame(width: 80).textFieldStyle(.roundedBorder).disabled(running)

                if running {
                    Button(role: .destructive) { stop() } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button { start() } label: { Label("Start dev", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.projectDir.isEmpty)
                }

                if let readyURL {
                    Button { NSWorkspace.shared.open(readyURL) } label: {
                        Label(readyURL.absoluteString, systemImage: "safari")
                    }
                    .controlSize(.small)
                }
                if running && readyURL == nil { ProgressView().controlSize(.small) }
                Spacer()
                Button { lines.removeAll() } label: { Image(systemName: "trash") }.disabled(lines.isEmpty)
            }
        }
        .padding(12)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).id(i)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) { if let last = lines.indices.last { proxy.scrollTo(last, anchor: .bottom) } }
            .overlay {
                if lines.isEmpty {
                    ContentUnavailableView("Dev server not running", systemImage: "play.rectangle",
                                           description: Text(model.projectDir.isEmpty
                                            ? "Choose a project folder containing a wrangler config, then Start."
                                            : "Press Start to run wrangler dev locally."))
                }
            }
        }
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.projectDir = url.path }
    }

    private func start() {
        lines = []; readyURL = nil
        var args = ["dev", "--ip", "127.0.0.1"]
        if !port.isEmpty { args += ["--port", port] }
        do {
            let h = try WranglerCLI.shared.streamSync(args, cwd: model.projectDir.nilIfEmpty,
                onLine: { line in
                    Task { @MainActor in
                        appendLine(line)
                    }
                },
                onEnd: { _ in Task { @MainActor in running = false; handle = nil; readyURL = nil } })
            handle = h; running = true
        } catch { appendLine("⚠️ \(error.localizedDescription)") }
    }

    @MainActor private func appendLine(_ line: String) {
        let clean = stripANSI(line)
        if !clean.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(clean) }
        if lines.count > 4000 { lines.removeFirst(lines.count - 4000) }
        // Detect "Ready on http://127.0.0.1:PORT"
        if readyURL == nil, let r = clean.range(of: "https?://[0-9A-Za-z.:]+", options: .regularExpression) {
            readyURL = URL(string: String(clean[r]))
        }
    }

    private func stop() { handle?.terminate(); handle = nil; running = false; readyURL = nil }
}
