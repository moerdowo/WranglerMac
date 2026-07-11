import Foundation

/// A deployed Worker script, from the Cloudflare API (wrangler has no
/// "list all workers" command, so we call the account scripts endpoint using
/// wrangler's stored OAuth token).
struct WorkerScript: Decodable, Identifiable, Hashable {
    let id: String
    let created_on: String?
    let modified_on: String?
    let usage_model: String?
}

private struct CFListResponse<T: Decodable>: Decodable {
    let result: [T]?
    let success: Bool
    let errors: [CFError]?
}

private struct CFError: Decodable { let code: Int?; let message: String? }

enum CFAPIError: LocalizedError {
    case noToken
    case http(Int)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noToken: return "No Cloudflare session found. Sign in on the Account screen."
        case .http(let c): return "Cloudflare API returned HTTP \(c)."
        case .api(let m): return m
        }
    }
}

/// Minimal read-only Cloudflare API client backed by wrangler's OAuth token.
enum CloudflareAPI {
    static let base = "https://api.cloudflare.com/client/v4"

    /// wrangler's token store on macOS.
    private static var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/.wrangler/config/default.toml")
    }

    /// (token, isExpired). Reads the current OAuth access token from disk.
    static func tokenInfo() -> (token: String, expired: Bool)? {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return nil }
        func value(_ key: String) -> String? {
            guard let r = text.range(of: "\(key)\\s*=\\s*\"([^\"]*)\"", options: .regularExpression) else { return nil }
            let line = String(text[r])
            guard let q = line.range(of: "\"([^\"]*)\"", options: .regularExpression) else { return nil }
            return String(line[q]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        guard let token = value("oauth_token"), !token.isEmpty else { return nil }
        var expired = false
        if let exp = value("expiration_time"), let date = parseDate(exp) {
            expired = Date() >= date.addingTimeInterval(-60)
        }
        return (token, expired)
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? {
            let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]; return g.date(from: s)
        }()
    }

    /// GET a list endpoint and return its `result` array.
    static func getList<T: Decodable>(_ path: String, token: String, as: T.Type) async throws -> [T] {
        var req = URLRequest(url: URL(string: base + path)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw CFAPIError.http(code) }
        let decoded = try JSONDecoder().decode(CFListResponse<T>.self, from: data)
        guard decoded.success else {
            throw CFAPIError.api(decoded.errors?.first?.message ?? "Request failed (HTTP \(code)).")
        }
        return decoded.result ?? []
    }

    static func listWorkers(account: String, token: String) async throws -> [WorkerScript] {
        try await getList("/accounts/\(account)/workers/scripts", token: token, as: WorkerScript.self)
    }

    /// Cron triggers for a Worker. Returns the raw cron expressions.
    static func schedules(account: String, script: String, token: String) async throws -> [String] {
        struct Schedule: Decodable { let cron: String? }
        let list = try await getList("/accounts/\(account)/workers/scripts/\(script)/schedules",
                                     token: token, as: Schedule.self)
        return list.compactMap { $0.cron }
    }
}
