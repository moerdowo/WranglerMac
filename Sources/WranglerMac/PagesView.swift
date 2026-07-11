import SwiftUI
import AppKit

struct PagesView: View {
    @Environment(AppModel.self) private var model
    @State private var outcome: LoadOutcome<PagesProject>?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            content
                .background(.background)
                .navigationTitle("Pages")
                .navigationDestination(for: PagesProject.self) { PagesDetailView(project: $0, account: model.activeAccountID ?? "") }
                .toolbar {
                    if model.accounts.count > 1 {
                        ToolbarItem(placement: .automatic) { accountPicker }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                    }
                }
                .task { if outcome == nil { await reload() } }
        }
    }

    private var accountPicker: some View {
        Picker("Account", selection: Binding(
            get: { model.activeAccountID ?? "" },
            set: { model.selectedAccountID = $0; Task { await reload() } })) {
            ForEach(model.accounts) { acct in Text(acct.name).tag(acct.accountID) }
        }
        .pickerStyle(.menu).frame(maxWidth: 220)
    }

    @ViewBuilder private var content: some View {
        switch outcome {
        case .none:
            LoadingMatrix(caption: "LOADING PAGES", tint: Color(hex: 0xF6821F))
        case .rows(let projects):
            if projects.isEmpty {
                ContentUnavailableView("No Pages projects", systemImage: "doc.richtext",
                                       description: Text("This account has no Cloudflare Pages projects."))
            } else { list(projects) }
        case .raw:
            EmptyView()
        case .failure(let msg):
            ContentUnavailableView {
                Label("Couldn’t load Pages", systemImage: "exclamationmark.triangle")
            } description: { Text(msg).font(.callout) } actions: {
                Button("Retry") { Task { await reload() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func list(_ projects: [PagesProject]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pages").font(.title3).bold()
                    Spacer()
                    Text("^[\(projects.count) project](inflect: true)").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                ForEach(projects.sorted { ($0.latest_deployment?.created_on ?? "") > ($1.latest_deployment?.created_on ?? "") }) { p in
                    NavigationLink(value: p) {
                        ResourceCard(icon: "doc.richtext.fill", tint: Color(hex: 0xF6821F),
                                     title: p.name,
                                     subtitle: p.subdomain,
                                     monospacedSubtitle: false,
                                     badge: p.gitDescription != nil ? "git" : "direct")
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.vertical, 22)
        }
    }

    private func reload() async {
        loading = true; defer { loading = false }
        guard let account = model.activeAccountID, !account.isEmpty else {
            outcome = .failure("No Cloudflare account found. Sign in on the Account screen first."); return
        }
        guard let token = await model.freshToken() else {
            outcome = .failure("No Cloudflare session found. Sign in on the Account screen first."); return
        }
        do { outcome = .rows(try await CloudflareAPI.listPagesProjects(account: account, token: token)) }
        catch { outcome = .failure(error.localizedDescription) }
    }
}

// MARK: - Pages detail

struct PagesDetailView: View {
    @Environment(AppModel.self) private var model
    let project: PagesProject
    let account: String

    @State private var deployments: [PagesDeployment] = []
    @State private var secrets: [WorkerSecret] = []
    @State private var didLoad = false
    @State private var busy = false
    @State private var status: String?
    @State private var confirmDelete = false
    @State private var confirmDeleteSecret: String?
    @State private var showAddSecret = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !didLoad {
                    LoadingMatrix(caption: "LOADING PROJECT", tint: Color(hex: 0xF6821F))
                } else {
                    overviewCard
                    if let latest = project.latest_deployment { latestCard(latest) }
                    secretsCard
                    deploymentsCard
                    dangerZone
                }
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle(project.name)
        .navigationSubtitle("Pages project")
        .task { await loadAll() }
        .sheet(isPresented: $showAddSecret) {
            AddSecretSheet { name, value in showAddSecret = false; Task { await addSecret(name: name, value: value) } }
                cancel: { showAddSecret = false }
        }
        .confirmationDialog("Delete Pages project “\(project.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete project", role: .destructive) { Task { await deleteProject() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the project and all its deployments.") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF6A94A), Color(hex: 0xF6821F)], startPoint: .top, endPoint: .bottom))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "doc.richtext.fill").foregroundStyle(.white).font(.title2))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.title2).bold().textSelection(.enabled)
                if let s = project.subdomain { Text(s).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let url = project.liveURL {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open site", systemImage: "safari") }
                    .buttonStyle(.borderedProminent)
            }
            Button { Task { await loadAll() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
        }
    }

    private var overviewCard: some View {
        SectionBox(title: "Overview", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if let s = project.subdomain { linkRow("Subdomain", s, url: project.liveURL) }
                infoRow("Production branch", project.production_branch ?? "—")
                infoRow("Source", project.gitDescription ?? "Direct upload")
                if let f = project.framework, !f.isEmpty { infoRow("Framework", f) }
                infoRow("Functions", (project.uses_functions ?? false) ? "Yes" : "No")
                if let created = isoPretty(project.created_on) { infoRow("Created", created) }
                if let domains = project.domains, !domains.isEmpty {
                    infoRow("Custom domains", domains.joined(separator: ", "))
                }
            }
        }
    }

    private func latestCard(_ d: PagesDeployment) -> some View {
        SectionBox(title: "Latest deployment", systemImage: "shippingbox") {
            PagesDeploymentRow(deployment: d, highlight: true)
        }
    }

    private var secretsCard: some View {
        SectionBox(title: "Environment secrets", systemImage: "key.fill", accessory: {
            Button { showAddSecret = true } label: { Image(systemName: "plus") }.buttonStyle(.borderless)
        }) {
            if secrets.isEmpty {
                Text("No secrets.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(secrets) { s in
                        HStack {
                            Image(systemName: "key").foregroundStyle(.secondary)
                            Text(s.name).font(.system(.callout, design: .monospaced))
                            Spacer()
                            Button(role: .destructive) { confirmDeleteSecret = s.name } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).foregroundStyle(.red)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .confirmationDialog("Delete secret “\(confirmDeleteSecret ?? "")”?",
                            isPresented: Binding(get: { confirmDeleteSecret != nil }, set: { if !$0 { confirmDeleteSecret = nil } }),
                            titleVisibility: .visible) {
            Button("Delete secret", role: .destructive) { if let s = confirmDeleteSecret { Task { await deleteSecret(s) } } }
            Button("Cancel", role: .cancel) { confirmDeleteSecret = nil }
        }
    }

    private var deploymentsCard: some View {
        SectionBox(title: "Deployments", systemImage: "clock.arrow.circlepath") {
            if deployments.isEmpty {
                Text("No deployments.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(deployments.prefix(15))) { d in
                        PagesDeploymentRow(deployment: d, highlight: false)
                        if d.id != deployments.prefix(15).last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var dangerZone: some View {
        SectionBox(title: "Danger Zone", systemImage: "exclamationmark.triangle", tint: .red) {
            HStack {
                Text("Permanently delete this Pages project.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete project", systemImage: "trash") }
                    .buttonStyle(.bordered).disabled(busy)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout)
    }

    private func linkRow(_ label: String, _ value: String, url: URL?) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            if let url {
                Button { NSWorkspace.shared.open(url) } label: {
                    Text(value).foregroundStyle(Color(hex: 0x3A7BD5))
                }.buttonStyle(.plain)
            } else { Text(value) }
            Spacer()
        }.font(.callout)
    }

    // MARK: Data

    private func loadAll() async {
        await loadDeployments()
        await loadSecrets()
        didLoad = true
    }

    private func loadDeployments() async {
        guard !account.isEmpty, let token = await model.freshToken() else { return }
        deployments = (try? await CloudflareAPI.pagesDeployments(account: account, project: project.name, token: token)) ?? []
    }

    private func loadSecrets() async {
        let r = await model.exec(["pages", "secret", "list", "--project-name", project.name])
        if r.ok, let decoded = try? JSONDecoder().decode([WorkerSecret].self, from: WranglerCLI.extractJSON(from: r.stdout)) {
            secrets = decoded
        } else if r.ok {
            secrets = parseSecretNames(stripANSI(r.stdout))
        } else {
            secrets = []
        }
    }

    private func parseSecretNames(_ text: String) -> [WorkerSecret] {
        text.split(separator: "\n").compactMap { raw -> WorkerSecret? in
            var l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("-") { l = String(l.dropFirst()).trimmingCharacters(in: .whitespaces) }
            guard l.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { return nil }
            return WorkerSecret(name: l, type: "secret_text")
        }
    }

    private func addSecret(name: String, value: String) async {
        busy = true; defer { busy = false }
        let r = await model.exec(["pages", "secret", "put", name, "--project-name", project.name], stdin: value)
        status = r.ok ? "Secret “\(name)” saved." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
        await loadSecrets()
    }

    private func deleteSecret(_ name: String) async {
        confirmDeleteSecret = nil
        busy = true; defer { busy = false }
        let r = await model.exec(["pages", "secret", "delete", name, "--project-name", project.name])
        status = r.ok ? "Secret “\(name)” deleted." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
        await loadSecrets()
    }

    private func deleteProject() async {
        busy = true; defer { busy = false }
        let r = await model.exec(["pages", "project", "delete", project.name, "-y"])
        status = r.ok ? "Project deleted. Return to the Pages list." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
    }
}

struct PagesDeploymentRow: View {
    let deployment: PagesDeployment
    let highlight: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(statusColor).frame(width: 9, height: 9).padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(relativeTime(deployment.created_on) ?? "—").fontWeight(.semibold)
                    EnvBadge(env: deployment.environment)
                    if let s = deployment.status { StatusBadge(status: s) }
                    Spacer()
                }
                if let branch = deployment.branch {
                    Label(branch, systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary)
                }
                if let msg = deployment.commitMessage, !msg.isEmpty {
                    Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let urlStr = deployment.url, let url = URL(string: urlStr) {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Text(urlStr).font(.system(.caption, design: .monospaced)).foregroundStyle(Color(hex: 0x3A7BD5)).lineLimit(1)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, highlight ? 4 : 10)
        .help(isoPretty(deployment.created_on) ?? "")
    }

    private var statusColor: Color {
        switch (deployment.status ?? "").lowercased() {
        case "success", "active": return .green
        case "failure", "failed": return .red
        default: return .orange
        }
    }
}

struct EnvBadge: View {
    let env: String?
    var body: some View {
        let production = (env ?? "").lowercased() == "production"
        Text((env ?? "—").uppercased())
            .font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((production ? Color(hex: 0x7C5CFC) : Color(hex: 0x3A7BD5)).opacity(0.15), in: Capsule())
            .foregroundStyle(production ? Color(hex: 0x7C5CFC) : Color(hex: 0x3A7BD5))
    }
}

struct StatusBadge: View {
    let status: String
    private var tint: Color {
        switch status.lowercased() {
        case "success", "active": return .green
        case "failure", "failed": return .red
        default: return .orange
        }
    }
    var body: some View {
        Text(status)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
