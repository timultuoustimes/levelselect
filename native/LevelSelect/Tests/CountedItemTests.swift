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

/// A pin on a counted item is one spot of many. Exploring it used to tick the
/// whole item — one Korok Seed found, all 900 marked done — because a linked
/// pin read and wrote the item's checkbox.
@MainActor
struct CountedItemPinTests {

    private var png: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
    }

    private func setUp() throws -> (Repository, Game, Playthrough, GameMap) {
        let repo = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let game = repo.addGame(name: "Breath of the Wild", status: .playing)
        let schema = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "collect", "name": "Collectibles", "type": "checklist",
                            "items": [["id": "korok", "name": "Korok Seeds", "countTarget": 900],
                                      ["id": "master-sword", "name": "Master Sword"]]]],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let map = try repo.addMap(to: game, data: png, name: "Hyrule", kind: .world)
        return (repo, game, pt, map)
    }

    private func states(_ pt: Playthrough) -> [String: TrackerStateRecord] {
        Dictionary((pt.trackerStates ?? []).filter { $0.deletedAt == nil }.map { ($0.itemID, $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    @Test("Exploring one seed's pin counts one seed, not all 900")
    func exploringAPinCountsOne() throws {
        let (repo, game, pt, map) = try setUp()
        let a = repo.addMarker(to: map, x: 0.2, y: 0.2, linkedTrackerItemID: "korok")
        let b = repo.addMarker(to: map, x: 0.8, y: 0.8, linkedTrackerItemID: "korok")

        repo.setExplored(a, true, in: game)

        #expect(repo.trackerState(pt, itemID: "korok")?.count == 1)
        #expect(repo.trackerState(pt, itemID: "korok")?.completed == false)
        let counted: Set<String> = ["korok"]
        #expect(repo.isExplored(a, states: states(pt), counted: counted))
        // The other seed hasn't been found just because this one was.
        #expect(!repo.isExplored(b, states: states(pt), counted: counted))
    }

    @Test("Exploring the same pin twice counts it once; un-exploring takes it back")
    func noDriftFromRepeats() throws {
        let (repo, game, pt, map) = try setUp()
        let a = repo.addMarker(to: map, x: 0.2, y: 0.2, linkedTrackerItemID: "korok")
        repo.setExplored(a, true, in: game)
        repo.setExplored(a, true, in: game)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 1)

        repo.setExplored(a, false, in: game)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 0)
        #expect(a.exploredAt == nil)
    }

    @Test("A checkbox item's pin still ticks the item")
    func checkboxItemsUnchanged() throws {
        let (repo, game, pt, map) = try setUp()
        let sword = repo.addMarker(to: map, x: 0.5, y: 0.5, linkedTrackerItemID: "master-sword")
        repo.setExplored(sword, true, in: game)
        #expect(repo.trackerState(pt, itemID: "master-sword")?.completed == true)
        // One record of it being done, not two.
        #expect(sword.exploredAt == nil)
    }

    @Test("A found pin belongs to the playthrough: a new run starts it unfound, and shows it was found before")
    func pinsArePerPlaythrough() throws {
        let (repo, game, pt, map) = try setUp()
        let a = repo.addMarker(to: map, x: 0.2, y: 0.2, linkedTrackerItemID: "korok")
        _ = repo.addMarker(to: map, x: 0.8, y: 0.8, linkedTrackerItemID: "korok")
        let counted: Set<String> = ["korok"]
        repo.setExplored(a, true, in: game)

        let second = repo.addPlaythrough(to: game, named: "Second run")
        #expect(game.activePlaythrough?.id == second.id)
        #expect(!repo.isExplored(a, states: states(second), counted: counted))
        #expect(repo.markersFoundBefore(in: game, counted: counted) == [a.id])

        repo.setExplored(a, true, in: game)
        #expect(repo.trackerState(second, itemID: "korok")?.count == 1)
        #expect(repo.markersFoundBefore(in: game, counted: counted).isEmpty)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 1)
    }

    @Test("Two devices' finds, synced, add up instead of overwriting each other")
    func syncedFindsAddUp() throws {
        let (repo, game, pt, map) = try setUp()
        let a = repo.addMarker(to: map, x: 0.2, y: 0.2, linkedTrackerItemID: "korok")
        let b = repo.addMarker(to: map, x: 0.8, y: 0.8, linkedTrackerItemID: "korok")
        // This device found a; the other device's find of b arrives as its own
        // state, while the count record kept this device's 1.
        repo.setExplored(a, true, in: game)
        repo.setTrackerItem(pt, itemID: repo.pinStateID(b), done: true)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 1)

        let outcome = repo.reconcile(game)
        #expect(outcome.flooredCounts == 1)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 2)
    }

    @Test("Deleting or relinking a found pin takes its count back")
    func deleteAndRelinkTakeTheCountBack() throws {
        let (repo, game, pt, map) = try setUp()
        let a = repo.addMarker(to: map, x: 0.2, y: 0.2, linkedTrackerItemID: "korok")
        let b = repo.addMarker(to: map, x: 0.8, y: 0.8, linkedTrackerItemID: "korok")
        repo.setExplored(a, true, in: game)
        repo.setExplored(b, true, in: game)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 2)

        repo.deleteMarker(a)
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 1)

        repo.updateMarker(b, label: "", category: .collectible, notes: "", linkedTrackerItemID: "master-sword")
        #expect(repo.trackerState(pt, itemID: "korok")?.count == 0)
        #expect(repo.trackerState(pt, itemID: repo.pinStateID(b))?.completed != true)
    }

    @Test("An old game-wide found stamp moves into the playthrough, once")
    func legacyStampsMigrate() throws {
        let (repo, game, pt, map) = try setUp()
        let pin = repo.addMarker(to: map, x: 0.5, y: 0.5, label: "Bench")
        pin.exploredAt = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(repo.markersFoundBefore(in: game, counted: []) == [pin.id])

        #expect(repo.reconcile(game).migratedPins == 1)
        #expect(pin.exploredAt == nil)
        #expect(repo.isExplored(pin, states: states(pt)))
        #expect(repo.trackerState(pt, itemID: repo.pinStateID(pin))?.completedAt
                == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(repo.reconcile(game).migratedPins == 0)
    }

    @Test("A counted item knows its target; a checkbox has none")
    func countTargets() throws {
        let (repo, game, _, _) = try setUp()
        #expect(repo.countTarget(of: "korok", in: game) == 900)
        #expect(repo.countTarget(of: "master-sword", in: game) == nil)
        #expect(repo.countTarget(of: "missing", in: game) == nil)
    }
}

