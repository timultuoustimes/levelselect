import Foundation
import SwiftData

/// **Writes the badge ledger, once per badge, and says what was new.**
///
/// The rules live in `Badges` and are pure; this gathers the counts they read
/// and records what they justify. `EarnedBadge` is a ledger on purpose — a
/// badge earned once must not vanish because the data behind it changed — so
/// awarding only ever inserts.
///
/// **Silent the first time.** An existing library has already earned most of
/// what it can, and celebrating fourteen badges at once on launch day is a
/// confetti cannon rather than a moment. The first pass writes them with no
/// celebration and records that it happened; everything after that celebrates.
@MainActor
enum BadgeAwarder {

    /// Set once the ledger has been filled from an existing library.
    private static let backfilledKey = "levelselect.badges.backfilled"
    /// The first build wrote every backfilled badge as "now". This repairs
    /// them once, from the same evidence the awarder now dates by.
    ///
    /// **v2 (09-21).** v1 ran with five rules that had no date at all — first
    /// tracker, every week counted, the return, and both history spans — plus
    /// beaten tiers dated by raw completions and collection badges dated to
    /// the latest finish anywhere. Those badges were written as "today" and v1
    /// left them there. A new key runs the repair once more with the fixed
    /// dates; a badge whose evidence is gone has no date and is left alone.
    private static let redatedKey = "levelselect.badges.redated.v2"
    /// True until the Journal has acknowledged a silent backfill.
    static let summaryPendingKey = "levelselect.badges.summaryPending"

    /// What a pass found, for the UI to celebrate (or not).
    struct Result {
        var newlyEarned: [Badges.Definition] = []
        /// True when this was the quiet first pass over an existing library.
        var wasBackfill = false
    }

