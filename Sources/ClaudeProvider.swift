import Foundation
import Security

struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    let logoAsset = "anthropic"

    func fetch() async -> ProviderState {
        guard let tok = Self.token() else { return .noAuth }
        if let exp = tok.expiresAt, Date() >= exp { return .expired }
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        guard let r = await Http.get(url, headers: [
            "Authorization": "Bearer \(tok.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "ClaudeLimits/0.2 (macOS)",
        ]) else { return .networkError("request failed") }
        return stateFor(status: r.status, data: r.data, parse: Self.parse)
    }

    struct Token { let accessToken: String; let expiresAt: Date? }

    static func token() -> Token? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let t = oauth["accessToken"] as? String, !t.isEmpty else { return nil }
        let exp = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Token(accessToken: t, expiresAt: exp)
    }

    static func parse(_ data: Data) -> [Metric]? {
        struct Resp: Decodable {
            struct L: Decodable { let kind: String?; let percent: Int?; let resets_at: String? }
            let limits: [L]?
        }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data),
              let limits = r.limits, !limits.isEmpty else { return nil }
        var out: [Metric] = []
        for l in limits {
            let id: String, label: String
            switch l.kind {
            case "session": id = "5h"; label = "5-hour"
            case "weekly_all": id = "7d"; label = "Weekly"
            default: continue
            }
            let p = l.percent ?? 0
            out.append(Metric(id: id, label: label, percentUsed: p, display: "\(p)%",
                              resetsAt: l.resets_at.flatMap(parseISODate)))
        }
        return out.isEmpty ? nil : out
    }
}
