import Foundation
import Security

// Our own generic-password items (e.g. the OpenRouter key entered in Settings).
enum KeychainStore {
    private static func service(_ name: String) -> String { "com.edvard.claudelimits.\(name)" }

    static func read(_ name: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service(name),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    static func write(_ name: String, _ value: String) {
        let svc = service(name)
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
        ] as CFDictionary)
        guard !value.isEmpty else { return }
        SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecValueData as String: Data(value.utf8),
        ] as CFDictionary, nil)
    }
}
