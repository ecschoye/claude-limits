import Foundation

struct OpenRouterProvider: UsageProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    let logoAsset = "openrouter"

    func fetch() async -> ProviderState {
        guard let key = Self.key() else { return .noAuth }
        let h = ["Authorization": "Bearer \(key)"]
        guard let r = await Http.get(URL(string: "https://openrouter.ai/api/v1/credits")!, headers: h) else {
            return .networkError("request failed")
        }
        let base = stateFor(status: r.status, data: r.data, parse: Self.parse)
        guard case .ok(var metrics) = base else { return base }
        // Best-effort activity (daily/weekly/monthly spend) from /auth/key.
        if let a = await Http.get(URL(string: "https://openrouter.ai/api/v1/auth/key")!, headers: h),
           a.status == 200, let spend = Self.parseActivity(a.data) {
            metrics.append(contentsOf: spend)
        }
        return .ok(metrics)
    }

    // env (if launched from a shell) -> ~/.zshenv -> our own Keychain item (Settings field).
    static func key() -> String? {
        if let k = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !k.isEmpty { return k }
        if let k = fromZshenv() { return k }
        return KeychainStore.read("openrouter")
    }

    static func fromZshenv() -> String? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".zshenv")
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let r = line.range(of: "OPENROUTER_API_KEY=") else { continue }
            var v = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
                v = String(v.dropFirst().dropLast())
            }
            if !v.isEmpty { return v }
        }
        return nil
    }

    static func parse(_ data: Data) -> [Metric]? {
        struct Resp: Decodable {
            struct D: Decodable { let total_credits: Double?; let total_usage: Double? }
            let data: D?
        }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data), let d = r.data,
              let total = d.total_credits, let used = d.total_usage else { return nil }
        let remaining = max(0, total - used)
        let pct = total > 0 ? Int((used / total * 100).rounded()) : 0
        let display = remaining >= 100 ? String(format: "$%.0f", remaining)
                                       : String(format: "$%.2f", remaining)
        return [Metric(id: "credits", label: "Credits", percentUsed: pct, display: display,
                       resetsAt: nil, amount: remaining)]
    }

    // Daily/weekly/monthly spend ($) from /auth/key.
    static func parseActivity(_ data: Data) -> [Metric]? {
        struct Resp: Decodable {
            struct D: Decodable { let usage_daily: Double?; let usage_weekly: Double?; let usage_monthly: Double? }
            let data: D?
        }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data), let d = r.data else { return nil }
        func m(_ id: String, _ label: String, _ v: Double?) -> Metric? {
            guard let v else { return nil }
            return Metric(id: id, label: label, percentUsed: 0, display: String(format: "$%.2f", v), resetsAt: nil)
        }
        let out = [m("daily", "Today", d.usage_daily),
                   m("weekly", "This week", d.usage_weekly),
                   m("monthly", "This month", d.usage_monthly)].compactMap { $0 }
        return out.isEmpty ? nil : out
    }
}
