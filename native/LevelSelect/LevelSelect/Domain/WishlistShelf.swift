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
    /// Which shelf a wanted game belongs on.
    ///
    /// Three, not two. Tim, 2026-08-31: *"For new games within 2026 or later
    /// with just a year, those are going to have announcement days and should
    /// have a category of their own."* He is right — a game with a date and a
    /// game merely promised this year are not the same kind of waiting, and
    /// folding them together made "Coming soon" claim five games when one of
    /// them was a February release and another had no date at all.
    enum Shelf {
        /// A real date, still ahead. The countdown case.
        case comingSoon
        /// Announced, but nobody has said when. IGDB carries the year alone.
        case noDateYet
        /// Out in the world.
        case outNow
    }

    /// See `MetadataRefresh.isYearOnly` — date precision lives there.
    static func isYearOnly(_ date: Date, calendar: Calendar = .current) -> Bool {
        MetadataRefresh.isYearOnly(date, calendar: calendar)
    }

    /// A calendar whose day boundaries match how release dates are stamped.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    static func shelf(for game: Game, now: Date = .now,
                      calendar: Calendar = .current) -> Shelf {
        guard let date = game.firstReleaseDate, !MetadataRefresh.isMissing(date) else {
            // No date at all is not a promise of one.
            return .outNow
        }
        if isYearOnly(date) {
            // UTC on both sides, for the same reason `awaitsAnnouncedDate`
            // needs it: a 1 January placeholder is stored at UTC midnight and
            // reads as the previous year in any western timezone, which filed
            // this year's unannounced games under "Out now".
            let utc = ReleaseCountdown.utc
            return utc.component(.year, from: date)
                >= utc.component(.year, from: now) ? .noDateYet : .outNow
        }
        return date > now ? .comingSoon : .outNow
    }

    /// A real date, still ahead — soonest first, because that is the order you
    /// will experience them in.
    static func comingSoon(_ games: [Game], now: Date = .now) -> [Game] {
        games.filter { shelf(for: $0, now: now) == .comingSoon }
            .sorted { ($0.firstReleaseDate ?? .distantFuture) < ($1.firstReleaseDate ?? .distantFuture) }
    }

    /// Announced, no date. Alphabetical, because there is no other order —
    /// sorting by a 1 January placeholder would be sorting by nothing.
    static func noDateYet(_ games: [Game], now: Date = .now) -> [Game] {
        games.filter { shelf(for: $0, now: now) == .noDateYet }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Out in the world, and yours whenever you decide.
    static func outNow(_ games: [Game], now: Date = .now) -> [Game] {
        games.filter { shelf(for: $0, now: now) == .outNow }
    }

    /// Exactly as much as is known, and no more.
    ///
    /// Only ever called for the dated shelf now, so it never has to print a
    /// year-only placeholder — but it still refuses to claim a day, because
    /// `firstReleaseDate` carries no precision flag and IGDB's own answer can
    /// be a month.
    static func releaseLabel(_ date: Date, calendar: Calendar = .current) -> String {
        if isYearOnly(date) {
            return String(calendar.component(.year, from: date))
        }
        // Formatted in UTC, because a release date is a CALENDAR DATE and not
        // an instant. IGDB stamps them at UTC midnight, so rendering in a
        // western timezone walks them back a day — Resident Evil Requiem
        // launched on 27 February and the wishlist printed "Feb 26, 2026".
        return date.formatted(Date.FormatStyle(timeZone: .gmt)
            .month(.abbreviated).day().year())
    }

    /// See `ReleaseCountdown` — shared with the widgets so the shelf and the
    /// Home Screen can never count to different days.
    static func countdown(to date: Date, from now: Date = .now) -> String? {
        ReleaseCountdown.countdown(to: date, from: now)
    }

    static let countdownHorizon = ReleaseCountdown.horizon
}
