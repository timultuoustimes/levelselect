import Foundation

/// **A year, a quarter or a month of your own library, read back to you.**
///
/// Spotify-Wrapped-shaped and built entirely on the device from records you
/// already own: no server sees any of it, which argues the privacy stance
/// rather than merely respecting it ([[LevelSelect stats expansion and
/// Replay]]).
///
/// One engine for all three cadences, because they differ only in the range
/// they read. A profile is this with no range at all, which is why nothing
/// here is named for a year.
///
/// **Presentation over the existing model — no new persistence.** Every
/// number below is a walk over sessions, completions and the badge ledger.
/// That also means a Replay is never wrong about the past: it is recomputed,
/// not remembered, and the badge dates that appear in it are the dates the
/// ledger recorded rather than the day an animation happened to play.
struct Replay {

    // MARK: The span

    /// Which cadence a replay covers. The date inside is any date within the
    /// period, not its first day — callers pass "now" and get the period
    /// containing it.
    enum Span: Equatable {
        case month(Date)
        case quarter(Date)
        case year(Date)
        /// **Every imported hour, on one page.** A year holding nothing but
        /// hours carried in from Steam used to get a page of its own, and one
        /// 5-hour range across 2018–2026 made eight empty ones (Fable, build
        /// 40 runtime, 09-21). Those hours now live here, each with the years
        /// you placed it in. A year that has anything else still shows its
        /// placed hours as a line of their own.
        case beforeTracking

        /// The period this span covers, in the given calendar.
        func interval(_ calendar: Calendar = .current) -> DateInterval {
            switch self {
            case .beforeTracking:
                // No days: nothing dated falls inside it.
                return DateInterval(start: .distantPast, duration: 0)
            case .month(let date):
                return calendar.dateInterval(of: .month, for: date)
                    ?? DateInterval(start: date, duration: 0)
            case .year(let date):
                return calendar.dateInterval(of: .year, for: date)
                    ?? DateInterval(start: date, duration: 0)
            case .quarter(let date):
                // `.quarter` is not a reliable component to take an interval
                // of on every calendar, so the quarter is built from its
                // three months — which is also what makes it correct for a
                // calendar whose year does not start in January.
                let month = calendar.component(.month, from: date)
                let firstMonth = ((month - 1) / 3) * 3 + 1
                var start = calendar.dateComponents([.year], from: date)
                start.month = firstMonth
                start.day = 1
                guard let from = calendar.date(from: start),
                      let to = calendar.date(byAdding: .month, value: 3, to: from) else {
                    return DateInterval(start: date, duration: 0)
                }
                return DateInterval(start: from, end: to)
            }
        }
    }

    // MARK: What it found

    /// One game and how long it had of the period.
    struct Played: Identifiable, Equatable {
        let id: UUID
        let name: String
        let seconds: TimeInterval
        let sessions: Int
    }

    /// One game finished inside the period, and the day it happened.
    struct Finish: Identifiable, Equatable {
        let id: UUID
        let name: String
        let date: Date
        /// The label you gave it — "Cleared", "100%" — rather than a verdict
        /// of the app's own.
        let label: String
        /// The date as precisely as it was recorded, and no more: a finish
        /// logged as "just the year" is "2015", never "Jan 1". The same
        /// renderer the game page uses (`CompletionEvent.fuzzyText`), so the
        /// two can't disagree (Fable, build 40 runtime, 09-21).
        var dateText: String = ""
        /// The console it was finished on, when the finish says.
        var platform: String?
    }

    var span: Span = .year(.now)
    var range = DateInterval(start: .distantPast, duration: 0)

    var totalSeconds: TimeInterval = 0
    var sessionCount = 0
    /// Distinct days with at least one session. "You played on 84 days" is a
    /// truer picture of a year than an hour count alone.
    var daysPlayed = 0
    var longestSession: TimeInterval = 0
    /// The day with the most play, and how much — nil for a period with none.
    var busiestDay: (day: Date, seconds: TimeInterval)?
    /// The game that filled the busiest day, and what day of the week it was
    /// — for "One long Saturday with Hollow Knight".
    var busiestDayGame: String?
    var busiestWeekday: String?

    var played: [Played] = []
    var finished: [Finish] = []
    /// Games added to the library inside the period.
    var added = 0
    var memoriesWritten = 0
    var badges: [Badges.Definition] = []

