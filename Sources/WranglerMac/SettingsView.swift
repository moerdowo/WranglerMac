import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("wrangler binary") {
                LabeledContent("Status") {
                    Label(model.binaryAvailable ? "Found" : "Not found",
                          systemImage: model.binaryAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(model.binaryAvailable ? .green : .orange)
                }
                LabeledContent("Version", value: model.version.trimmingCharacters(in: .whitespacesAndNewlines))

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
