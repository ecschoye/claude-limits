import Foundation

enum Severity: String, Equatable {
    case normal, warning, critical, unknown
    init(raw: String?) {
        switch raw?.lowercased() {
        case "normal": self = .normal
        case "warning", "warn": self = .warning
        case "critical": self = .critical
        default: self = .unknown
        }
    }
}

struct UsageWindow: Identifiable, Equatable {
    let id: String        // "session" | "weekly"
    let title: String
    let percent: Int
    let resetsAt: Date?
    let severity: Severity
    let isActive: Bool
}

// Decoded straight off GET /api/oauth/usage. The `limits` array is the cleanest
// source: each entry self-describes group/kind/percent/reset/severity.
private struct UsageResponse: Decodable {
    struct Limit: Decodable {
        let kind: String?
        let percent: Int?
        let resets_at: String?
        let is_active: Bool?
        let severity: String?
    }
    let limits: [Limit]?
}

enum UsageParse {
    /// Returns the session + weekly windows, or nil if the response no longer
    /// carries a usable `limits` array (treat nil as schema drift, surface loudly).
    static func parse(_ data: Data) -> [UsageWindow]? {
        guard let resp = try? JSONDecoder().decode(UsageResponse.self, from: data),
              let limits = resp.limits, !limits.isEmpty
        else { return nil }

        var out: [UsageWindow] = []
        for l in limits {
            let id: String, title: String
            switch l.kind {
            case "session":    id = "session"; title = "5-hour session"
            case "weekly_all": id = "weekly";  title = "Weekly"
            default: continue   // skip weekly_scoped / unknown kinds for v1
            }
            out.append(UsageWindow(
                id: id, title: title,
                percent: l.percent ?? 0,
                resetsAt: l.resets_at.flatMap(parseDate),
                severity: Severity(raw: l.severity),
                isActive: l.is_active ?? false))
        }
        return out.isEmpty ? nil : out
    }

    // resets_at looks like "2026-06-22T06:00:00.989998+00:00" (microsecond fraction).
    // ISO8601DateFormatter is finicky with >3 fractional digits, so strip the fraction;
    // sub-second precision is irrelevant for a minute-grained countdown.
    static func parseDate(_ s: String) -> Date? {
        let cleaned = s.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: cleaned)
    }
}

/// Human countdown, e.g. 11580s -> "3h 13m", 2700s -> "45m", 0 -> "now".
func formatRemaining(_ seconds: Int) -> String {
    let s = max(0, seconds)
    if s == 0 { return "now" }
    let h = s / 3600, m = (s % 3600) / 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}
