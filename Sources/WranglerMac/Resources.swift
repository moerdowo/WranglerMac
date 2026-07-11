import SwiftUI

/// Shared loader: run a wrangler command, try to decode `T`, else fall back to
/// raw stdout. Records the invocation in the console/audit log.
@MainActor
func loadResource<T: Decodable & Identifiable>(
    _ model: AppModel,
    args: [String],
    as type: T.Type,
    decode: (Data) throws -> [T]
) async -> LoadOutcome<T> {
    var jsonArgs = args
    if !jsonArgs.contains("--json") { jsonArgs.append("--json") }
    do {
        let r = try await WranglerCLI.shared.run(jsonArgs, cwd: model.projectDir.nilIfEmpty)
        model.record(r)
        guard r.ok else {
            // Retry without --json for a human-readable fallback.
            let plain = try await WranglerCLI.shared.run(args, cwd: model.projectDir.nilIfEmpty)
            model.record(plain)
            if plain.ok { return .raw(plain.stdout) }
            return .failure(r.stderr.nilIfEmpty ?? r.stdout)
        }
        let data = WranglerCLI.extractJSON(from: r.stdout)
        do {
            return .rows(try decode(data))
        } catch {
            // JSON present but shape differs — show raw so the user still sees it.
            return .raw(r.stdout)
        }
    } catch {
        return .failure(error.localizedDescription)
    }
}

struct KVView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ResourceScreen(title: "KV Namespaces", systemImage: "tablecells") {
            await loadResource(model, args: ["kv", "namespace", "list"], as: KVNamespace.self) {
                try JSONDecoder().decode([KVNamespace].self, from: $0)
            }
        } rowContent: { ns in
            VStack(alignment: .leading, spacing: 2) {
                Text(ns.title).fontWeight(.medium)
                Text(ns.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(.vertical, 2)
        }
    }
}

struct D1View: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ResourceScreen(title: "D1 Databases", systemImage: "cylinder.split.1x2") {
            await loadResource(model, args: ["d1", "list"], as: D1Database.self) {
                try JSONDecoder().decode([D1Database].self, from: $0)
            }
        } rowContent: { db in
            VStack(alignment: .leading, spacing: 2) {
                Text(db.name).fontWeight(.medium)
                Text(db.uuid).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(.vertical, 2)
        }
    }
}

struct R2View: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ResourceScreen(title: "R2 Buckets", systemImage: "externaldrive") {
            await loadResource(model, args: ["r2", "bucket", "list"], as: R2Bucket.self) { data in
                // Accept either a bare array or a { "buckets": [...] } wrapper.
                if let list = try? JSONDecoder().decode([R2Bucket].self, from: data) { return list }
                return try JSONDecoder().decode(R2BucketList.self, from: data).buckets
            }
        } rowContent: { bucket in
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.name).fontWeight(.medium)
                if let d = bucket.creation_date {
                    Text("created \(d)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct QueuesView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ResourceScreen(title: "Queues", systemImage: "tray.full") {
            await loadResource(model, args: ["queues", "list"], as: QueueInfo.self) {
                try JSONDecoder().decode([QueueInfo].self, from: $0)
            }
        } rowContent: { q in
            VStack(alignment: .leading, spacing: 2) {
                Text(q.displayName).fontWeight(.medium)
                if let id = q.queue_id {
                    Text(id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
