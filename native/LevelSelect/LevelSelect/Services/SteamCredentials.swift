import Foundation
import Security

/// The player's own Steam Web API key and the profile it reads.
///
/// Same rules as `RACredentials`, for the same reasons. The key reads the
/// account's library and achievements and Valve's terms make it personal, so it
/// lives in the Keychain, `…ThisDeviceOnly`, never synced, and goes to
/// api.steampowered.com directly — never through our server, whose invocation
/// logs capture requests.
///
/// A key of LevelSelect's own behind the proxy was the other way to do this,
/// and is the one ruled out: every call would then carry a SteamID through our
/// infrastructure, which is exactly the user identity the device-direct rule
/// keeps off it.
enum SteamCredentials {
    struct Value: Equatable, Sendable {
        /// The 64-bit SteamID, as Steam writes it (17 digits). Stable across
        /// renames, unlike the custom profile name, so it is what calls use.
        var steamID: String
        var apiKey: String
        /// The display name Steam reported, shown so a connection is legible.
        var personaName: String?
    }

    private static let service = "com.timultuoustimes.levelselect.steam"
    private static let account = "webApiKey"
    private static let steamIDKey = "steam.id"
    private static let personaKey = "steam.persona"

    /// The SteamID and name are not secrets; only the key is in the Keychain.
    static var current: Value? {
        guard let steamID = UserDefaults.standard.string(forKey: steamIDKey),
              !steamID.isEmpty,
              let apiKey = readKey(), !apiKey.isEmpty
        else { return nil }
        return Value(steamID: steamID, apiKey: apiKey,
                     personaName: UserDefaults.standard.string(forKey: personaKey))
    }

    static var isConfigured: Bool { current != nil }

    @discardableResult
    static func save(_ value: Value) -> Bool {
        let steamID = value.steamID.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = value.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !steamID.isEmpty, !key.isEmpty else { return false }
        // Key first, as in RACredentials: the other order can leave a new
        // profile beside the previous key if the Keychain write fails.
        guard writeKey(key) else { return false }
        UserDefaults.standard.set(steamID, forKey: steamIDKey)
        if let name = value.personaName, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: personaKey)
        } else {
            UserDefaults.standard.removeObject(forKey: personaKey)
        }
        return true
    }

    /// False when the Keychain refused, so the caller can say "still
    /// connected" instead of showing a disconnected screen over a live key.
    @discardableResult
    static func clear() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { return false }
        UserDefaults.standard.removeObject(forKey: steamIDKey)
        UserDefaults.standard.removeObject(forKey: personaKey)
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
        let updated = SecItemUpdate(baseQuery() as CFDictionary, [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
