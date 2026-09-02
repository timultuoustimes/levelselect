import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 36 — the journal takes the tab, and the timeline is built from
/// records that were already there.
@MainActor
struct Build36JournalTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// A game with one playthrough, ready to hang sessions and runs off.
    private func makeGame(_ context: ModelContext, name: String) -> (Game, Playthrough) {
        let game = Game(name: name)
        let playthrough = Playthrough()
        playthrough.game = game
        context.insert(game)
        context.insert(playthrough)
        return (game, playthrough)
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        JournalBuilder.calendar.date(from: DateComponents(
            year: y, month: m, day: d, hour: hour)) ?? .now
    }

    // MARK: The spine

    /// The whole premise of the feature: the writing was already in the store,
    /// dated and synced, and only ever visible inside the sheet that produced
    /// it. Nothing new is written to show it — so a note typed into a session
    /// must reach the timeline unchanged.
    @Test func aSessionsNoteReachesTheTimeline() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Hollow Knight")

        let session = Session()
        session.playthrough = playthrough
        session.startDate = day(2026, 8, 29, hour: 22)
        session.endDate = session.startDate.addingTimeInterval(3600)
        session.accumulatedDuration = 3600
        session.notes = "Finally beat Hornet. Third night on it."
        context.insert(session)

        let periods = JournalBuilder.periods(from: [game])
        let entry = try? #require(periods.first?.entries.first)
        #expect(entry?.note == "Finally beat Hornet. Third night on it.")
        #expect(entry?.kind == .session)
        #expect(entry?.title == "Hollow Knight")
    }

    /// A note that is only whitespace is an absent note wearing a value's
    /// clothes, and a row draws differently when one is genuinely there.
    @Test func blankNotesCountAsNoNote() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Hades")

        let session = Session()
        session.playthrough = playthrough
        session.startDate = day(2026, 8, 29)
        session.endDate = session.startDate.addingTimeInterval(60)
        session.notes = "   \n  "
        context.insert(session)

        #expect(JournalBuilder.periods(from: [game]).first?.entries.first?.note == nil)
    }

    /// A running session has not happened yet — it belongs to the timer on
    /// Home, not to the record of what you did.
    @Test func aRunningSessionIsNotAnEntry() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Balatro")

        let running = Session()
        running.playthrough = playthrough
        running.startDate = day(2026, 9, 2)
        running.endDate = nil
        context.insert(running)

        #expect(JournalBuilder.periods(from: [game]).isEmpty)
    }

    // MARK: Grain — the part that must not invent precision

    /// **The rule the whole grouping exists for.** A finish recorded as "2011"
    /// is stored on 1 January with `datePrecision == "year"` precisely so it
    /// can be *printed* as 2011. Filing it under a heading reading "Saturday
    /// 1 January 2011" would take a truth the model went to real trouble to
    /// keep and hand it back as the lie it was designed to avoid.
    @Test func aYearOnlyFinishIsFiledUnderTheYear() {
        let context = makeContext()
        let (game, _) = makeGame(context, name: "Skyrim")

        let finish = CompletionEvent()
        finish.game = game
        finish.date = day(2011, 1, 1, hour: 0)
        finish.datePrecision = "year"
        finish.label = .cleared
        context.insert(finish)

        let period = try? #require(JournalBuilder.periods(from: [game]).first)
        #expect(period?.grain == .year)
        #expect(period?.title() == "2011")
    }

    @Test func aMonthPrecisionFinishIsFiledUnderTheMonth() {
        let context = makeContext()
        let (game, _) = makeGame(context, name: "Tunic")

        let finish = CompletionEvent()
        finish.game = game
        finish.date = day(2025, 12, 14)
        finish.datePrecision = "month"
        finish.label = .hundredPercent
        context.insert(finish)

        let period = try? #require(JournalBuilder.periods(from: [game]).first)
        #expect(period?.grain == .month)
        #expect(period?.title().contains("December") == true)
        #expect(period?.title().contains("14") == false)   // the day it does not know
    }

    /// A session is an instant the app timestamped itself, so it is always a
    /// day — the vagueness is a property of finishes alone.
    @Test func sessionsAreAlwaysDayGrain() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Celeste")

        let session = Session()
        session.playthrough = playthrough
        session.startDate = day(2026, 8, 20)
        session.endDate = session.startDate.addingTimeInterval(600)
        context.insert(session)

        #expect(JournalBuilder.periods(from: [game]).first?.grain == .day)
    }

    // MARK: Grouping and order

    /// A day gathers everything that happened on it, whatever kind it was —
    /// the unit is the day, and sessions are its rows.
    @Test func aDayGathersEveryKindThatHappenedOnIt() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Hades")

        let morning = Session()
        morning.playthrough = playthrough
        morning.startDate = day(2026, 8, 25, hour: 9)
        morning.endDate = morning.startDate.addingTimeInterval(1800)
        context.insert(morning)

        let evening = Session()
        evening.playthrough = playthrough
        evening.startDate = day(2026, 8, 25, hour: 21)
        evening.endDate = evening.startDate.addingTimeInterval(1800)
        context.insert(evening)

        let run = Run(templateID: "default",
                      startedAt: day(2026, 8, 25, hour: 20),
                      outcome: RunOutcome.success)
        run.playthrough = playthrough
        run.endedAt = day(2026, 8, 25, hour: 20)
        context.insert(run)

        let finish = CompletionEvent()
        finish.game = game
        finish.date = day(2026, 8, 25, hour: 22)
        finish.label = .cleared
        context.insert(finish)

        let periods = JournalBuilder.periods(from: [game])
        #expect(periods.count == 1)
        #expect(periods.first?.entries.count == 4)
        // Latest first, so the page never reverses direction mid-column.
        #expect(periods.first?.entries.first?.kind == .completion)
    }

    @Test func daysRunNewestFirst() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Tunic")

        for d in [10, 28, 19] {
            let session = Session()
            session.playthrough = playthrough
            session.startDate = day(2026, 8, d)
            session.endDate = session.startDate.addingTimeInterval(600)
            context.insert(session)
        }

        let starts = JournalBuilder.periods(from: [game]).map(\.start)
        #expect(starts == starts.sorted(by: >))
    }

    /// A session that ran past midnight belongs to the evening you remember
    /// it as, which is the day it STARTED.
    @Test func aSessionBelongsToTheDayItStarted() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Disco Elysium")

        let session = Session()
        session.playthrough = playthrough
        session.startDate = day(2026, 8, 20, hour: 23)
        session.endDate = day(2026, 8, 21, hour: 1)
        context.insert(session)

        let period = try? #require(JournalBuilder.periods(from: [game]).first)
        #expect(period?.start == JournalBuilder.calendar.startOfDay(for: day(2026, 8, 20)))
    }

    /// Deleted records are gone from the journal too — Recently Deleted holds
    /// them, and a timeline that still showed them would be reporting a
    /// library the user no longer has.
    @Test func softDeletedRecordsStayOut() {
        let context = makeContext()
        let (game, playthrough) = makeGame(context, name: "Animal Well")

        let session = Session()
        session.playthrough = playthrough
        session.startDate = day(2026, 8, 18)
        session.endDate = session.startDate.addingTimeInterval(600)
        session.deletedAt = .now
        context.insert(session)

        #expect(JournalBuilder.periods(from: [game]).isEmpty)
    }

    // MARK: Headings

    @Test func todayAndYesterdayGetTheirOwnWords() {
        let now = Date.now
        let today = JournalPeriod(
            start: JournalBuilder.calendar.startOfDay(for: now),
            grain: .day, entries: [])
        let yesterday = JournalPeriod(
            start: JournalBuilder.calendar.startOfDay(
                for: now.addingTimeInterval(-86_400)),
            grain: .day, entries: [])
        #expect(today.title(now: now) == "Today")
        #expect(yesterday.title(now: now) == "Yesterday")
    }

    /// A journal read today does not need to keep saying 2026; one read in
    /// 2027 very much needs to say which year it is looking at.
    @Test func theYearAppearsOnlyWhenItIsNotTheCurrentOne() {
        let now = day(2026, 9, 2)
        let thisYear = JournalPeriod(start: day(2026, 3, 14), grain: .day, entries: [])
        let lastYear = JournalPeriod(start: day(2025, 3, 14), grain: .day, entries: [])
        #expect(thisYear.title(now: now).contains("2026") == false)
        #expect(lastYear.title(now: now).contains("2025"))
    }
}

