import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Folding a RetroAchievements account's unlocks into a tracker.
///
/// The rule the whole feature rests on: **union, never subtraction**. RA is
/// authoritative for "you earned this" and nothing else. It has no idea you
/// played the cartridge on real hardware last week, so an unlock it doesn't
/// know about is not evidence of anything — and un-ticking on that basis would
/// be the app telling someone they didn't do a thing they did.
///
/// That matters more than it sounds, because a sync is repeatable: anything
/// this can get wrong, it gets wrong again every time it runs.
@MainActor
struct RetroAchievementsSyncTests {

    private func setup() -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Castlevania", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)
        return (repo, game)
    }

    /// Shaped like what the proxy returns: an RA category carrying the game id.
    private var schema: Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "sources": [["type": "retroachievements",
                         "url": "https://retroachievements.org/game/1462"]],
            "categories": [[
                "id": "retroachievements", "name": "Achievements",
                "type": "checklist", "raGameID": 1462,
                "items": [
                    ["id": "ra-1", "name": "Vampire Killer", "metadata": ["points": 5, "raID": 1]],
                    ["id": "ra-2", "name": "Stalker", "metadata": ["points": 5, "raID": 2]],
                    ["id": "ra-3", "name": "Wicked Child", "metadata": ["points": 5, "raID": 3]],
                ],
            ]],
        ])
    }

    private func unlock(_ id: String, hardcore: Bool = true, points: Int = 5)
        -> RetroAchievementsService.Unlock {
        .init(itemID: id, hardcore: hardcore, earnedAt: .now, points: points)
    }

    // MARK: The dedicated playthrough

    /// Separate from your runs, because RA has no idea a run happened.
    @Test func syncingCreatesADedicatedPlaythroughOnce() {
        let (repo, game) = setup()
        let mine = repo.ensureDefaultPlaythrough(for: game)

        let ra = repo.raPlaythrough(for: game)
        #expect(ra.id != mine.id)
        #expect(ra.name == Repository.raPlaythroughName)

        // Called again — and again on the other device — it finds the same one.
        #expect(repo.raPlaythrough(for: game).id == ra.id)
        #expect(game.livePlaythroughs.count == 2)
    }

    /// It must not hijack the timer's target. You start a session against the
    /// run you're on, not against a record of your account.
    @Test func theRAPlaythroughDoesNotBecomeCurrent() {
        let (repo, game) = setup()
        let mine = repo.ensureDefaultPlaythrough(for: game)

        _ = repo.raPlaythrough(for: game)

        #expect(game.currentPlaythroughID == mine.id)
        #expect(game.activePlaythrough?.id == mine.id)
    }

    // MARK: Union, never subtraction

    @Test func unlocksTickTheMatchingItems() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        let outcome = repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-3")], to: ra, in: game)

        #expect(outcome.newlyTicked == 2)
        #expect(repo.trackerState(ra, itemID: "ra-1")?.completed == true)
        #expect(repo.trackerState(ra, itemID: "ra-2")?.completed != true)
        #expect(repo.trackerState(ra, itemID: "ra-3")?.completed == true)
    }

    /// The load-bearing one. A tick RA doesn't know about — earned on original
    /// hardware — survives every future sync.
    @Test func aTickRADoesNotKnowAboutIsNeverRemoved() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)
        repo.setTrackerItem(ra, itemID: "ra-2", done: true)

        // RA reports only ra-1. ra-2 is absent from its answer entirely.
        repo.applyRAUnlocks([unlock("ra-1")], to: ra, in: game)

        #expect(repo.trackerState(ra, itemID: "ra-2")?.completed == true)
        #expect(repo.trackerState(ra, itemID: "ra-1")?.completed == true)
    }

    /// Repeatable: running it twice changes nothing the second time, which is
    /// what makes it safe to run on every visit.
    @Test func syncingTwiceIsNotADoubleCount() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        let first = repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-2")], to: ra, in: game)
        let second = repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-2")], to: ra, in: game)

        #expect(first.newlyTicked == 2)
        #expect(second.newlyTicked == 0)
        #expect(second.alreadyTicked == 2)
    }

    /// Your own playthrough is untouched. Someone replaying Super Metroid has
    /// a fresh run, and an account record that says they finished it in 2019 —
    /// two facts, kept apart.
    @Test func yourOwnPlaythroughIsNotTickedBySync() {
        let (repo, game) = setup()
        let mine = repo.ensureDefaultPlaythrough(for: game)
        let ra = repo.raPlaythrough(for: game)

        repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-2"), unlock("ra-3")], to: ra, in: game)

        #expect(repo.trackerState(mine, itemID: "ra-1")?.completed != true)
        #expect(mine.progressPercent == 0)
    }

    /// Softcore counts. Filtering it out would be refusing to record something
    /// that happened.
    @Test func aSoftcoreUnlockStillCounts() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        repo.applyRAUnlocks([unlock("ra-1", hardcore: false)], to: ra, in: game)

        #expect(repo.trackerState(ra, itemID: "ra-1")?.completed == true)
    }

    /// An unlock for an achievement this tracker doesn't list means the set was
    /// revised after import. Counted and reported, so the app can suggest
    /// re-importing rather than dropping it in silence.
    @Test func anUnlockTheTrackerHasNeverHeardOfIsReportedNotSwallowed() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        let outcome = repo.applyRAUnlocks(
            [unlock("ra-1"), unlock("ra-999")], to: ra, in: game)

        #expect(outcome.newlyTicked == 1)
        #expect(outcome.unknownToTracker == 1)
        #expect(repo.trackerState(ra, itemID: "ra-999") == nil)
    }

    // MARK: Points

    /// The importer has written `metadata.points` since the first version and
    /// nothing read it, so a 635-point set reported no points at all. Parsed
    /// off the blob, no schema version involved.
    @Test func pointsAreReadFromItemMetadata() {
        let (repo, game) = setup()
        let items = repo.trackerCategories(for: game).flatMap(\.items)

        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.points == 5 })
        #expect(items.compactMap(\.points).reduce(0, +) == 15)
    }

    /// A tracker with no notion of points reports none, rather than zero —
    /// "0 pts" on a generated tracker is noise pretending to be information.
    @Test func aTrackerWithoutPointsHasNoneRatherThanZero() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [[
                "id": "bosses", "name": "Bosses", "type": "checklist",
                "items": [["id": "hornet", "name": "Hornet"]],
            ]]]), mode: .addAll)

        let items = repo.trackerCategories(for: game).flatMap(\.items)
        #expect(items.first?.points == nil)
        #expect(items.compactMap(\.points).isEmpty)
    }

    /// The name the session controls check against has to be the one the
    /// repository actually creates, or the timer reappears on the record.
    @Test func theRecordPlaythroughIsNamedWhatTheUICheckExpects() {
        let (repo, game) = setup()
        #expect(repo.raPlaythrough(for: game).name == Repository.raPlaythroughName)
        #expect(Repository.raPlaythroughName == "RetroAchievements")
    }

    // MARK: Finding the game again

    /// Sync looks the RA game up from the tracker itself. Losing that id
    /// silently would leave a set that can never be refreshed.
    @Test func theRAGameIDSurvivesImportIntoAnExistingTracker() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Castlevania", status: .playing)

        // A generated tracker first — so the RA import merges into a root
        // whose `sources` will never mention RetroAchievements.
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [[
                "id": "stages", "name": "Stages", "type": "checklist",
                "items": [["id": "s1", "name": "Stage 1"]],
            ]]]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)

        #expect(TrackerSchemaJSON.retroAchievementsGameID(
            in: game.trackerSchema!.jsonData) == 1462)
    }

    @Test func aTrackerWithNoRAImportHasNoGameID() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [[
                "id": "bosses", "name": "Bosses", "type": "checklist",
                "items": [["id": "hornet", "name": "Hornet"]],
            ]]]), mode: .addAll)

        #expect(TrackerSchemaJSON.retroAchievementsGameID(
            in: game.trackerSchema!.jsonData) == nil)
    }
}
