import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Library's select mode can delete a selection (09-21) — the last gap in
/// `docs/legacy-web-parity.md`. Deleting several is one action, so undoing it
/// puts all of them back.
@MainActor
struct Build40BulkDeleteTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func games(_ repo: Repository, _ names: [String]) -> [Game] {
        names.map { repo.addGame(name: $0) }
    }

    @Test("Deleting a selection hides every game in it, and nothing else")
    func deletingASelection() {
        let repo = store()
        let all = games(repo, ["Hades", "Celeste", "Tunic"])
        for game in all.prefix(2) { repo.softDelete(game) }
        #expect(all[0].deletedAt != nil)
        #expect(all[1].deletedAt != nil)
        #expect(all[2].deletedAt == nil)
    }

    @Test("Undo restores the whole batch, not just the first game")
    func undoRestoresTheBatch() {
        let repo = store()
        let all = games(repo, ["Hades", "Celeste", "Tunic"])
        for game in all { repo.softDelete(game) }
        let undo = AppNavigator.DeletedGame(id: all[0].id, name: "3 games",
                                            alsoDeleted: all.dropFirst().map(\.id))
        #expect(undo.allIDs.count == 3)
        for id in undo.allIDs { #expect(repo.restoreGame(id: id)) }
        #expect(all.allSatisfy { $0.deletedAt == nil })
    }
}