/// Build 36 — the prompt that gives the timeline something to read.
@MainActor
struct Build36SessionNoteTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private func endedSession(_ context: ModelContext,
                              endedAgo: TimeInterval,
                              notes: String? = nil,
                              deleted: Bool = false) -> Session {
        let game = Game(name: "Hades")
        let playthrough = Playthrough()
        playthrough.game = game
        let session = Session()
        session.playthrough = playthrough
        session.endDate = Date.now.addingTimeInterval(-endedAgo)
        session.startDate = session.endDate!.addingTimeInterval(-1800)
        session.notes = notes
        if deleted { session.deletedAt = .now }
        context.insert(game); context.insert(playthrough); context.insert(session)
        return session
    }

    /// The question is about the thing you were just doing.
    @Test func aJustFinishedSessionIsAskedAbout() {
        let context = makeContext()
        let session = endedSession(context, endedAgo: 30)
        #expect(SessionNotePrompt.candidate(among: [session], watermark: 0)?.id == session.id)
    }

    /// **The line between helpful and an interrogation.** "What happened?" is
    /// a good question about ten minutes ago and a bad one about last Tuesday,
    /// so anything past the window is left alone forever.
    @Test func anOldSessionIsNeverAskedAbout() {
        let context = makeContext()
        let old = endedSession(context, endedAgo: SessionNotePrompt.window + 60)
        #expect(SessionNotePrompt.candidate(among: [old], watermark: 0) == nil)
    }

    /// Already written about is already answered.
    @Test func aSessionThatAlreadyHasANoteIsSkipped() {
        let context = makeContext()
        let written = endedSession(context, endedAgo: 30, notes: "Beat the third boss.")
        #expect(SessionNotePrompt.candidate(among: [written], watermark: 0) == nil)
    }

    /// A whitespace note is not a note, so the question is still open.
    @Test func aBlankNoteDoesNotCountAsAnswered() {
        let context = makeContext()
        let blank = endedSession(context, endedAgo: 30, notes: "   ")
        #expect(SessionNotePrompt.candidate(among: [blank], watermark: 0) != nil)
    }

    /// A running session has not ended; there is nothing to ask about yet.
    @Test func aRunningSessionIsNotACandidate() {
        let context = makeContext()
        let running = endedSession(context, endedAgo: 30)
        running.endDate = nil
        #expect(SessionNotePrompt.candidate(among: [running], watermark: 0) == nil)
    }

    @Test func aDeletedSessionIsNotACandidate() {
        let context = makeContext()
        let gone = endedSession(context, endedAgo: 30, deleted: true)
        #expect(SessionNotePrompt.candidate(among: [gone], watermark: 0) == nil)
    }

    /// The watermark is what stops a relaunch asking the same question again.
    @Test func theWatermarkRetiresASessionForGood() {
        let context = makeContext()
        let session = endedSession(context, endedAgo: 30)
        let mark = session.endDate!.timeIntervalSinceReferenceDate
        #expect(SessionNotePrompt.candidate(among: [session], watermark: mark) == nil)
    }

    /// Two in the window means the one you just finished, not the older one.
    @Test func theMostRecentlyEndedSessionWins() {
        let context = makeContext()
        let older = endedSession(context, endedAgo: 400)
        let newer = endedSession(context, endedAgo: 20)
        #expect(SessionNotePrompt.candidate(among: [older, newer], watermark: 0)?.id == newer.id)
    }

    /// **Writing a note must not touch the clock.** `updateSession` recomputes
    /// the duration from start and end, and for a session that was paused those
    /// deliberately disagree — so routing a note through it would inflate the
    /// recorded playtime. This is the same class of bug build 34 fixed in the
    /// session editor, and the notes-only path exists to avoid repeating it.
    @Test func savingANoteLeavesAPausedSessionsDurationAlone() {
        let context = makeContext()
        let session = endedSession(context, endedAgo: 30)
        // Half an hour of wall clock, ten minutes actually played.
        session.accumulatedDuration = 600
        let before = session.accumulatedDuration

        Repository(context).setSessionNotes(session, "Stopped for dinner halfway.")

        #expect(session.accumulatedDuration == before)
        #expect(session.notes == "Stopped for dinner halfway.")
    }
}

