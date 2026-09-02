import Foundation

/// One thing you did, and when.
///
/// **Nothing here is stored.** The app has been generating a diary since build
/// one and throwing the spine away at display time: a session, a finish and a
/// run are all "something you did, on a date, with your own words optionally
/// attached", and every one of them was readable only inside the sheet that
/// produced it. `Session.notes`, `CompletionEvent.notes` and `Run.notes` are
/// already dated, already synced, and already written. This type is the spine,
/// rebuilt at read time — which is why the journal costs no new model, no
/// CloudKit promote, and asks nothing new of anyone.
struct JournalEntry: Identifiable {
    enum Kind {
        case session, completion, run, memory

        var icon: String {
            switch self {
            case .session:    "timer"
            case .completion: "flag.checkered"
            case .run:        "dice.fill"
            case .memory:     "sparkles"
            }
        }
    }

    let id: UUID
    let kind: Kind
    /// When it happened, for ordering. What it is *filed under* is `grain`,
    /// which is not always a day.
    let date: Date
    /// How precisely `date` is actually known. Sessions and runs are instants
    /// the app timestamped itself; only a finish can be vague.
    let grain: JournalPeriod.Grain
    let game: Game?
    /// What the entry is about. The game's name, nearly always.
    let title: String
    /// The app's own summary — a finish label, a run outcome.
    ///
    /// A session's summary is its `duration` instead, because formatting it
    /// here would mean reaching into `UI/Formatting.swift`, and **Domain is
    /// compiled into the watch target while UI is not** (see `project.yml`).
    /// Baking a display string into a value type would have been the wrong
    /// shape regardless; the watch simply refuses to let it compile.
    let detail: String?

    /// How long a session ran. Formatted by whoever draws it.
    let duration: TimeInterval?
    /// Your words. The reason the whole surface exists.
    let note: String?
    let companions: [Companion]

    /// The record behind a session entry, so the timeline can hand it to the
    /// editor that already exists. Nil for finishes and runs, which are
    /// edited from the game page where their own editors live.
    let session: Session?

    /// The record behind a memory entry, editable from the timeline because
    /// the timeline is the only place a memory appears at all.
    var memory: Memory? = nil

    /// Pictures attached to a memory. A photo of the morning itself is most
    /// of the point of writing one down, so the timeline shows them rather
    /// than hiding them behind an edit sheet.
    var images: [GameImage] = []

    /// A heading in the entry's own words, for a date no grain can describe.
    ///
    /// "Christmas 1995 or 1996" filed under a heading reading **1995** would
    /// assert the very thing the record declines to — so an uncertain memory
    /// becomes its own period, titled by what was actually written.
    var headingOverride: String? = nil
}

/// A heading and the entries under it.
///
/// Not simply "a day", because the app already refuses to pretend it knows
/// more than it was told. A finish recorded as *"2011"* is stored on 1 January
/// with `datePrecision == "year"` precisely so it can be *printed* as 2011 —
/// filing it under a heading reading "Saturday 1 January 2011" would take a
/// truth the model went to some trouble to preserve and turn it back into the
/// lie it was designed to avoid. So the grain of a heading is the grain of
/// what it holds.
struct JournalPeriod: Identifiable {
    enum Grain: Int, Comparable {
        case day = 0, month = 1, year = 2
        static func < (a: Grain, b: Grain) -> Bool { a.rawValue < b.rawValue }

        /// `CompletionEvent.datePrecision`'s vocabulary, reused rather than a
        /// second one invented beside it.
        init(precision: String?) {
            switch precision {
            case "year":  self = .year
            case "month": self = .month
            default:      self = .day
            }
        }

        func start(of date: Date, calendar: Calendar) -> Date {
            switch self {
            case .day:   calendar.startOfDay(for: date)
            case .month: calendar.dateInterval(of: .month, for: date)?.start
                            ?? calendar.startOfDay(for: date)
            case .year:  calendar.dateInterval(of: .year, for: date)?.start
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
    /// assumed.**
    ///
    /// Three separate bugs in this build came from a date formatter defaulting
    /// to `Calendar.current`: a UTC-midnight 1 January reads as 31 December —
    /// and therefore the *previous year* — for everyone west of Greenwich. The
    /// app legitimately has two calendars, because a release date and a memory
    /// are calendar facts while a session is something you did where you were
    /// sitting. Whichever one grouped these entries has to be the one that
    /// names them, or the heading disagrees with its own contents.
    var calendar: Calendar = JournalBuilder.calendar

    var id: String {
        "\(grain.rawValue)@\(start.timeIntervalSince1970)@\(headingOverride ?? "")"
    }

    /// The heading. Relative for the two days everyone has a word for, and the
    /// year dropped while it is the current one — a journal you are reading
    /// today does not need to keep saying 2026.
    func title(now: Date = .now) -> String {
        if let headingOverride { return headingOverride }
        switch grain {
        case .year:  return String(calendar.component(.year, from: start))
        case .month: return start.formatted(.dateTime.month(.wide).year())
        case .day:
            if calendar.isDateInToday(start)     { return "Today" }
            if calendar.isDateInYesterday(start) { return "Yesterday" }
            let sameYear = calendar.component(.year, from: start)
                        == calendar.component(.year, from: now)
            return sameYear
                ? start.formatted(.dateTime.weekday(.wide).day().month(.wide))
                : start.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year())
        }
    }
}

enum JournalBuilder {
    /// **Local, on purpose — and deliberately not the UTC calendar the release
    /// dates use.**
    ///
    /// Those two look like the same decision and are opposites. A release date
    /// is a calendar fact the world agrees on, so it is read in UTC or it
    /// drifts a day for everyone west of Greenwich. A session is something
    /// *you* did, and the day it belongs to is the day it was where you were
    /// sitting.
    static var calendar: Calendar { .current }

