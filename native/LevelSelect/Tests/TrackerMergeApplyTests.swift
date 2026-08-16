import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The store-level half of the merge work: folding a generated schema into an
/// existing one while carrying the user's progress across items that came back
/// under a different id. The engine's own rules are covered in
/// `TrackerMergeTests`; these cover what happens to real progress records.
@MainActor
struct TrackerMergeApplyTests {

    private func game(named name: String) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    private func schema(_ items: [(String, String)],
                        category: String = "bosses",
                        categoryName: String = "Bosses") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": category, "name": categoryName, "type": "checklist",
                            "items": items.map { ["id": $0.0, "name": $0.1] }]],
        ])
    }

    private let original: [(String, String)] = [
        ("false-knight", "False Knight"),
        ("hornet", "Hornet"),
        ("soul-master", "Soul Master"),
    ]

    // MARK: First generation

    @Test func firstGenerationJustInstalls() {
        let (repo, game) = self.game(named: "Hollow Knight")
        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)

        #expect(game.trackerSchema != nil)
        #expect(outcome.added == 3)
        #expect(outcome.lostProgress.isEmpty)
    }

    // MARK: The headline case

    /// A regeneration that returns the same content under re-slugged ids used
    /// to silently zero every tick. The progress records must follow.
    @Test func replaceCarriesProgressAcrossRenamedIDs() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "false-knight", done: true)
        repo.setTrackerItem(pt, itemID: "hornet", done: true)

        let regenerated = schema([("boss-false-knight", "False Knight"),
                                  ("boss-hornet", "Hornet"),
                                  ("boss-soul-master", "Soul Master")])
        let outcome = repo.applyGeneratedSchema(for: game, jsonData: regenerated, mode: .replace)

        #expect(outcome.renamed == 3)
        // Only the two carrying progress needed moving.
        #expect(outcome.migrated == 2)
        #expect(outcome.lostProgress.isEmpty)
        #expect(repo.trackerState(pt, itemID: "boss-false-knight")?.completed == true)
        #expect(repo.trackerState(pt, itemID: "boss-hornet")?.completed == true)
        // And the old ids are gone rather than left behind as duplicates.
        #expect(repo.trackerState(pt, itemID: "false-knight") == nil)
    }

    /// Progress percentage is the visible symptom — it collapsed on
    /// regeneration because recomputeProgress intersects state ids with schema
    /// ids. After migration it must hold.
    ///
    /// Note the explicit `recomputeProgress`: `setTrackerItem` doesn't do it,
    /// the two call sites in `TrackerSectionView` do. This mirrors the real
    /// flow rather than asserting an invariant the repository doesn't keep.
    @Test func progressPercentSurvivesARename() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "false-knight", done: true)
        repo.setTrackerItem(pt, itemID: "hornet", done: true)
        repo.recomputeProgress(game)
        let before = pt.progressPercent

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ("boss-false-knight", "False Knight"),
            ("boss-hornet", "Hornet"),
            ("boss-soul-master", "Soul Master"),
        ]), mode: .replace)

        #expect(before > 60)
        #expect(pt.progressPercent == before)
    }

    /// A part-filled rank is the user's work too, and rank lives on the same
    /// record — so it has to ride along with the id rewrite.
    @Test func rankProgressMigratesAsWellAsCompletion() {
        let (repo, game) = self.game(named: "Hades")
        repo.applyGeneratedSchema(for: game,
                                  jsonData: schema([("mirror-death-defiance", "Death Defiance")],
                                                   category: "mirror", categoryName: "Mirror of Night"),
                                  mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerRank(pt, itemID: "mirror-death-defiance", rank: 3, maxRank: 5)

        repo.applyGeneratedSchema(for: game,
                                  jsonData: schema([("death-defiance", "Death Defiance")],
                                                   category: "mirror", categoryName: "Mirror of Night"),
                                  mode: .replace)

        #expect(repo.trackerState(pt, itemID: "death-defiance")?.rank == 3)
    }

    /// The safety property of the additive modes: they never adopt incoming
    /// ids, so there is nothing to migrate and nothing that can be lost — even
    /// when the incoming tracker is strictly worse.
    @Test func additiveModesCannotLoseProgress() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "soul-master", done: true)

        let worse = schema([("boss-false-knight", "False Knight")])
        let outcome = repo.applyGeneratedSchema(for: game, jsonData: worse, mode: .addAll)

        #expect(outcome.migrated == 0)
        #expect(outcome.lostProgress.isEmpty)
        #expect(repo.trackerState(pt, itemID: "soul-master")?.completed == true)
        #expect(pt.progressPercent > 0)
    }

    @Test func replaceReportsProgressItReallyLost() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "soul-master", done: true)
        repo.setTrackerItem(pt, itemID: "hornet", done: true)

        // Soul Master is dropped entirely; Hornet survives untouched.
        let outcome = repo.applyGeneratedSchema(
            for: game, jsonData: schema([("hornet", "Hornet")]), mode: .replace)

        #expect(outcome.lostProgress.map(\.id) == ["soul-master"])
        #expect(repo.trackerState(pt, itemID: "hornet")?.completed == true)
    }

    // MARK: Rescue

    @Test func rescueKeepsADroppedItemAsACompletedGoal() throws {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "soul-master", done: true)

        let outcome = repo.applyGeneratedSchema(
            for: game, jsonData: schema([("hornet", "Hornet")]), mode: .replace)
        #expect(repo.rescueAsPersonalGoals(outcome.lostProgress, for: game) == 1)

        let schemaData = try #require(game.trackerSchema?.jsonData)
        let goals = TrackerSchemaJSON.categories(from: schemaData)
            .first { $0.id == TrackerSchemaJSON.personalGoalsID }
        #expect(goals?.items.map(\.name) == ["Soul Master"])
        // The tick came with it, rather than arriving as unfinished work.
        #expect(repo.trackerState(pt, itemID: "goal-rescued-soul-master")?.completed == true)
    }

    @Test func rescuingTheSameItemTwiceDoesNotDuplicateIt() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "soul-master", done: true)
        let outcome = repo.applyGeneratedSchema(
            for: game, jsonData: schema([("hornet", "Hornet")]), mode: .replace)

        #expect(repo.rescueAsPersonalGoals(outcome.lostProgress, for: game) == 1)
        #expect(repo.rescueAsPersonalGoals(outcome.lostProgress, for: game) == 0)

        let goals = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
            .first { $0.id == TrackerSchemaJSON.personalGoalsID }
        #expect(goals?.items.count == 1)
    }

    /// Rescued goals live in Personal Goals, which every mode preserves — so a
    /// later regeneration must not be able to take them away again.
    @Test func rescuedGoalsSurviveALaterReplace() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema(original), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "soul-master", done: true)
        let outcome = repo.applyGeneratedSchema(
            for: game, jsonData: schema([("hornet", "Hornet")]), mode: .replace)
        repo.rescueAsPersonalGoals(outcome.lostProgress, for: game)

        repo.applyGeneratedSchema(for: game, jsonData: schema([("nosk", "Nosk")]), mode: .replace)

        let goals = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
            .first { $0.id == TrackerSchemaJSON.personalGoalsID }
        #expect(goals?.items.map(\.name) == ["Soul Master"])
        #expect(repo.trackerState(pt, itemID: "goal-rescued-soul-master")?.completed == true)
    }

    // MARK: Regression guard from real data

    /// Mina the Hollower ships "Thorne (Round 1/2/3)". These are three distinct
    /// bosses whose names differ only by a trailing number, so any loosening of
    /// the match rules would pair them wrongly — and because this path rewrites
    /// progress ids, a mis-pair wouldn't lose a tick, it would move it onto the
    /// WRONG boss, which is worse. Pin the behaviour.
    @Test func similarlyNamedItemsAreNotConflated() {
        let (repo, game) = self.game(named: "Mina the Hollower")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ("thorne-1", "Thorne (Round 1)"),
            ("thorne-2", "Thorne (Round 2)"),
            ("thorne-3", "Thorne (Round 3)"),
        ], category: "story", categoryName: "Story Bosses"), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "thorne-1", done: true)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ("boss-thorne-round-1", "Thorne (Round 1)"),
            ("boss-thorne-round-2", "Thorne (Round 2)"),
            ("boss-thorne-round-3", "Thorne (Round 3)"),
        ], category: "story", categoryName: "Story Bosses"), mode: .replace)

        #expect(repo.trackerState(pt, itemID: "boss-thorne-round-1")?.completed == true)
        #expect(repo.trackerState(pt, itemID: "boss-thorne-round-2") == nil)
        #expect(repo.trackerState(pt, itemID: "boss-thorne-round-3") == nil)
    }
}
