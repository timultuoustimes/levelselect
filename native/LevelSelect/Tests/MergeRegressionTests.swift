import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Regressions from the external review of 2026-08-17.
///
/// Every one of these had a passing test beside it while the bug was live. The
/// common shape: the existing test used the happy-path input the code was
/// written for — one playthrough, distinct ids, no name collisions — so it
/// proved the intention rather than the behaviour. These use the boundary the
/// code actually accepts.
@MainActor
struct MergeRegressionTests {

    private func game(named name: String) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    private func category(id: String, name: String, items: [(String, String)],
                          locked: Bool = false) -> [String: Any] {
        var cat: [String: Any] = ["id": id, "name": name, "type": "checklist",
                                  "items": items.map { ["id": $0.0, "name": $0.1] }]
        if locked { cat["locked"] = true }
        return cat
    }

    // MARK: 1 — replacement must migrate EVERY playthrough

    /// The schema belongs to the game, so a regeneration affects all of its
    /// playthroughs. Migrating only the active one left every other playthrough
    /// pointing at item ids that no longer existed — progress that looked reset
    /// with no warning and no rescue.
    @Test func replaceMigratesProgressInEveryPlaythrough() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .addAll)

        let first = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(first, itemID: "hornet", done: true)

        // A second playthrough — Steel Soul, NG+, whatever — with its own tick.
        let second = repo.addPlaythrough(to: game, named: "Steel Soul")
        repo.setTrackerItem(second, itemID: "hornet", done: true)
        // `addPlaythrough` switches to it, so `second` is now the active one.

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("boss-hornet", "Hornet")]),
        ]), mode: .replace)

        // BOTH records move, not just the active playthrough's.
        #expect(outcome.migrated == 2)
        #expect(repo.trackerState(second, itemID: "boss-hornet")?.completed == true)
        #expect(repo.trackerState(first, itemID: "boss-hornet")?.completed == true)
        #expect(repo.trackerState(first, itemID: "hornet") == nil)
    }

    /// Loss has to be reported from every playthrough too, or the rescue offer
    /// silently under-counts what's about to go.
    @Test func lostProgressCountsEveryPlaythrough() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses",
                     items: [("hornet", "Hornet"), ("nosk", "Nosk")]),
        ]), mode: .addAll)

        let first = repo.ensureDefaultPlaythrough(for: game)
        let second = repo.addPlaythrough(to: game, named: "Steel Soul")
        // Only the INACTIVE playthrough has progress on the item about to go.
        repo.setTrackerItem(first, itemID: "nosk", done: true)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .replace)

        #expect(outcome.lostProgress.map(\.id) == ["nosk"])
        _ = second
    }

    @Test func rescueMovesTheRecordInEveryPlaythrough() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("nosk", "Nosk")]),
        ]), mode: .addAll)
        let first = repo.ensureDefaultPlaythrough(for: game)
        let second = repo.addPlaythrough(to: game, named: "Steel Soul")
        repo.setTrackerItem(first, itemID: "nosk", done: true)
        repo.setTrackerItem(second, itemID: "nosk", done: true)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .replace)
        #expect(repo.rescueAsPersonalGoals(outcome.lostProgress, for: game) == 1)

        #expect(repo.trackerState(first, itemID: "goal-rescued-nosk")?.completed == true)
        #expect(repo.trackerState(second, itemID: "goal-rescued-nosk")?.completed == true)
    }

    // MARK: 2 — a locked category must survive an id collision

    /// Generators reuse common slugs. If one returns a category called
    /// `achievements` and the user has a LOCKED imported category with the same
    /// id, the locked one used to be dropped — and because the diff filters
    /// locked ids out of the incoming side, the review never mentioned it.
    @Test func lockedCategorySurvivesAnIncomingIDCollision() {
        let current = schema([
            category(id: "achievements", name: "Achievements",
                     items: [("mine-1", "My pasted item"), ("mine-2", "Another")],
                     locked: true),
        ])
        let incoming = schema([
            category(id: "achievements", name: "Achievements",
                     items: [("gen-1", "Generated thing")]),
        ])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cat = TrackerSchemaJSON.categories(from: out).first { $0.id == "achievements" }

        #expect(cat?.items.map(\.name) == ["My pasted item", "Another"])
        #expect(TrackerSchemaJSON.lockedCategoryIDs(in: out) == ["achievements"])
    }

    @Test func personalGoalsAlsoSurviveAnIDCollision() {
        let goals: [String: Any] = ["id": TrackerSchemaJSON.personalGoalsID,
                                    "name": "Personal Goals",
                                    "items": [["id": "goal-1", "name": "Beat it hitless"]]]
        let current = schema([goals])
        let incoming = schema([["id": TrackerSchemaJSON.personalGoalsID,
                                "name": "Personal Goals",
                                "items": [["id": "bogus", "name": "Invented goal"]]]])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cat = TrackerSchemaJSON.categories(from: out)
            .first { $0.id == TrackerSchemaJSON.personalGoalsID }

        #expect(cat?.items.map(\.name) == ["Beat it hitless"])
    }

    // MARK: 3 — a note must not travel to another category's item

    /// Two categories each containing an item called "Complete" is ordinary.
    /// A single global lookup gave one category's private note to the other
    /// category's item — the note wasn't lost, it was shown in the wrong place,
    /// which is worse.
    @Test func notesStayInTheirOwnCategory() throws {
        var current = schema([
            category(id: "story", name: "Story", items: [("story-done", "Complete")]),
            category(id: "extras", name: "Extras", items: [("extras-done", "Complete")]),
        ])
        current = try #require(TrackerSchemaJSON.editingItem(
            categoryID: "story", itemID: "story-done",
            note: "Only true of the story one", in: current))

        // Regeneration re-slugs both ids; the names still collide.
        let incoming = schema([
            category(id: "story", name: "Story", items: [("s1", "Complete")]),
            category(id: "extras", name: "Extras", items: [("e1", "Complete")]),
        ])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cats = TrackerSchemaJSON.categories(from: out)

        #expect(cats.first { $0.id == "story" }?.items.first?.note == "Only true of the story one")
        #expect(cats.first { $0.id == "extras" }?.items.first?.note == nil)
    }

    // MARK: 4 — duplicate ids in one payload must not both land

    /// AI output is untrusted input, not a valid primary-key set. The
    /// seen-set was computed once before appending, so a payload containing the
    /// same id twice appended both — and since progress is keyed by item id,
    /// the two rows would then share one checkmark.
    @Test func duplicateIDsInOnePayloadAreNotBothAdded() {
        let current = schema([category(id: "bosses", name: "Bosses", items: [])])
        let incoming = schema([
            category(id: "bosses", name: "Bosses",
                     items: [("dupe", "First"), ("dupe", "Second")]),
        ])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let ids = TrackerSchemaJSON.categories(from: out).flatMap(\.items).map(\.id)

        #expect(ids.count == Set(ids).count)
        #expect(ids.filter { $0 == "dupe" }.count == 1)
    }

    /// Same guard for names, since matching is name-aware.
    @Test func duplicateNamesInOnePayloadAreNotBothAdded() {
        let current = schema([category(id: "bosses", name: "Bosses", items: [])])
        let incoming = schema([
            category(id: "bosses", name: "Bosses",
                     items: [("a", "False Knight"), ("b", "false-knight")]),
        ])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        #expect(TrackerSchemaJSON.categories(from: out).flatMap(\.items).count == 1)
    }
}
