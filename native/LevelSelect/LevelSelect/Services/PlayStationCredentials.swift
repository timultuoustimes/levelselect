import Foundation

/// The PlayStation sign-in LevelSelect keeps: a refresh token, not the NPSSO.
///
/// The NPSSO someone pastes works like their password, so it is exchanged with
/// Sony once and never stored. What stays is the refresh token that exchange
/// returns — in the Keychain, this device only, never synced, sent only to
/// Sony. It expires after about two months, and then the answer is to connect
/// again.
enum PlayStationCredentials {
    struct Value: Equatable, Sendable {
        var refreshToken: String
        var refreshExpiry: Date?
        /// Sony's account id, shown so a connection is legible.
        var accountID: String?
    }

    private static let secret = KeychainSecret(
        service: "com.timultuoustimes.levelselect.playstation", account: "refreshToken")
    private static let expiryKey = "psn.refreshExpiry"
    private static let accountKey = "psn.accountID"

    static var current: Value? {
        guard let token = secret.read(), !token.isEmpty else { return nil }
        return Value(refreshToken: token,
                     refreshExpiry: UserDefaults.standard.object(forKey: expiryKey) as? Date,
                     accountID: UserDefaults.standard.string(forKey: accountKey))
    }

    static var isConfigured: Bool { current != nil }

    @discardableResult
    static func save(_ value: Value) -> Bool {
        guard !value.refreshToken.isEmpty, secret.write(value.refreshToken) else { return false }
        UserDefaults.standard.set(value.refreshExpiry, forKey: expiryKey)
        UserDefaults.standard.set(value.accountID, forKey: accountKey)
        return true
    }

    @discardableResult
    static func clear() -> Bool {
        guard secret.delete() else { return false }
        UserDefaults.standard.removeObject(forKey: expiryKey)
        UserDefaults.standard.removeObject(forKey: accountKey)
        return true
    }
}