/// Build 36 — memories: the records that reach back further than the app does.
@MainActor
struct Build36MemoryTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private func utc(_ y: Int, _ m: Int, _ d: Int) -> Date {
        ReleaseCountdown.utc.date(from: DateComponents(year: y, month: m, day: d)) ?? .now
    }

    /// **The rule the whole fuzzy-date design rests on.** A model that
    /// round-trips "Christmas 1995 or 1996" into "Dec 1995 – Jan 1997" has
    /// destroyed the entry and made it slightly wrong in the same step.
    @Test func typedWordsAreShownVerbatim() {
        let memory = Memory(title: "Got a Sega Genesis",
                            kind: "acquired",
                            earliest: utc(1995, 12, 1),
                            latest: utc(1997, 1, 31),
                            precision: nil,
                            whenText: "Christmas 1995 or 1996")
        #expect(memory.dateText == "Christmas 1995 or 1996")
        #expect(memory.isUncertain)
    }

    /// The refinement, not a contradiction: re-rendering is correct for
    /// PRECISION, verbatim is correct for UNCERTAINTY. A date that was picked
    /// rather than described has no words to preserve, so storing a copy would
    /// only give the two a chance to disagree.
    @Test func aPickedDateRendersFromItsPrecision() {
        let yearOnly = Memory(title: "Beat it sometime that year",
                              earliest: utc(2011, 1, 1),
                              latest: utc(2011, 12, 31),
                              precision: "year")
        #expect(yearOnly.dateText == "2011")
        #expect(!yearOnly.isUncertain)
    }

    /// Whitespace is not words — it must not beat the renderable interval.
    @Test func blankWordsFallBackToThePrecision() {
        let memory = Memory(title: "A memory",
                            earliest: utc(2011, 1, 1),
                            latest: utc(2011, 12, 31),
                            precision: "year",
                            whenText: "   ")
        #expect(memory.dateText == "2011")
    }

    /// Narrowing the interval as evidence arrives — a photo's EXIF, say — must
    /// never overwrite the sentence. "Christmas 1995, confirmed by photo" is
    /// the right outcome; "December 25, 1995" is not.
    @Test func narrowingTheIntervalLeavesTheWordsAlone() {
        let memory = Memory(title: "Got a Sega Genesis",
                            kind: "acquired",
                            earliest: utc(1995, 12, 1),
                            latest: utc(1997, 1, 31),
                            precision: nil,
                            whenText: "Christmas 1995 or 1996")
        memory.earliest = utc(1995, 12, 25)
        memory.latest = utc(1995, 12, 25)
        #expect(memory.dateText == "Christmas 1995 or 1996")
    }

    /// A memory need not be about a game at all — "first LAN party" has
    /// neither a game nor a console, and that is the point of the model.
    @Test func aMemoryCanStandAloneWithNoGame() {
        let context = makeContext()
        let memory = Memory(title: "First LAN party", earliest: utc(2001, 6, 1),
                            latest: utc(2001, 6, 30), precision: "month")
        context.insert(memory)
        #expect(memory.game == nil)
        #expect(memory.dateText.contains("2001"))
    }

    /// **Deleting a game must not erase your memory of owning it.** The
    /// relationship is nullify rather than cascade, and it exists at all
    /// because CloudKit refuses to load a store with an inverse-less
    /// relationship — Memory.game on its own took the container down.
    @Test func deletingAGameLeavesTheMemoryStanding() throws {
        let context = makeContext()
        let game = Game(name: "Columns")
        let memory = Memory(title: "Came with the Genesis", kind: "acquired")
        context.insert(game)
        context.insert(memory)
        memory.game = game

        context.delete(game)
        try context.save()

        let survivors = try context.fetch(FetchDescriptor<Memory>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.title == "Came with the Genesis")
        #expect(survivors.first?.game == nil)
    }

    /// Ownership is a chain of events, not a current value — which is what
    /// lets it express owning the same thing twice with a gap in the middle,
    /// the story Game.ownership's chip array cannot tell.
    @Test func ownershipIsAChainOfDatedEvents() {
        let context = makeContext()
        for (kind, year) in [("acquired", 1995), ("sold", 2004), ("acquired", 2026)] {
            let event = Memory(title: "\(kind) \(year)", kind: kind,
                               earliest: utc(year, 1, 1), latest: utc(year, 12, 31),
                               precision: "year")
            context.insert(event)
        }
        let chain = (try? context.fetch(FetchDescriptor<Memory>()))?
            .sorted { $0.earliest < $1.earliest } ?? []
        #expect(chain.map(\.kind) == ["acquired", "sold", "acquired"])
    }
}

