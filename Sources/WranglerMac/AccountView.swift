import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.yellow)
                        .frame(width: 54, height: 54)
                        .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading) {
                        Text("Cloudflare Account").font(.title2).bold()
                        Text("wrangler \(model.version.trimmingCharacters(in: .whitespacesAndNewlines))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                GroupBox("whoami") {
                    if model.whoamiOutput.isEmpty {
                        Text("No session information yet.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal) {
                            Text(model.whoamiOutput)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HStack {
                    Button {
                        Task { busy = true; await model.login(); busy = false }
                    } label: { Label("Login", systemImage: "person.badge.key") }

                    Button {
                        Task { busy = true; await model.refreshWhoami(); busy = false }
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }

                    Button(role: .destructive) {
                        Task { busy = true; await model.logout(); busy = false }
                    } label: { Label("Logout", systemImage: "rectangle.portrait.and.arrow.right") }

                    if busy { ProgressView().controlSize(.small) }
                    Spacer()
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .navigationTitle("Account")
    }
}
