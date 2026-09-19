import Foundation
import Security

/// The user's itch.io OAuth token.
///
/// Same rules as `RACredentials`, and for the same reason: this token reads
/// their library, so it is password-equivalent and lives in the Keychain
/// rather than UserDefaults — a plist any backup or file-container pull can
/// read. This project has pulled that exact plist off a device to debug sync,
/// which is precisely the argument.
///
/// **Not synced.** `kSecAttrSynchronizable` is left off so it never rides
/// iCloud Keychain, and `...ThisDeviceOnly` keeps it out of encrypted backups
/// too. Connecting on the iPad as well as the phone is the cost of that.
///
/// **Never proxied.** itch.io is called device-direct, the way RetroAchievements
/// is — the edge function's invocation logs capture request headers, so routing
/// a bearer token through it would write a password-equivalent into platform
/// telemetry on every sync.
///
/// The token itself is opaque and long-lived: itch's implicit flow issues no
/// refresh token, so a revoked or expired token surfaces as a 401 and the
/// answer is to connect again rather than to renew anything.
enum ItchCredentials {
    struct Value: Equatable, Sendable {
        var token: String
        /// Who the token belongs to, shown so a connected account is legible.
        /// Purely a label — every call authenticates with the token.
        var username: String?
    }

    private static let service = "com.timultuoustimes.levelselect.itch"
    private static let account = "oauthToken"
    private static let usernameKey = "itch.username"

    static var current: Value? {
        guard let token = readToken(), !token.isEmpty else { return nil }
        return Value(token: token,
                     username: UserDefaults.standard.string(forKey: usernameKey))
    }

    static var isConfigured: Bool { current != nil }

    @discardableResult
    static func save(_ value: Value) -> Bool {
        let token = value.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return false }
        // Token first, label second — the other order can leave a device
        // showing "connected as X" beside a previous account's token.
        guard writeToken(token) else { return false }
        if let name = value.username, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: usernameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: usernameKey)
        }
        return true
    }

    /// False when the Keychain item could not be removed, so a caller can say
    /// "still connected" rather than showing a disconnected screen over a
    /// token that is still on the device.
    @discardableResult
    static func clear() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { return false }
        UserDefaults.standard.removeObject(forKey: usernameKey)
        return true
    }

    // MARK: Keychain

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery() as CFDictionary)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
