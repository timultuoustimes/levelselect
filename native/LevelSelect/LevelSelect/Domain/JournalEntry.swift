import Foundation

/// A day's worth of one game, or one memory.
///
/// **The unit is a game-day, not a session.** The first version made every
/// session its own row, and a real timeline showed what that costs: Mina the
/// Hollower three times on 27 June, Mixtape twice on the 14th, each row
/// repeating the cover, the name and the date to say "and then a bit more".
/// Tim: *"What if we do it so that it says that you played the game and it
/// gives a summary of what you did in the game that day."*
///
/// It also fixes something the old shape fudged. Playing a game, logging a run
/// and finishing it in the same afternoon is **one story**, and the timeline
/// was telling it three times with nothing to say they were related.
///
/// Nothing here is stored. `Session`, `Run` and `CompletionEvent` have carried
/// dated user writing since build one; this is the spine, rebuilt at read time.
struct JournalEntry: Identifiable {
    enum Kind {
        case play, memory

        var icon: String {
            switch self {
            case .play:   "gamecontroller.fill"
            // NOT sparkles. That glyph means "the machine made this" —
            // platform-wide, and in this app specifically on Generate with AI,
            // Suggest Categories and Collection from a Prompt. A memory is the
            // opposite: the one kind of entry that only a person can write.
            // Tim: *"It feels weird that the icon for 'generate with AI' and
            // for a memory are the sparkles. They shouldn't be the same."*
            //
            // `text.quote` keeps the app's document vocabulary — a scroll for
            // Home, a closed book for the Journal — and reads as something
            // recounted, which is what a memory is.
            case .memory: "text.quote"
            }
        }
    }

    let id: String
    let kind: Kind
    /// The latest thing that happened, for ordering within the day.
    let date: Date
    /// How precisely `date` is known. Only a memory or a backfilled finish
    /// can be vague.
    let grain: JournalPeriod.Grain
    let game: Game?
    let title: String

    // MARK: A day of play

    /// Kept rather than counted: the detail view lists them, and re-finding
    /// them in a second pass would be a second chance to disagree with this
    /// one.
    var sessions: [Session] = []
    var runs: [Run] = []
    var finishes: [CompletionEvent] = []

    /// Total time across the day's sessions.
    var duration: TimeInterval = 0

    /// Everything written that day, in the order it happened. Session notes,
    /// run notes and the note on a finish are all "what you said about this
    /// game today" — sorting them by which record happened to hold them would
    /// leak an implementation detail into a diary.
    var notes: [String] = []

    // MARK: A memory

    var memory: Memory? = nil
    var detail: String? = nil
    var images: [GameImage] = []
    var companions: [Companion] = []
    var headingOverride: String? = nil
}

/// A heading and the entries under it.
///
/// Not simply "a day", because the app already refuses to pretend it knows
/// more than it was told. A finish recorded as *"2011"* is stored on 1 January
/// with `datePrecision == "year"` precisely so it can be *printed* as 2011 —
/// filing it under "Saturday 1 January 2011" would take a truth the model went
/// to trouble to preserve and hand it back as the lie it was designed to
/// avoid.
struct JournalPeriod: Identifiable {
    /// How wide a period is. Ordered narrow to wide, which is what the
    /// `Comparable` conformance is for — two periods starting on the same
    /// instant sort with the more precise one first.
    ///
    /// **Season and decade are first-class, not spans with a label.** Tim, on
    /// where "summer 1998" and "the 1990s" belong: *"I think first-class
    /// season/decade headers."* Before this they could only be stored as a
    /// bare interval with no name for how wide it was, so the calendar had
    /// nothing to group them by. B1.
    enum Grain: Int, Comparable {
        case day = 0, month = 1, season = 2, year = 3, decade = 4
        static func < (a: Grain, b: Grain) -> Bool { a.rawValue < b.rawValue }