    /// Imported hours somebody attributed to this period by hand.
    ///
    /// **Kept apart from `totalSeconds` on purpose.** Steam reports one
    /// lifetime number with no dates; a person can say which year it was, and
    /// that is worth having — but it is a recollection, not a record, and it
    /// has no days in it. So it is named separately and never spread across
    /// the calendar, where it would put squares in a heatmap that nothing
    /// actually happened on.
    struct Carried: Identifiable, Equatable {
        let id: UUID
        /// The game the hours belong to — for its cover.
        var gameID: UUID? = nil
        let name: String
        let seconds: TimeInterval
        /// "2022", or "2021–2023" when the hours were placed across a range.
        /// A range says so on every year it touches, because the person said
        /// the span, not the year.
        let span: String
        var isRange: Bool { span.contains("–") }
    }
    var carried: [Carried] = []
    var carriedSeconds: TimeInterval { carried.reduce(0) { $0 + $1.seconds } }

    /// A period with nothing in it at all. Worth asking before presenting
    /// one: a recap of a month you didn't play is a reproach, not a gift.
    var isEmpty: Bool {
        sessionCount == 0 && finished.isEmpty && added == 0
            && memoriesWritten == 0 && carried.isEmpty
    }

    var gamesPlayedCount: Int { played.count }

    // MARK: Building one

    /// Everything a replay reads. Passed in rather than fetched so the engine
    /// stays a pure function of its inputs and can be tested without a store.
    struct Source {
        var games: [Game] = []
        var completions: [CompletionEvent] = []
        var memories: [Memory] = []
        /// Badge id → when it was earned, from the ledger.
        var badgeDates: [String: Date] = [:]
    }

    static func make(_ span: Span, from source: Source,
                     calendar: Calendar = .current, now: Date = .now) -> Replay {
        var replay = Replay()
        replay.span = span
        if span == .beforeTracking { return beforeTracking(source) }
        let range = span.interval(calendar)
        replay.range = range

        // Sessions, each counted whole in the period it began — see `overlap`.
        var perGame: [UUID: (name: String, seconds: TimeInterval, sessions: Int)] = [:]
        var perDay: [Date: TimeInterval] = [:]
        var perDayGame: [Date: [String: TimeInterval]] = [:]

        for game in source.games {
            for playthrough in game.livePlaythroughs {
                for session in (playthrough.sessions ?? []) where session.deletedAt == nil {
                    let seconds = overlap(session, with: range, now: now)
                    guard seconds > 0 else { continue }
                    replay.totalSeconds += seconds
                    replay.sessionCount += 1
                    replay.longestSession = max(replay.longestSession, seconds)

                    var entry = perGame[game.id] ?? (game.name, 0, 0)
                    entry.seconds += seconds
                    entry.sessions += 1
                    perGame[game.id] = entry

                    // Filed under the day it STARTED. A session that runs
                    // past midnight belongs to the evening you began it, the
                    // way anyone describing their night would say it.
                    let day = calendar.startOfDay(for: session.startDate)
                    perDay[day, default: 0] += seconds
                    perDayGame[day, default: [:]][game.name, default: 0] += seconds
                }
            }
        }

        replay.played = perGame
            .map { Played(id: $0.key, name: $0.value.name,
                          seconds: $0.value.seconds, sessions: $0.value.sessions) }
            .sorted { ($0.seconds, $0.name) > ($1.seconds, $1.name) }
        replay.daysPlayed = perDay.count
        if let busiest = perDay.max(by: { $0.value < $1.value }) {
            replay.busiestDay = (busiest.key, busiest.value)
            replay.busiestDayGame = perDayGame[busiest.key]?
                .max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
            replay.busiestWeekday = busiest.key.formatted(
                Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        }

        replay.finished = source.completions
            .filter { $0.deletedAt == nil && range.contains($0.date) }
            .compactMap { event in
                guard let game = event.game, game.deletedAt == nil else { return nil }
                return Finish(id: game.id, name: game.name, date: event.date,
                              label: event.labelText, dateText: event.dateText,
                              platform: event.platform)
            }
            .sorted { $0.date < $1.date }

        replay.added = source.games.filter {
            $0.deletedAt == nil && range.contains($0.addedAt)
        }.count

        replay.memoriesWritten = source.memories.filter {
            $0.deletedAt == nil && range.contains($0.createdAt)
        }.count

        // Hours somebody attributed to a year by hand. Only for a span that
        // is a whole year or contains one — a month cannot hold a claim whose
        // finest grain is a year without pretending to know more than it does.
        if case .year = span {
            let year = calendar.component(.year, from: range.start)
            for game in source.games where game.deletedAt == nil {
                for playthrough in game.livePlaythroughs {
                    for covering in playthrough.carriedOverSpans.covering(year)
                    where covering.seconds > 0 {
                        replay.carried.append(
                            Carried(id: covering.id, gameID: game.id, name: game.name,
                                    seconds: covering.seconds, span: covering.label))
                    }
                }
            }
            replay.carried.sort { ($0.seconds, $0.name) > ($1.seconds, $1.name) }
        }

        replay.badges = source.badgeDates
            .filter { range.contains($0.value) }
            .sorted { $0.value < $1.value }
            .compactMap { Badges.definition($0.key) }

        return replay
    }

    /// Every hour carried in from before tracking, each with the years it
    /// was placed in — and, where only part of a lump was placed, the rest
    /// as one line with no years.
    private static func beforeTracking(_ source: Source) -> Replay {
        var replay = Replay()
        replay.span = .beforeTracking
        for game in source.games where game.deletedAt == nil {
            for playthrough in game.livePlaythroughs where playthrough.carriedOverSeconds > 0 {
                for span in playthrough.carriedOverSpans where span.seconds > 0 {
                    replay.carried.append(Carried(id: span.id, gameID: game.id, name: game.name,
                                                  seconds: span.seconds, span: span.label))
                }
                let loose = playthrough.unattributedCarriedSeconds
                if loose > 0 {
                    replay.carried.append(Carried(id: playthrough.id, gameID: game.id, name: game.name,
                                                  seconds: loose, span: ""))
                }
            }
        }
        replay.carried.sort { ($0.seconds, $0.name) > ($1.seconds, $1.name) }
        return replay
    }

    /// How much of a session this period gets: **all of it, if it began
    /// here, and none of it otherwise.**
    ///
    /// This used to clip a session to the period by wall clock, so a session
    /// begun at 22:00 on New Year's Eve split two and two between the years.
    /// That was only right for a session played straight through, and the
    /// store cannot tell which ones were. A paused session has no end date, so
    /// its old time was spread from its start to *now* and leaked into every
    /// later month; a resumed one had its earlier segments smeared across the
    /// gap between them; and an edited one whose end preceded its start came
    /// back as zero despite a valid duration. Codex, build 40 static
    /// assessment, 2026-09-21.
    ///
    /// Attributing the whole session to the day it started is what Charts'
    /// By Month already does, so the two can no longer disagree, and it uses
    /// `elapsed` — the session's own authority on how long it lasted — without
    /// pretending to know where inside that span the play fell. Exact
    /// boundaries would need play segments stored as they happen: a schema
    /// change, and one Tim chose not to make (09-21).
    private static func overlap(_ session: Session, with range: DateInterval,
                                now: Date) -> TimeInterval {
        guard range.contains(session.startDate) else { return 0 }
        return max(0, session.elapsed(asOf: now))
    }
}

extension Replay.Span {
    /// What to call this period. The year is always there, because a replay
    /// is a thing you look back at.
    func title(_ calendar: Calendar = .current) -> String {
        if self == .beforeTracking { return "Before you tracked" }
        let start = interval(calendar).start
        let year = calendar.component(.year, from: start)
        switch self {
        case .year:
            return "\(year)"
        case .month:
            // **Formatted in the calendar's time zone, not the device's.**
            // A bare `.dateTime.month(.wide)` renders the first instant of a
            // month as the last evening of the month before wherever the
            // clock runs behind the calendar, so August's replay came out
            // titled "July". The locale stays the reader's; only the zone
            // comes from the calendar.
            let style = Date.FormatStyle(calendar: calendar,
                                         timeZone: calendar.timeZone).month(.wide)
            return "\(start.formatted(style)) \(year)"
        case .quarter:
            let quarter = (calendar.component(.month, from: start) - 1) / 3 + 1
            return "Q\(quarter) \(year)"
        case .beforeTracking:
            return "Before you tracked"
        }
    }

