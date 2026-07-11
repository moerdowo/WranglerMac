import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Runtime") {
                LabeledContent("Source") {
                    Label(model.usingBundledRuntime ? "Bundled (self-contained)" : "System / override",
                          systemImage: model.usingBundledRuntime ? "shippingbox.fill" : "externaldrive")
                        .foregroundStyle(model.usingBundledRuntime ? .green : .secondary)
                }
                if let info = model.bundledRuntimeInfo {
                    LabeledContent("Bundled", value: info)
                }
                Text("WranglerMac ships with its own Node.js and wrangler, so every feature works without installing anything. Set an override below to use your own wrangler instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("wrangler binary") {
                LabeledContent("Status") {
                    Label(model.binaryAvailable ? "Found" : "Not found",
                          systemImage: model.binaryAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(model.binaryAvailable ? .green : .orange)
                }
                LabeledContent("Active version", value: model.version.trimmingCharacters(in: .whitespacesAndNewlines))

                TextField("Path override", text: Binding(
                    get: { model.wranglerPath },
                    set: { model.wranglerPath = $0 }))
                    .textFieldStyle(.roundedBorder)
                Text("Absolute path to `wrangler`, or `npx` to run via npx. Leave blank to auto-detect.")
                    .font(.caption).foregroundStyle(.secondary)

                Button("Re-check environment") { Task { await model.refreshEnvironment() } }
            }

            Section("Project directory") {
                HStack {
                    TextField("wrangler.toml directory", text: Binding(
                        get: { model.projectDir },
                        set: { model.projectDir = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseProjectDir() }
                }
                Text("Used for commands that read your Worker config (dev, deploy, tail without a name).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private func chooseProjectDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.projectDir = url.path
        }
    }
}
