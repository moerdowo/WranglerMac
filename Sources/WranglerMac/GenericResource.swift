import SwiftUI

/// A generic Cloudflare resource type that can be listed, inspected, created,
/// and deleted through wrangler — used to add many resources with little code.
struct CFResourceType: Hashable {
    let key: String
    let name: String            // sidebar / title
    let icon: String
    let tintHex: UInt32
    let noun: String
    let listArgs: [String]
    let listJSON: Bool
    let idKeys: [String]        // JSON/table keys that identify the item for commands
    let nameKeys: [String]      // keys used for the display title
    let subtitleKeys: [String]
    let badgeKey: String?
    let getArgs: [String]?      // detail command prefix; +[id]
    let createArgs: [String]?   // simple `create <name>` prefix; +[name]. nil = not creatable here
    let deleteArgs: [String]?   // delete prefix; +[id]. nil = not deletable
    var tint: Color { Color(hex: tintHex) }

    static func == (a: CFResourceType, b: CFResourceType) -> Bool { a.key == b.key }
    func hash(into h: inout Hasher) { h.combine(key) }
}

enum CFResources {
    static let vectorize = CFResourceType(
        key: "vectorize", name: "Vectorize", icon: "cube.transparent", tintHex: 0x00B3A4, noun: "index",
        listArgs: ["vectorize", "list"], listJSON: true,
        idKeys: ["name"], nameKeys: ["name"], subtitleKeys: ["description", "created_on"], badgeKey: "metric",
        getArgs: ["vectorize", "get"], createArgs: nil, deleteArgs: ["vectorize", "delete"])

    static let hyperdrive = CFResourceType(
        key: "hyperdrive", name: "Hyperdrive", icon: "bolt.horizontal.fill", tintHex: 0xF6821F, noun: "config",
        listArgs: ["hyperdrive", "list"], listJSON: false,
        idKeys: ["id", "Id", "ID"], nameKeys: ["name", "Name"], subtitleKeys: ["id", "Id"], badgeKey: nil,
        getArgs: ["hyperdrive", "get"], createArgs: nil, deleteArgs: ["hyperdrive", "delete"])

    static let workflows = CFResourceType(
        key: "workflows", name: "Workflows", icon: "arrow.triangle.2.circlepath", tintHex: 0x7C5CFC, noun: "workflow",
        listArgs: ["workflows", "list"], listJSON: false,
        idKeys: ["name", "Name"], nameKeys: ["name", "Name"], subtitleKeys: ["script_name", "Script", "class_name"], badgeKey: nil,
        getArgs: ["workflows", "describe"], createArgs: nil, deleteArgs: ["workflows", "delete"])

    static let pipelines = CFResourceType(
        key: "pipelines", name: "Pipelines", icon: "drop.fill", tintHex: 0x3A7BD5, noun: "pipeline",
        listArgs: ["pipelines", "list"], listJSON: true,
        idKeys: ["id", "name"], nameKeys: ["name"], subtitleKeys: ["id", "endpoint"], badgeKey: nil,
        getArgs: ["pipelines", "get"], createArgs: nil, deleteArgs: ["pipelines", "delete"])

    static let containers = CFResourceType(
        key: "containers", name: "Containers", icon: "shippingbox.fill", tintHex: 0x2AA79B, noun: "container",
        listArgs: ["containers", "list"], listJSON: true,
        idKeys: ["id", "ID"], nameKeys: ["name", "Name"], subtitleKeys: ["id", "ID", "image"], badgeKey: "status",
        getArgs: ["containers", "info"], createArgs: nil, deleteArgs: ["containers", "delete"])

    static let dispatch = CFResourceType(
        key: "dispatch", name: "Dispatch Namespaces", icon: "square.stack.3d.up.fill", tintHex: 0x9B59B6, noun: "namespace",
        listArgs: ["dispatch-namespace", "list"], listJSON: false,
        idKeys: ["namespace_name", "name", "Name"], nameKeys: ["namespace_name", "name", "Name"], subtitleKeys: ["namespace_id", "id"], badgeKey: nil,
        getArgs: ["dispatch-namespace", "get"], createArgs: ["dispatch-namespace", "create"], deleteArgs: ["dispatch-namespace", "delete"])

    static let secretsStore = CFResourceType(
        key: "secrets-store", name: "Secrets Store", icon: "lock.shield.fill", tintHex: 0xE74C3C, noun: "store",
        listArgs: ["secrets-store", "store", "list"], listJSON: false,
        idKeys: ["id", "Id"], nameKeys: ["name", "Name"], subtitleKeys: ["id", "Id"], badgeKey: nil,
        getArgs: nil, createArgs: ["secrets-store", "store", "create"], deleteArgs: nil)