    /// The chip's label: "September" rather than "September 2026" for a month
    /// in the current year, where the year is noise. Everything else as
    /// `title`.
    func chipTitle(_ calendar: Calendar = .current, now: Date = .now) -> String {
        guard case .month = self else { return title(calendar) }
        let start = interval(calendar).start
        guard calendar.component(.year, from: start) == calendar.component(.year, from: now) else {
            return title(calendar)
        }
        return start.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide))
    }
}

// MARK: - The headline

extension Replay {
    /// **What leads the recap: the strongest true thing the period holds.**
    ///
    /// The hero was always the timed total, so a year holding only imported
    /// hours opened on "0s", and a year with a single finish opened on "0s"
    /// with "You kept the record even where you didn't play" directly above
    /// the finish (Fable, build 40 runtime, 09-21). A period is led by what it
    /// actually has.
    enum Lead: Equatable {
        /// Hours measured by sessions.
        case timed(TimeInterval)
        /// Imported hours the person placed in this period.
        case placed(TimeInterval)
        case finished(Int)
        case added(Int)
        case remembered(Int)
    }

    var lead: Lead? {
        if totalSeconds > 0 { return .timed(totalSeconds) }
        if carriedSeconds > 0 { return .placed(carriedSeconds) }
        if !finished.isEmpty { return .finished(finished.count) }
        if added > 0 { return .added(added) }
        if memoriesWritten > 0 { return .remembered(memoriesWritten) }
        return nil
    }

