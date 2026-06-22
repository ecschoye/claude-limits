import Foundation

enum FetchState: Equatable {
    case ok([UsageWindow])
    case expired           // local token past expiresAt, skipped the call
    case noToken           // keychain has no Claude Code item
    case keychainDenied    // keychain locked / ACL refused
    case unauthorized      // 401 even after a keychain re-read + retry
    case rateLimited       // 429
    case schemaMismatch    // 200 but the shape changed
    case serverError(Int)
    case networkError(String)
    case loading
}

enum UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func fetch(token: ClaudeToken) async -> FetchState {
        if Date() >= token.expiresAt { return .expired }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        // Probe established this single beta header is sufficient; no version/UA spoofing.
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("ClaudeLimits/0.1 (macOS)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return .networkError("no HTTP response")
            }
            switch http.statusCode {
            case 200:
                return UsageParse.parse(data).map(FetchState.ok) ?? .schemaMismatch
            case 401: return .unauthorized
            case 429: return .rateLimited
            default:  return .serverError(http.statusCode)
            }
        } catch {
            return .networkError((error as NSError).localizedDescription)
        }
    }
}
