import Foundation

/// What the Home header says about you.
///
/// Three numbers, chosen because each one moves. Tim's cut of an earlier
/// four-stat band: "174 games" and "5 finished" are the two that look identical
/// week after week, and a header that never changes is a header nobody reads
/// twice. Playing, this week and total all answer *how it's going*.
///
/// Computed from the `[Game]` Home already queries rather than fetching
/// sessions separately — the relationships are loaded, and walking them once
/// costs nothing next to a second round trip through the context.
struct PlayerSummary {
    /// Games with status `.playing`, matching the Now Playing shelf's count.
    var playing: Int = 0
    var weekSeconds: TimeInterval = 0
    var totalSeconds: TimeInterval = 0

    /// Cover art for the games played in the last seven days, most recently
    /// played first — the backdrop's raw material.
    var recentCovers: [String] = []

    /// One game's art, for when the week is too quiet to build a backdrop
    /// from. The game you're on now, or failing that the last one you touched.
    var fallbackBackdrop: String?

    /// Below this, a ribbon reads as a mistake rather than a pattern — two
    /// covers tilted behind a portrait look like a layout bug. Fall back to
    /// one game's artwork instead, which is a composition rather than a gap.
    static let minimumRibbon = 3

    var usesRibbon: Bool { recentCovers.count >= Self.minimumRibbon }

    static func make(from games: [Game], now: Date = .now) -> PlayerSummary {
        var summary = PlayerSummary()
        let weekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)

        // (game, most recent session start) for anything played this week.
        var recent: [(game: Game, at: Date)] = []

        for game in games {
            if game.status == .playing { summary.playing += 1 }

            var latestThisWeek: Date?
            for playthrough in game.livePlaythroughs {
                for session in (playthrough.sessions ?? []) where session.deletedAt == nil {
                    let seconds = session.elapsed(asOf: now)
                    summary.totalSeconds += seconds
                    if session.startDate >= weekAgo {
                        summary.weekSeconds += seconds
                        if session.startDate > (latestThisWeek ?? .distantPast) {
                            latestThisWeek = session.startDate
                        }
                    }
                }
            }
            if let at = latestThisWeek { recent.append((game, at)) }
        }

        summary.recentCovers = recent
            .sorted { $0.at > $1.at }
            .compactMap { $0.game.displayCoverURLString }

        // Whatever is being played that HAS art — not merely whatever is
        // being played.
        //
        // `first(where: status == .playing)` looked right and was wrong: it
        // took the first playing game even when that game had no artwork at
        // all, so the header rendered empty while a shelf full of covers sat
        // underneath it. Anyone whose current game was added by hand saw a
        // blank header and no reason why.
        let playing = games.filter { $0.status == .playing }
        let mostRecent = recent.max(by: { $0.at < $1.at })?.game
        // Most recently PLAYED first, not first-in-the-list.
        //
        // `playing.compactMap(\.backdropURLString).first` took whichever
        // playing game the query happened to hand over first — the array is
        // sorted by name — so with eleven games in progress the header showed
        // an alphabetical accident. Tim, 08-31: the backdrop was a game he
        // had not played this week, while the one he had just played sat in
        // Continue Playing directly beneath it.
        //
        // The header is about how it is going, so it leads with the game you
        // last actually touched, and only falls back to "something you are
        // playing" when nothing has been played this week at all.
        summary.fallbackBackdrop =
            mostRecent?.backdropURLString
            ?? mostRecent?.displayCoverURLString
            ?? playing.compactMap(\.backdropURLString).first
            ?? playing.compactMap(\.displayCoverURLString).first

        return summary
    }
}
