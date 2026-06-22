import Foundation

// One displayed number: a usage window (5h/7d, with reset) or a balance (credits, no reset).
struct Metric: Identifiable, Equatable {
    let id: String          // "5h" | "7d" | "credits"
    let label: String       // "5-hour" | "Weekly" | "Credits"
    let percentUsed: Int    // 0..100, drives the bar + tier color
    let display: String     // menu bar value: "45%" | "$20.86"
    let resetsAt: Date?     // windows only; nil for balances
    let amount: Double?     // numeric value for balances (e.g. $ remaining); nil for windows

    init(id: String, label: String, percentUsed: Int, display: String,
         resetsAt: Date?, amount: Double? = nil) {
        self.id = id; self.label = label; self.percentUsed = percentUsed
        self.display = display; self.resetsAt = resetsAt; self.amount = amount
    }
}

// OpenRouter low-credit alert threshold ($). 0 = off.
enum NotifyPrefs {
    static var threshold: Double {
        (UserDefaults.standard.object(forKey: "or.threshold") as? Double) ?? 5
    }
}

enum ProviderState: Equatable {
    case loading
    case ok([Metric])
    case noAuth          // no credentials found
    case expired         // local token past expiry
    case unauthorized    // 401
    case rateLimited     // 429
    case schemaMismatch  // 200 but unparseable, or 400/403/404 (endpoint changed)
    case serverError(Int)
    case networkError(String)
}

protocol UsageProvider: Sendable {
    var id: String { get }            // "claude" | "codex" | "openrouter"
    var displayName: String { get }
    var logoAsset: String { get }     // Resources/<name>.pdf|png, monochrome
    func fetch() async -> ProviderState
}

enum Http {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func get(_ url: URL, headers: [String: String]) async -> (status: Int, data: Data)? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return nil }
            return (http.statusCode, data)
        } catch { return nil }
    }
}

// Map an HTTP status + body to a ProviderState via the provider's parser.
func stateFor(status: Int, data: Data, parse: (Data) -> [Metric]?) -> ProviderState {
    switch status {
    case 200: return parse(data).map(ProviderState.ok) ?? .schemaMismatch
    case 401: return .unauthorized
    case 429: return .rateLimited
    case 400, 403, 404: return .schemaMismatch   // endpoint/header changed
    default: return .serverError(status)
    }
}

func formatRemaining(_ seconds: Int) -> String {
    let s = max(0, seconds)
    if s == 0 { return "now" }
    let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

// resets_at can be ISO ("...T06:00:00.989998+00:00") or unix epoch seconds.
func parseISODate(_ s: String) -> Date? {
    let cleaned = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: cleaned)
}

// Which menu bar icons are enabled, as "provider:metric" strings (e.g. "claude:5h").
enum MenuConfig {
    static let key = "menu.icons"
    static let defaultIcons = "claude:5h"

    static func icons() -> [String] {
        (UserDefaults.standard.string(forKey: key) ?? defaultIcons)
            .split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
    static func providers() -> Set<String> {
        Set(icons().compactMap { $0.split(separator: ":").first.map(String.init) })
    }
    static func isOn(_ icon: String) -> Bool { icons().contains(icon) }
    static func set(_ icons: [String]) {
        UserDefaults.standard.set(icons.joined(separator: ","), forKey: key)
    }
    static func toggle(_ icon: String, _ on: Bool) {
        var i = icons(); i.removeAll { $0 == icon }
        if on { i.append(icon) }
        set(i)
    }
}
