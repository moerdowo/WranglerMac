import SwiftUI
import AppKit

/// Parse a wrangler command's output into groups of (key, value) rows —
/// handles JSON objects/arrays and wrangler's aligned "key: value" text.
func parseFieldGroups(_ output: String) -> [[(String, String)]] {
    let cleaned = stripANSI(output)
    let data = WranglerCLI.extractJSON(from: cleaned)
    if let obj = try? JSONSerialization.jsonObject(with: data) {
        if let arr = obj as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }.map { orderedRows($0) }
        }
        if let dict = obj as? [String: Any] {
            if let inner = (dict["result"] ?? dict["results"]) as? [Any] {
                let groups = inner.compactMap { $0 as? [String: Any] }.map { orderedRows($0) }
                if !groups.isEmpty { return groups }
            }
            return [orderedRows(dict)]
        }
    }
    // Text: split into blocks by blank lines; parse "key: value" lines.
    var groups: [[(String, String)]] = []
    for block in cleaned.components(separatedBy: "\n\n") {
        var rows: [(String, String)] = []
        for raw in block.split(separator: "\n") {
            let line = String(raw)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z0-9_.\\-]+$", options: .regularExpression) != nil else { continue }
            guard !val.isEmpty else { continue }
            rows.append((key, val))
        }
        if !rows.isEmpty { groups.append(rows) }
    }
    return groups
}

private func orderedRows(_ d: [String: Any]) -> [(String, String)] {
    flattenPublic(d).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
}

func statValue(_ rows: [(String, String)], _ keys: [String]) -> String? {
    for k in keys { if let hit = rows.first(where: { $0.0.lowercased() == k.lowercased() }) { return hit.1 } }
    return nil
}

/// snake_case / camelCase → "Title Case".
func humanizeKey(_ k: String) -> String {
    var s = k.replacingOccurrences(of: "_", with: " ")
    s = s.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
    return s.split(separator: " ").map { w -> String in
        let lower = w.lowercased()
        if ["id", "url", "ssl", "tls", "cors", "r2", "d1", "kv"].contains(lower) { return lower.uppercased() }
        return w.prefix(1).uppercased() + w.dropFirst().lowercased()
    }.joined(separator: " ")
}

/// Humanize a field value: bytes, thousands, dates, booleans.
func formatValue(_ key: String, _ value: String) -> String {
    let lk = key.lowercased()
    if value == "true" { return "Yes" }
    if value == "false" { return "No" }
    if value.contains("T"), parseISODate(value) != nil { return isoPretty(value) ?? value }
    if let n = Double(value), n.rounded() == n {
        let i = Int64(n)
        if lk.contains("size") || lk.contains("bytes") { return byteString(i) }
        return numberString(i)
    }
    return value
}

func byteString(_ bytes: Int64) -> String {
    let f = ByteCountFormatter(); f.countStyle = .file
    return f.string(fromByteCount: bytes)
}
func numberString(_ n: Int64) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

// MARK: - Views

/// A clean key/value rows renderer with URL detection.
struct FieldRowsView: View {
    let rows: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    Text(humanizeKey(row.0))
                        .foregroundStyle(.secondary)
                        .frame(width: 150, alignment: .leading)
                    valueView(row.0, row.1)
                    Spacer(minLength: 0)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder private func valueView(_ key: String, _ value: String) -> some View {
        if value.hasPrefix("http"), let url = URL(string: value) {
            Button { NSWorkspace.shared.open(url) } label: {
                Text(value).foregroundStyle(Color(hex: 0x6ba7ec)).lineLimit(1).truncationMode(.middle)
            }.buttonStyle(.plain)
        } else if value == "Yes" || value == "true" || value.lowercased() == "active" || value.lowercased() == "enabled" {
            Label(formatValue(key, value), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else if value == "No" || value == "false" {
            Text(formatValue(key, value)).foregroundStyle(.secondary)
        } else {
            Text(formatValue(key, value)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A big-number stat tile.
struct StatTile: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 15))
            Text(value).font(.title3).bold().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.25), lineWidth: 1))
    }
}
