import SwiftUI

/// Outcome of loading a resource list: decoded rows, or a raw-text fallback
/// (so the app stays useful even when a wrangler version doesn't emit JSON).
enum LoadOutcome<Row> {
    case rows([Row])
    case raw(String)
    case failure(String)
}

/// Generic scrollable, card-based list screen backed by an async wrangler command.
/// Each card pushes a `destination` detail view within the screen's NavigationStack.
struct ResourceScreen<Row: Identifiable & Hashable, RowView: View, Destination: View>: View {
    let title: String
    let systemImage: String
    var itemNoun: String = "item"
    var accent: Color = Color(hex: 0xF6821F)
    var createKind: ResourceKind? = nil
    let load: () async -> LoadOutcome<Row>
    @ViewBuilder let rowContent: (Row) -> RowView
    @ViewBuilder let destination: (Row) -> Destination

    @State private var outcome: LoadOutcome<Row>?
    @State private var loading = false
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            content
                .background(.background)
                .navigationTitle(title)
                .navigationDestination(for: Row.self) { destination($0) }
                .toolbar {
                    if let createKind {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showCreate = true } label: { Label("New", systemImage: "plus") }
                                .help("Create \(title)")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await reload() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(loading)
                    }
                }
                .sheet(isPresented: $showCreate) {
                    if let createKind {
                        CreateResourceSheet(kind: createKind) { success in
                            showCreate = false
                            if success { Task { await reload() } }
                        }
                    }
                }
                .task { if outcome == nil { await reload() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch outcome {
        case .none:
            LoadingMatrix(caption: "LOADING \(title.uppercased())", tint: accent)
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

                ForEach(rows) { row in
                    NavigationLink(value: row) { rowContent(row) }
                        .buttonStyle(.plain)
                }
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
