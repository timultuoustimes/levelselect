import Foundation

/// What the wishlist is, as opposed to a list of games you happen not to own.
///
/// Every other tab looks backwards. Home is what you are playing, Library is
/// what you have and how you feel about it, Stats is what you did. The
/// wishlist is the only forward-looking surface in the app — and it was
/// rendering as an undifferentiated grid, which is exactly what Library looks
/// like, so the one thing that made it different was invisible.
///
/// The split that makes it itself is already in the data: **some of these are
/// not out yet.** A game you could buy this afternoon and a game arriving in
/// February are different kinds of wanting, and only one of them is waiting.
enum WishlistShelf {
    /// Games with a real release date still in the future, soonest first.
    ///
    /// "Real" excludes the epoch artifact the CSV import left on a third of
    /// the library — see `MetadataRefresh.isMissing(_:)`. A 1970 date is a
    /// missing date, and a missing date is not an announcement.
    static func comingSoon(_ games: [Game], now: Date = .now) -> [Game] {
        games
            .filter { game in
                guard let date = game.firstReleaseDate,
                      !MetadataRefresh.isMissing(date) else { return false }
                return date > now
            }
            .sorted { ($0.firstReleaseDate ?? .distantFuture) < ($1.firstReleaseDate ?? .distantFuture) }
    }

    /// Everything else — out in the world, and yours whenever you decide.
    /// Includes games with no known date at all: "we don't know when" is not
    /// the same claim as "it's coming", and only one of those should sit under
    /// a heading promising a date.
    static func outNow(_ games: [Game], now: Date = .now) -> [Game] {
        let soon = Set(comingSoon(games, now: now).map(\.id))
        return games.filter { !soon.contains($0.id) }
    }

    /// Month and year, never a day.
    ///
    /// IGDB stores a year-only release as the 1st of January, and the app has
    /// no precision flag on `firstReleaseDate` to tell that apart from a game
    /// genuinely launching on New Year's Day. Printing "1 January 2026" would
    /// invent a precision the data does not have; "January 2026" is true
    /// either way. Same reasoning as `CompletionEvent.datePrecision`, solved
    /// by not asking the question.
    static func releaseLabel(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}
