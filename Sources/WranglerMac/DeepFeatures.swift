import SwiftUI
import AppKit

/// Pretty-print JSON, else strip wrangler's banner. Used for sub-resource output.
func prettyOutput(_ raw: String) -> String {
    let cleaned = stripANSI(raw)
    let data = WranglerCLI.extractJSON(from: cleaned)
    if let obj = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
       let s = String(data: pretty, encoding: .utf8), (obj is [Any] || obj is [String: Any]) {
        return s
    }
    return stripBanner(cleaned)
}

/// A collapsible section that runs a read command and shows its output, with a
/// refresh control and optional action buttons (which receive a reload hook).
struct SubResourceSection<Actions: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let systemImage: String
    let args: [String]
    var emptyText: String = "None configured."
    @ViewBuilder var actions: (@escaping () -> Void) -> Actions

    @State private var output = ""
    @State private var loading = true

    init(title: String, systemImage: String, args: [String], emptyText: String = "None configured.",
         @ViewBuilder actions: @escaping (@escaping () -> Void) -> Actions = { _ in EmptyView() }) {
        self.title = title; self.systemImage = systemImage; self.args = args
        self.emptyText = emptyText; self.actions = actions
    }

    var body: some View {
        SectionBox(title: title, systemImage: systemImage, accessory: {
            HStack(spacing: 8) {
                actions { reload() }
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }) {
            if loading {
                ProgressView().controlSize(.small)
            } else if output.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
            } else {
                Text(output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await run() }
    }

    private func reload() { Task { await run() } }

    private func run() async {
        loading = true; defer { loading = false }
        let r = await model.exec(args)
        let o = prettyOutput(r.ok ? r.stdout : (r.stderr.nilIfEmpty ?? r.stdout))
        // Treat "empty JSON list" and banner-only as empty.
        output = (o == "[]" || o.isEmpty) ? "" : o
    }
}

/// R2 public-access (r2.dev URL) control with enable/disable.
struct R2PublicAccessSection: View {
    @Environment(AppModel.self) private var model
    let bucket: String
    @State private var output = ""
    @State private var busy = false

    var body: some View {
        SectionBox(title: "Public access (r2.dev)", systemImage: "globe", accessory: {
            HStack(spacing: 8) {
                Button("Enable") { Task { await toggle(true) } }.controlSize(.small).disabled(busy)
                Button("Disable") { Task { await toggle(false) } }.controlSize(.small).disabled(busy)
            }
        }) {
            if output.isEmpty {
                Text("Loading…").font(.callout).foregroundStyle(.secondary)
            } else {
                Text(output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let r = await model.exec(["r2", "bucket", "dev-url", "get", bucket])
        output = prettyOutput(r.ok ? r.stdout : (r.stderr.nilIfEmpty ?? r.stdout))
    }
    private func toggle(_ on: Bool) async {
        busy = true; defer { busy = false }
        _ = await model.exec(["r2", "bucket", "dev-url", on ? "enable" : "disable", bucket])
        await load()
    }
}
