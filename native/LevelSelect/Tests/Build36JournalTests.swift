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
