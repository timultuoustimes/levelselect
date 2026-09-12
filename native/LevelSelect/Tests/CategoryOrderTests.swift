import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Which order the tracker's categories sit in.
///
/// Two rules that have to coexist: planned scaffolding sinks below real
/// content automatically, and above that line the order is the user's to set —
/// "Korok Seeds at the top so I can tap + while I play" is a statement about
/// how someone plays, not something the generator gets to decide.
///
/// Both act on the STORED order rather than sorting at render time, so there
/// is exactly one order: what you see is what a move then acts on, and the
/// iPad shows the same thing.
@MainActor
struct CategoryOrderTests {

    private func game() -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: "Breath of the Wild", status: .playing))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    private func names(_ repo: Repository, _ game: Game) -> [String] {
        repo.trackerCategories(for: game).map(\.name)
    }

    private func id(_ repo: Repository, _ game: Game, _ name: String) -> String {
        repo.trackerCategories(for: game).first { $0.name == name }!.id
    }

    /// Filling a category lifts it above the ones still waiting — including
    /// past a planned category that was sitting above it.
    @Test func aFilledCategoryRisesAboveThePlannedOnes() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Shrines", plannedCount: 120)
        repo.addPlannedCategory(to: game, named: "Memories", plannedCount: 18)
        repo.addPlannedCategory(to: game, named: "Towers", plannedCount: 15)
        #expect(names(repo, game) == ["Shrines", "Memories", "Towers"])

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "memories", "name": "Memories", "type": "collectibles",
             "items": [["id": "m1", "name": "Subdued Ceremony"]]],
        ]), mode: .replaceCategories(ids: [id(repo, game, "Memories")]))

        #expect(names(repo, game) == ["Memories", "Shrines", "Towers"])
    }

    /// The already-filled ones keep their own order when another joins them —
    /// sinking the planned block must not reshuffle everything else.
    @Test func sinkingThePlannedBlockLeavesFilledOrderAlone() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "beasts", "name": "Divine Beasts", "type": "checklist",
             "items": [["id": "b1", "name": "Vah Ruta"]]],
            ["id": "quests", "name": "Main Quests", "type": "sequence",
             "items": [["id": "q1", "name": "Follow the Sheikah Slate"]]],
        ]), mode: .addAll)
        repo.addPlannedCategory(to: game, named: "Shrines", plannedCount: 120)
        repo.addPlannedCategory(to: game, named: "Towers", plannedCount: 15)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "towers", "name": "Towers", "type": "checklist",
             "items": [["id": "t1", "name": "Great Plateau Tower"]]],
        ]), mode: .replaceCategories(ids: [id(repo, game, "Towers")]))

        #expect(names(repo, game) == ["Divine Beasts", "Main Quests", "Towers", "Shrines"])
    }

    /// The actual ask: pin the one you're working on to the top.
    @Test func moveToTopPutsACategoryFirstAndKeepsTheRestInOrder() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "a", "name": "Divine Beasts", "type": "checklist", "items": [["id": "1", "name": "One"]]],
            ["id": "b", "name": "Main Quests", "type": "checklist", "items": [["id": "2", "name": "Two"]]],
            ["id": "c", "name": "Korok Seeds", "type": "collectibles", "items": [["id": "3", "name": "Korok Seeds"]]],
        ]), mode: .addAll)

        #expect(repo.moveCategoryToTop("c", in: game))
        #expect(names(repo, game) == ["Korok Seeds", "Divine Beasts", "Main Quests"])
    }

    /// And it survives a reload from the store, because it is written to the
    /// schema rather than held in the view.
    @Test func aManualOrderIsWrittenToTheSchema() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "a", "name": "First", "type": "checklist", "items": [["id": "1", "name": "One"]]],
            ["id": "b", "name": "Second", "type": "checklist", "items": [["id": "2", "name": "Two"]]],
        ]), mode: .addAll)
        repo.moveCategoryToTop("b", in: game)

        let stored = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
        #expect(stored.map(\.id) == ["b", "a"])
    }

    @Test func movingUpAndDownWalksOneStepAtATime() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "a", "name": "A", "type": "checklist", "items": [["id": "1", "name": "One"]]],
            ["id": "b", "name": "B", "type": "checklist", "items": [["id": "2", "name": "Two"]]],
            ["id": "c", "name": "C", "type": "checklist", "items": [["id": "3", "name": "Three"]]],
        ]), mode: .addAll)

        #expect(repo.moveCategory("c", in: game, by: -1))
        #expect(names(repo, game) == ["A", "C", "B"])
        #expect(repo.moveCategory("c", in: game, by: -1))
        #expect(names(repo, game) == ["C", "A", "B"])
        #expect(repo.moveCategory("c", in: game, by: 1))
        #expect(names(repo, game) == ["A", "C", "B"])
    }

    /// Moving off either end is refused rather than silently wrapping around
    /// to the other one — a disabled menu item, not a surprise jump.
    @Test func movingPastEitherEndIsRefused() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "a", "name": "A", "type": "checklist", "items": [["id": "1", "name": "One"]]],
            ["id": "b", "name": "B", "type": "checklist", "items": [["id": "2", "name": "Two"]]],
        ]), mode: .addAll)

        #expect(repo.moveCategory("a", in: game, by: -1) == false)
        #expect(repo.moveCategory("b", in: game, by: 1) == false)
        #expect(repo.moveCategoryToTop("a", in: game) == false)   // already there
        #expect(names(repo, game) == ["A", "B"])
    }

    /// A reorder must never lose, duplicate, or empty a category — this writes
    /// the whole array back, so a bug here costs the tracker.
    @Test func reorderingNeverLosesOrDuplicatesContent() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "a", "name": "A", "type": "checklist",
             "items": [["id": "1", "name": "One"], ["id": "2", "name": "Two"]]],
            ["id": "b", "name": "B", "type": "checklist", "items": [["id": "3", "name": "Three"]]],
        ]), mode: .addAll)
        repo.addPlannedCategory(to: game, named: "Planned", plannedCount: 9)

        repo.moveCategoryToTop("b", in: game)

        let after = repo.trackerCategories(for: game)
        #expect(after.count == 3)
        #expect(Set(after.map(\.id)).count == 3)
        #expect(after.first { $0.id == "a" }?.items.count == 2)
        #expect(after.first { $0.id == "b" }?.items.count == 1)
        // And the planned one is still planned, with its size intact.
        #expect(after.first { $0.name == "Planned" }?.plannedCount == 9)
    }

    /// An unknown id changes nothing. The ids come from a JSON blob, so a
    /// stale one is a real possibility, and dropping every category not named
    /// in the list would be catastrophic.
    @Test func anUnknownIdIsIgnoredRatherThanDestructive() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "a", "name": "A", "type": "checklist", "items": [["id": "1", "name": "One"]]],
            ["id": "b", "name": "B", "type": "checklist", "items": [["id": "2", "name": "Two"]]],
        ]), mode: .addAll)

        #expect(repo.moveCategoryToTop("does-not-exist", in: game) == false)
        #expect(names(repo, game) == ["A", "B"])

        // And the underlying reorder keeps anything the list omits.
        let data = TrackerSchemaJSON.reordering(to: ["b"], in: game.trackerSchema!.jsonData)!
        #expect(TrackerSchemaJSON.categories(from: data).map(\.id) == ["b", "a"])
    }
}
