import SwiftUI
import AppKit

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false

    private var info: WhoAmIInfo { WhoAmIInfo.parse(model.whoamiOutput) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                if info.loggedIn {
                    accountsSection
                } else {
                    signedOutCard
                }
                runtimeFooter
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
        }
        .background(.background)
        .navigationTitle("Account")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(busy)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(spacing: 18) {
            Image("Logo")
                .resizable().interpolation(.high)
                .frame(width: 66, height: 66)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(info.loggedIn ? "Signed in" : "Not signed in")
                    .font(.caption).textCase(.uppercase).kerning(0.8)
                    .foregroundStyle(.white.opacity(0.7))
                Text(info.email ?? info.accounts.first?.name ?? "Cloudflare account")
                    .font(.title2).bold()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let auth = info.authType {
                    Label(auth, systemImage: "key.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer(minLength: 8)
            statusPill
        }
        .padding(22)
        .frame(height: 132)
        .frame(maxWidth: .infinity)
        .background {
            ZStack(alignment: .trailing) {
                LinearGradient(colors: [Color(hex: 0x2C6FBB), Color(hex: 0x14335E)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 160, weight: .bold))
                    .foregroundStyle(.white.opacity(0.07))
                    .rotationEffect(.degrees(8))
                    .offset(x: 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(info.loggedIn ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .shadow(color: (info.loggedIn ? Color.green : Color.orange).opacity(0.8), radius: 4)
            Text(info.loggedIn ? "Connected" : "Offline")
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(.white.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
    }

    // MARK: Signed-in content

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                if !info.accounts.isEmpty {
                    Text("^[\(info.accounts.count) account](inflect: true)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if info.accounts.isEmpty {
                InfoTile(icon: "person.crop.circle", tint: .blue,
                         title: info.email ?? "Signed in",
                         subtitle: "No accounts reported by wrangler.")
            } else {
                ForEach(info.accounts) { acct in
                    AccountCard(account: acct)
                }
            }

            actionRow
        }
    }

    private var signedOutCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            VStack(spacing: 5) {
                Text("Connect your Cloudflare account").font(.headline)
                Text("Sign in to manage Workers, KV, D1, R2, Queues and live logs. This opens Cloudflare in your browser to authorize wrangler.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { busy = true; await model.login(); busy = false }
            } label: {
                Label("Sign in with Cloudflare", systemImage: "bolt.fill")
                    .frame(maxWidth: 260)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(busy)
            if busy { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.separator, lineWidth: 1))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { busy = true; await refresh() }
            } label: { Label("Refresh", systemImage: "arrow.clockwise") }

            Button(role: .destructive) {
                Task { busy = true; await model.logout(); busy = false }
            } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }

            if busy { ProgressView().controlSize(.small) }
            Spacer()
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }

    private var runtimeFooter: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.binaryAvailable ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .shadow(color: (model.binaryAvailable ? Color.green : Color.orange).opacity(0.7), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.binaryAvailable ? "wrangler \(wranglerVersion)" : "wrangler not found")
                    .fontWeight(.medium)
                Text(model.bundledRuntimeInfo ?? (model.usingBundledRuntime ? "Bundled runtime" : "System runtime"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: model.usingBundledRuntime ? "shippingbox.fill" : "externaldrive")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private var wranglerVersion: String {
        let digits = model.version.split(whereSeparator: { !$0.isNumber && $0 != "." })
        return digits.first.map(String.init) ?? model.version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refresh() async {
        busy = true; defer { busy = false }
        await model.refreshWhoami()
    }
}

// MARK: - Components

private struct AccountCard: View {
    let account: WhoAmIInfo.CFAccount
    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x3B82C4), Color(hex: 0x255A97)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 42, height: 42)
                .overlay(Image(systemName: "building.2.fill").foregroundStyle(.white).font(.system(size: 17)))

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).fontWeight(.semibold).lineLimit(1)
                Text(account.accountID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(1)
            }
            Spacer()
            Button {
                copyToPasteboard(account.accountID)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy ID", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy account ID")
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.separator, lineWidth: 1))
    }
}

private struct InfoTile: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 20))
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.separator, lineWidth: 1))
    }
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