        /// `CompletionEvent.datePrecision`'s vocabulary, reused rather than a
        /// second one invented beside it.
        init(precision: String?) {
            switch precision {
            case "decade": self = .decade
            case "year":   self = .year
            case "season": self = .season
            case "month":  self = .month
            default:       self = .day
            }
        }

        func start(of date: Date, calendar: Calendar) -> Date {
            switch self {
            case .day:   calendar.startOfDay(for: date)
            case .month: calendar.dateInterval(of: .month, for: date)?.start
                            ?? calendar.startOfDay(for: date)
            case .season: Memory.seasonInterval(of: date)?.lowerBound
                            ?? calendar.startOfDay(for: date)
            case .year:  calendar.dateInterval(of: .year, for: date)?.start
                            ?? calendar.startOfDay(for: date)
            case .decade: Memory.decadeInterval(of: date)?.lowerBound
                            ?? calendar.startOfDay(for: date)
            }
        }
    }

    let start: Date
    let grain: Grain
    let entries: [JournalEntry]
    /// Set when the period exists to carry one uncertain memory, and the only
    /// accurate heading is the sentence its author wrote.
    var headingOverride: String? = nil

    /// **The calendar this period was bucketed in, carried rather than
    /// assumed.** A UTC-midnight 1 January reads as the previous year west of
    /// Greenwich, so whichever calendar grouped these entries must be the one
    /// that names them.
    var calendar: Calendar = JournalBuilder.calendar

    var id: String { "\(grain.rawValue)@\(start.timeIntervalSince1970)@\(headingOverride ?? "")" }

    /// The period's own calendar, applied to a format style.
    ///
    /// `Date.formatted` uses the CURRENT calendar and time zone unless told
    /// otherwise, which quietly undid the care taken above: a UTC-midnight
    /// 25 December was bucketed correctly by `calendar` and then titled
    /// "24 December" west of Greenwich, because only the bucketing honored it.
    /// Locale is left alone — the user's language is not the period's business.
    private func styled(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var s = style
        s.calendar = calendar
        s.timeZone = calendar.timeZone
        return s
    }

    func title(now: Date = .now) -> String {
        if let headingOverride { return headingOverride }
        switch grain {
        // "The 1990s" — the decade named the way anybody says it.
        case .decade:
            let first = calendar.component(.year, from: start)
            return "The \(first)s"
        // A season memory always carries the words it was written with, so
        // this is a fallback rather than the usual path — and it deliberately
        // names months rather than a season, because which three months are
        // "summer" depends on which half of the planet you were on.
        case .season:
            let end = calendar.date(byAdding: .month, value: 2, to: start) ?? start
            return start.formatted(styled(.dateTime.month(.abbreviated)))
                + "–" + end.formatted(styled(.dateTime.month(.abbreviated).year()))
        case .year:  return String(calendar.component(.year, from: start))
        case .month: return start.formatted(styled(.dateTime.month(.wide).year()))
        case .day:
            if calendar.isDateInToday(start)     { return "Today" }
            if calendar.isDateInYesterday(start) { return "Yesterday" }
            let sameYear = calendar.component(.year, from: start)
                        == calendar.component(.year, from: now)
            return sameYear
                ? start.formatted(styled(.dateTime.weekday(.wide).day().month(.wide)))
                : start.formatted(styled(.dateTime.weekday(.abbreviated).day().month(.wide).year()))
        }
    }
}

enum JournalBuilder {
    /// **Local, on purpose — and deliberately not the UTC calendar the release
    /// dates use.** A release date is a calendar fact the world agrees on; a
    /// session is something *you* did, and the day it belongs to is the day it
    /// was where you were sitting.
    static var calendar: Calendar { .current }