    /// Everything, newest first.
    ///
    /// Entries with no note are kept. A journal of only the days you felt like
    /// writing is a journal that is empty, and the record of having played at
    /// all is what the writing later hangs off.
    static func periods(from games: [Game],
                        standalone: [Memory] = [],
                        now: Date = .now) -> [JournalPeriod] {
        var entries: [JournalEntry] = []

        for game in games {
            for playthrough in game.livePlaythroughs {
                for session in (playthrough.sessions ?? []) where session.deletedAt == nil {
                    // A running session has not happened yet. It belongs to
                    // the timer on Home, not to the record of what you did.
                    guard session.endDate != nil else { continue }
                    entries.append(JournalEntry(
                        id: session.id,
                        kind: .session,
                        date: session.startDate,
                        grain: .day,
                        game: game,
                        title: game.name,
                        detail: nil,
                        duration: session.elapsed(),
                        note: session.notes?.journalText,
                        companions: session.companions,
                        session: session))
                }
                for run in (playthrough.runs ?? []) where run.deletedAt == nil {
                    guard run.outcome != .inProgress else { continue }
                    entries.append(JournalEntry(
                        id: run.id,
                        kind: .run,
                        date: run.endedAt ?? run.startedAt,
                        grain: .day,
                        game: game,
                        title: game.name,
                        detail: run.outcome.journalText,
                        duration: nil,
                        note: run.notes?.journalText,
                        companions: run.companions,
                        session: nil))
                }
            }
            for memory in (game.memories ?? []) where memory.deletedAt == nil {
                entries.append(Self.entry(for: memory))
            }
            for finish in (game.completionEvents ?? []) where finish.deletedAt == nil {
                entries.append(JournalEntry(
                    id: finish.id,
                    kind: .completion,
                    date: finish.date,
                    grain: JournalPeriod.Grain(precision: finish.datePrecision),
                    game: game,
                    title: game.name,
                    detail: finish.journalLabel,
                    duration: nil,
                    note: finish.notes?.journalText,
                    companions: finish.companions,
                    session: nil))
            }
        }

        // Memories with no game at all — "first LAN party" — reach the
        // timeline through nothing else, so they are fetched rather than
        // walked to. They are the whole reason the model allows a nil game.
        entries.append(contentsOf: standalone.map(Self.entry(for:)))

        return group(entries)
    }

    /// One memory, as a timeline entry.
    static func entry(for memory: Memory) -> JournalEntry {
        JournalEntry(
            id: memory.id,
            kind: .memory,
            // The interval's start orders it; what it PRINTS is its own words.
            date: memory.earliest,
            grain: JournalPeriod.Grain(precision: memory.precision),
            game: memory.game,
            title: memory.title,
            detail: memory.detailLine,
            duration: nil,
            note: memory.body?.journalText,
            companions: memory.companions,
            session: nil,
            memory: memory,
            images: (memory.images ?? []).filter { $0.deletedAt == nil }
                .sorted { $0.addedAt < $1.addedAt },
            // Only when no grain can describe it. A year-precision memory is
            // perfectly happy under a year heading.
            headingOverride: memory.isUncertain ? memory.dateText : nil)
    }

    private static func group(_ entries: [JournalEntry]) -> [JournalPeriod] {
        var buckets: [String: (start: Date, grain: JournalPeriod.Grain,
                               calendar: Calendar, items: [JournalEntry])] = [:]

        for entry in entries {
            // A memory's dates are UTC calendar facts; a session's day is the
            // day it was where you were sitting. Each entry is bucketed in its
            // own calendar rather than one being forced into the other's.
            let entryCalendar = entry.kind == .memory ? Memory.calendar : calendar
            let start = entry.grain.start(of: entry.date, calendar: entryCalendar)
            // The override joins the key, so two uncertain memories in one
            // year stay two periods rather than merging under one sentence.
            let key = "\(entry.grain.rawValue)@\(start.timeIntervalSince1970)@\(entry.headingOverride ?? "")"
            buckets[key, default: (start, entry.grain, entryCalendar, [])].items.append(entry)
        }

        return buckets.values
            .map {
                JournalPeriod(
                    start: $0.start,
                    grain: $0.grain,
                    // Within a period, latest first — the same direction the
                    // page reads, so scrolling never reverses mid-column.
                    entries: $0.items.sorted { $0.date > $1.date },
                    headingOverride: $0.items.first?.headingOverride,
                    calendar: $0.calendar)
            }
            // Newest first. When a year bucket and a day inside it land on the
            // same instant, the precise one goes on top: it says more.
            .sorted {
                $0.start == $1.start ? $0.grain < $1.grain : $0.start > $1.start
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
        case .custom:         customLabel?.journalText ?? "Finished"
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
