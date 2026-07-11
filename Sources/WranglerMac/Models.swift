import Foundation

struct KVNamespace: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
}

struct KVKey: Decodable, Identifiable, Hashable {
    let name: String
    let expiration: Int?
    var id: String { name }

    enum CodingKeys: String, CodingKey { case name, expiration }
}

struct WorkerSecret: Decodable, Identifiable, Hashable {
    let name: String
    let type: String?
    var id: String { name }
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

/// Structured view of `wrangler whoami` output.
struct WhoAmIInfo {
    var loggedIn: Bool
    var email: String?
    var authType: String?
    var accounts: [CFAccount]

    struct CFAccount: Identifiable, Hashable {
        let name: String
        let accountID: String
        var id: String { accountID }
    }

    /// Empty / unknown state.
    static let unknown = WhoAmIInfo(loggedIn: false, email: nil, authType: nil, accounts: [])

    /// Best-effort parse of the human-readable `whoami` table output.
    static func parse(_ output: String) -> WhoAmIInfo {
        let lower = output.lowercased()
        let loggedOut = lower.contains("not authenticated")
            || lower.contains("not logged in")
            || lower.contains("you are not")
        var info = WhoAmIInfo.unknown

        if let m = output.range(of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#,
                                options: .regularExpression) {
            info.email = String(output[m])
        }
        if lower.contains("oauth token") { info.authType = "OAuth Token" }
        else if lower.contains("api token") { info.authType = "API Token" }
        else if lower.contains("global api key") { info.authType = "Global API Key" }

        // Parse the account table: data rows contain the │ (U+2502) cell divider.
        for raw in output.split(separator: "\n") {
            guard raw.contains("│") else { continue }
            let cells = raw.split(separator: "│")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard cells.count >= 2 else { continue }
            if cells[0].lowercased().contains("account name") { continue } // header row
            let name = cells[0], id = cells[1]
            let looksLikeID = id.range(of: #"^[0-9a-fA-F]{16,}$"#, options: .regularExpression) != nil
            if looksLikeID || id.count >= 10 {
                info.accounts.append(.init(name: name, accountID: id))
            }
        }

        info.loggedIn = !loggedOut && (info.email != nil || !info.accounts.isEmpty || lower.contains("logged in"))
        return info
    }
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
    case workers = "Workers"
    case kv = "KV Namespaces"
    case d1 = "D1 Databases"
    case r2 = "R2 Buckets"
    case queues = "Queues"
    case dev = "Dev Server"
    case config = "Config Editor"
    case logs = "Live Logs"
    case console = "Console"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .account: return "person.crop.circle"
        case .workers: return "bolt.horizontal.circle"
        case .kv: return "tablecells"
        case .d1: return "cylinder.split.1x2"
        case .r2: return "externaldrive"
        case .queues: return "tray.full"
        case .dev: return "play.rectangle"
        case .config: return "doc.badge.gearshape"
        case .logs: return "waveform"
        case .console: return "terminal"
        case .settings: return "gearshape"
        }
    }
}
