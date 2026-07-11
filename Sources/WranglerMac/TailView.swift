import SwiftUI

struct TailView: View {
    @Environment(AppModel.self) private var model
    @State private var workerName = ""
    @State private var lines: [LogLine] = []
    @State private var handle: StreamHandle?
    @State private var running = false
    @State private var autoscroll = true

    struct LogLine: Identifiable { let id = UUID(); let text: String }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            logBody
        }
        .navigationTitle("Live Logs")
        .onDisappear { stop() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField("Worker name (or leave blank to use project dir)", text: $workerName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)
                .disabled(running)

            if running {
                Button(role: .destructive) { stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { start() } label: { Label("Start tail", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
            }

            Toggle("Auto-scroll", isOn: $autoscroll).toggleStyle(.switch).controlSize(.small)
            Spacer()
            Button { lines.removeAll() } label: { Image(systemName: "trash") }
                .disabled(lines.isEmpty)
            if running { ProgressView().controlSize(.small) }
        }
        .padding(10)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) {
                if autoscroll, let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .overlay {
                if lines.isEmpty {
                    ContentUnavailableView("No log output yet",
                                           systemImage: "waveform",
                                           description: Text("Start a tail to stream production logs for a deployed Worker."))
                }
            }
        }
    }

    private func start() {
        var args = ["tail"]
        if !workerName.trimmingCharacters(in: .whitespaces).isEmpty { args.append(workerName) }
        args.append(contentsOf: ["--format", "pretty"])
        do {
            let h = try WranglerCLI.shared.streamSync(
                args, cwd: model.projectDir.nilIfEmpty,
                onLine: { line in
                    Task { @MainActor in
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { lines.append(LogLine(text: line)) }
                        if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
                    }
                },
                onEnd: { _ in
                    Task { @MainActor in running = false; handle = nil }
                })
            handle = h
            running = true
        } catch {
            lines.append(LogLine(text: "⚠️ \(error.localizedDescription)"))
        }
    }

    private func stop() {
        handle?.terminate()
        handle = nil
        running = false
    }
}
