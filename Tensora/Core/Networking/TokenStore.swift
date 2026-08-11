import Foundation
import Security

/// Keychain-backed storage for the JWT pair issued by Django.
///
/// Tokens live in the keychain rather than `UserDefaults` so they survive
/// reinstall-free app updates without being readable from a backup.
final class TokenStore {

    private let service: String
    private let accessKey = "access-token"
    private let refreshKey = "refresh-token"

    init(service: String = "app.tensora.auth") {
        self.service = service
    }

    var accessToken: String? {
        get { read(accessKey) }
        set { write(newValue, for: accessKey) }
    }

    var refreshToken: String? {
        get { read(refreshKey) }
        set { write(newValue, for: refreshKey) }
    }

    var isSignedIn: Bool { accessToken != nil }

    func store(session: AuthSession) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
    }

    func clear() {
        write(nil, for: accessKey)
        write(nil, for: refreshKey)
    }

    // MARK: - Keychain

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func read(_ key: String) -> String? {
        var query = self.query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String?, for key: String) {
        let query = self.query(key)
        SecItemDelete(query as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(insert as CFDictionary, nil)
    }
}
