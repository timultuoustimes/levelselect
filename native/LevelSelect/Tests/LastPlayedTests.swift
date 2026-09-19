import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// `Playthrough.lastPlayedAt` is a cache of "the newest session's start", and
/// every write that can move or remove a session has to keep it honest.
@MainActor
struct LastPlayedTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// The demo library exposed this plainly: sessions are seeded newest-first,
    /// so the final unconditional write was the OLDEST one and Hollow Knight's
    /// hero card read "last played 5 months ago" directly above a session list
    /// whose top row said two days.
    @Test func backfillingOldSessionsDoesNotMoveLastPlayedBackwards() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        // Newest first, exactly how the seeder writes them.
        for daysAgo in stride(from: 1.5, through: 136.5, by: 9) {
            _ = repo.logManualSession(on: pt, duration: 3600,
                                      date: Date.now.addingTimeInterval(-daysAgo * 86_400))
        }

        let days = Date.now.timeIntervalSince(pt.lastPlayedAt!) / 86_400
        #expect(days < 3, "last played should be the newest session, not the oldest")
    }

    /// Back-filling history is not playing it.
    @Test func aForgottenSessionFromLastMonthIsNotLastPlayed() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        _ = repo.logManualSession(on: pt, duration: 3600, date: .now)
        let recent = pt.lastPlayedAt!
        _ = repo.logManualSession(on: pt, duration: 3600,
                                  date: Date.now.addingTimeInterval(-30 * 86_400))

        #expect(pt.lastPlayedAt == recent)
    }

    /// Editing CAN move a date either way, so that path recomputes: dragging
    /// the newest session back a week moves "last played" back with it.
    @Test func editingTheNewestSessionMovesLastPlayed() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        _ = repo.logManualSession(on: pt, duration: 3600,
                                  date: Date.now.addingTimeInterval(-20 * 86_400))
        let newest = repo.logManualSession(on: pt, duration: 3600, date: .now)

        let movedTo = Date.now.addingTimeInterval(-40 * 86_400)
        repo.updateSession(newest, start: movedTo,
                           end: movedTo.addingTimeInterval(3600), notes: nil)

        // The 20-day-old session is now the most recent.
        let days = Date.now.timeIntervalSince(pt.lastPlayedAt!) / 86_400
        #expect(days > 19 && days < 21)
    }

    /// Deleting the most recent session used to leave the playthrough claiming
    /// a date whose session no longer existed.
    @Test func deletingTheNewestSessionMovesLastPlayedBack() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Tunic", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        _ = repo.logManualSession(on: pt, duration: 3600,
                                  date: Date.now.addingTimeInterval(-10 * 86_400))
        let newest = repo.logManualSession(on: pt, duration: 3600, date: .now)

        repo.deleteSession(newest)

        let days = Date.now.timeIntervalSince(pt.lastPlayedAt!) / 86_400
        #expect(days > 9 && days < 11)
    }

    /// Deleting the only session leaves nothing to claim.
    @Test func deletingTheOnlySessionClearsLastPlayed() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Balatro", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let only = repo.logManualSession(on: pt, duration: 3600, date: .now)

        repo.deleteSession(only)
        #expect(pt.lastPlayedAt == nil)
    }
}


/// Home and Stats have to mean the same thing by "a week".
@MainActor
struct RecentPlayWindowTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// Stats used calendar windows while Home used a rolling seven days, so on
    /// the 1st of a month the pair read "5h 59m this week / 0s this month" —
    /// a month containing less than the week inside it — and Home reported a
    /// different "this week" from Stats one tab over.
    @Test func aMonthNeverHoldsLessThanTheWeekInsideIt() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        // Two days ago — inside both windows however the calendar falls.
        _ = repo.logManualSession(on: pt, duration: 2 * 3600,
                                  date: Date.now.addingTimeInterval(-2 * 86_400))
        // Twenty days ago — inside the month only.
        _ = repo.logManualSession(on: pt, duration: 3 * 3600,
                                  date: Date.now.addingTimeInterval(-20 * 86_400))

        let week = Date.now.addingTimeInterval(-7 * 86_400)
        let month = Date.now.addingTimeInterval(-30 * 86_400)
        let sessions = (pt.sessions ?? []).filter { $0.deletedAt == nil }
        let inWeek = sessions.filter { $0.startDate >= week }.reduce(0) { $0 + $1.elapsed() }
        let inMonth = sessions.filter { $0.startDate >= month }.reduce(0) { $0 + $1.elapsed() }

        #expect(inWeek == 2 * 3600)
        #expect(inMonth == 5 * 3600)
        #expect(inMonth >= inWeek, "the longer window must always contain the shorter one")
    }

    /// And Stats' seven days is the same seven days Home counts.
    @Test func homeAndStatsAgreeOnAWeek() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        _ = repo.logManualSession(on: pt, duration: 90 * 60,
                                  date: Date.now.addingTimeInterval(-3 * 86_400))

        let summary = PlayerSummary.make(from: [game])
        let week = Date.now.addingTimeInterval(-7 * 86_400)
        let statsWeek = (pt.sessions ?? [])
            .filter { $0.deletedAt == nil && $0.startDate >= week }
            .reduce(0) { $0 + $1.elapsed() }

        #expect(summary.weekSeconds == statsWeek)
    }
}
