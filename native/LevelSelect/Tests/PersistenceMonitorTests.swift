import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Beta P0: Repository mutations must be explicitly committed — visible from a
/// second context immediately, not whenever autosave gets around to it.
@MainActor
struct PersistenceMonitorTests {

    @Test func repositoryMutationIsDurableAcrossContexts() throws {
        let container = LevelSelectStore.makeContainer(inMemory: true)
        let repo = Repository(ModelContext(container))

        let game = repo.addGame(name: "Persist Me")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.startSession(on: pt)

        // A brand-new context only sees SAVED state — this fails if the
        // mutations were still sitting unsaved in the first context.
        let fresh = ModelContext(container)
        let games = try fresh.fetch(FetchDescriptor<Game>())
        #expect(games.count == 1)
        #expect(games.first?.name == "Persist Me")
        let sessions = try fresh.fetch(FetchDescriptor<Session>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.state == .running)
    }

    /// Every test store comes from this factory, so this is the one place the
    /// suite's stability is decided. An in-memory configuration left on
    /// `.automatic` resolves to the app's iCloud container, and the mirroring
    /// delegate that comes with it intermittently crashed saves with "No
    /// eligible connection available" — reported as a PASS with exit code 65.
    @Test func inMemoryStoresNeverMirrorToCloudKit() {
        let container = LevelSelectStore.makeContainer(inMemory: true)
        #expect(container.configurations.allSatisfy { $0.cloudKitContainerIdentifier == nil })
    }

    @Test func sessionLifecycleCommitsEachTransition() throws {
        let container = LevelSelectStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = Repository(context)
        let game = repo.addGame(name: "Lifecycle")
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let session = repo.startSession(on: pt, at: Date(timeIntervalSinceNow: -600))
        repo.pauseSession(session)
        #expect(try latestState(container) == .paused)
        repo.resumeSession(session)
        #expect(try latestState(container) == .running)
        repo.stopSession(session)
        #expect(try latestState(container) == .stopped)
    }

    @Test func monitorCommitIsNoOpWithoutChangesAndClearsOnDismiss() {
        let container = LevelSelectStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let monitor = PersistenceMonitor.shared

        monitor.commit(context)          // no changes — must not record failure
        #expect(monitor.lastErrorMessage == nil)
        monitor.retry()                  // nothing pending — safe no-op
        monitor.dismiss()
        #expect(monitor.lastErrorMessage == nil)
    }

    private func latestState(_ container: ModelContainer) throws -> SessionState? {
        try ModelContext(container).fetch(FetchDescriptor<Session>()).first?.state
    }
}
