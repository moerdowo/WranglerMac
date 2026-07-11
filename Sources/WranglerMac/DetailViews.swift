import SwiftUI
import AppKit

// MARK: - KV key browser / editor

struct KVDetailView: View {
    @Environment(AppModel.self) private var model
    let namespace: KVNamespace

    @State private var keys: [KVKey] = []
    @State private var loadState: LoadState = .loading
    @State private var prefix = ""
    @State private var selectedName: String?
    @State private var value = ""
    @State private var originalValue = ""
    @State private var valueLoading = false
    @State private var busy = false
    @State private var showAdd = false
    @State private var confirmDelete: String?
    @State private var toast: String?

    enum LoadState: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        HSplitView {
            keyList.frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            editor.frame(minWidth: 320)
        }
        .navigationTitle(namespace.title)
        .navigationSubtitle("KV namespace")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .help("Add key")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await loadKeys() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(busy)
            }
        }
        .task { await loadKeys() }
        .sheet(isPresented: $showAdd) { addSheet }
        .overlay(alignment: .bottom) { toastView }
    }

    private var keyList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Filter by prefix", text: $prefix)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await loadKeys() } }
            }
            .padding(8)
            Divider()

            switch loadState {
            case .loading:
                LoadingMatrix(caption: "LOADING KEYS", tint: Color(hex: 0x2AA79B), cols: 10)
            case .failed(let msg):
                Spacer()
                ContentUnavailableView("Couldn’t load keys", systemImage: "exclamationmark.triangle",
                                       description: Text(msg).font(.caption))
                Spacer()
            case .loaded:
                if keys.isEmpty {
                    Spacer()
                    ContentUnavailableView("No keys", systemImage: "key",
                                           description: Text(prefix.isEmpty ? "This namespace is empty." : "No keys match “\(prefix)”."))
                    Spacer()
                } else {
                    List(keys, selection: $selectedName) { key in
                        Label(key.name, systemImage: "key.fill")
                            .lineLimit(1)
                            .tag(key.name)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .background(.background)
        .onChange(of: selectedName) { _, name in
            if let name { Task { await loadValue(name) } }
        }
    }

    @ViewBuilder private var editor: some View {
        if let selectedName {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedName).font(.headline).lineLimit(1).textSelection(.enabled)
                        Text("value").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if valueLoading { ProgressView().controlSize(.small) }
                }
                .padding(12)
                Divider()

                TextEditor(text: $value)
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .disabled(valueLoading)

                Divider()
                HStack {
                    Button(role: .destructive) { confirmDelete = selectedName } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Spacer()
                    if value != originalValue {
                        Text("Modified").font(.caption).foregroundStyle(.orange)
                    }
                    Button { Task { await save(selectedName) } } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || valueLoading || value == originalValue)
                }
                .padding(12)
            }
            .confirmationDialog("Delete “\(confirmDelete ?? "")”?",
                                isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete key", role: .destructive) {
                    if let k = confirmDelete { Task { await deleteKey(k) } }
                }
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            } message: { Text("This permanently removes the key from the namespace.") }
        } else {
            ContentUnavailableView("Select a key", systemImage: "sidebar.right",
                                   description: Text("Choose a key to view and edit its value."))
        }
    }

    private var addSheet: some View {
        AddKeySheet { name, val in
            showAdd = false
            Task { await addKey(name: name, value: val) }
        } cancel: { showAdd = false }
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.callout).padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(.separator))
                .padding(.bottom, 16).transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Actions

    private func nsArgs(_ extra: [String]) -> [String] {
        extra + ["--namespace-id", namespace.id]
    }

    private func loadKeys() async {
        loadState = .loading
        var args = ["kv", "key", "list", "--namespace-id", namespace.id]
        if !prefix.isEmpty { args += ["--prefix", prefix] }
        let r = await model.exec(args)
        guard r.ok else { loadState = .failed(stripANSI(r.stderr.nilIfEmpty ?? r.stdout)); return }
        do {
            keys = try JSONDecoder().decode([KVKey].self, from: WranglerCLI.extractJSON(from: r.stdout))
            loadState = .loaded
        } catch {
            loadState = .failed("Unexpected output.\n" + stripANSI(r.stdout))
        }
    }

    private func loadValue(_ name: String) async {
        valueLoading = true; defer { valueLoading = false }
        let r = await model.exec(nsArgs(["kv", "key", "get", name]))
        let v = r.ok ? r.stdout : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
        value = v.hasSuffix("\n") ? String(v.dropLast()) : v
        originalValue = value
    }

    private func save(_ name: String) async {
        busy = true; defer { busy = false }
        let r = await model.exec(nsArgs(["kv", "key", "put", name, value]))
        if r.ok { originalValue = value; flash("Saved “\(name)”") }
        else { flash("Save failed") }
    }

    private func deleteKey(_ name: String) async {
        confirmDelete = nil
        busy = true; defer { busy = false }
        let r = await model.exec(nsArgs(["kv", "key", "delete", name]))
        if r.ok {
            selectedName = nil; value = ""; originalValue = ""
            flash("Deleted “\(name)”")
            await loadKeys()
        } else { flash("Delete failed") }
    }

    private func addKey(name: String, value: String) async {
        busy = true; defer { busy = false }
        let r = await model.exec(nsArgs(["kv", "key", "put", name, value]))
        if r.ok { flash("Added “\(name)”"); await loadKeys(); selectedName = name }
        else { flash("Add failed") }
    }

    private func flash(_ msg: String) {
        withAnimation { toast = msg }
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); withAnimation { toast = nil } }
    }
}

