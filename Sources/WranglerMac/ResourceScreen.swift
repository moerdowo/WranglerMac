import SwiftUI

/// Outcome of loading a resource list: decoded rows, or a raw-text fallback
/// (so the app stays useful even when a wrangler version doesn't emit JSON).
enum LoadOutcome<Row> {
    case rows([Row])
    case raw(String)
    case failure(String)
}

/// Generic scrollable list screen backed by an async wrangler command.
struct ResourceScreen<Row: Identifiable, RowView: View>: View {
    let title: String
    let systemImage: String
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
                    List(rows) { rowContent($0) }
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

    private func reload() async {
        loading = true
        defer { loading = false }
        outcome = await load()
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
