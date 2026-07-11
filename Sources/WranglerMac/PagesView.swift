import SwiftUI
import AppKit

struct PagesView: View {
    @Environment(AppModel.self) private var model
    @State private var outcome: LoadOutcome<PagesProject>?
    @State private var loading = false
    @State private var showNew = false

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
                        Button { showNew = true } label: { Label("New project", systemImage: "plus") }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                    }
                }
                .sheet(isPresented: $showNew) {
                    PagesDeployView(existingProject: nil, initialBranch: "main") { success in
                        showNew = false
                        if success { Task { await reload() } }
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
    @State private var showDeploy = false

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
        .sheet(isPresented: $showDeploy) {
            PagesDeployView(existingProject: project.name,
                            initialBranch: project.production_branch ?? "main") { success in
                showDeploy = false
                if success { Task { await loadAll() } }
            }
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
            Button { showDeploy = true } label: { Label("Deploy", systemImage: "arrow.up.circle.fill") }
                .buttonStyle(.borderedProminent)
            if let url = project.liveURL {
                Button { NSWorkspace.shared.open(url) } label: { Label("Open site", systemImage: "safari") }
                    .buttonStyle(.bordered)
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

// MARK: - Deploy (drag & drop folder / files / zip)

struct PagesDeployView: View {
    @Environment(AppModel.self) private var model
    /// nil = create a new project; otherwise deploy to this existing project.
    let existingProject: String?
    var initialBranch: String = "main"
    var onFinished: (Bool) -> Void

    @State private var name = ""
    @State private var branch = ""
    @State private var sourceDir: URL?
    @State private var sourceLabel = ""
    @State private var targeted = false
    @State private var preparing = false
    @State private var deploying = false
    @State private var output: [String] = []
    @State private var resultURL: URL?
    @State private var error: String?
    @State private var handle: StreamHandle?

    private var isCreate: Bool { existingProject == nil }
    private var projectName: String { existingProject ?? name }
    private var canDeploy: Bool {
        sourceDir != nil && !deploying && (existingProject != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isCreate ? "New Pages project" : "Deploy to \(existingProject!)")
                .font(.title3).bold()

            if isCreate {
                TextField("project-name", text: $name)
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            HStack {
                Text("Branch").foregroundStyle(.secondary)
                TextField("production branch", text: $branch).textFieldStyle(.roundedBorder)
            }

            dropZone

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }

            if deploying || !output.isEmpty || resultURL != nil {
                outputArea
            }

            HStack {
                if let resultURL {
                    Button { NSWorkspace.shared.open(resultURL) } label: { Label("Open deployment", systemImage: "safari") }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button("Close") { handle?.terminate(); onFinished(resultURL != nil) }
                Button {
                    Task { await deploy() }
                } label: {
                    if deploying { Text("Deploying…") } else { Label("Deploy", systemImage: "arrow.up.circle.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canDeploy)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { if branch.isEmpty { branch = initialBranch } }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: sourceDir == nil ? "square.and.arrow.down.on.square" : "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(sourceDir == nil ? Color.secondary : Color.green)
            if preparing {
                Text("Preparing…").font(.callout).foregroundStyle(.secondary)
            } else if let _ = sourceDir {
                Text(sourceLabel).font(.callout).fontWeight(.medium).lineLimit(1)
                Text("Ready to deploy").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Drop a folder, files, or a .zip here").font(.callout)
                Text("or").font(.caption).foregroundStyle(.tertiary)
                Button("Choose…") { choose() }.controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(targeted ? Color(hex: 0xF6821F).opacity(0.12) : Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(targeted ? Color(hex: 0xF6821F) : Color.secondary.opacity(0.4))
        )
        .dropDestination(for: URL.self) { urls, _ in
            Task { await handleDrop(urls) }
            return true
        } isTargeted: { targeted = $0 }
    }

    private var outputArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(output.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).id(i)
                    }
                }.padding(6)
            }
            .frame(height: 140)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: output.count) { if let last = output.indices.last { proxy.scrollTo(last, anchor: .bottom) } }
        }
    }

    // MARK: Source selection

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { Task { await handleDrop(panel.urls) } }
    }

    private func handleDrop(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        preparing = true; error = nil
        defer { preparing = false }
        do {
            let dir = try prepareDeployDirectory(urls)
            sourceDir = dir
            sourceLabel = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
            if isCreate && name.isEmpty {
                name = sanitizeProjectName(urls[0].deletingPathExtension().lastPathComponent)
            }
        } catch {
            self.error = "Couldn’t read dropped items: \(error.localizedDescription)"
        }
    }

    // MARK: Deploy

    private func deploy() async {
        guard let dir = sourceDir else { return }
        deploying = true; output = []; resultURL = nil; error = nil
        let proj = projectName
        let br = branch.trimmingCharacters(in: .whitespaces)

        if isCreate {
            let r = await model.exec(["pages", "project", "create", proj,
                                      "--production-branch", br.isEmpty ? "main" : br])
            if !r.ok && !(r.stdout + r.stderr).lowercased().contains("already") {
                append("⚠️ create: " + stripANSI(r.stderr.nilIfEmpty ?? r.stdout))
            }
        }

        var args = ["pages", "deploy", dir.path, "--project-name", proj,
                    "--commit-dirty=true", "--commit-message", "Deployed via WranglerMac"]
        if !br.isEmpty { args += ["--branch", br] }

        do {
            handle = try WranglerCLI.shared.streamSync(args,
                onLine: { line in Task { @MainActor in append(line) } },
                onEnd: { code in Task { @MainActor in
                    deploying = false; handle = nil
                    if code != 0 && resultURL == nil { error = "Deploy exited with code \(code)." }
                    if code == 0 { onFinished(true) }
                } })
        } catch {
            deploying = false
            self.error = error.localizedDescription
        }
    }

    @MainActor private func append(_ line: String) {
        let c = stripANSI(line)
        if !c.trimmingCharacters(in: .whitespaces).isEmpty { output.append(c) }
        if output.count > 3000 { output.removeFirst(output.count - 3000) }
        // Last pages.dev URL in the stream is the deployment URL.
        if let r = c.range(of: #"https://[a-z0-9.-]+\.pages\.dev"#, options: .regularExpression) {
            resultURL = URL(string: String(c[r]))
        }
    }
}

private func sanitizeProjectName(_ raw: String) -> String {
    let lowered = raw.lowercased()
    let mapped = lowered.map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
    return String(mapped).replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

/// Resolve dropped URLs to a single directory to deploy: a folder is used as-is,
/// a .zip is extracted, and loose files are copied into a temp directory.
func prepareDeployDirectory(_ urls: [URL]) throws -> URL {
    let fm = FileManager.default
    if urls.count == 1 {
        let u = urls[0]
        var isDir: ObjCBool = false
        fm.fileExists(atPath: u.path, isDirectory: &isDir)
        if isDir.boolValue { return u }
        if u.pathExtension.lowercased() == "zip" { return try extractZip(u) }
    }
    let temp = makeTempDir()
    for u in urls {
        try fm.copyItem(at: u, to: temp.appendingPathComponent(u.lastPathComponent))
    }
    return temp
}

private func extractZip(_ zip: URL) throws -> URL {
    let dest = makeTempDir()
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-x", "-k", zip.path, dest.path]
    try p.run(); p.waitUntilExit()
    // If the archive contains a single top-level folder, deploy that folder.
    let items = (try? FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: [.isDirectoryKey]))?
        .filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" } ?? []
    if items.count == 1 {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: items[0].path, isDirectory: &isDir)
        if isDir.boolValue { return items[0] }
    }
    return dest
}

private func makeTempDir() -> URL {
    let t = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("WranglerMac-deploy-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
    return t
}
