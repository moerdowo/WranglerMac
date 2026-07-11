import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .account

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Account") {
                    row(.account)
                }
                Section("Resources") {
                    row(.workers); row(.pages); row(.kv); row(.d1); row(.r2); row(.queues)
                }
                Section("Tools") {
                    row(.dev); row(.config); row(.logs); row(.console); row(.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { statusBar }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ section: SidebarItem) -> some View {
        Label(section.rawValue, systemImage: section.symbol).tag(section)
    }

    @ViewBuilder private var detail: some View {
        if model.checkingEnvironment {
            LoadingMatrix(caption: "CHECKING WRANGLER")
        } else if !model.binaryAvailable {
            MissingBinaryView()
        } else {
            switch selection ?? .account {
            case .account: AccountView()
            case .workers: WorkersView()
            case .pages: PagesView()
            case .kv: KVView()
            case .d1: D1View()
            case .r2: R2View()
            case .queues: QueuesView()
            case .dev: DevRunnerView()
            case .config: ConfigEditorView()
            case .logs: TailView()
            case .console: ConsoleView()
            case .settings: SettingsView()
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.binaryAvailable ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(model.binaryAvailable ? "wrangler \(shortVersion)" : "wrangler not found")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var shortVersion: String {
        // wrangler --version prints e.g. "⛅️ wrangler 3.x.x"
        let digits = model.version.split(whereSeparator: { !$0.isNumber && $0 != "." })
        return digits.first.map(String.init) ?? model.version
    }
}

struct MissingBinaryView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ContentUnavailableView {
            Label("wrangler not found", systemImage: "bolt.trianglebadge.exclamationmark")
        } description: {
            Text("WranglerMac drives the local wrangler CLI. Install it globally with `npm i -g wrangler`, or point at an existing install (or `npx`) in Settings.")
        } actions: {
            Button("Open Settings") { }
                .disabled(true)
            Button("Re-check") { Task { await model.refreshEnvironment() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
