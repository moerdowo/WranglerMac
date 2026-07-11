import Foundation

struct KVNamespace: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
}

struct D1Database: Decodable, Identifiable, Hashable {
    let uuid: String
    let name: String
    let version: String?
    var id: String { uuid }

    enum CodingKeys: String, CodingKey { case uuid, name, version }
}

struct R2Bucket: Decodable, Identifiable, Hashable {
    let name: String
    let creation_date: String?
    var id: String { name }
}

/// R2 `bucket list --json` may wrap results in `{ "buckets": [...] }`.
struct R2BucketList: Decodable {
    let buckets: [R2Bucket]
}

struct QueueInfo: Decodable, Identifiable, Hashable {
    let queue_id: String?
    let queue_name: String?
    var id: String { queue_id ?? queue_name ?? UUID().uuidString }
    var displayName: String { queue_name ?? queue_id ?? "queue" }
}

/// A single command execution recorded for the Console / audit log.
struct ConsoleEntry: Identifiable {
    let id = UUID()
    let command: String
    let output: String
    let ok: Bool
    let date: Date
}

/// Sidebar destinations.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case account = "Account"
    case kv = "KV Namespaces"
    case d1 = "D1 Databases"
    case r2 = "R2 Buckets"
    case queues = "Queues"
    case logs = "Live Logs"
    case console = "Console"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .account: return "person.crop.circle"
        case .kv: return "tablecells"
        case .d1: return "cylinder.split.1x2"
        case .r2: return "externaldrive"
        case .queues: return "tray.full"
        case .logs: return "waveform"
        case .console: return "terminal"
        case .settings: return "gearshape"
        }
    }
}