    static let aiModels = CFResourceType(
        key: "ai-models", name: "AI Models", icon: "sparkles", tintHex: 0xF39C12, noun: "model",
        listArgs: ["ai", "models", "list"], listJSON: false,
        idKeys: ["name", "Name"], nameKeys: ["name", "Name"], subtitleKeys: ["task", "Task", "description"], badgeKey: nil,
        getArgs: nil, createArgs: nil, deleteArgs: nil)

    static let aiSearch = CFResourceType(
        key: "ai-search", name: "AI Search", icon: "magnifyingglass.circle.fill", tintHex: 0xF39C12, noun: "instance",
        listArgs: ["ai-search", "list"], listJSON: false,
        idKeys: ["name", "id"], nameKeys: ["name"], subtitleKeys: ["id", "source", "description"], badgeKey: nil,
        getArgs: ["ai-search", "get"], createArgs: nil, deleteArgs: ["ai-search", "delete"])

    static let browser = CFResourceType(
        key: "browser", name: "Browser Sessions", icon: "globe", tintHex: 0x3A7BD5, noun: "session",
        listArgs: ["browser", "list"], listJSON: false,
        idKeys: ["sessionId", "id", "ID"], nameKeys: ["sessionId", "id"], subtitleKeys: ["startTime", "status"], badgeKey: "status",
        getArgs: nil, createArgs: nil, deleteArgs: ["browser", "close"])

    static let tunnels = CFResourceType(
        key: "tunnels", name: "Tunnels", icon: "point.3.filled.connected.trianglepath.dotted", tintHex: 0xF6821F, noun: "tunnel",
        listArgs: ["tunnel", "list"], listJSON: false,
        idKeys: ["id", "ID"], nameKeys: ["name", "NAME", "Name"], subtitleKeys: ["id", "ID"], badgeKey: nil,
        getArgs: ["tunnel", "info"], createArgs: ["tunnel", "create"], deleteArgs: ["tunnel", "delete"])

    static let vpc = CFResourceType(
        key: "vpc", name: "VPC Services", icon: "network", tintHex: 0x9B59B6, noun: "service",
        listArgs: ["vpc", "service", "list"], listJSON: false,
        idKeys: ["id", "ID"], nameKeys: ["name", "Name"], subtitleKeys: ["id", "type"], badgeKey: nil,
        getArgs: ["vpc", "service", "get"], createArgs: nil, deleteArgs: nil)

    static let mtls = CFResourceType(
        key: "mtls", name: "mTLS Certificates", icon: "lock.badge.clock", tintHex: 0xE74C3C, noun: "certificate",
        listArgs: ["mtls-certificate", "list"], listJSON: false,
        idKeys: ["id", "ID"], nameKeys: ["name", "Name", "id"], subtitleKeys: ["id", "issuer", "expires_on"], badgeKey: nil,
        getArgs: nil, createArgs: nil, deleteArgs: ["mtls-certificate", "delete"])

    static let turnstile = CFResourceType(
        key: "turnstile", name: "Turnstile", icon: "checkmark.shield.fill", tintHex: 0x2AA79B, noun: "widget",
        listArgs: ["turnstile", "widget", "list"], listJSON: false,
        idKeys: ["sitekey", "id"], nameKeys: ["name"], subtitleKeys: ["sitekey", "domains"], badgeKey: nil,
        getArgs: ["turnstile", "widget", "get"], createArgs: nil, deleteArgs: ["turnstile", "widget", "delete"])

    static let all = [vectorize, hyperdrive, workflows, pipelines, containers, dispatch, secretsStore, aiModels,
                      aiSearch, browser, tunnels, vpc, mtls, turnstile]
    static func byKey(_ k: String) -> CFResourceType? { all.first { $0.key == k } }
}

struct GenericItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let badge: String?
    /// Full record for the detail view when the list already carries everything.
    let raw: [String: String]
    func hash(into h: inout Hasher) { h.combine(id); h.combine(title) }
    static func == (a: GenericItem, b: GenericItem) -> Bool { a.id == b.id && a.title == b.title }
}

/// Parse a wrangler list output (JSON array, `{result:[...]}`, or a box-drawing
/// table) into generic items.
func parseGenericItems(_ output: String, type: CFResourceType) -> [GenericItem] {
    let dicts = parseRecords(output)
    return dicts.compactMap { d -> GenericItem? in
        let id = firstValue(d, type.idKeys) ?? firstValue(d, type.nameKeys)
        let title = firstValue(d, type.nameKeys) ?? id
        guard let title, !title.isEmpty else { return nil }
        let subtitle = type.subtitleKeys.compactMap { d[$0] }.first { !$0.isEmpty }
        let badge = type.badgeKey.flatMap { d[$0] }?.nilIfEmpty
        return GenericItem(id: (id ?? title), title: title, subtitle: subtitle, badge: badge, raw: d)
    }
}

