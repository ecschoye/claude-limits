import Foundation

struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let logoAsset = "openai"

    func fetch() async -> ProviderState {
        guard let auth = Self.auth() else { return .noAuth }
        if let exp = auth.exp, Date() >= exp { return .expired }
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        var headers = [
            "Authorization": "Bearer \(auth.accessToken)",
            "User-Agent": "codex-cli/0.141.0",
        ]
        if let aid = auth.accountId { headers["chatgpt-account-id"] = aid }
        guard let r = await Http.get(url, headers: headers) else { return .networkError("request failed") }
        return stateFor(status: r.status, data: r.data, parse: Self.parse)
    }

    struct Auth { let accessToken: String; let accountId: String?; let exp: Date? }

    static func auth() -> Auth? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/auth.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let at = tokens["access_token"] as? String, !at.isEmpty else { return nil }
        return Auth(accessToken: at, accountId: tokens["account_id"] as? String, exp: jwtExpiry(at))
    }

    // Unverified decode of the JWT `exp` claim (we only need expiry, not validation).
    static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let exp = obj["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func parse(_ data: Data) -> [Metric]? {
        struct W: Decodable { let used_percent: Int?; let reset_at: Double? }
        struct RL: Decodable { let primary_window: W?; let secondary_window: W? }
        struct Resp: Decodable { let rate_limit: RL? }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data), let rl = r.rate_limit else { return nil }
        func metric(_ w: W?, _ id: String, _ label: String) -> Metric? {
            guard let w, let p = w.used_percent else { return nil }
            return Metric(id: id, label: label, percentUsed: p, display: "\(p)%",
                          resetsAt: w.reset_at.map { Date(timeIntervalSince1970: $0) })
        }
        let out = [metric(rl.primary_window, "5h", "5-hour"),
                   metric(rl.secondary_window, "7d", "Weekly")].compactMap { $0 }
        return out.isEmpty ? nil : out
    }
}
