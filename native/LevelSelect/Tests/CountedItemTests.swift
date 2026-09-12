import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Counted items: one row that counts instead of hundreds that can't exist.
///
/// 900 koroks, 100 seeds, a shiny counter — these are the games the tracker
/// simply couldn't hold, because nobody generates or scrolls nine hundred
/// rows. `TrackerStateRecord.count` has been in the store and deployed to
/// CloudKit Production the whole time with nothing reading or writing it.
@MainActor
struct CountedItemTests {

    private func game() -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Breath of the Wild", status: .playing)
        let schema = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "collect", "name": "Collectibles", "type": "checklist",
                            "items": [["id": "korok", "name": "Korok Seeds",
                                       "countTarget": 900]]]],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    private func item(_ repo: Repository, _ game: Game) -> TrackerItemDTO? {
        repo.trackerCategories(for: game).flatMap(\.items).first { $0.id == "korok" }
    }

    @Test func aTargetSurvivesTheSchemaRoundTrip() {
        let (repo, game, _) = self.game()
        #expect(item(repo, game)?.countTarget == 900)
    }

    @Test func countingUpTicksTheItemOnlyAtTheTarget() {
        let (repo, game, pt) = self.game()
        repo.setTrackerCount(pt, itemID: "korok", count: 899, target: 900)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 899)
        #expect(repo.trackerState(pt, itemID: "korok")?.completed == false)

        repo.setTrackerCount(pt, itemID: "korok", count: 900, target: 900)
        #expect(repo.trackerState(pt, itemID: "korok")?.completed == true)
        #expect(pt.progressPercent == 100)
    }

    /// Miscounting is normal — the number goes down as easily as up, and the
    /// tick comes back off with it rather than staying stuck on.
    @Test func countingBackDownUnticksIt() {
        let (repo, game, pt) = self.game()
        repo.setTrackerCount(pt, itemID: "korok", count: 900, target: 900)
        repo.setTrackerCount(pt, itemID: "korok", count: 899, target: 900)

        #expect(repo.trackerState(pt, itemID: "korok")?.completed == false)
        #expect(pt.progressPercent == 0)
    }

    /// The control's edges: no negative counts, nothing past the total.
    @Test func countsAreClampedToTheirRange() {
        let (repo, game, pt) = self.game()
        repo.setTrackerCount(pt, itemID: "korok", count: -5, target: 900)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 0)

        repo.setTrackerCount(pt, itemID: "korok", count: 5000, target: 900)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 900)
        #expect(repo.trackerState(pt, itemID: "korok")?.completed == true)
    }

    /// Any item can become a counter, and go back to being a checkbox — an
    /// empty total must clear the key, not leave a stale one behind.
    @Test func anItemCanBecomeACounterAndStopBeingOne() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "categories": [["id": "grubs", "name": "Grubs", "type": "checklist",
                                "items": [["id": "grub", "name": "Grubs rescued"]]]],
            ]), mode: .addAll)

        #expect(repo.trackerCategories(for: game).flatMap(\.items).first?.countTarget == nil)

        repo.setTrackerCountTarget(game, categoryID: "grubs", itemID: "grub", target: 46)
        #expect(repo.trackerCategories(for: game).flatMap(\.items).first?.countTarget == 46)

        repo.setTrackerCountTarget(game, categoryID: "grubs", itemID: "grub", target: nil)
        #expect(repo.trackerCategories(for: game).flatMap(\.items).first?.countTarget == nil)
    }

    /// A counted item keeps its progress when a regeneration renames its id —
    /// counts ride the same state record as ticks, so the existing migration
    /// carries them.
    @Test func countsSurviveARenameMigration() {
        let (repo, game, pt) = self.game()
        repo.setTrackerCount(pt, itemID: "korok", count: 437, target: 900)

        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "categories": [["id": "collect", "name": "Collectibles", "type": "checklist",
                                "items": [["id": "korok-seeds", "name": "Korok Seeds",
                                           "countTarget": 900]]]],
            ]), mode: .replace)

        #expect(repo.trackerState(pt, itemID: "korok-seeds")?.count == 437)
    }
}
