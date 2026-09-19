import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Two timers on two different games, and the way back from a delete.
@MainActor
struct TimerAndUndoTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func running(_ repo: Repository, _ name: String) -> Session {
        let game = repo.addGame(name: name, status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        return repo.startSession(on: pt)
    }

    private func allSessions(_ repo: Repository) -> [Session] {
        (try? repo.context.fetch(FetchDescriptor<Session>())) ?? []
    }

    // MARK: Two games at once — Tim's E2

    @Test func oneTimerIsNotAConflict() {
        let repo = repo()
        _ = running(repo, "Hollow Knight")
        #expect(OverlappingTimerGuard.crossGameSessions(
            among: allSessions(repo), dismissed: []) == nil)
    }

    @Test func twoGamesTimingAtOnceIsRaised() {
        let repo = repo()
        _ = running(repo, "Hollow Knight")
        _ = running(repo, "Hades")

        let found = OverlappingTimerGuard.crossGameSessions(
            among: allSessions(repo), dismissed: [])
        #expect(found?.count == 2)
        // Oldest first: the one you forgot is the one being asked about.
        #expect(found?.first?.playthrough?.game?.name == "Hollow Knight")
    }

    /// The same game timed twice is the OTHER guard's business — a sync
    /// conflict, not a forgotten timer. Raising both would ask two questions
    /// about one situation.
    @Test func oneGameTimedTwiceIsLeftToTheOtherGuard() {
        let repo = repo()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        _ = repo.startSession(on: pt)
        // What a second device's session looks like when it arrives.
        let twin = Session(startDate: .now)
        repo.context.insert(twin)
        twin.playthrough = pt

        #expect(OverlappingTimerGuard.crossGameSessions(
            among: allSessions(repo), dismissed: []) == nil)
    }

    @Test func keepingBothIsRememberedForThatPair() {
        let repo = repo()
        _ = running(repo, "Hollow Knight")
        _ = running(repo, "Hades")
        let sessions = allSessions(repo)
        let key = OverlappingTimerGuard.key(for: sessions)

        #expect(OverlappingTimerGuard.crossGameSessions(
            among: sessions, dismissed: [key]) == nil)
    }

    /// …but a THIRD game is a new situation and asks again.
    @Test func aThirdGameAsksAgain() {
        let repo = repo()
        _ = running(repo, "Hollow Knight")
        _ = running(repo, "Hades")
        let firstKey = OverlappingTimerGuard.key(for: allSessions(repo))
        _ = running(repo, "Balatro")

        #expect(OverlappingTimerGuard.crossGameSessions(
            among: allSessions(repo), dismissed: [firstKey]) != nil)
    }

    @Test func aStoppedTimerIsNotAConflict() {
        let repo = repo()
        let first = running(repo, "Hollow Knight")
        _ = running(repo, "Hades")
        repo.stopSession(first)

        #expect(OverlappingTimerGuard.crossGameSessions(
            among: allSessions(repo), dismissed: []) == nil)
    }

    // MARK: Undo a delete — Tim's C3

    /// The toast holds an id, not the object: the row is tombstoned the moment
    /// it appears, and keeping a model object alive across that is how a
    /// deleted-object crash happens.
    @Test func aDeletedGameIsRestorableByID() {
        let repo = repo()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let id = game.id
        repo.softDelete(game)
        #expect(repo.trashedGames().count == 1)

        #expect(repo.restoreGame(id: id))
        #expect(repo.trashedGames().isEmpty)
    }

    @Test func restoringSomethingAlreadyGoneSaysSoRatherThanCrashing() {
        let repo = repo()
        #expect(repo.restoreGame(id: UUID()) == false)
    }
}
