import Foundation

/// What the app knows about a release date, in the one place both targets can
/// read it.
///
/// The rules already existed, in `MetadataRefresh` and `WishlistShelf` — but
/// those live in Domain, which the widget extension does not compile. A
/// releases widget that counted down differently from the wishlist beside it
/// would be worse than no widget, and the way that happens is two copies of
/// "is this a placeholder" drifting apart. So the rules moved here, where the
/// app and the widgets share them, and Domain delegates rather than repeats.
enum ReleaseCountdown {
    /// A calendar whose day boundaries match how release dates are stamped.
    ///
    /// IGDB stamps them at UTC midnight, so a western timezone walks them back
    /// a day — Resident Evil Requiem launched on 27 February and the wishlist
    /// printed "Feb 26, 2026" until this was fixed.
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    /// A date near the epoch is missing data wearing a date's clothes.
    static let epochArtifactWindow: TimeInterval = 172_800

    static func isMissing(_ date: Date?) -> Bool {
        guard let date else { return true }
        return abs(date.timeIntervalSince1970) < epochArtifactWindow
    }

    /// BOTH ends of the year are placeholders. 1 January is the app's own
    /// shorthand for "the year is all we know"; **31 December is IGDB's** — it
    /// pads a year-only or fourth-quarter release to the last day of the
    /// period. A game genuinely launching on either day is misfiled as
    /// year-only, and that trade is deliberate: the cost is showing "2026"
    /// instead of a day, against promising a launch date nobody has given.
    static func isYearOnly(_ date: Date) -> Bool {
        let parts = utc.dateComponents([.month, .day], from: date)
        return (parts.month == 1 && parts.day == 1)
            || (parts.month == 12 && parts.day == 31)
    }

    /// How long until it lands — "Tomorrow", "in 6 days", "in 3 weeks".
    ///
    /// Counted in whole UTC days, not by subtracting instants. A release is a
    /// calendar date, so "Tomorrow" has to mean the next date on the calendar
    /// rather than a point 24 hours away — otherwise a game landing tomorrow
    /// morning reads as "Today" all of this evening.
    ///
    /// `nil` for a date that has passed, and for a year-only placeholder:
    /// counting to 31 December would invent a precision the app refuses
    /// everywhere else.
    static func countdown(to date: Date, from now: Date = .now) -> String? {
        guard !isMissing(date), !isYearOnly(date) else { return nil }
        let today = utc.startOfDay(for: now)
        let landing = utc.startOfDay(for: date)
        guard let days = utc.dateComponents([.day], from: today, to: landing).day,
              days >= 0 else { return nil }
        switch days {
        case 0:      return "Today"
        case 1:      return "Tomorrow"
        case 2...13: return "in \(days) days"
        case 14...59:
            let weeks = days / 7
            return "in \(weeks) week\(weeks == 1 ? "" : "s")"
        default:
            let months = max(2, Int((Double(days) / 30.44).rounded()))
            return "in \(months) months"
        }
    }

    /// Whole days until it lands, or nil if it already has.
    static func days(until date: Date, from now: Date = .now) -> Int? {
        guard let d = utc.dateComponents([.day],
                                         from: utc.startOfDay(for: now),
                                         to: utc.startOfDay(for: date)).day,
              d >= 0 else { return nil }
        return d
    }

    /// How near a countdown stays useful.
    ///
    /// "in 6 days" tells you something you would act on; "in 11 months" tells
    /// you less than the date does, and a wishlist full of them reads as a
    /// page of vague waiting. Past this, the shelf prints the date it knows.
    static let horizon = 60

    /// Exactly as much as is known, and no more.
    static func dateLabel(_ date: Date) -> String {
        if isYearOnly(date) { return String(utc.component(.year, from: date)) }
        return date.formatted(Date.FormatStyle(timeZone: .gmt)
            .month(.abbreviated).day().year())
    }
}
