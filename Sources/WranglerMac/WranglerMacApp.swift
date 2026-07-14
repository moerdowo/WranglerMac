import SwiftUI

@main
struct WranglerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
                .task { await model.refreshEnvironment() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdaterManager.shared.checkForUpdates() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterManager = UpdaterManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE so a broken pipe when writing to a wrangler subprocess's
        // stdin surfaces as an error rather than killing the app.
        signal(SIGPIPE, SIG_IGN)
        updaterManager.start()
    }
}
