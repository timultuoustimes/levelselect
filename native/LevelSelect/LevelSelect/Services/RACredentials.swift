import Foundation
import Security

/// The user's own RetroAchievements credentials.
///
/// Their Web API key is a password-equivalent — it reads their whole account —
/// so it lives in the Keychain rather than UserDefaults, which is a plist any
/// backup or file-container pull can read. (This project has pulled that exact
/// plist off a device to debug sync, which is precisely the argument.)
///
/// Deliberately NOT synced: `kSecAttrSynchronizable` is left off, so it never
/// rides iCloud Keychain, and `...ThisDeviceOnly` accessibility keeps it out of
/// encrypted backups too. Plain `AfterFirstUnlock` would still have migrated
/// through a backup to a restored device — "stays on this device" has to mean
/// that literally or not be claimed.
///
/// It also never reaches our own server. It used to be proxied through the
/// Supabase edge function, whose invocation logs capture request bodies AND
/// headers — so every connect and sync was writing a password-equivalent into
/// platform telemetry. User-scoped calls now go device → RetroAchievements
/// directly; see `RetroAchievementsService.callRA`.
///
/// Entering it on the iPad as well as the phone is the cost of that.
enum RACredentials {
    struct Value: Equatable, Sendable {
        var username: String
        var apiKey: String
        /// RA's stable id for this account. Their docs say the username "is
        /// not considered a stable value" — it has been changeable since 2025,
        /// and every user-scoped endpoint takes a ULID in its place. Stored so
        /// a rename on RA doesn't quietly break sync months later; the
        /// username is kept only to show who's connected.
        var ulid: String?
    }

    private static let service = "com.timultuoustimes.levelselect.retroachievements"
    private static let account = "webApiKey"
    private static let usernameKey = "ra.username"
    private static let ulidKey = "ra.ulid"

    /// The username is not a secret and is shown in Settings, so it sits in
    /// UserDefaults; only the key goes in the Keychain.
    static var current: Value? {
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              !username.isEmpty,
              let apiKey = readKey(), !apiKey.isEmpty
        else { return nil }
        return Value(username: username, apiKey: apiKey,
                     ulid: UserDefaults.standard.string(forKey: ulidKey))
    }

    static var isConfigured: Bool { current != nil }

    @discardableResult
    static func save(_ value: Value) -> Bool {
        let username = value.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = value.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty, !key.isEmpty else { return false }
        // Key FIRST, metadata second. The other order leaves a device holding
        // a new username and ULID beside the previous key if the Keychain
        // write fails — a mixed state that reads as "connected as X" while
        // authenticating as Y.
        guard writeKey(key) else { return false }
        UserDefaults.standard.set(username, forKey: usernameKey)
        if let ulid = value.ulid, !ulid.isEmpty {
            UserDefaults.standard.set(ulid, forKey: ulidKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ulidKey)
        }
        return true
    }

    /// Returns false when the Keychain item could not be removed, so the
    /// caller can say "still connected" rather than showing a disconnected UI
    /// over a key that is still on the device.
    @discardableResult
    static func clear() -> Bool {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: ulidKey)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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
        // Only "there was nothing to update" justifies adding. Falling through
        // on ANY error meant a locked or otherwise unavailable item became an
        // add that failed as a duplicate — reported as failure, but only after
        // the caller had already been told to trust the new value.
        guard updated == errSecItemNotFound else { return false }

        var query = baseQuery()
        query[kSecValueData as String] = data
        // After first unlock so a background refresh works with the phone in a
        // pocket; ThisDeviceOnly so it never migrates through a backup.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