    /// **Debounced, off the one path every write takes.**
    ///
    /// Hanging this on `WidgetBridge.refresh` covered games and sessions and
    /// missed everything widgets don't care about — writing a memory earned
    /// nothing until something else happened (Tim, 09-21). `Repository`
    /// commits through `persist()`, so that is where this belongs; the delay
    /// coalesces a burst of writes (an import, a bulk edit) into one pass.
    static func schedule(in context: ModelContext) {
        guard !isAwarding else { return }      // our own save is not an event
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            award(in: context)
        }
    }

    private static var pending: Task<Void, Never>?
    private static var isAwarding = false

    /// Run after anything that can move a count: a session stops, a completion
    /// is added, a tracker item is ticked, a game arrives, a console or memory
    /// is recorded. Cheap enough to call often — it is a handful of fetches
    /// and a set difference.
    @discardableResult
    static func award(in context: ModelContext, now: Date = .now) -> Result {
        let (facts, dates) = factsAndDates(in: context, now: now)
        let deserved = Badges.earned(from: facts)
        guard !deserved.isEmpty else { return Result() }

        let ledger = existing(in: context)
        redateIfNeeded(ledger, dates: dates, context: context)
        let held = Set(ledger.map(\.badgeID))
        let missing = deserved.filter { !held.contains($0) }
        guard !missing.isEmpty else { return Result() }

        let defaults = UserDefaults.standard
        let firstPass = !defaults.bool(forKey: backfilledKey)
        isAwarding = true
        defer { isAwarding = false }
        for id in missing {
            // **Dated from the thing that earned it, not from today.**
            // Backfilling an existing library with "now" made every badge
            // claim it happened this afternoon (Tim, King Kai, 09-21). The
            // tenth completion has a date; the hundredth hour happened during
            // a particular session. Where the evidence can't say, today is
            // the honest answer.
            context.insert(EarnedBadge(badgeID: id, earnedAt: dates[id] ?? now))
        }
        try? context.save()
        defaults.set(true, forKey: backfilledKey)
        // A silent backfill still deserves saying so, once, where badges live.
        if firstPass { defaults.set(true, forKey: summaryPendingKey) }

        let earned = firstPass ? [] : missing.compactMap(Badges.definition)
        // The toast lives on the navigator, the way a deleted game's undo
        // does. `celebrate` rather than a direct append: it holds the badge
        // back if a sheet is open over the root.
        AppNavigator.shared.celebrate(earned)
        return Result(newlyEarned: earned, wasBackfill: firstPass)
    }

    /// One-time repair for badges written before dates were worked out.
    private static func redateIfNeeded(_ ledger: [EarnedBadge], dates: [String: Date],
                                       context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: redatedKey), !ledger.isEmpty else { return }
        for badge in ledger {
            guard let real = dates[badge.badgeID],
                  abs(real.timeIntervalSince(badge.earnedAt)) > 86_400 else { continue }
            badge.earnedAt = real
            badge.updatedAt = .now
            badge.revision += 1
        }
        try? context.save()
        defaults.set(true, forKey: redatedKey)
    }

    /// Every badge held, newest first — what the Journal reads.
    static func existing(in context: ModelContext) -> [EarnedBadge] {
        let all = (try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? []
        return all.filter { $0.deletedAt == nil }.sorted { $0.earnedAt > $1.earnedAt }
    }

    // MARK: The counts

    static func facts(in context: ModelContext, now: Date = .now) -> BadgeFacts {
        factsAndDates(in: context, now: now).facts
    }

    /// The counts, and when each badge they justify was actually earned.
    static func factsAndDates(in context: ModelContext,
                              now: Date = .now) -> (facts: BadgeFacts, dates: [String: Date]) {
        let games = ((try? context.fetch(FetchDescriptor<Game>())) ?? []).filter { $0.deletedAt == nil }
        let completions = ((try? context.fetch(FetchDescriptor<CompletionEvent>())) ?? [])
            .filter { $0.deletedAt == nil }
        let memories = ((try? context.fetch(FetchDescriptor<Memory>())) ?? []).filter { $0.deletedAt == nil }
        let consoles = ((try? context.fetch(FetchDescriptor<Console>())) ?? []).filter { $0.deletedAt == nil }

        var f = BadgeFacts()
        f.gamesAdded = games.count
        f.consoles = consoles.count
        f.memories = memories.count

        // A game is beaten if it carries a completion, whatever its status now
        // — the ledger's own rule, applied to the count that feeds it.
        f.gamesBeaten = Set(completions.compactMap { $0.game?.id }).count

        let sessions = games.flatMap { $0.livePlaythroughs.flatMap { ($0.sessions ?? []) } }
            .filter { $0.deletedAt == nil }
        f.sessionsLogged = sessions.count
        f.hoursPlayed = games.reduce(0) { total, game in
            total + game.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime(asOf: now) }
        } / 3600

        // **Every rule below answers "when", and the fact is whether it has
        // an answer.** These were Booleans, and each threw away the date that
        // made it true — so five badges were deserved with no date to put on
        // them and fell back to *today* (Codex, build 40, 09-21). Deriving the
        // fact from the date means a badge can no longer be earned without
        // one.
        let firstBeaten = firstBeatenDates(completions)
        let trackerDate = firstTrackerFinished(games)
        f.trackersFinished = games.filter { isTrackerFinished($0) }.count

        let days = playDays(sessions)
        f.longestStreakDays = longestStreak(in: days)
        let everyWeekDate = firstMonthWithEveryWeek(days)
        f.hadMonthWithEveryWeek = everyWeekDate != nil
        let returnDate = firstReturnAfterGap(sessions, months: 6)
        f.returnedAfterSixMonths = returnDate != nil

        let systemDate = firstSystemBeaten(games, firstBeaten: firstBeaten)
        f.beatEverySystemGame = systemDate != nil
        let collectionDate = firstCollectionFinished(context, firstBeaten: firstBeaten)
        f.completedACollection = collectionDate != nil

        if let earliestPlay = sessions.map(\.startDate).min(),
           completions.contains(where: { $0.date < earliestPlay }) {
            f.beatenBeforeInstall = true
        }
        f.hasVagueDate = memories.contains { ($0.precision ?? "day") != "day" }

        // History spans everything dated — sessions included, as the rule
        // says. They were left out, so a library timed across six years with
        // one memory had "no history".
        let dated = (completions.map(\.date) + memories.map(\.earliest)
                     + sessions.map(\.startDate)).sorted()
        if let first = dated.first, let last = dated.last {
            let years = Calendar.current.dateComponents([.year], from: first, to: last).year ?? 0
            f.yearsOfHistory = max(0, years)
        }

        var dates: [String: Date] = [:]
        let completionDates = completions.map(\.date).sorted()
        let sessionStarts = sessions.map(\.startDate).sorted()
        let addedDates = games.map(\.addedAt).sorted()
        let consoleDates = consoles.map(\.createdAt).sorted()

        dates["first.beaten"] = completionDates.first
        dates["first.session"] = sessionStarts.first
        dates["first.memory"] = memories.map(\.createdAt).min()
        dates["first.console"] = consoleDates.first
        dates["first.tracker"] = trackerDate
        // **Distinct games, not completion events.** The count is of games
        // beaten, so the tenth is the tenth *game* — a replay of one you had
        // already beaten used to move the date earlier.
        nth(&dates, "beaten", firstBeaten.values.sorted(), [10, 25, 50, 100])
        nth(&dates, "sessions", sessionStarts, [10, 100, 500])
        nth(&dates, "added", addedDates, [10, 100, 500])
        nth(&dates, "consoles", consoleDates, [1, 5, 10])

        // The hour tiers happened during a session: walk them in order and
        // note which one carried the total past each threshold.
        //
        // **Imported hours count as played before tracking began** — that is
        // what they are. So the walk starts from them, and a threshold they
        // cross on their own is dated to the earliest thing the library
        // knows, since those hours were already behind you by then. The count
        // included them and the dating didn't, so an imported-only badge was
        // dated today.
        let carried = games.reduce(0) { total, game in
            total + game.livePlaythroughs.reduce(0) { $0 + $1.carriedOverSeconds }
        }
        let earliestKnown = [sessionStarts.first, addedDates.first].compactMap { $0 }.min()
        for n in [10, 100, 500, 1000] where carried / 3600 >= Double(n) {
            dates["hours.\(n)"] = earliestKnown
        }
        var running = carried
        for session in sessions.sorted(by: { $0.startDate < $1.startDate }) {
            let before = running / 3600
            running += session.elapsed(asOf: now)
            let after = running / 3600
            for n in [10, 100, 500, 1000] where before < Double(n) && after >= Double(n) {
                dates["hours.\(n)"] = session.startDate
            }
        }

        if let streakEnd = streakEnd(in: days, length: 7) { dates["streak.7"] = streakEnd }
        if let streakEnd = streakEnd(in: days, length: 30) { dates["streak.30"] = streakEnd }
        dates["habit.everyWeek"] = everyWeekDate
        dates["habit.return"] = returnDate
        dates["collection.systemBeaten"] = systemDate
        dates["collection.finished"] = collectionDate
        if f.beatenBeforeInstall { dates["history.beforeApp"] = completionDates.first }
        if f.hasVagueDate {
            dates["history.vague"] = memories.filter { ($0.precision ?? "day") != "day" }
                .map(\.createdAt).min()
        }
        // N years of history happened on the first dated thing at least N
        // years after the earliest one. A year-grain memory sits on 1 January,
        // which is the grain it was given — the date is no more exact than the
        // memory, and no less.
        if let first = dated.first {
            for n in [5, 10] {
                guard let threshold = Calendar.current.date(byAdding: .year, value: n, to: first) else { continue }
                dates["historyYears.\(n)"] = dated.first { $0 >= threshold }
            }
        }
        return (f, dates.compactMapValues { $0 })
    }

    /// When the nth of something happened — the badge for "10 games beaten"
    /// belongs on the day the tenth was.
    private static func nth(_ dates: inout [String: Date], _ key: String,
                            _ sorted: [Date], _ thresholds: [Int]) {
        for n in thresholds where sorted.count >= n { dates["\(key).\(n)"] = sorted[n - 1] }
    }

    /// The last day of the first run of `length` consecutive days.
    private static func streakEnd(in days: Set<Date>, length: Int) -> Date? {
        let calendar = Calendar.current
        let sorted = days.sorted()
        var run = 1
        for (previous, day) in zip(sorted, sorted.dropFirst()) {
            if calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
                if run >= length { return day }
            } else {
                run = 1
            }
        }
        return nil
    }

    // MARK: The awkward ones

    /// A tracker counts as finished at 100%, read from the percentage the
    /// repository already maintains (`recomputeProgress`) — so a badge can
    /// never disagree with the number on the game's own page.
    private static func isTrackerFinished(_ game: Game) -> Bool {
        game.livePlaythroughs.contains { $0.progressPercent >= 100 }
    }

    /// Local days that carry play, as `yyyy-MM-dd` ordinals.
    private static func playDays(_ sessions: [Session]) -> Set<Date> {
        let calendar = Calendar.current
        return Set(sessions.map { calendar.startOfDay(for: $0.startDate) })
    }

    private static func longestStreak(in days: Set<Date>) -> Int {
        guard !days.isEmpty else { return 0 }
        let calendar = Calendar.current
        let sorted = days.sorted()
        var best = 1, run = 1
        for (previous, day) in zip(sorted, sorted.dropFirst()) {
            if calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1; best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    /// The day each game was first beaten — one per game, however many times
    /// it was finished since.
    private static func firstBeatenDates(_ completions: [CompletionEvent]) -> [UUID: Date] {
        var out: [UUID: Date] = [:]
        for event in completions {
            guard let id = event.game?.id else { continue }
            out[id] = min(out[id] ?? event.date, event.date)
        }
        return out
    }

    /// When the first tracker reached 100%: the last tick on the earliest
    /// finished playthrough.
    private static func firstTrackerFinished(_ games: [Game]) -> Date? {
        games.flatMap(\.livePlaythroughs)
            .filter { $0.progressPercent >= 100 }
            .compactMap { pt -> Date? in
                let ticks = (pt.trackerStates ?? [])
                    .filter { $0.deletedAt == nil && $0.completed }
                    .map(\.tickedAt)
                return ticks.max() ?? pt.lastPlayedAt
            }
            .min()
    }

    /// A calendar month in which every week the month touches had play — and
    /// the day the first such month was completed: when its last missing
    /// week got its first session.
    private static func firstMonthWithEveryWeek(_ days: Set<Date>) -> Date? {
        let calendar = Calendar.current
        let byMonth = Dictionary(grouping: days) { calendar.dateInterval(of: .month, for: $0)?.start ?? $0 }
        return byMonth.compactMap { month, played -> Date? in
            guard let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
            var weeks: Set<Date> = []
            var cursor = interval.start
            while cursor < interval.end {
                if let week = calendar.dateInterval(of: .weekOfYear, for: cursor)?.start { weeks.insert(week) }
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
            }
            var firstInWeek: [Date: Date] = [:]
            for day in played {
                guard let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { continue }
                firstInWeek[week] = min(firstInWeek[week] ?? day, day)
            }
            guard !weeks.isEmpty, weeks.isSubset(of: Set(firstInWeek.keys)) else { return nil }
            return weeks.compactMap { firstInWeek[$0] }.max()
        }
        .min()
    }

    /// One game, put down for six months or more, and picked up again — dated
    /// to the first session that picked it up.
    private static func firstReturnAfterGap(_ sessions: [Session], months: Int) -> Date? {
        let calendar = Calendar.current
        let byGame = Dictionary(grouping: sessions) { $0.playthrough?.game?.id }
        return byGame.values.compactMap { sessions -> Date? in
            let dates = sessions.map(\.startDate).sorted()
            return zip(dates, dates.dropFirst()).first { previous, next in
                (calendar.dateComponents([.month], from: previous, to: next).month ?? 0) >= months
            }?.1
        }
        .min()
    }

    /// Every game you own on one system, beaten — at least three, so a console
    /// with one game on it isn't an achievement. Dated to when the first such
    /// system's last game fell, not to the latest finish anywhere.
    private static func firstSystemBeaten(_ games: [Game], firstBeaten: [UUID: Date]) -> Date? {
        let owned = games.filter { !($0.ownedPlatforms ?? []).isEmpty }
        let bySystem = Dictionary(grouping: owned) { PlatformKey.canonical(($0.ownedPlatforms ?? []).first ?? "") }
        return bySystem.values.compactMap { games -> Date? in
            guard games.count >= 3 else { return nil }
            let dates = games.map { firstBeaten[$0.id] }
            guard dates.allSatisfy({ $0 != nil }) else { return nil }
            return dates.compactMap { $0 }.max()
        }
        .min()
    }

    /// A collection of two or more, every game in it beaten — dated to when
    /// the first such collection's last game fell.
    private static func firstCollectionFinished(_ context: ModelContext,
                                                firstBeaten: [UUID: Date]) -> Date? {
        let collections = ((try? context.fetch(FetchDescriptor<GameCollection>())) ?? [])
            .filter { $0.deletedAt == nil }
        return collections.compactMap { (collection: GameCollection) -> Date? in
            let members = collection.gameIDs.compactMap(UUID.init(uuidString:))
            guard members.count >= 2 else { return nil }
            let dates = members.map { firstBeaten[$0] }
            guard dates.allSatisfy({ $0 != nil }) else { return nil }
            return dates.compactMap { $0 }.max()
        }
        .min()
    }
}