private func firstValue(_ d: [String: String], _ keys: [String]) -> String? {
    for k in keys { if let v = d[k], !v.isEmpty { return v } }
    return nil
}

/// Turn list output into `[[key:value]]` records — JSON or table.
private func parseRecords(_ output: String) -> [[String: String]] {
    let data = WranglerCLI.extractJSON(from: output)
    if let obj = try? JSONSerialization.jsonObject(with: data) {
        var arr: [Any]?
        if let a = obj as? [Any] { arr = a }
        else if let dict = obj as? [String: Any] {
            arr = (dict["result"] as? [Any]) ?? (dict["results"] as? [Any]) ?? [dict]
        }
        if let arr {
            return arr.compactMap { $0 as? [String: Any] }.map { flatten($0) }
        }
    }
    return parseTable(output)
}

private func flatten(_ d: [String: Any], prefix: String = "") -> [String: String] {
    var out: [String: String] = [:]
    for (k, v) in d {
        let key = prefix.isEmpty ? k : "\(prefix).\(k)"
        switch v {
        case is NSNull: out[key] = ""
        case let s as String: out[key] = s
        case let n as NSNumber: out[key] = n.stringValue
        case let sub as [String: Any]: out.merge(flatten(sub, prefix: key)) { a, _ in a }
        case let arr as [Any]: out[key] = arr.map { "\($0)" }.joined(separator: ", ")
        default: out[key] = "\(v)"
        }
    }
    return out
}

private func parseTable(_ output: String) -> [[String: String]] {
    let lines = stripANSI(output).split(separator: "\n").map(String.init)
    let rows = lines.filter { $0.contains("│") }
    guard rows.count >= 1 else { return [] }
    func cells(_ line: String) -> [String] {
        line.split(separator: "│").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    // First │-row is the header.
    let header = cells(rows[0]).filter { !$0.isEmpty }
    guard !header.isEmpty else { return [] }
    var records: [[String: String]] = []
    for row in rows.dropFirst() {
        let c = cells(row)
        let vals = c.filter { !$0.isEmpty || true } // keep alignment
        // Rebuild trimmed non-edge cells:
        let trimmed = c.enumerated().filter { $0.offset > 0 && $0.offset <= header.count }.map { $0.element }
        let use = trimmed.count == header.count ? trimmed : Array(vals.prefix(header.count))
        guard use.count == header.count else { continue }
        if use[0].lowercased() == header[0].lowercased() { continue }
        var rec: [String: String] = [:]
        for (i, h) in header.enumerated() where i < use.count { rec[h] = use[i] }
        records.append(rec)
    }
    return records
}

// MARK: - Generic list view

struct GenericResourceView: View {
    @Environment(AppModel.self) private var model
    let type: CFResourceType

    @State private var items: [GenericItem] = []
    @State private var phase: Phase = .loading
    @State private var showCreate = false
    enum Phase: Equatable { case loading, ok, failed(String) }

    var body: some View {
        NavigationStack {
            content
                .background(.background)
                .navigationTitle(type.name)
                .navigationDestination(for: GenericItem.self) { GenericResourceDetail(type: type, item: $0) }
                .toolbar {
                    if type.createArgs != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showCreate = true } label: { Label("New", systemImage: "plus") }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
                .sheet(isPresented: $showCreate) {
                    GenericCreateSheet(type: type) { ok in showCreate = false; if ok { Task { await load() } } }
                }
                .task { if phase == .loading { await load() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            LoadingMatrix(caption: "LOADING \(type.name.uppercased())", tint: type.tint)
        case .failed(let m):
            ContentUnavailableView {
                Label("Couldn’t load \(type.name)", systemImage: "exclamationmark.triangle")
            } description: { Text(m).font(.callout) } actions: {
                Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
            }
        case .ok:
            if items.isEmpty {
                ContentUnavailableView("No \(type.name)", systemImage: type.icon,
                                       description: Text("This account has no \(type.noun)s, or they aren’t available here."))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(type.name).font(.title3).bold()
                            Spacer()
                            Text("^[\(items.count) \(type.noun)](inflect: true)").font(.callout).foregroundStyle(.secondary)
                        }.padding(.bottom, 2)
                        ForEach(items) { item in
                            if type.getArgs != nil {
                                NavigationLink(value: item) { card(item) }.buttonStyle(.plain)
                            } else {
                                card(item)
                            }
                        }
                    }
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                    .padding(.horizontal, 28).padding(.vertical, 22)
                }
            }
        }
    }

    private func card(_ item: GenericItem) -> some View {
        ResourceCard(icon: type.icon, tint: type.tint, title: item.title,
                     subtitle: item.subtitle, monospacedSubtitle: false,
                     badge: item.badge, copyValue: item.id)
    }

    private func load() async {
        phase = .loading
        var args = type.listArgs
        if type.listJSON && !args.contains("--json") { args.append("--json") }
        let r = await model.exec(args)
        guard r.ok else { phase = .failed(stripANSI(r.stderr.nilIfEmpty ?? r.stdout)); return }
        items = parseGenericItems(r.stdout, type: type)
        phase = .ok
    }
}

