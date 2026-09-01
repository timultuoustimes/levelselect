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