private struct AddKeySheet: View {
    let add: (String, String) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New key").font(.headline)
            TextField("Key name", text: $name).textFieldStyle(.roundedBorder)
            Text("Value").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $value)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Add") { add(name, value) }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

// MARK: - D1 SQL console

// MARK: - D1 database detail (Schema + Query)

struct DBColumn: Identifiable {
    let name: String
    let type: String
    let notNull: Bool
    let pk: Bool
    let defaultValue: String?
    var id: String { name }
}

struct DBForeignKey: Identifiable {
    let from: String
    let table: String
    let to: String
    var id: String { "\(from)->\(table).\(to)" }
}

struct DBTable: Identifiable {
    let name: String
    var columns: [DBColumn]
    var foreignKeys: [DBForeignKey]
    var createSQL: String?
    var id: String { name }
    /// Tables that reference this one (populated after all tables load).
    var referencedBy: [String] = []
}

struct D1DetailView: View {
    @Environment(AppModel.self) private var model
    let database: D1Database

    enum Mode: String, CaseIterable { case schema = "Schema", query = "Query" }
    @State private var mode: Mode = .schema

    @State private var tables: [DBTable] = []
    @State private var selected: String?
    @State private var schemaError: String?
    @State private var loading = false
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .padding(10)
            Divider()

