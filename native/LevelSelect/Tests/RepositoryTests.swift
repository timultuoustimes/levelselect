import Testing
import Foundation
import SwiftData
@testable import LevelSelect

@MainActor
struct RepositoryTests {

    private func newContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private func liveGameCount(_ ctx: ModelContext) throws -> Int {
        let d = FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil })
        return try ctx.fetchCount(d)
    }

    @Test func addGameThenSoftDeleteTombstones() throws {
        let ctx = newContext()
        let repo = Repository(ctx)
        let g = repo.addGame(name: "Hollow Knight", status: .playing)
        #expect(try liveGameCount(ctx) == 1)
        #expect(g.revision == 0)

        repo.softDelete(g)
        #expect(g.deletedAt != nil)
        #expect(g.revision == 1)                // touch bumped it
        #expect(try liveGameCount(ctx) == 0)    // filtered as tombstoned
        // row still exists (soft delete), just excluded from live queries:
        #expect(try ctx.fetchCount(FetchDescriptor<Game>()) == 1)
    }

    @Test func ensureDefaultPlaythroughIsIdempotent() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let g = repo.addGame(name: "Hades")
        let p1 = repo.ensureDefaultPlaythrough(for: g)
        let p2 = repo.ensureDefaultPlaythrough(for: g)
        #expect(p1.id == p2.id)
        #expect(g.playthroughs.filter { $0.deletedAt == nil }.count == 1)
        #expect(g.currentPlaythroughID == p1.id)
    }

    @Test func completionMarksGameCompleted() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let g = repo.addGame(name: "Celeste", status: .playing)
        repo.addCompletion(to: g, label: .completed)
        #expect(g.status == .completed)
        #expect(g.completionEvents.count == 1)
    }

    @Test func totalPlaytimeSumsSessions() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let g = repo.addGame(name: "Dead Cells", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: g)
        repo.logManualSession(on: pt, duration: 1000)
        repo.logManualSession(on: pt, duration: 2000)
        #expect(abs(pt.totalPlaytime() - 3000) < 0.001)
    }
}
