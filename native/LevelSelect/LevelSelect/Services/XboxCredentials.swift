import Foundation

/// The Xbox sign-in LevelSelect keeps: Microsoft's refresh token.
///
/// Sign-in happens on Microsoft's own page, so the password never reaches the
/// app. The refresh token stays in the Keychain, this device only, never
/// synced, and goes only to Microsoft and Xbox. The gamertag and Xbox user id
/// are labels and live in UserDefaults.
enum XboxCredentials {
    struct Value: Equatable, Sendable {
        var refreshToken: String
        var gamertag: String?
        var xuid: String?
    }

    private static let secret = KeychainSecret(
        service: "com.timultuoustimes.levelselect.xbox", account: "refreshToken")
    private static let gamertagKey = "xbox.gamertag"
    private static let xuidKey = "xbox.xuid"

    static var current: Value? {
        guard let token = secret.read(), !token.isEmpty else { return nil }
        return Value(refreshToken: token,
                     gamertag: UserDefaults.standard.string(forKey: gamertagKey),
                     xuid: UserDefaults.standard.string(forKey: xuidKey))
    }

    static var isConfigured: Bool { current != nil }

    @discardableResult
    static func save(_ value: Value) -> Bool {
        guard !value.refreshToken.isEmpty, secret.write(value.refreshToken) else { return false }
        UserDefaults.standard.set(value.gamertag, forKey: gamertagKey)
        UserDefaults.standard.set(value.xuid, forKey: xuidKey)
        return true
    }

    @discardableResult
    static func clear() -> Bool {
        guard secret.delete() else { return false }
        UserDefaults.standard.removeObject(forKey: gamertagKey)
        UserDefaults.standard.removeObject(forKey: xuidKey)
        return true
    }
}