    static func periods(from games: [Game],
                        standalone: [Memory] = [],
                        now: Date = .now) -> [JournalPeriod] {
        var entries: [JournalEntry] = []
        for game in games {
            entries.append(contentsOf: playEntries(for: game))
            for memory in (game.memories ?? []) where memory.deletedAt == nil {
                entries.append(contentsOf: candidateEntries(for: memory))
            }
        }
        // Memories with no game reach the timeline through nothing else.
        entries.append(contentsOf: standalone.flatMap(candidateEntries(for:)))
        return group(entries)
    }

    /// One entry per day this game saw any activity.
    static func playEntries(for game: Game) -> [JournalEntry] {
        var byDay: [Date: (sessions: [Session], runs: [Run], finishes: [CompletionEvent])] = [:]

        for playthrough in game.livePlaythroughs {
            for session in (playthrough.sessions ?? []) where session.deletedAt == nil {
                // A running session has not happened yet — it belongs to the
                // timer on Home, not the record of what you did.
                guard session.endDate != nil else { continue }
                byDay[calendar.startOfDay(for: session.startDate), default: ([], [], [])]
                    .sessions.append(session)
            }
            for run in (playthrough.runs ?? []) where run.deletedAt == nil {
                guard run.outcome != .inProgress else { continue }
                let when = run.endedAt ?? run.startedAt
                byDay[calendar.startOfDay(for: when), default: ([], [], [])].runs.append(run)
            }
        }
        for finish in (game.completionEvents ?? []) where finish.deletedAt == nil {
            // A vague finish ("2011") has no day to join; it is handled below.
            guard JournalPeriod.Grain(precision: finish.datePrecision) == .day else { continue }
            byDay[calendar.startOfDay(for: finish.date), default: ([], [], [])]
                .finishes.append(finish)
        }

        var result = byDay.map { day, parts -> JournalEntry in
            let sessions = parts.sessions.sorted { $0.startDate < $1.startDate }
            let runs = parts.runs.sorted {
                ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt)
            }
            let finishes = parts.finishes.sorted { $0.date < $1.date }
            let latest = [sessions.last?.startDate,
                          runs.last.map { $0.endedAt ?? $0.startedAt },
                          finishes.last?.date].compactMap { $0 }.max() ?? day
            let written: [(Date, String?)] =
                sessions.map { ($0.startDate, $0.notes) }
                + runs.map { ($0.endedAt ?? $0.startedAt, $0.notes) }
                + finishes.map { ($0.date, $0.notes) }
            return JournalEntry(
                id: "\(game.id.uuidString)@\(day.timeIntervalSince1970)",
                kind: .play,
                date: latest,
                grain: .day,
                game: game,
                title: game.name,
                sessions: sessions,
                runs: runs,
                finishes: finishes,
                duration: sessions.reduce(0) { $0 + $1.elapsed() },
                notes: written.sorted { $0.0 < $1.0 }.compactMap { $0.1?.journalText })
        }

