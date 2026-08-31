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
    /// IGDB year-only precision lands on **1 January**, so a date cannot
    /// always be compared as a day.
    ///
    /// The Ocarina of Time remake, added 2026-08-31: announced at the June
    /// Direct for "late 2026", no date confirmed, so IGDB carries the year
    /// alone — stored as 1 January 2026, which is eight months in the past.
    /// Compared as a day it read as already out, filed under "Out now", and
    /// the one genuinely awaited game on the wishlist was the one the feature
    /// failed to catch.
    ///
    /// A game with a confirmed date gets an exact date from IGDB — Resident
    /// Evil Requiem carries 27 February, Pragmata 17 April, and both correctly
    /// read as released. So **year-only is itself the signal**: it means
    /// nobody has announced a day, which for the current year or later means
    /// it is still ahead.
    static func isYearOnly(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return parts.month == 1 && parts.day == 1
    }

    /// Games still ahead of you, soonest first.
    ///
    /// "Real" excludes the epoch artifact the CSV import left on a third of
    /// the library — see `MetadataRefresh.isMissing(_:)`. A 1970 date is a
    /// missing date, and a missing date is not an announcement.
    static func comingSoon(_ games: [Game], now: Date = .now) -> [Game] {
        let thisYear = Calendar.current.component(.year, from: now)
        return games
            .filter { game in
                guard let date = game.firstReleaseDate,
                      !MetadataRefresh.isMissing(date) else { return false }
                if isYearOnly(date) {
                    // No day announced. This year or later is still ahead.
                    return Calendar.current.component(.year, from: date) >= thisYear
                }
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

    /// Exactly as much as is known, and no more.
    ///
    /// A year-only date prints as the year. Printing "January 2026" for a game
    /// arriving in November would be inventing a month out of a storage
    /// convention — the same mistake as printing a day, one level up.
    /// Otherwise month and year, never a day: `firstReleaseDate` carries no
    /// precision flag, so a day would claim more than the data holds.
    static func releaseLabel(_ date: Date, calendar: Calendar = .current) -> String {
        if isYearOnly(date) {
            return String(calendar.component(.year, from: date))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
