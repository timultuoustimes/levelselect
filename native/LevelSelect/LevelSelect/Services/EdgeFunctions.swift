import Foundation

/// Shared setup for calls to the Supabase edge functions (IGDB proxy, AI
/// tracker generator, map finder).
///
/// Those functions run without a Supabase auth session, so the server guards
/// them with an app key plus per-install quotas. This adds the two headers
/// that make that work:
///
///   x-ls-app-key  — shared secret, injected at build time from the gitignored
///                   `Secrets.xcconfig` (the repo is public). Absent in a
///                   clone without that file; the server also treats the key
///                   as optional until `LS_APP_SECRET` is set, so a build
///                   without it still works during rollout.
///   x-ls-install  — random per-install id, so one device's quota can't be
///                   burned by another. Not tied to the user or their iCloud
///                   account, and never leaves these three requests.
enum EdgeFunctions {
    /// Build-time key from `LSAppKey` in Info.plist. Empty/missing → nil.
    ///
    /// iOS/macOS only: the watch target generates its Info.plist without this
    /// key, and makes no edge-function calls of its own.
    static let appKey: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LSAppKey") as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }()

    /// Stable random id for this install. Deliberately not the iCloud user or
    /// the device id — it exists only to scope server-side rate limits.
    static let installID: String = {
        let key = "ls.installID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()

    /// Apply the shared headers to an edge-function request.
    static func authorize(_ request: inout URLRequest) {
        if let appKey { request.setValue(appKey, forHTTPHeaderField: "x-ls-app-key") }
        request.setValue(installID, forHTTPHeaderField: "x-ls-install")
    }
}