    /// **Whether this period gets a page of its own.** Anything dated —
    /// play, a finish, a game arriving, a memory — earns one. Imported hours
    /// alone do not: they have no days in them, and a year holding nothing
    /// else was an empty page with a number on it. Those hours are on the
    /// "Before you tracked" page instead (Fable's Replay mockup, 09-21).
    var offersOwnPage: Bool {
        sessionCount > 0 || !finished.isEmpty || added > 0 || memoriesWritten > 0
    }

    /// "year", "month", "quarter" — for "A badge this year".
    var periodWord: String {
        switch span {
        case .month: "month"
        case .quarter: "quarter"
        case .year: "year"
        case .beforeTracking: "time"
        }
    }

    /// **The one sentence, written as a remark rather than a readout** — and
    /// it changes shape because the data did (Fable's Replay mockup, 09-21):
    ///
    /// | When | It says |
    /// |---|---|
    /// | One day holds 60% of it, and was long | One long Saturday with *Hollow Knight*, and not much else. |
    /// | One game | All *Celeste*. |
    /// | Top game is 60% or more | Mostly *Hollow Knight*. |
    /// | Top two within 15% of each other, together most of it | *Hollow Knight* and *Hades*, about evenly. |
    /// | Otherwise | *Eleven* games, and *Stardew Valley* more than any. |
    /// | …plus a finish | …and you finished it. / …and you finished *Celeste*. |
    /// | A finish and no play | You finished *Chrono Trigger*. |
    ///
    /// "Mostly" needs 60%: it said "Mostly Hollow Knight" over a quarter
    /// where Hollow Knight was 29%. "About evenly" also needs the two to be
    /// most of the period, or eleven games with two close at the top would be
    /// described as a pair.
    var sentence: String {
        guard let top = played.first, totalSeconds > 0 else { return quietSentence }

        // Who the sentence is about, if it is about one game — so a finish of
        // that same game can be "it" rather than its name twice.
        var subject: String?
        var opener: String
        var trailer = "."

        if let day = busiestDay, let game = busiestDayGame, let weekday = busiestWeekday,
           // 60%, not the mockup's "over half": at 53% the other days held
           // nearly as much, and "not much else" was false.
           day.seconds >= totalSeconds * 0.6, day.seconds >= 3 * 3600 {
            opener = "One long \(weekday) with \(game)"
            subject = game
            trailer = ", and not much else."
        } else if played.count == 1 {
            opener = "All \(top.name)"
            subject = top.name
        } else if top.seconds / totalSeconds >= 0.6 {
            opener = "Mostly \(top.name)"
            subject = top.name
        } else if let second = played.dropFirst().first,
                  (top.seconds - second.seconds) / top.seconds <= 0.15,
                  (top.seconds + second.seconds) / totalSeconds >= 0.6 {
            opener = "\(top.name) and \(second.name), about evenly"
        } else {
            // "and" once: with a finish to follow, the first one goes, or it
            // read "Eleven games, and Stardew Valley more than any, and you
            // finished Hollow Knight."
            let joiner = finished.isEmpty ? ", and " : ", "
            opener = "\(Self.spelled(played.count, capitalized: true)) games\(joiner)\(top.name) more than any"
        }

        switch finished.count {
        case 0:
            return opener + trailer
        case 1:
            let finish = finished[0].name
            return opener + (finish == subject ? ", and you finished it." : ", and you finished \(finish).")
        default:
            return opener + ", and you finished \(Self.spelled(finished.count, capitalized: false)) games."
        }
    }

    /// A period with no play in it.
    private var quietSentence: String {
        if !finished.isEmpty {
            // Said plainly. "The year you finished Kirby" read as a caption
            // about a caption (Tim, 09-21); the period is already the page's
            // title.
            return finished.count == 1
                ? "You finished \(finished[0].name)."
                : "You finished \(Self.spelled(finished.count, capitalized: false)) games."
        }
        if let first = carried.first {
            return carried.count == 1 ? "\(first.name), from before you tracked it."
                                      : "\(Self.spelled(carried.count, capitalized: true)) games, from before you tracked them."
        }
        if added > 0 {
            return added == 1 ? "A game joined your library." : "\(Self.spelled(added, capitalized: true)) games joined your library."
        }
        if memoriesWritten > 0 {
            return memoriesWritten == 1 ? "You wrote a memory." : "You wrote \(Self.spelled(memoriesWritten, capitalized: false)) memories."
        }
        return ""
    }

    /// "Eleven games" rather than "11 games" in a sentence; digits past
    /// ninety-nine, where the words get longer than the point.
    static func spelled(_ n: Int, capitalized: Bool) -> String {
        guard n < 100 else { return "\(n)" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        let word = formatter.string(from: NSNumber(value: n)) ?? "\(n)"
        return capitalized ? word.prefix(1).uppercased() + word.dropFirst() : word
    }
}
