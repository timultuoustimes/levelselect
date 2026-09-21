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

        /// The period this span covers, in the given calendar.
        func interval(_ calendar: Calendar = .current) -> DateInterval {
            switch self {
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
        let range = span.interval(calendar)
        replay.range = range

        // Sessions, each counted whole in the period it began — see `overlap`.
        var perGame: [UUID: (name: String, seconds: TimeInterval, sessions: Int)] = [:]
        var perDay: [Date: TimeInterval] = [:]

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
        }

        replay.finished = source.completions
            .filter { $0.deletedAt == nil && range.contains($0.date) }
            .compactMap { event in
                guard let game = event.game, game.deletedAt == nil else { return nil }
                return Finish(id: game.id, name: game.name, date: event.date,
                              label: event.labelText)
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
                            Carried(id: covering.id, name: game.name,
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
        }
    }
}
