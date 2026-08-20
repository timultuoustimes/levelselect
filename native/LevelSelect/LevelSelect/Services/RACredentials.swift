import Foundation
import Security

/// The user's own RetroAchievements credentials.
///
/// Their Web API key is a password-equivalent — it reads their whole account —
/// so it lives in the Keychain rather than UserDefaults, which is a plist any
/// backup or file-container pull can read. (This project has pulled that exact
/// plist off a device to debug sync, which is precisely the argument.)
///
/// Deliberately NOT synced. `kSecAttrSynchronizable` is left off, so the key
/// stays on the device it was entered on and never rides iCloud Keychain. The
/// server never stores it either — it's sent per request and used to call RA
/// as the user, so RA sees their own account doing the reading.
///
/// Entering it on the iPad as well as the phone is a small cost for a key
/// that never leaves the device it was typed into.
enum RACredentials {
    struct Value: Equatable, Sendable {
        var username: String
        var apiKey: String
    }

    private static let service = "com.timultuoustimes.levelselect.retroachievements"
    private static let account = "webApiKey"
    private static let usernameKey = "ra.username"

    /// The username is not a secret and is shown in Settings, so it sits in
    /// UserDefaults; only the key goes in the Keychain.
    static var current: Value? {
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              !username.isEmpty,
              let apiKey = readKey(), !apiKey.isEmpty
        else { return nil }
        return Value(username: username, apiKey: apiKey)
    }

    static var isConfigured: Bool { current != nil }

    @discardableResult
    static func save(_ value: Value) -> Bool {
        let username = value.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = value.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !key.isEmpty else { return false }
        UserDefaults.standard.set(username, forKey: usernameKey)
        return writeKey(key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        // Update in place when it's already there; SecItemAdd would fail with
        // errSecDuplicateItem and silently leave the old key behind, which is
        // the worst outcome — the user changes their key and nothing changes.
        let updated = SecItemUpdate(baseQuery() as CFDictionary,
                                    [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }

        var query = baseQuery()
        query[kSecValueData as String] = data
        // Available after first unlock, not while locked: a background refresh
        // shouldn't fail just because the phone is in a pocket. Not synced.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