/// A planned category that gets items stops being a plan, however the items
/// arrived. Only a one-category fill used to clear the flag, so a pasted list
/// or a regeneration filling a plan by name left it sunk among the unfilled
/// plans, still quoting its planned size.
@MainActor
struct PlannedCategoryFillTests {

    private func trackerWithPlan() -> (Repository, Game) {
        let repo = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let plan = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [
                ["id": "grubs", "name": "Grubs", "items": [["id": "g1", "name": "Grub 1"]]],
                ["id": "cat-endings", "name": "Endings", "pending": true, "plannedCount": 4, "items": []],
            ],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: plan, mode: .addAll)
        return (repo, game)
    }

    private var endingsArrive: Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "endings", "name": "Endings",
                            "items": [["id": "sealed", "name": "Sealed Siblings"]]]],
        ])
    }

    @Test("A plan filled by Add New stops being a plan, and isn't duplicated")
    func addNewFillsThePlan() {
        let (repo, game) = trackerWithPlan()
        #expect(repo.trackerCategories(for: game).first { $0.name == "Endings" }?.pending == true)

        repo.applyGeneratedSchema(for: game, jsonData: endingsArrive, mode: .addAll)

        let endings = repo.trackerCategories(for: game).filter { $0.name == "Endings" }
        #expect(endings.count == 1, "the plan should be filled, not joined by a second Endings")
        #expect(endings.first?.items.isEmpty == false)
        #expect(endings.first?.pending == false)
    }

    @Test("A plan filled by Replace stops being a plan")
    func replaceFillsThePlan() {
        let (repo, game) = trackerWithPlan()
        repo.applyGeneratedSchema(for: game, jsonData: endingsArrive, mode: .replace)
        let endings = repo.trackerCategories(for: game).first { $0.name == "Endings" }
        #expect(endings?.items.isEmpty == false)
        #expect(endings?.pending == false)
    }
}

/// Add New reported "added 16, removed 16" after removing nothing: the summary
/// was the diff's count of what a REPLACE would do.
@MainActor
struct AddNewOutcomeTests {
    private func data(_ raw: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": raw])
    }

    @Test("Add New reports what it added, and never claims to have removed anything")
    func reportsWhatHappened() {
        let repo = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: data([
            ["id": "grubs", "name": "Grubs",
             "items": [["id": "g1", "name": "Grub 1"], ["id": "g2", "name": "Grub 2"]]],
        ]), mode: .addAll)

        // The answer names Grub 2 differently and brings two new grubs. A
        // Replace would remove "Grub 2"; Add New keeps it.
        let outcome = repo.applyGeneratedSchema(for: game, jsonData: data([
            ["id": "grubs", "name": "Grubs",
             "items": [["id": "g1", "name": "Grub 1"],
                       ["id": "x1", "name": "Grub in Crossroads"],
                       ["id": "x2", "name": "Grub in Greenpath"]]],
        ]), mode: .addAll)

        let total = repo.trackerCategories(for: game).flatMap(\.items).count
        #expect(outcome.removed == 0)
        #expect(outcome.renamed == 0)
        #expect(outcome.added == total - 2)
        #expect(total == 4)
    }
}
