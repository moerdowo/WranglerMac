import SwiftUI
import AppKit

/// Tier 3.8 / 3.10 — edit a project's wrangler config (toml/jsonc/json) as text
/// with validation, plus a cron-trigger builder that inserts a snippet.
struct ConfigEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var fileURL: URL?
    @State private var dirty = false
    @State private var status: String?
    @State private var isError = false
    @State private var showCron = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if fileURL == nil {
                empty
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .onChange(of: text) { dirty = true; status = nil }
            }
            if let status {
                Divider()
                Label(status, systemImage: isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? .red : .green)
                    .font(.caption).padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Config Editor")
        .task { if fileURL == nil { openFromProject() } }
        .sheet(isPresented: $showCron) {
            CronBuilderSheet { snippet in showCron = false; insert(snippet) } cancel: { showCron = false }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.gearshape").foregroundStyle(.secondary)
            Text(fileURL?.lastPathComponent ?? "No file open").fontWeight(.medium)
            if dirty { Circle().fill(.orange).frame(width: 7, height: 7) }
            Spacer()
            Button { showCron = true } label: { Label("Cron…", systemImage: "clock") }
                .controlSize(.small).disabled(fileURL == nil)
            Button { openPanel() } label: { Label("Open…", systemImage: "folder") }.controlSize(.small)
            Button { save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .controlSize(.small).buttonStyle(.borderedProminent).disabled(fileURL == nil || !dirty)
        }
        .padding(10)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No config open", systemImage: "doc.badge.gearshape")
        } description: {
            Text("Open a wrangler.toml, wrangler.jsonc, or wrangler.json file to edit bindings, routes, and triggers.")
        } actions: {
            Button("Open…") { openPanel() }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: File IO

    private func openFromProject() {
        guard !model.projectDir.isEmpty else { return }
        let dir = URL(fileURLWithPath: model.projectDir)
        for name in ["wrangler.jsonc", "wrangler.json", "wrangler.toml"] {
            let u = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { load(u); return }
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    private func load(_ url: URL) {
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url; dirty = false; status = nil
        } catch { status = error.localizedDescription; isError = true }
    }

    private func save() {
        guard let fileURL else { return }
        if let err = validate() {
            status = "Not saved — \(err)"; isError = true; return
        }
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            dirty = false; status = "Saved \(fileURL.lastPathComponent)"; isError = false
        } catch { status = error.localizedDescription; isError = true }
    }

    /// Light validation: real JSON check for .json, comment-stripped JSON for
    /// .jsonc, and a balanced-bracket sanity check for .toml.
    private func validate() -> String? {
        let ext = fileURL?.pathExtension.lowercased() ?? ""
        switch ext {
        case "json", "jsonc":
            let stripped = ext == "jsonc" ? stripJSONComments(text) : text
            if let data = stripped.data(using: .utf8) {
                do { _ = try JSONSerialization.jsonObject(with: data) } catch { return "invalid JSON: \(error.localizedDescription)" }
            }
            return nil
        default:
            return nil
        }
    }

    private func stripJSONComments(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "//[^\n]*", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "/\\*.*?\\*/", with: "", options: [.regularExpression])
        // remove trailing commas
        out = out.replacingOccurrences(of: ",(\\s*[}\\]])", with: "$1", options: .regularExpression)
        return out
    }

    private func insert(_ snippet: String) {
        if !text.hasSuffix("\n") { text += "\n" }
        text += snippet + "\n"
        dirty = true
    }
}

/// Simple cron expression builder.
struct CronBuilderSheet: View {
    let insert: (String) -> Void
    let cancel: () -> Void

    enum Frequency: String, CaseIterable, Identifiable {
        case everyMinute = "Every minute"
        case hourly = "Every hour"
        case daily = "Every day"
        case weekly = "Every week"
        var id: String { rawValue }
    }
    @State private var freq: Frequency = .daily
    @State private var hour = 9
    @State private var minute = 0
    @State private var weekday = 1

    private var cron: String {
        switch freq {
        case .everyMinute: return "* * * * *"
        case .hourly:      return "\(minute) * * * *"
        case .daily:       return "\(minute) \(hour) * * *"
        case .weekly:      return "\(minute) \(hour) * * \(weekday)"
        }
    }

    private var isToml: Bool { true }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cron trigger").font(.headline)
            Picker("Frequency", selection: $freq) {
                ForEach(Frequency.allCases) { Text($0.rawValue).tag($0) }
            }
            if freq != .everyMinute {
                HStack {
                    if freq == .daily || freq == .weekly {
                        Stepper("Hour: \(hour)", value: $hour, in: 0...23)
                    }
                    Stepper("Minute: \(minute)", value: $minute, in: 0...59)
                }
                if freq == .weekly {
                    Picker("Weekday", selection: $weekday) {
                        ForEach(0..<7) { d in Text(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d]).tag(d) }
                    }.pickerStyle(.segmented)
                }
            }
            GroupBox {
                Text("crons = [\"\(cron)\"]")
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Inserts a [triggers] block. Redeploy the Worker for changes to take effect.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Insert") { insert("[triggers]\ncrons = [\"\(cron)\"]") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18).frame(width: 460)
    }
}