        // A finish too vague for a day still belongs somewhere — it stands
        // alone at its own grain rather than inventing a day to join.
        for finish in (game.completionEvents ?? []) where finish.deletedAt == nil {
            let grain = JournalPeriod.Grain(precision: finish.datePrecision)
            guard grain != .day else { continue }
            result.append(JournalEntry(
                id: finish.id.uuidString,
                kind: .play,
                date: finish.date,
                grain: grain,
                game: game,
                title: game.name,
                finishes: [finish],
                notes: [finish.notes?.journalText].compactMap { $0 }))
        }
        return result
    }

    /// **"Christmas 1995 or 1996" belongs on both Christmases.**
    ///
    /// It used to land only on the first candidate — the day was known, the
    /// year was not, so the app picked the earlier one and the later one had
    /// nothing on it. That is the app quietly resolving an uncertainty its
    /// owner deliberately left open. Tim, asked whether first-candidate was
    /// the final rule: *"I feel like it should show on both candidate days."*
    ///
    /// Only when the day IS known and only the year is in doubt — which is
    /// exactly the shape `MemorySheet` writes when "I know the day" is on:
    /// same month and day, different years. Anything else (a vague month, a
    /// whole year, a span with no day) has no candidate days to place, and
    /// gets its single entry as before.
    ///
    /// Each copy carries the year in its id so grouping keeps them apart, and
    /// the same `Memory` so tapping either opens the one entry that exists —
    /// there is one memory here, shown twice, not two memories.
    static func candidateEntries(for memory: Memory) -> [JournalEntry] {
        let base = entry(for: memory)
        guard memory.precision == nil, memory.hasKnownDay else { return [base] }

        let cal = Memory.calendar
        let from = cal.dateComponents([.year, .month, .day], from: memory.earliest)
        let to = cal.dateComponents([.year, .month, .day], from: memory.latest)
        guard let firstYear = from.year, let lastYear = to.year,
              lastYear > firstYear,
              // The day is known exactly when both ends print the same one.
              from.month == to.month, from.day == to.day,
              // A guard against a pathological span turning one memory into a
              // hundred squares.
              lastYear - firstYear <= 8
        else { return [base] }

        return (firstYear...lastYear).compactMap { year in
            guard let date = cal.date(from: DateComponents(
                year: year, month: from.month, day: from.day)) else { return nil }
            return entry(for: memory,
                         id: "\(memory.id.uuidString)@\(year)",
                         date: date)
        }
    }

    /// The grain a memory is placed at.
    ///
    /// **An uncertain memory with no day is not a day.** It used to be given
    /// `.day` anyway, which is what put it on a square — 1 January, a date
    /// nobody wrote. Grained at the year instead, it lands in the area the
    /// calendar already keeps above the grid for entries that name no day.
    static func grain(for memory: Memory) -> JournalPeriod.Grain {
        if memory.precision == nil, !memory.hasKnownDay { return .year }
        return JournalPeriod.Grain(precision: memory.precision)
    }

    static func entry(for memory: Memory,
                      id: String? = nil,
                      date: Date? = nil) -> JournalEntry {
        JournalEntry(
            id: id ?? memory.id.uuidString,
            kind: .memory,
            date: date ?? memory.earliest,
            grain: grain(for: memory),
            game: memory.game,
            title: memory.title,
            notes: [memory.body?.journalText].compactMap { $0 },
            memory: memory,
            detail: memory.detailLine,
            images: (memory.images ?? []).filter { $0.deletedAt == nil }
                .sorted { $0.addedAt < $1.addedAt },
            companions: memory.companions,
            headingOverride: memory.isUncertain ? memory.dateText : nil)
    }

    /// The square a date belongs in, whichever calendar dated it.
    ///
    /// **This grid is where the app's two calendars meet.** A session is
    /// dated where you were sitting; a memory is a UTC calendar fact. Both
    /// have to land on the square whose number they would print, so the
    /// conversion goes through year/month/day rather than the instant — a
    /// UTC midnight on 25 December is 24 December in Sydney, and "Christmas
    /// 1995" filed under the 24th is the calendar quietly rewriting someone's
    /// history.
    /// - Parameter grid: the calendar the squares are drawn in. Defaults to
    ///   the journal's own; a parameter so the rule can be tested from a
    ///   timezone other than the one the tests happen to run in.
    static func square(for date: Date, in source: Calendar,
                       grid: Calendar = calendar) -> Date {
        let parts = source.dateComponents([.year, .month, .day], from: date)
        return grid.date(from: DateComponents(year: parts.year,
                                              month: parts.month,
                                              day: parts.day))
            ?? grid.startOfDay(for: date)
    }

    /// A tapped square, named in the calendar a `Memory` is stored in.
    ///
    /// The inverse of `square(for:in:)`, and needed for the same reason:
    /// `Repository.saveMemory` truncates through `Memory.calendar`, so handing
    /// it a local midnight would file the 14th as the 13th for anyone east of
    /// Greenwich.
    static func memoryDate(for square: Date, grid: Calendar = calendar) -> Date {
        let parts = grid.dateComponents([.year, .month, .day], from: square)
        return Memory.calendar.date(from: DateComponents(year: parts.year,
                                                         month: parts.month,
                                                         day: parts.day))
            ?? square
    }

    private static func group(_ entries: [JournalEntry]) -> [JournalPeriod] {
        var buckets: [String: (start: Date, grain: JournalPeriod.Grain,
                               calendar: Calendar, items: [JournalEntry])] = [:]

        for entry in entries {
            // A memory's dates are UTC calendar facts; a day of play is the
            // day it was where you were sitting.
            let entryCalendar = entry.kind == .memory ? Memory.calendar : calendar
            let start = entry.grain.start(of: entry.date, calendar: entryCalendar)
            // **Key on the DAY, not on the instant.**
            //
            // The two calendars above are deliberate — a memory's dates are
            // UTC calendar facts, a day of play is the day it was where you
            // were sitting — but keying on `timeIntervalSince1970` made that
            // difference structural: in EDT, midnight UTC is 8pm the previous
            // day, so a session and a memory on the SAME day produced two
            // starts four hours apart, two buckets, and two sections that both
            // said "Today". Fable saw it on 2026-09-07: "Today — Hades · 1 run"
            // with the memory under its own second "Today" header.
            //
            // The components answer the question the reader is asking — which
            // day is this — and each is still computed in its own calendar, so
            // neither entry moves off the day it belongs to.
            let parts = entryCalendar.dateComponents([.year, .month, .day], from: start)
            let day = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
            let key = "\(entry.grain.rawValue)@\(day)@\(entry.headingOverride ?? "")"
            buckets[key, default: (start, entry.grain, entryCalendar, [])].items.append(entry)
        }

        return buckets.values
            .map {
                JournalPeriod(
                    start: $0.start,
                    grain: $0.grain,
                    // `id` breaks the tie, because `sorted` is not stable
                    // and two entries can share a date — a session day and a
                    // memory written for it, or two memories on one day. Same
                    // library, two devices, two orders otherwise, and two
                    // exports that diff against each other. Codex data #11.
                    entries: $0.items.sorted {
                        $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
                    },
                    headingOverride: $0.items.first?.headingOverride,
                    calendar: $0.calendar)
            }
            // **Total, like the entries inside it.** Start and grain were not
            // enough: the bucket key includes the verbatim heading, so "sometime
            // in 1998" and "around 1998" make two year-grain periods that both
            // begin on 1 January. The comparator called neither before the
            // other, and dictionary iteration order is not stable — so those two
            // sections could swap between runs or devices. Codex data #11, the
            // half that was still open. The heading is the thing that separated
            // them, so it is the thing that orders them.
            .sorted {
                if $0.start != $1.start { return $0.start > $1.start }
                if $0.grain != $1.grain { return $0.grain < $1.grain }
                return ($0.headingOverride ?? "") < ($1.headingOverride ?? "")
            }
    }
}

extension RunOutcome {
    var journalText: String {
        switch self {
        case .success:    "Run won"
        case .failure:    "Run lost"
        case .neutral:    "Run ended"
        case .inProgress: "Run in progress"
        }
    }
}

extension CompletionEvent {
    /// The short noun a timeline row needs. `CompletionSection` spells these
    /// out as sentences for its picker ("100% — all of my list"); a row under
    /// a date wants the label, not the explanation.
    var journalLabel: String {
        switch label {
        case .cleared:        "Beaten"
        case .completed:      "Completed"
        case .hundredPercent: "100%"
        case .newGamePlus:    "New Game+"
        case .custom:         customLabel?.journalText ?? "Beaten"
        }
    }
}

extension String {
    /// Blank strings are absent values wearing a value's clothes, and a row
    /// draws differently when a note is genuinely there.
    var journalText: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
