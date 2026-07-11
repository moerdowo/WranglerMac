import SwiftUI

enum ResourceParseError: Error { case empty }

/// Strip ANSI SGR color escapes so fallback/error text is readable.
func stripANSI(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
}

/// Run a wrangler command and turn its output into rows via a per-command
/// `parse` closure (wrangler's JSON support is inconsistent, so each command
/// decides how to read its own output). Records the invocation in the console.
/// On a parse error we fall back to raw text, or an empty state if there's
/// nothing but wrangler's banner.
@MainActor
func loadResource<T: Identifiable>(
    _ model: AppModel,
    args: [String],
    parse: (String) throws -> [T]
) async -> LoadOutcome<T> {
    do {
        let r = try await WranglerCLI.shared.run(args, cwd: model.projectDir.nilIfEmpty)
        model.record(r)
        guard r.ok else { return .failure(stripANSI(r.stderr.nilIfEmpty ?? r.stdout)) }
        do {
            return .rows(try parse(r.stdout))
        } catch {
            let cleaned = stripBanner(stripANSI(r.stdout))
            return cleaned.isEmpty ? .rows([]) : .raw(cleaned)
        }
    } catch {
        return .failure(error.localizedDescription)
    }
}

/// Remove wrangler's "⛅️ wrangler x.y.z" banner and rule lines.
private func stripBanner(_ s: String) -> String {
    s.split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0) }
        .filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            if t.contains("wrangler") && t.contains("⛅") { return false }
            if t.allSatisfy({ $0 == "─" || $0 == " " }) { return false }
            return true
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

struct KVView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        // `kv namespace list` emits JSON natively (and rejects --json).
        ResourceScreen(title: "KV Namespaces", systemImage: "tablecells", itemNoun: "namespace") {
            await loadResource(model, args: ["kv", "namespace", "list"]) { out in
                try JSONDecoder().decode([KVNamespace].self, from: WranglerCLI.extractJSON(from: out))
            }
        } rowContent: { ns in
            ResourceCard(icon: "tablecells", tint: Color(hex: 0x2AA79B),
                         title: ns.title, subtitle: ns.id, copyValue: ns.id)
        } destination: { ns in
            KVDetailView(namespace: ns)
        }
    }
}

struct D1View: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        // `d1 list` supports --json.
        ResourceScreen(title: "D1 Databases", systemImage: "cylinder.split.1x2", itemNoun: "database") {
            await loadResource(model, args: ["d1", "list", "--json"]) { out in
                try JSONDecoder().decode([D1Database].self, from: WranglerCLI.extractJSON(from: out))
            }
        } rowContent: { db in
            ResourceCard(icon: "cylinder.split.1x2", tint: Color(hex: 0x7C5CFC),
                         title: db.name, subtitle: db.uuid,
                         badge: db.version, copyValue: db.uuid)
        } destination: { db in
            D1ConsoleView(database: db)
        }
    }
}

struct R2View: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        // `r2 bucket list` prints "name:" / "creation_date:" pairs (no JSON mode).
        ResourceScreen(title: "R2 Buckets", systemImage: "externaldrive", itemNoun: "bucket") {
            await loadResource(model, args: ["r2", "bucket", "list"]) { out in
                let buckets = parseR2Buckets(out)
                if buckets.isEmpty { throw ResourceParseError.empty }
                return buckets
            }
        } rowContent: { bucket in
            ResourceCard(icon: "externaldrive.fill", tint: Color(hex: 0xF6821F),
                         title: bucket.name,
                         subtitle: bucket.creation_date.map(prettyDate),
                         monospacedSubtitle: false,
                         copyValue: bucket.name)
        } destination: { bucket in
            R2DetailView(bucket: bucket)
        }
    }
}

struct QueuesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        // `queues list` prints a table (no JSON mode); empty accounts show only the banner.
        ResourceScreen(title: "Queues", systemImage: "tray.full", itemNoun: "queue") {
            await loadResource(model, args: ["queues", "list"]) { out in
                let queues = parseQueues(out)
                if queues.isEmpty { throw ResourceParseError.empty }
                return queues
            }
        } rowContent: { q in
            ResourceCard(icon: "tray.full.fill", tint: Color(hex: 0x3A7BD5),
                         title: q.displayName, subtitle: q.queue_id,
                         copyValue: q.queue_id)
        } destination: { q in
            QueueDetailView(queueName: q.displayName)
        }
    }
}

// MARK: - Text parsers

private func parseR2Buckets(_ output: String) -> [R2Bucket] {
    var buckets: [R2Bucket] = []
    var pendingName: String?
    for rawLine in stripANSI(output).split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("name:") {
            pendingName = line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("creation_date:"), let name = pendingName {
            let date = line.dropFirst("creation_date:".count).trimmingCharacters(in: .whitespaces)
            buckets.append(R2Bucket(name: name, creation_date: date))
            pendingName = nil
        }
    }
    return buckets
}

private func parseQueues(_ output: String) -> [QueueInfo] {
    var queues: [QueueInfo] = []
    for rawLine in stripANSI(output).split(separator: "\n") {
        guard rawLine.contains("│") else { continue }
        let cells = rawLine.split(separator: "│")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = cells.first else { continue }
        let lower = first.lowercased()
        if lower == "name" || lower.contains("queue name") || lower.hasPrefix("---") { continue }
        queues.append(QueueInfo(queue_id: cells.count > 1 ? cells[1] : nil, queue_name: first))
    }
    return queues
}

/// Turn an ISO8601 timestamp into a friendly "Feb 14, 2023" if possible.
private func prettyDate(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return "created \(iso)" }
    let out = DateFormatter()
    out.dateStyle = .medium
    return "created \(out.string(from: date))"
}
