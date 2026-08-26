import Foundation

/// Where RetroAchievements' own art lives, and how the app asks for it.
///
/// Badge and icon URLs are public and carry no credentials, so they load
/// through ordinary AsyncImage with the shared URL cache — the same treatment
/// covers get — rather than the ephemeral credential session.
enum RAArt {
    /// Badge art for one achievement. RA serves every badge in two states:
    /// full colour and a greyed "_lock" variant. Using their locked art for
    /// unearned rows means nothing unearned can ever look earned.
    static func badgeURL(_ badge: String, earned: Bool) -> URL? {
        URL(string: "https://media.retroachievements.org/Badge/\(badge)\(earned ? "" : "_lock").png")
    }

    /// Site-relative image paths ("/Images/067895.png") → absolute.
    static func mediaURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://retroachievements.org\(path)")
    }

    static func gamePage(_ gameID: Int) -> URL {
        URL(string: "https://retroachievements.org/game/\(gameID)")!
    }

    static func profilePage(username: String) -> URL? {
        guard var components = URLComponents(string: "https://retroachievements.org") else { return nil }
        components.path = "/user/\(username)"
        return components.url
    }
}

/// The mastery wall, cached so Stats doesn't hit RA on every appearance.
///
/// Application Support, not the store: it's a redrawable mirror of RA's own
/// records, per-device on purpose — the credential that fetches it is
/// per-device too.
@MainActor
enum RAAwardsCache {
    private static let staleAfter: TimeInterval = 24 * 60 * 60

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ra-awards.json")
    }

    struct Stored: Codable {
        let fetchedAt: Date
        let awards: [RetroAchievementsService.Award]
    }

    static func load() -> Stored? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static var isStale: Bool {
        guard let stored = load() else { return true }
        return Date().timeIntervalSince(stored.fetchedAt) > staleAfter
    }

    static func save(_ awards: [RetroAchievementsService.Award]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(Stored(fetchedAt: Date(), awards: awards))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Disconnecting RA should take the wall with it.
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
