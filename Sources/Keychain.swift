import Foundation
import Security

enum KeychainError: Error, Equatable {
    case notFound        // Claude Code never logged in / not installed
    case accessDenied    // keychain locked, or ACL refused this binary
    case malformed       // item read but JSON/token shape unexpected
    case other(OSStatus)
}

struct ClaudeToken {
    let accessToken: String
    let expiresAt: Date
    let subscriptionType: String
}

enum Keychain {
    // The Claude Code CLI stores one generic-password item whose value is a JSON blob.
    // We only read it; we never write back (writing risks desyncing the CLI's token).
    static func readToken() -> Result<ClaudeToken, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: return .failure(.notFound)
        case errSecAuthFailed, errSecInteractionNotAllowed: return .failure(.accessDenied)
        default: return .failure(.other(status))
        }
        guard let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else {
            return .failure(.malformed)
        }
        let expiresMs = (oauth["expiresAt"] as? Double) ?? 0
        let sub = (oauth["subscriptionType"] as? String) ?? "unknown"
        return .success(ClaudeToken(
            accessToken: token,
            expiresAt: Date(timeIntervalSince1970: expiresMs / 1000),
            subscriptionType: sub))
    }
}