/// Build 36 — memories reaching the timeline, at the grain they actually have.
@MainActor
struct Build36MemoryTimelineTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private func utc(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Memory.calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? .now
    }

    /// **The heading a disjunction gets.** "Christmas 1995 or 1996" under a
    /// heading reading 1995 would assert the one thing the record declines to,
    /// so it becomes its own period titled by what was actually written.
    @Test func anUncertainMemoryIsItsOwnPeriodInItsOwnWords() {
        let memory = Memory(title: "Got a Sega Genesis", kind: "acquired",
                            earliest: utc(1995, 1, 1), latest: utc(1996, 12, 31),
                            precision: nil, whenText: "Christmas 1995 or 1996")
        let periods = JournalBuilder.periods(from: [], standalone: [memory])
        #expect(periods.count == 1)
        #expect(periods.first?.title() == "Christmas 1995 or 1996")
    }

    /// Two uncertain memories in one year stay two periods — merging them
    /// would file one under the other's sentence.
    @Test func twoUncertainMemoriesDoNotMerge() {
        let a = Memory(title: "Genesis", earliest: utc(1995, 1, 1), latest: utc(1996, 12, 31),
                       precision: nil, whenText: "Christmas 1995 or 1996")
        let b = Memory(title: "Game Gear", earliest: utc(1995, 1, 1), latest: utc(1996, 12, 31),
                       precision: nil, whenText: "A birthday around then")
        #expect(JournalBuilder.periods(from: [], standalone: [a, b]).count == 2)
    }

    /// A memory that DOES have a grain is perfectly happy under a normal
    /// heading — the override is for uncertainty, not for memories.
    @Test func aYearPrecisionMemoryUsesTheYearHeading() {
        let memory = Memory(title: "Finished it at last",
                            earliest: utc(2011, 1, 1), latest: utc(2011, 12, 31),
                            precision: "year")
        let periods = JournalBuilder.periods(from: [], standalone: [memory])
        #expect(periods.first?.title() == "2011")
        #expect(periods.first?.grain == .year)
    }

    /// A memory with no game reaches the timeline through nothing else — it is
    /// the reason the model allows a nil game at all.
    @Test func aStandaloneMemoryStillAppears() {
        let memory = Memory(title: "First LAN party",
                            earliest: utc(2001, 6, 1), latest: utc(2001, 6, 30),
                            precision: "month")
        let entries = JournalBuilder.periods(from: [], standalone: [memory])
            .flatMap(\.entries)
        #expect(entries.count == 1)
        #expect(entries.first?.game == nil)
        #expect(entries.first?.kind == .memory)
    }

    /// **The interval, not the instant.** A year-precision memory must span the
    /// whole year — stored as a bare instant it would sort as though its
    /// precision were a day, which is what the precision field exists to stop.
    @Test func savingAYearPrecisionMemorySpansTheYear() {
        let context = makeContext()
        let memory = Memory(title: "Beat it that year")
        Repository(context).saveMemory(memory, on: utc(2011, 7, 14),
                                       precision: "year", words: nil)
        #expect(memory.earliest == utc(2011, 1, 1))
        #expect(Memory.calendar.component(.year, from: memory.latest) == 2011)
        #expect(Memory.calendar.component(.month, from: memory.latest) == 12)
    }

    /// Saving a disjunction stores nil precision — "1995 or 1996" is two
    /// years, and claiming year precision would say it was one.
    @Test func savingAnUncertainSpanStoresNoPrecision() {
        let context = makeContext()
        let memory = Memory(title: "Got a Sega Genesis")
        Repository(context).saveMemory(
            memory, on: utc(1995, 1, 1), precision: nil,
            words: "Christmas 1995 or 1996",
            span: utc(1995, 1, 1)...utc(1996, 12, 31))
        #expect(memory.precision == nil)
        #expect(memory.isUncertain)
        #expect(memory.whenText == "Christmas 1995 or 1996")
    }

    /// Blank words are not words — they must not be stored as if they were,
    /// or the entry would print nothing where its date should be.
    @Test func blankWordsAreNotStored() {
        let context = makeContext()
        let memory = Memory(title: "A memory")
        Repository(context).saveMemory(memory, on: utc(2011, 1, 1),
                                       precision: "year", words: "   ")
        #expect(memory.whenText == nil)
        #expect(memory.dateText == "2011")
    }

    /// **The predicate the timeline actually runs.**
    ///
    /// A memory with no game is fetched rather than walked to from a game, so
    /// the whole standalone path depends on SwiftData evaluating `game == nil`
    /// against a *relationship*. That is exactly the sort of predicate that
    /// compiles, reads correctly, and quietly matches nothing — and if it did,
    /// "first LAN party" would vanish with no error anywhere.
    @Test func theStandaloneQueryFindsMemoriesWithNoGame() throws {
        let context = makeContext()
        let attached = Memory(title: "Finished Columns")
        let game = Game(name: "Columns")
        context.insert(game)
        context.insert(attached)
        attached.game = game

        let alone = Memory(title: "First LAN party")
        context.insert(alone)
        try context.save()

        let found = try context.fetch(FetchDescriptor<Memory>(
            predicate: #Predicate { $0.deletedAt == nil && $0.game == nil }))
        #expect(found.count == 1)
        #expect(found.first?.title == "First LAN party")
    }

    /// An ownership event says which verb it was; a plain memory does not.
    @Test func anOwnershipEventNamesItself() {
        let acquired = Memory(title: "Got a Genesis", kind: "acquired")
        acquired.platform = "Sega Genesis"
        #expect(acquired.detailLine?.contains("Acquired") == true)
        #expect(acquired.detailLine?.contains("Sega Genesis") == true)

        let plain = Memory(title: "Played at a friend's")
        #expect(plain.detailLine == nil)
    }

    /// A kind this build has never heard of — added later, arriving over
    /// CloudKit — reads as a plain memory rather than failing to decode.
    @Test func anUnknownKindDegradesToAPlainMemory() {
        let future = Memory(title: "Something new", kind: "repaired")
        #expect(Memory.kindLabels["repaired"] == nil)
        #expect(future.detailLine == nil)
    }
}

/// Build 36 — Old Favorite is beaten-agnostic, and finishing had to stop
/// meaning "the status currently says Completed".
@MainActor
struct Build36OldFavoriteTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// **The bug the status would otherwise have caused.** Sonic 2 is beaten
    /// and will be beaten again. Moving it to Old Favorite must not un-beat
    /// it — counting `status == .completed` made the finished percentage fall
    /// when a game simply moved shelves.
    @Test func aBeatenGameStaysFinishedAfterMovingToOldFavorite() {
        let context = makeContext()
        let game = Game(name: "Sonic the Hedgehog 2", status: .completed)
        let finish = CompletionEvent(date: .now, label: .cleared)
        context.insert(game)
        context.insert(finish)
        finish.game = game
        #expect(game.isFinished)

        game.status = .oldFavorite
        #expect(game.isFinished, "A completion event is the record; the status is only where it sits now.")
    }

    /// The fallback, for the games marked Completed before there was any event
    /// to record — 13 of Tim's 21 on the day this shipped.
    @Test func statusAloneStillCountsAsFinished() {
        let game = Game(name: "An old import", status: .completed)
        #expect(game.isFinished)
    }

    /// And a game nobody ever finished is not finished, whatever else is true.
    @Test func anOldFavoriteWithNoFinishIsNotFinished() {
        let game = Game(name: "Awesome Possum", status: .oldFavorite)
        #expect(!game.isFinished)
    }

    /// A deleted completion event does not keep a game finished — Recently
    /// Deleted has to mean something.
    @Test func aDeletedFinishDoesNotCount() {
        let context = makeContext()
        let game = Game(name: "Barkley Shut Up and Jam", status: .oldFavorite)
        let finish = CompletionEvent(date: .now, label: .cleared)
        finish.deletedAt = .now
        context.insert(game)
        context.insert(finish)
        finish.game = game
        #expect(!game.isFinished)
    }

    /// The status carries no claim about finishing in either direction — which
    /// is the whole point of it, and the thing its blurb has to keep saying.
    @Test func oldFavoriteSaysNothingAboutFinishing() {
        #expect(!GameStatus.oldFavorite.blurb.lowercased().contains("never"))
        #expect(!GameStatus.oldFavorite.blurb.lowercased().contains("unfinished"))
        // It is the pair to `ongoing`, and the two must stay distinguishable:
        // one has no ending, the other has one that does not matter.
        #expect(GameStatus.ongoing.blurb != GameStatus.oldFavorite.blurb)
    }
}