// MARK: - Generic detail view

struct GenericResourceDetail: View {
    @Environment(AppModel.self) private var model
    let type: CFResourceType
    let item: GenericItem

    @State private var fields: [(String, String)] = []
    @State private var raw = ""
    @State private var loading = true
    @State private var busy = false
    @State private var status: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if loading {
                    LoadingMatrix(caption: "LOADING", tint: type.tint)
                } else {
                    if !fields.isEmpty {
                        SectionBox(title: "Details", systemImage: "info.circle") {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(fields, id: \.0) { k, v in
                                    HStack(alignment: .top) {
                                        Text(k).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
                                        Text(v).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    }.font(.callout)
                                }
                            }
                        }
                    } else if !raw.isEmpty {
                        SectionBox(title: "Details", systemImage: "info.circle") {
                            Text(raw).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if type.deleteArgs != nil {
                        SectionBox(title: "Danger Zone", systemImage: "exclamationmark.triangle", tint: .red) {
                            HStack {
                                Text("Permanently delete this \(type.noun).").font(.callout).foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                                    .buttonStyle(.bordered).disabled(busy)
                            }
                        }
                    }
                    if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
                }
            }
            .frame(maxWidth: 680).frame(maxWidth: .infinity).padding(24)
        }
        .navigationTitle(item.title)
        .navigationSubtitle(type.name)
        .task { await load() }
        .confirmationDialog("Delete “\(item.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await deleteItem() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently removes the \(type.noun).") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [type.tint.opacity(0.95), type.tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: type.icon).foregroundStyle(.white).font(.title2))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.title2).bold().textSelection(.enabled)
                Text(item.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        // Seed from the row we already have.
        var record = item.raw
        if let getArgs = type.getArgs {
            let r = await model.exec(getArgs + [item.id])
            if r.ok {
                if let obj = try? JSONSerialization.jsonObject(with: WranglerCLI.extractJSON(from: r.stdout)) as? [String: Any] {
                    record = flattenPublic(obj)
                } else {
                    raw = stripBanner(stripANSI(r.stdout))
                }
            }
        }
        fields = record.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }.filter { !$0.1.isEmpty }
    }

    private func deleteItem() async {
        busy = true; defer { busy = false }
        let r = await model.exec((type.deleteArgs ?? []) + [item.id])
        status = r.ok ? "Deleted. Go back to the list." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
    }
}

/// Public flatten wrapper for the detail view.
func flattenPublic(_ d: [String: Any]) -> [String: String] {
    var out: [String: String] = [:]
    for (k, v) in d {
        switch v {
        case is NSNull: continue
        case let s as String: out[k] = s
        case let n as NSNumber: out[k] = n.stringValue
        case let sub as [String: Any]:
            for (sk, sv) in flattenPublic(sub) { out["\(k).\(sk)"] = sv }
        case let arr as [Any]: out[k] = arr.map { "\($0)" }.joined(separator: ", ")
        default: out[k] = "\(v)"
        }
    }
    return out
}

struct GenericCreateSheet: View {
    @Environment(AppModel.self) private var model
    let type: CFResourceType
    var onDone: (Bool) -> Void
    @State private var name = ""
    @State private var busy = false
    @State private var done = false
    @State private var success = false
    @State private var output = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [type.tint.opacity(0.95), type.tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: type.icon).foregroundStyle(.white).font(.title3))
                Text("New \(type.noun.capitalized)").font(.title3).bold()
                Spacer()
            }
            if done {
                Label(success ? "Created \(name)" : "Couldn’t create",
                      systemImage: success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(success ? .green : .red).font(.headline)
                if !output.isEmpty {
                    Text(output).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                TextField("name", text: $name).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
            }
            HStack {
                Spacer()
                if done {
                    Button("Done") { onDone(success) }.buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") { onDone(false) }
                    Button { Task { await create() } } label: { if busy { Text("Creating…") } else { Text("Create") } }
                        .buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
        }
        .padding(20).frame(width: 440)
    }

    private func create() async {
        busy = true; defer { busy = false }
        let r = await model.exec((type.createArgs ?? []) + [name.trimmingCharacters(in: .whitespaces)])
        success = r.ok; done = true
        output = stripANSI(r.ok ? r.stdout : (r.stderr.nilIfEmpty ?? r.stdout)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
