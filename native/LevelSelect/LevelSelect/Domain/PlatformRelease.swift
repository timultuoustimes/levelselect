import Foundation

/// When a game lands, per platform.
///
/// Schema V4's Option B: *"out on PC, coming to Switch 2"* is one game with
/// two true answers, and `firstReleaseDate` can only hold one. Storing them
/// all means the app stops having to pick a winner — and picking a winner is
/// what made a game's date depend on a platform the user may never have
/// chosen.
///
/// Read back through `Game.platformReleases`. `firstReleaseDate` remains the
/// single answer the shelf, the countdown and the widgets use; this is the
/// fuller record behind it.
struct StoredPlatformRelease: Codable, Hashable, Sendable {
    /// IGDB's platform name, verbatim — matched with `PlatformIcon.consoleKey`
    /// like everywhere else, so "Nintendo Switch" and "Switch" agree.
    var platform: String
    var date: Date
    /// Whether that date is a real day or a padded placeholder. Stored rather
    /// than re-derived: `isYearOnly` can only see 1 January and 31 December,
    /// and IGDB's own answer is better than that guess when we have it.
    var hasDay: Bool
}

extension Game {
    /// The stored per-platform dates, newest write wins.
    var platformReleases: [StoredPlatformRelease] {
        get {
            guard let data = platformReleasesData else { return [] }
            return (try? JSONDecoder().decode([StoredPlatformRelease].self, from: data)) ?? []
        }
        set {
            platformReleasesData = newValue.isEmpty
                ? nil
                : try? JSONEncoder().encode(newValue)
        }
    }

    /// The date for one platform, if the game has one.
    ///
    /// Matched on `consoleKey` rather than string equality, because the app
    /// carries "Switch 2" where IGDB says "Nintendo Switch 2" and both must
    /// find the same row.
    func releaseDate(on platform: String?) -> StoredPlatformRelease? {
        guard let platform else { return nil }
        let key = PlatformIcon.consoleKey(platform)
        return platformReleases.first { PlatformIcon.consoleKey($0.platform) == key }
    }

    /// The soonest platform release that names a real day.
    ///
    /// What the app should say when you have not chosen a platform: every
    /// platform saying 4 September is a better answer than IGDB's own summary
    /// saying "2026".
    var earliestAnnouncedRelease: StoredPlatformRelease? {
        platformReleases
            .filter { $0.hasDay && !ReleaseCountdown.isYearOnly($0.date) }
            .min { $0.date < $1.date }
    }

    /// The date this game has FOR YOU.
    ///
    /// Resolved when read, not when written, which is the point of storing
    /// them all: change the platform you own a game on and its date follows,
    /// with no refetch and no dependence on what IGDB happened to say the day
    /// it was added.
    ///
    /// Order: the platform you chose — **whatever it says** — then the
    /// soonest announced day across every platform, then `firstReleaseDate`,
    /// which is what every game written before V4 has and all a manually
    /// added one will ever have.
    ///
    /// A chosen platform wins even when its date is vague, and that ordering
    /// is the point rather than an oversight. Falling through to another
    /// platform's precise day would answer a question nobody asked: if you
    /// own it on Switch 2 and Switch 2 has no announced day, "nobody has said
    /// when your copy arrives" is the true answer and PC's 4 September is a
    /// date for somebody else's copy. That is the same borrowed-date mistake
    /// a guessed platform was making before V4 existed.
    var effectiveReleaseDate: Date? {
        if let mine = releaseDate(on: chosenPlatform) { return mine.date }
        if let soonest = earliestAnnouncedRelease { return soonest.date }
        return firstReleaseDate
    }

    /// Platforms this game is still coming to, soonest first.
    ///
    /// The point of storing them all: a game can be out on one machine and
    /// months away on another, and until now the app could only say one of
    /// those things.
    func upcomingReleases(now: Date = .now) -> [StoredPlatformRelease] {
        platformReleases
            .filter { $0.hasDay && !ReleaseCountdown.isYearOnly($0.date) && $0.date > now }
            .sorted { $0.date < $1.date }
    }
}
