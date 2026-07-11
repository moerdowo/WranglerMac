import SwiftUI

/// Outcome of loading a resource list: decoded rows, or a raw-text fallback
/// (so the app stays useful even when a wrangler version doesn't emit JSON).
enum LoadOutcome<Row> {
    case rows([Row])
    case raw(String)
    case failure(String)
}

/// Generic scrollable, card-based list screen backed by an async wrangler command.
struct ResourceScreen<Row: Identifiable, RowView: View>: View {
    let title: String
    let systemImage: String
    var itemNoun: String = "item"
    let load: () async -> LoadOutcome<Row>
    @ViewBuilder let rowContent: (Row) -> RowView

    @State private var outcome: LoadOutcome<Row>?
    @State private var loading = false

    var body: some View {
        Group {
            switch outcome {
            case .none:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .rows(let rows):
                if rows.isEmpty {
                    ContentUnavailableView("No \(title)", systemImage: systemImage,
                                           description: Text("Nothing here yet, or your account has none."))
                } else {
                    cardList(rows)
                }
            case .raw(let text):
                RawOutputView(text: text)
            case .failure(let msg):
                ContentUnavailableView {
                    Label("Couldn’t load \(title)", systemImage: "exclamationmark.triangle")
                } description: {
                    ScrollView { Text(msg).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                        .frame(maxHeight: 220)
                }
            }
        }
        .background(.background)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await reload() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .task { if outcome == nil { await reload() } }
    }

    private func cardList(_ rows: [Row]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.title3).bold()
                    Spacer()
                    Text("^[\(rows.count) \(itemNoun)](inflect: true)")
                        .font(.callout).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .padding(.bottom, 2)

                ForEach(rows) { rowContent($0) }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        outcome = await load()
    }
}

/// A polished, tappable-looking resource row: gradient icon tile, title,
/// monospaced identifier, optional trailing badge, and a copy-to-clipboard action.
struct ResourceCard: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var monospacedSubtitle: Bool = true
    var badge: String? = nil
    var copyValue: String? = nil

    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: icon).foregroundStyle(.white).font(.system(size: 17, weight: .medium)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold).lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(monospacedSubtitle ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled).lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.caption2).fontWeight(.medium)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }

            if let copyValue {
                Button {
                    copyToPasteboard(copyValue)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.separator, lineWidth: 1))
    }
}

struct RawOutputView: View {
    let text: String
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(text.isEmpty ? "(no output)" : text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