            switch mode {
            case .schema: schemaView
            case .query: D1QueryConsole(database: database)
            }
        }
        .navigationTitle(database.name)
        .navigationSubtitle("D1 database")
        .toolbar {
            if mode == .schema {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await loadSchema() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(loading)
                }
            }
        }
        .task { if !loaded { await loadSchema() } }
    }

    @ViewBuilder private var schemaView: some View {
        if loading {
            LoadingMatrix(caption: "READING SCHEMA", tint: Color(hex: 0x7C5CFC))
        } else if let schemaError {
            ContentUnavailableView {
                Label("Couldn’t read schema", systemImage: "exclamationmark.triangle")
            } description: { Text(schemaError).font(.callout) } actions: {
                Button("Retry") { Task { await loadSchema() } }.buttonStyle(.borderedProminent)
            }
        } else if tables.isEmpty {
            ContentUnavailableView("No tables", systemImage: "tablecells",
                                   description: Text("This database has no user tables."))
        } else {
            HSplitView {
                tableList.frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
                if let t = tables.first(where: { $0.name == selected }) ?? tables.first {
                    D1TableDetail(table: t)
                } else {
                    Color.clear
                }
            }
        }
    }

    private var tableList: some View {
        List(selection: $selected) {
            Section("\(tables.count) tables") {
                ForEach(tables) { t in
                    HStack(spacing: 8) {
                        Image(systemName: "tablecells").foregroundStyle(Color(hex: 0x7C5CFC))
                        Text(t.name).lineLimit(1)
                        Spacer()
                        if !t.foreignKeys.isEmpty {
                            Image(systemName: "link").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("\(t.columns.count)").font(.caption).foregroundStyle(.tertiary)
                    }
                    .tag(t.name)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Schema loading

    /// Run a D1 command and return one dict-array per statement result set.
    private func runD1(_ sql: String) async -> (sets: [[[String: Any]]]?, error: String?) {
        let r = await model.exec(["d1", "execute", database.name, "--remote", "--json", "--command", sql])
        guard r.ok else { return (nil, stripANSI(r.stderr.nilIfEmpty ?? r.stdout)) }
        let data = WranglerCLI.extractJSON(from: r.stdout)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return (nil, "Unexpected output from D1.")
        }
        return (arr.map { ($0["results"] as? [[String: Any]]) ?? [] }, nil)
    }

    private func loadSchema() async {
        loading = true; defer { loading = false; loaded = true }
        schemaError = nil

        let listSQL = "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name"
        let (listSets, listErr) = await runD1(listSQL)
        if let listErr { schemaError = listErr; return }
        guard let first = listSets?.first else { schemaError = "No result."; return }

        let meta: [(name: String, sql: String?)] = first.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            return (name, row["sql"] as? String)
        }
        if meta.isEmpty { tables = []; return }

        // Batch PRAGMA table_info + foreign_key_list for every table.
        let pragma = meta.map { m -> String in
            let q = m.name.replacingOccurrences(of: "\"", with: "\"\"")
            return "PRAGMA table_info(\"\(q)\"); PRAGMA foreign_key_list(\"\(q)\");"
        }.joined(separator: " ")
        let (pragmaSets, _) = await runD1(pragma)

        var built: [DBTable] = []
        for (i, m) in meta.enumerated() {
            var columns: [DBColumn] = []
            var fks: [DBForeignKey] = []
            if let sets = pragmaSets, sets.count >= 2 * i + 2 {
                columns = sets[2 * i].map { row in
                    DBColumn(name: row["name"] as? String ?? "?",
                             type: (row["type"] as? String ?? "").uppercased(),
                             notNull: asInt(row["notnull"]) == 1,
                             pk: asInt(row["pk"]) > 0,
                             defaultValue: row["dflt_value"] as? String)
                }
                fks = sets[2 * i + 1].map { row in
                    DBForeignKey(from: row["from"] as? String ?? "?",
                                 table: row["table"] as? String ?? "?",
                                 to: row["to"] as? String ?? "?")
                }
            }
            built.append(DBTable(name: m.name, columns: columns, foreignKeys: fks, createSQL: m.sql))
        }

        // Reverse relations: who references each table.
        for i in built.indices {
            let name = built[i].name
            built[i].referencedBy = built
                .filter { $0.foreignKeys.contains { $0.table == name } }
                .map { $0.name }
        }

        tables = built
        if selected == nil { selected = built.first?.name }
    }

    private func asInt(_ v: Any?) -> Int {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }
}

struct D1TableDetail: View {
    let table: DBTable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x9B7CFC), Color(hex: 0x7C5CFC)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "tablecells").foregroundStyle(.white).font(.title3))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(table.name).font(.title2).bold().textSelection(.enabled)
                        Text("^[\(table.columns.count) column](inflect: true) · ^[\(table.foreignKeys.count) relation](inflect: true)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                columnsSection
                if !table.foreignKeys.isEmpty { relationsSection }
                if !table.referencedBy.isEmpty { referencedBySection }
                if let sql = table.createSQL, !sql.isEmpty { createSection(sql) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Columns").font(.headline).padding(.bottom, 8)
            ForEach(Array(table.columns.enumerated()), id: \.element.id) { idx, col in
                HStack(spacing: 10) {
                    Image(systemName: col.pk ? "key.fill" : (isFK(col.name) ? "link" : "circle.dashed"))
                        .foregroundStyle(col.pk ? Color.yellow : (isFK(col.name) ? Color(hex: 0x3A7BD5) : Color.secondary.opacity(0.5)))
                        .font(.caption).frame(width: 16)
                    Text(col.name).font(.system(.callout, design: .monospaced)).fontWeight(col.pk ? .semibold : .regular)
                    Spacer()
                    if !col.defaultValue.isNilOrEmpty {
                        Text("default \(col.defaultValue!)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    if col.notNull && !col.pk {
                        Text("NOT NULL").font(.caption2).foregroundStyle(.orange)
                    }
                    if !col.type.isEmpty {
                        Text(col.type).font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 7)
                if idx < table.columns.count - 1 { Divider() }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private var relationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Foreign keys", systemImage: "arrow.right.circle").font(.headline)
            ForEach(table.foreignKeys) { fk in
                HStack(spacing: 6) {
                    Text(fk.from).font(.system(.callout, design: .monospaced)).foregroundStyle(Color(hex: 0x3A7BD5))
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text("\(fk.table).\(fk.to)").font(.system(.callout, design: .monospaced))
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x3A7BD5).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var referencedBySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Referenced by", systemImage: "arrow.left.circle").font(.headline)
            FlowText(items: table.referencedBy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private func createSection(_ sql: String) -> some View {
        DisclosureGroup("CREATE statement") {
            Text(sql).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
        .padding(14)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private func isFK(_ column: String) -> Bool { table.foreignKeys.contains { $0.from == column } }
}

/// Wrapping row of small pills.
struct FlowText: View {
    let items: [String]
    var body: some View {
        WrapHStack(items: items) { name in
            Text(name).font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: Capsule())
        }
    }
}

/// Minimal wrapping HStack.
struct WrapHStack<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content
    var body: some View {
        // Simple flow using a LazyVGrid of adaptive columns.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

struct D1QueryConsole: View {
    @Environment(AppModel.self) private var model
    let database: D1Database

    @State private var sql = "SELECT name FROM sqlite_master WHERE type='table';"
    @State private var columns: [String] = []
    @State private var rows: [[String]] = []
    @State private var message: String?
    @State private var isError = false
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            editorPane
            Divider()
            resultsPane
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("SQL", systemImage: "curlybraces").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
                } label: { Label("Tables", systemImage: "list.bullet.rectangle") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button { Task { await run() } } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(running || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextEditor(text: $sql)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            Text("Runs against the remote database with `--remote`.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    @ViewBuilder private var resultsPane: some View {
        if running {
            LoadingMatrix(caption: "RUNNING QUERY", tint: Color(hex: 0x7C5CFC))
        } else if let message {
            VStack(spacing: 10) {
                Image(systemName: isError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                    .font(.largeTitle).foregroundStyle(isError ? .red : .green)
                ScrollView { Text(message).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
                    .frame(maxHeight: 160)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if columns.isEmpty {
            ContentUnavailableView("No results yet", systemImage: "tablecells",
                                   description: Text("Write a query and press Run (⌘↩)."))
        } else {
            D1ResultTable(columns: columns, rows: rows)
        }
    }

    private func run() async {
        running = true; defer { running = false }
        message = nil; isError = false; columns = []; rows = []
        let r = await model.exec(["d1", "execute", database.name, "--remote", "--json", "--command", sql])
        guard r.ok else {
            isError = true
            message = stripANSI(r.stderr.nilIfEmpty ?? r.stdout).nilIfEmpty ?? "Query failed."
            return
        }
        let parsed = parseD1(r.stdout)
        columns = parsed.columns
        rows = parsed.rows
        if columns.isEmpty {
            message = parsed.summary ?? "Statement executed successfully."
        }
    }
}

private struct D1ResultTable: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(columns.indices, id: \.self) { i in
                        Text(columns[i]).fontWeight(.semibold)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .frame(minWidth: 90, alignment: .leading)
                    }
                }
                .background(.quaternary.opacity(0.5))
                Divider()
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(columns.indices, id: \.self) { c in
                            Text(c < rows[r].count ? rows[r][c] : "")
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .frame(minWidth: 90, alignment: .leading)
                        }
                    }
                    Divider()
                }
            }
            .padding(1)
        }
    }
}

/// Parse `d1 execute --json` output: `[{ "results": [ {col:val} ], "meta": {...} }]`.
func parseD1(_ stdout: String) -> (columns: [String], rows: [[String]], summary: String?) {
    let data = WranglerCLI.extractJSON(from: stdout)
    guard let top = try? JSONSerialization.jsonObject(with: data),
          let arr = top as? [[String: Any]], let last = arr.last else {
        return ([], [], nil)
    }
    let results = (last["results"] as? [[String: Any]]) ?? []
    guard let first = results.first else {
        var summary = "Statement executed successfully."
        if let meta = last["meta"] as? [String: Any] {
            let changes = meta["changes"] ?? meta["rows_written"] ?? 0
            summary = "OK · \(changes) change(s)"
        }
        return ([], [], summary)
    }
    // Column order isn't preserved by JSON parsing; sort for stable display.
    let columns = first.keys.sorted()
    let rows: [[String]] = results.map { row in
        columns.map { key in
            switch row[key] {
            case nil, is NSNull: return "NULL"
            case let s as String: return s
            case let n as NSNumber: return n.stringValue
            case let v?: return String(describing: v)
            }
        }
    }
    return (columns, rows, nil)
}

// MARK: - R2 object operations

struct R2DetailView: View {
    @Environment(AppModel.self) private var model
    let bucket: R2Bucket

    @State private var objectKey = ""
    @State private var status: String?
    @State private var isError = false
    @State private var busy = false
    @State private var confirmDelete = false

    private var objectPath: String { "\(bucket.name)/\(objectKey)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                objectPanel
                if let status {
                    Label(status, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? .orange : .green)
                        .font(.callout)
                }
                infoNote
            }
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle(bucket.name)
        .navigationSubtitle("R2 bucket")
        .confirmationDialog("Delete “\(objectKey)” from \(bucket.name)?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete object", role: .destructive) { Task { await deleteObject() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently removes the object from the bucket.") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF6A94A), Color(hex: 0xF6821F)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "externaldrive.fill").foregroundStyle(.white).font(.title3))
            VStack(alignment: .leading) {
                Text(bucket.name).font(.title2).bold()
                if let d = bucket.creation_date {
                    Text(d).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var objectPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Object").font(.headline)
            TextField("object key / path", text: $objectKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack(spacing: 10) {
                Button { uploadObject() } label: { Label("Upload…", systemImage: "arrow.up.doc") }
                Button { Task { await downloadObject() } } label: { Label("Download", systemImage: "arrow.down.doc") }
                    .disabled(objectKey.isEmpty)
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(objectKey.isEmpty)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator))
    }

    private var infoNote: some View {
        Label {
            Text("wrangler can get, put, and delete objects by key, but does not support listing objects in a bucket. Enter a known key above.")
        } icon: { Image(systemName: "info.circle") }
        .font(.caption).foregroundStyle(.secondary)
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Actions

    private func uploadObject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if objectKey.isEmpty { objectKey = url.lastPathComponent }
        Task {
            busy = true; defer { busy = false }
            let r = await model.exec(["r2", "object", "put", objectPath, "--file", url.path, "--remote"])
            set(r.ok ? "Uploaded \(objectKey)" : stripANSI(r.stderr.nilIfEmpty ?? r.stdout), error: !r.ok)
        }
    }

    private func downloadObject() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (objectKey as NSString).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; defer { busy = false }
        let r = await model.exec(["r2", "object", "get", objectPath, "--file", url.path, "--remote"])
        set(r.ok ? "Downloaded to \(url.lastPathComponent)" : stripANSI(r.stderr.nilIfEmpty ?? r.stdout), error: !r.ok)
        if r.ok { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func deleteObject() async {
        busy = true; defer { busy = false }
        let r = await model.exec(["r2", "object", "delete", objectPath, "--remote"])
        set(r.ok ? "Deleted \(objectKey)" : stripANSI(r.stderr.nilIfEmpty ?? r.stdout), error: !r.ok)
    }

    private func set(_ msg: String, error: Bool) { status = msg; isError = error }
}

// MARK: - Queue detail

struct QueueDetailView: View {
    @Environment(AppModel.self) private var model
    let queueName: String

    @State private var info = ""
    @State private var loading = true
    @State private var busy = false
    @State private var status: String?
    @State private var confirmPurge = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                GroupBox("Info") {
                    if loading {
                        LoadingMatrix(caption: "LOADING QUEUE", tint: Color(hex: 0x3A7BD5), cols: 12)
                    } else {
                        Text(info.isEmpty ? "No info returned." : info)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                actions
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle(queueName)
        .navigationSubtitle("Queue")
        .task { await loadInfo() }
        .confirmationDialog("Purge all messages from \(queueName)?",
                            isPresented: $confirmPurge, titleVisibility: .visible) {
            Button("Purge messages", role: .destructive) { Task { await purge() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes all messages currently in the queue.") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x5B9BE0), Color(hex: 0x3A7BD5)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "tray.full.fill").foregroundStyle(.white).font(.title3))
            Text(queueName).font(.title2).bold()
            Spacer()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { Task { await deliveryAction(pause: true) } } label: { Label("Pause delivery", systemImage: "pause.fill") }
            Button { Task { await deliveryAction(pause: false) } } label: { Label("Resume delivery", systemImage: "play.fill") }
            Button(role: .destructive) { confirmPurge = true } label: { Label("Purge", systemImage: "trash") }
            if busy { ProgressView().controlSize(.small) }
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    private func loadInfo() async {
        loading = true; defer { loading = false }
        let r = await model.exec(["queues", "info", queueName])
        info = stripANSI(r.ok ? r.stdout : (r.stderr.nilIfEmpty ?? r.stdout))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deliveryAction(pause: Bool) async {
        busy = true; defer { busy = false }
        let r = await model.exec(["queues", pause ? "pause-delivery" : "resume-delivery", queueName])
        status = r.ok ? (pause ? "Delivery paused." : "Delivery resumed.") : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
        await loadInfo()
    }

    private func purge() async {
        busy = true; defer { busy = false }
        let r = await model.exec(["queues", "purge", queueName, "--force"])
        status = r.ok ? "Queue purged." : stripANSI(r.stderr.nilIfEmpty ?? r.stdout)
    }
}
