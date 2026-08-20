import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Removing a category, or a whole tracker.
///
/// The only removals that existed were "an empty planned placeholder" and
/// "replace it with another generation" — so a tracker that had simply
/// misunderstood the game could not be thrown away, only overwritten.
///
/// These destroy content deliberately, which is the opposite of the rule they
/// look like they break: never remove user data by INFERENCE. An explicit,
/// confirmed instruction that has been told the numbers is a decision, not a
/// guess. What the tests pin is that the numbers are honest and that nothing
/// beyond the tracker goes with it.
@MainActor
struct TrackerRemovalTests {

    private func game() -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Castlevania", status: .playing)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    private func twoCategories(_ repo: Repository, _ game: Game) {
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "bat", "name": "Phantom Bat"], ["id": "medusa", "name": "Medusa"]]],
            ["id": "stages", "name": "Stages", "type": "checklist",
             "items": [["id": "s1", "name": "Stage 1"], ["id": "s2", "name": "Stage 2"]]],
        ]), mode: .addAll)
    }

    @Test func removingACategoryTakesOnlyThatCategory() {
        let (repo, game, _) = self.game()
        twoCategories(repo, game)

        #expect(repo.removeCategory(from: game, categoryID: "bosses"))

        let left = repo.trackerCategories(for: game)
        #expect(left.map(\.id) == ["stages"])
        #expect(left.first?.items.count == 2)
        // The tracker itself survives — this is not the whole-tracker removal.
        #expect(game.trackerSchema != nil)
    }

    /// Progress against items that no longer exist must not linger: it would
    /// count toward nothing and sync to every device forever.
    @Test func progressForRemovedItemsIsRetired() {
        let (repo, game, pt) = self.game()
        twoCategories(repo, game)
        repo.setTrackerItem(pt, itemID: "bat", done: true)
        repo.setTrackerItem(pt, itemID: "s1", done: true)

        repo.removeCategory(from: game, categoryID: "bosses")

        #expect(repo.trackerState(pt, itemID: "bat") == nil)     // tombstoned
        #expect(repo.trackerState(pt, itemID: "s1")?.completed == true)   // untouched
    }

    /// And the percentage follows, rather than being left quoting a total that
    /// no longer exists.
    @Test func progressPercentIsRecomputedAfterRemoval() {
        let (repo, game, pt) = self.game()
        twoCategories(repo, game)
        repo.setTrackerItem(pt, itemID: "s1", done: true)
        repo.setTrackerItem(pt, itemID: "s2", done: true)
        #expect(pt.progressPercent == 50)   // 2 of 4

        repo.removeCategory(from: game, categoryID: "bosses")

        #expect(pt.progressPercent == 100)  // 2 of the 2 that remain
    }

    @Test func removingTheTrackerLeavesTheGameWithNone() {
        let (repo, game, pt) = self.game()
        twoCategories(repo, game)
        repo.setTrackerItem(pt, itemID: "bat", done: true)

        #expect(repo.removeTracker(from: game))

        #expect(game.trackerSchema == nil)
        #expect(repo.trackerCategories(for: game).isEmpty)
        #expect(repo.trackerState(pt, itemID: "bat") == nil)
        #expect(pt.progressPercent == 0)
    }

    /// Sessions and completions are a different kind of record entirely — they
    /// are what you did, not what a generator listed. Removing a tracker must
    /// never touch them.
    @Test func sessionsAndCompletionsSurviveTrackerRemoval() {
        let (repo, game, pt) = self.game()
        twoCategories(repo, game)
        let session = repo.startSession(on: pt)
        repo.stopSession(session)
        repo.addCompletion(to: game)

        repo.removeTracker(from: game)

        let sessions = (pt.sessions ?? []).filter { $0.deletedAt == nil }
        #expect(sessions.count == 1)
        #expect(sessions.first?.endDate != nil)
        #expect((game.completionEvents ?? []).filter { $0.deletedAt == nil }.count == 1)
    }

    /// The confirmation quotes these numbers, so they have to be right — a
    /// warning that undercounts what's about to be lost is worse than none.
    @Test func theCostIsCountedBeforeAnythingIsRemoved() {
        let (repo, game, pt) = self.game()
        twoCategories(repo, game)
        repo.setTrackerItem(pt, itemID: "bat", done: true)

        let whole = repo.removalCost(for: game)
        #expect(whole.items == 4)
        #expect(whole.withProgress == 1)

        let bosses = repo.removalCost(for: game, categoryID: "bosses")
        #expect(bosses.items == 2)
        #expect(bosses.withProgress == 1)

        let stages = repo.removalCost(for: game, categoryID: "stages")
        #expect(stages.items == 2)
        #expect(stages.withProgress == 0)
    }

    /// "Progress" is broader than a tick — a note is work too, and a removal
    /// that silently takes one away would be the exact failure the merge
    /// review already had to be fixed for.
    @Test func aNoteCountsAsProgressWorthWarningAbout() {
        let (repo, game, _) = self.game()
        twoCategories(repo, game)
        _ = repo.editTrackerItem(game, categoryID: "bosses", itemID: "medusa",
                                 name: nil, location: nil, note: "use holy water")

        #expect(repo.removalCost(for: game, categoryID: "bosses").withProgress == 1)
    }

    @Test func removingSomethingThatIsntThereChangesNothing() {
        let (repo, game, _) = self.game()
        twoCategories(repo, game)

        #expect(repo.removeCategory(from: game, categoryID: "not-a-category") == false)
        #expect(repo.trackerCategories(for: game).count == 2)

        let (repo2, bare, _) = self.game()
        #expect(repo2.removeTracker(from: bare) == false)
    }

    /// Removal is not a one-way door out of the feature: the game can be given
    /// a tracker again afterwards, from scratch.
    @Test func aGameCanBeGivenANewTrackerAfterRemoval() {
        let (repo, game, _) = self.game()
        twoCategories(repo, game)
        repo.removeTracker(from: game)

        #expect(repo.addPlannedCategory(to: game, named: "Bosses", plannedCount: 6))
        #expect(repo.trackerCategories(for: game).map(\.name) == ["Bosses"])
    }
}
