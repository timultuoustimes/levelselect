import Foundation

/// Games you finished lately — Home's answer to what happens after the credits.
///
/// Tim, 08-31: *"I think home needs a 'recently completed' row, if you
/// recently beat a game within the last month?"* The gap is real. Beating a
/// game moves it out of Now Playing, and Home then has nothing to say about
/// it — the one moment the whole app is pointed at produces a disappearance.
enum RecentlyBeaten {
    /// A month. Long enough that a finish is still yours when you open the app
    /// a fortnight later, short enough that the shelf empties on its own and
    /// never becomes a second permanent "Finished" list — that pile is a fact
    /// about a collection and belongs in Library.
    static let window: TimeInterval = 30 * 24 * 60 * 60

    /// Most recently finished first.
    ///
    /// Fuzzy dates come along for free and correctly: a finish recorded as
    /// "August 2026" is stored inside the window and counts, while one
    /// recorded as "2011" is not and does not. See
    /// `CompletionEvent.datePrecision` — the app deliberately stores what you
    /// said rather than pretending to a day it never had.
    static func games(from games: [Game], now: Date = .now) -> [(game: Game, at: Date)] {
        let cutoff = now.addingTimeInterval(-window)
        return games.compactMap { game -> (game: Game, at: Date)? in
            let finishes = (game.completionEvents ?? [])
                .filter { $0.deletedAt == nil && $0.date >= cutoff && $0.date <= now }
            guard let latest = finishes.map(\.date).max() else { return nil }
            return (game, latest)
        }
        .sorted { $0.at > $1.at }
    }
}
