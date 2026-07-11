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

/// A stat-tile spec for a SubResourceSection: which keys to pull, label, icon.
struct StatSpec { let keys: [String]; let label: String; let icon: String }

/// A section that runs a read command and renders its output as clean key/value
/// cards (JSON or wrangler's "key: value" text), with optional stat tiles.
struct SubResourceSection<Actions: View>: View {
    @Environment(AppModel.self) private var model
    let title: String
    let systemImage: String
    let args: [String]
    var emptyText: String = "None configured."
    var tint: Color = Color(hex: 0xF6821F)
    var stats: [StatSpec] = []
    @ViewBuilder var actions: (@escaping () -> Void) -> Actions

    @State private var groups: [[(String, String)]] = []
    @State private var rawText = ""
    @State private var loading = true

    init(title: String, systemImage: String, args: [String], emptyText: String = "None configured.",
         tint: Color = Color(hex: 0xF6821F), stats: [StatSpec] = [],
         @ViewBuilder actions: @escaping (@escaping () -> Void) -> Actions = { _ in EmptyView() }) {
        self.title = title; self.systemImage = systemImage; self.args = args
        self.emptyText = emptyText; self.tint = tint; self.stats = stats; self.actions = actions
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
            } else if groups.isEmpty && rawText.isEmpty {
                Text(emptyText).font(.callout).foregroundStyle(.secondary)
            } else if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    if !stats.isEmpty, let first = groups.first { statRow(first) }
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                        if groups.count > 1 {
                            FieldRowsView(rows: g)
                                .padding(10)
                                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            FieldRowsView(rows: g)
                        }
                    }
                }
            } else {
                Text(rawText).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await run() }
    }

    @ViewBuilder private func statRow(_ rows: [(String, String)]) -> some View {
        let tiles = stats.compactMap { spec -> (String, String, String)? in
            guard let v = statValue(rows, spec.keys) else { return nil }
            return (formatValue(spec.keys.first ?? "", v), spec.label, spec.icon)
        }
        if !tiles.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                    StatTile(value: t.0, label: t.1, icon: t.2, tint: tint)
                }
            }
        }
    }

    private func reload() { Task { await run() } }

    private func run() async {
        loading = true; defer { loading = false }
        let r = await model.exec(args)
        let raw = r.ok ? r.stdout : (r.stderr.nilIfEmpty ?? r.stdout)
        let parsed = parseFieldGroups(raw)
        if parsed.isEmpty {
            let cleaned = stripBanner(stripANSI(raw))
            rawText = (cleaned == "[]" ? "" : cleaned)
            groups = []
        } else {
            groups = parsed
            rawText = ""
        }
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
