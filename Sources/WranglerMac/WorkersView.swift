import SwiftUI

/// Parse an ISO8601 timestamp, tolerating 6-digit fractional seconds.
func parseISODate(_ s: String?) -> Date? {
    guard var str = s else { return nil }
    if let dot = str.firstIndex(of: "."), let z = str[dot...].firstIndex(of: "Z") {
        let frac = str[str.index(after: dot)..<z]
        if frac.count > 3 { str.replaceSubrange(str.index(after: dot)..<z, with: frac.prefix(3)) }
    }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: str) { return d }
    let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
    return g.date(from: str)
}

/// Friendly absolute date, e.g. "Jul 9, 2026 at 3:23 PM".
func isoPretty(_ s: String?) -> String? {
    guard let date = parseISODate(s) else { return s }
    let out = DateFormatter(); out.dateStyle = .medium; out.timeStyle = .short
    return out.string(from: date)
}

/// Relative time, e.g. "3 days ago".
func relativeTime(_ s: String?) -> String? {
    guard let date = parseISODate(s) else { return nil }
    let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: Date())
}

/// Short version id like "d18bdcf4".
func shortID(_ id: String) -> String { String(id.prefix(8)) }

struct WorkersView: View {
    @Environment(AppModel.self) private var model
    @State private var outcome: LoadOutcome<WorkerScript>?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            content
                .background(.background)
                .navigationTitle("Workers")
                .navigationDestination(for: WorkerScript.self) { WorkerDetailView(script: $0, account: model.activeAccountID ?? "") }
                .toolbar {
                    if model.accounts.count > 1 {
                        ToolbarItem(placement: .automatic) { accountPicker }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                            .disabled(loading)
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
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rows(let workers):
            if workers.isEmpty {
                ContentUnavailableView("No Workers", systemImage: "bolt.horizontal.circle",
                                       description: Text("This account has no deployed Workers, or you’re not signed in."))
            } else {
                list(workers)
            }
        case .raw:
            EmptyView()
        case .failure(let msg):
            ContentUnavailableView {
                Label("Couldn’t load Workers", systemImage: "exclamationmark.triangle")
            } description: {
                Text(msg).font(.callout)
            } actions: {
                Button("Retry") { Task { await reload() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    private func list(_ workers: [WorkerScript]) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Workers").font(.title3).bold()
                    Spacer()
                    Text("^[\(workers.count) worker](inflect: true)").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                ForEach(workers.sorted { ($0.modified_on ?? "") > ($1.modified_on ?? "") }) { w in
                    NavigationLink(value: w) {
                        ResourceCard(icon: "bolt.fill", tint: Color(hex: 0xF6821F),
                                     title: w.id,
                                     subtitle: isoPretty(w.modified_on).map { "updated \($0)" } ?? w.id,
                                     monospacedSubtitle: false,
                                     badge: w.usage_model)
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
        do {
            let workers = try await CloudflareAPI.listWorkers(account: account, token: token)
            outcome = .rows(workers)
        } catch {
            outcome = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Worker detail

struct WorkerDetailView: View {
    @Environment(AppModel.self) private var model
    let script: WorkerScript
    let account: String

    @State private var crons: [String] = []
    @State private var deployments: [WorkerDeployment] = []
    @State private var versions: [WorkerVersion] = []
    @State private var deploymentsError: String?
    @State private var versionsError: String?
    @State private var secrets: [WorkerSecret] = []
    @State private var busy = false
    @State private var status: String?
    @State private var confirmDelete = false
    @State private var confirmRollback = false
    @State private var confirmDeleteSecret: String?
    @State private var showAddSecret = false

    // Inline tail
    @State private var tailLines: [String] = []
    @State private var tailHandle: StreamHandle?
    @State private var tailing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                overviewCard
                secretsCard
                deploymentsCard
                versionsCard
                logsCard
                dangerZone
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle(script.id)
        .navigationSubtitle("Worker")
        .task { await loadAll() }
        .onDisappear { tailHandle?.terminate() }
        .sheet(isPresented: $showAddSecret) {
            AddSecretSheet { name, value in
                showAddSecret = false
                Task { await addSecret(name: name, value: value) }
            } cancel: { showAddSecret = false }
        }
        .confirmationDialog("Delete Worker “\(script.id)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Worker", role: .destructive) { Task { await deleteWorker() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the deployed Worker and all its routes.") }
        .confirmationDialog("Roll back “\(script.id)” to the previous deployment?", isPresented: $confirmRollback, titleVisibility: .visible) {
            Button("Roll back", role: .destructive) { Task { await rollback() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Production traffic will move to the previous deployment.") }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF6A94A), Color(hex: 0xF6821F)], startPoint: .top, endPoint: .bottom))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "bolt.fill").foregroundStyle(.white).font(.title2))
            VStack(alignment: .leading, spacing: 3) {
                Text(script.id).font(.title2).bold().textSelection(.enabled)
                if let m = isoPretty(script.modified_on) { Text("updated \(m)").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { Task { await loadAll() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.bordered)
        }
    }

    private var overviewCard: some View {
        SectionBox(title: "Overview", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Name", script.id)
                if let u = script.usage_model { infoRow("Usage model", u) }
                if let c = isoPretty(script.created_on) { infoRow("Created", c) }
                if let m = isoPretty(script.modified_on) { infoRow("Modified", m) }
                infoRow("Cron triggers", crons.isEmpty ? "none" : crons.joined(separator: ", "))
            }
        }
    }

    private var secretsCard: some View {
        SectionBox(title: "Secrets", systemImage: "key.fill", accessory: {
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
        SectionBox(title: "Deployments", systemImage: "shippingbox") {
            if let deploymentsError {
                Text(deploymentsError).font(.callout).foregroundStyle(.secondary)
            } else if deployments.isEmpty {
                Text("No deployment history.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(deployments.enumerated()), id: \.element.id) { idx, dep in
                        DeploymentRow(deployment: dep, isActive: idx == 0)
                        if dep.id != deployments.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var versionsCard: some View {
        SectionBox(title: "Versions", systemImage: "clock.arrow.circlepath", accessory: {
            Button("Roll back", role: .destructive) { confirmRollback = true }
                .buttonStyle(.borderless).controlSize(.small).disabled(busy)
        }) {
            if let versionsError {
                Text(versionsError).font(.callout).foregroundStyle(.secondary)
            } else if versions.isEmpty {
                Text("No version history.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(versions) { ver in
                        VersionRow(version: ver)
                        if ver.id != versions.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var logsCard: some View {
        SectionBox(title: "Live Logs", systemImage: "waveform", accessory: {
            if tailing {
                Button(role: .destructive) { stopTail() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.borderless).controlSize(.small)
            } else {
                Button { startTail() } label: { Label("Tail", systemImage: "play.fill") }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }) {
            if tailLines.isEmpty {
                Text(tailing ? "Waiting for requests…" : "Start a tail to stream this Worker’s production logs.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(tailLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 160)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var dangerZone: some View {
        SectionBox(title: "Danger Zone", systemImage: "exclamationmark.triangle", tint: .red) {
            HStack {
                Text("Permanently delete this Worker.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Worker", systemImage: "trash") }
                    .buttonStyle(.bordered).disabled(busy)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    // MARK: Loading

    private func loadAll() async {
        await loadSecrets()
        await loadDeployments()
        await loadVersions()
        await loadCrons()
    }

    private func nameArgs(_ base: [String]) -> [String] { base + ["--name", script.id] }

    private func loadSecrets() async {
        let r = await model.exec(nameArgs(["secret", "list"]))
        if r.ok, let decoded = try? JSONDecoder().decode([WorkerSecret].self, from: WranglerCLI.extractJSON(from: r.stdout)) {
            secrets = decoded
        } else { secrets = [] }
    }

    private func loadDeployments() async {
        deploymentsError = nil
        let r = await model.exec(nameArgs(["deployments", "list", "--json"]))
        guard r.ok else { deploymentsError = stripANSI(r.stderr.nilIfEmpty ?? r.stdout); return }
        do { deployments = try JSONDecoder().decode([WorkerDeployment].self, from: WranglerCLI.extractJSON(from: r.stdout)) }
        catch { deployments = []; deploymentsError = "Couldn’t read deployments." }
    }

    private func loadVersions() async {
        versionsError = nil
        let r = await model.exec(nameArgs(["versions", "list", "--json"]))
        guard r.ok else { versionsError = stripANSI(r.stderr.nilIfEmpty ?? r.stdout); return }
        do { versions = try JSONDecoder().decode([WorkerVersion].self, from: WranglerCLI.extractJSON(from: r.stdout)) }
        catch { versions = []; versionsError = "Couldn’t read versions." }
    }

    private func loadCrons() async {
        guard !account.isEmpty, let token = await model.freshToken() else { return }
        crons = (try? await CloudflareAPI.schedules(account: account, script: script.id, token: token)) ?? []
    }

    // MARK: Actions

    private func addSecret(name: String, value: String) async {
        busy = true; defer { busy = false }
        let r = await model.exec(nameArgs(["secret", "put", name]), stdin: value)
        status = r.ok ? "Secret “\(name)” saved." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
        await loadSecrets()
    }

    private func deleteSecret(_ name: String) async {
        confirmDeleteSecret = nil
        busy = true; defer { busy = false }
        let r = await model.exec(nameArgs(["secret", "delete", name]))
        status = r.ok ? "Secret “\(name)” deleted." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
        await loadSecrets()
    }

    private func rollback() async {
        busy = true; defer { busy = false }
        let r = await model.exec(nameArgs(["rollback", "--message", "Rolled back via WranglerMac"]))
        status = r.ok ? "Rolled back." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
        await loadDeployments()
    }

    private func deleteWorker() async {
        busy = true; defer { busy = false }
        let r = await model.exec(nameArgs(["delete"]))
        status = r.ok ? "Worker deleted. Return to the Workers list." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
    }

    private func startTail() {
        tailLines = []
        do {
            let h = try WranglerCLI.shared.streamSync(["tail", script.id, "--format", "pretty"],
                onLine: { line in
                    Task { @MainActor in
                        if !line.trimmingCharacters(in: .whitespaces).isEmpty { tailLines.append(line) }
                        if tailLines.count > 2000 { tailLines.removeFirst(tailLines.count - 2000) }
                    }
                },
                onEnd: { _ in Task { @MainActor in tailing = false; tailHandle = nil } })
            tailHandle = h; tailing = true
        } catch { status = error.localizedDescription }
    }

    private func stopTail() { tailHandle?.terminate(); tailHandle = nil; tailing = false }
}

// MARK: - Reusable section box

struct SectionBox<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(title: String, systemImage: String, tint: Color = .secondary,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.systemImage = systemImage; self.tint = tint
        self.accessory = accessory; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage).font(.headline).foregroundStyle(tint == .secondary ? .primary : tint)
                Spacer()
                accessory()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator))
    }
}

/// A small colored pill for a deployment/version source (wrangler, dashboard, …).
struct SourceBadge: View {
    let source: String?
    private var text: String { (source ?? "unknown").replacingOccurrences(of: "_", with: " ") }
    private var tint: Color {
        switch (source ?? "").lowercased() {
        case "wrangler", "upload": return Color(hex: 0xF6821F)
        case "dashboard": return Color(hex: 0x3A7BD5)
        case "api": return Color(hex: 0x7C5CFC)
        default: return .secondary
        }
    }
    var body: some View {
        Text(text)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

private struct DeploymentRow: View {
    let deployment: WorkerDeployment
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? .green : .secondary)
                .font(.system(size: 15))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(relativeTime(deployment.created_on) ?? "—").fontWeight(.semibold)
                    if isActive {
                        Text("ACTIVE").font(.caption2).fontWeight(.bold).foregroundStyle(.green)
                    }
                    SourceBadge(source: deployment.source)
                    Spacer()
                }
                if let email = deployment.author_email {
                    Label(email, systemImage: "person").font(.caption).foregroundStyle(.secondary)
                }
                if let versions = deployment.versions, !versions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(versions, id: \.version_id) { v in
                            Text("\(Int(v.percentage ?? 100))% \(shortID(v.version_id))")
                                .font(.system(.caption2, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                if let msg = deployment.message {
                    Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 10)
        .help(isoPretty(deployment.created_on) ?? "")
    }
}

private struct VersionRow: View {
    let version: WorkerVersion
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(version.number ?? 0)")
                .font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
                .frame(minWidth: 34)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(shortID(version.id)).font(.system(.callout, design: .monospaced)).fontWeight(.medium)
                HStack(spacing: 6) {
                    if let t = relativeTime(version.metadata?.created_on) {
                        Text(t).font(.caption).foregroundStyle(.secondary)
                    }
                    SourceBadge(source: version.metadata?.source)
                }
            }
            Spacer()
            if let email = version.metadata?.author_email {
                Text(email).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Button {
                copyToPasteboard(version.id)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain).help("Copy full version ID")
        }
        .padding(.vertical, 8)
        .help(isoPretty(version.metadata?.created_on) ?? "")
    }
}

struct AddSecretSheet: View {
    let add: (String, String) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @State private var value = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New secret").font(.headline)
            TextField("SECRET_NAME", text: $name).textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            SecureField("Value", text: $value).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Save") { add(name, value) }.buttonStyle(.borderedProminent).disabled(name.isEmpty || value.isEmpty)
            }
        }
        .padding(18).frame(width: 420)
    }
}
