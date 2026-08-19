import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Stepped generation, stage one: plan the shape of a tracker as empty
/// categories, then fill them one at a time.
///
/// The adversarial shapes here are all about the gap between "the button ran"
/// and "the category has content in it": a planned id never appears in a
/// generated payload, so every one of these fills by NAME, and a payload that
/// names nothing recognisable has to leave the placeholder intact rather than
/// quietly emptying or quietly claiming success.
@MainActor
struct PlannedCategoryTests {

    private func game(named name: String = "Hollow Knight") -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    private func category(_ id: String, _ name: String, _ items: [(String, String)]) -> [String: Any] {
        ["id": id, "name": name, "type": "checklist",
         "items": items.map { ["id": $0.0, "name": $0.1] }]
    }

    private func cat(_ repo: Repository, _ game: Game, named name: String) -> TrackerCategoryDTO? {
        repo.trackerCategories(for: game).first { $0.name == name }
    }

    /// Planning is a legitimate way to START a tracker, not something only
    /// available to a game that already has one.
    @Test func planningCreatesTheSchemaOnAGameWithNoTracker() {
        let (repo, game) = self.game()
        #expect(game.trackerSchema == nil)

        #expect(repo.addPlannedCategory(to: game, named: "Bosses", plannedCount: 47))

        let bosses = cat(repo, game, named: "Bosses")
        #expect(bosses?.pending == true)
        #expect(bosses?.plannedCount == 47)
        #expect(bosses?.items.isEmpty == true)
    }

    /// Two categories called "Bosses" look identical in the list and only one
    /// of them is the one the generate button fills. Refused up front.
    @Test func aSecondCategoryWithTheSameNameIsRefused() {
        let (repo, game) = self.game()
        #expect(repo.addPlannedCategory(to: game, named: "Bosses"))

        #expect(repo.addPlannedCategory(to: game, named: "  bosses ") == false)
        #expect(repo.trackerCategories(for: game).count == 1)
    }

    /// Including against content that arrived from a generator rather than
    /// from planning — the clash is the same clash.
    @Test func planningCannotShadowAnExistingGeneratedCategory() {
        let (repo, game) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet")]),
        ]), mode: .addAll)

        #expect(repo.addPlannedCategory(to: game, named: "Bosses") == false)
        #expect(cat(repo, game, named: "Bosses")?.items.count == 1)
    }

    /// The load-bearing case. A planned category's id is generated locally
    /// (`cat-1a2b3c4d`) and can never appear in a generated payload, so the
    /// scoped fill has to land by name — and then stop reading as pending.
    @Test func generatingIntoAPlannedCategoryFillsItByNameAndClearsThePlanFlag() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Bosses", plannedCount: 47)
        let planned = cat(repo, game, named: "Bosses")!
        #expect(planned.id.hasPrefix("cat-"))

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("boss-fights-generated", "Bosses",
                     [("hornet", "Hornet"), ("radiance", "The Radiance")]),
            category("charms", "Charms", [("wayward", "Wayward Compass")]),
        ]), mode: .replaceCategories(ids: [planned.id]))

        let filled = cat(repo, game, named: "Bosses")
        #expect(filled?.items.map(\.id).sorted() == ["hornet", "radiance"])
        #expect(filled?.pending == false)
        #expect(filled?.plannedCount == nil)
        // Scoped means scoped: nothing else in the payload was installed.
        #expect(cat(repo, game, named: "Charms") == nil)
    }

    /// A payload that names nothing recognisable must leave the placeholder
    /// exactly as it was — still empty, still pending, still offering its own
    /// Generate button. Emptying it or clearing the flag would strand the
    /// category with no way back.
    @Test func aPayloadThatMatchesNothingLeavesThePlaceholderIntact() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Bosses", plannedCount: 47)
        let planned = cat(repo, game, named: "Bosses")!

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("endings", "Endings", [("true", "True Ending")]),
        ]), mode: .replaceCategories(ids: [planned.id]))

        let after = cat(repo, game, named: "Bosses")
        #expect(after?.items.isEmpty == true)
        #expect(after?.pending == true)
        #expect(after?.plannedCount == 47)
    }

    /// Filling one planned category must not disturb the ones still waiting.
    @Test func fillingOnePlannedCategoryLeavesTheOthersPlanned() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Bosses")
        repo.addPlannedCategory(to: game, named: "Charms", plannedCount: 40)
        let bosses = cat(repo, game, named: "Bosses")!

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("b", "Bosses", [("hornet", "Hornet")]),
            category("c", "Charms", [("wayward", "Wayward Compass")]),
        ]), mode: .replaceCategories(ids: [bosses.id]))

        #expect(cat(repo, game, named: "Bosses")?.pending == false)
        let charms = cat(repo, game, named: "Charms")
        #expect(charms?.pending == true)
        #expect(charms?.items.isEmpty == true)
        #expect(charms?.plannedCount == 40)
    }

    /// A whole-tracker generation run alongside a plan must not silently drop
    /// the empty placeholders the user sketched.
    @Test func anUnrelatedWholeTrackerGenerationDoesNotDropThePlan() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Charms", plannedCount: 40)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet")]),
        ]), mode: .addAll)

        #expect(cat(repo, game, named: "Charms")?.pending == true)
        #expect(cat(repo, game, named: "Bosses")?.items.count == 1)
    }

    /// Removing scaffolding is fine. Removing content is not — an empty
    /// planned heading is the app's, a filled category is the user's, and the
    /// difference has to hold even when the id is the planned one.
    @Test func onlyAnEmptyPlannedCategoryCanBeRemoved() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Bosses")
        repo.addPlannedCategory(to: game, named: "Charms")
        let bosses = cat(repo, game, named: "Bosses")!
        let charms = cat(repo, game, named: "Charms")!

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("b", "Bosses", [("hornet", "Hornet")]),
        ]), mode: .replaceCategories(ids: [bosses.id]))

        #expect(repo.removePlannedCategory(from: game, categoryID: bosses.id) == false)
        #expect(cat(repo, game, named: "Bosses")?.items.count == 1)

        #expect(repo.removePlannedCategory(from: game, categoryID: charms.id))
        #expect(cat(repo, game, named: "Charms") == nil)
    }

    /// A set too large to list arrives as one counter, so the placeholder has
    /// to say that rather than promising nine hundred rows. Getting this wrong
    /// made a correct fill look like a broken one.
    @Test func aCountedPlanSurvivesTheRoundTripSoTheRowCanSayWhatsComing() {
        let (repo, game) = self.game(named: "Breath of the Wild")
        #expect(repo.addPlannedCategory(to: game, named: "Korok Seeds",
                                        plannedCount: 900, counted: true))
        #expect(repo.addPlannedCategory(to: game, named: "Shrines", plannedCount: 120))

        // Re-parsed from stored JSON: the flag has to reach the other device
        // too, or the same row reads differently there.
        let stored = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
        let koroks = stored.first { $0.name == "Korok Seeds" }
        let shrines = stored.first { $0.name == "Shrines" }
        #expect(koroks?.counted == true)
        #expect(koroks?.plannedCount == 900)
        #expect(shrines?.counted == false)   // the default, not "everything is counted"
    }

    /// And once filled, the promise is spent — the flag goes with the rest of
    /// the planning scaffolding.
    @Test func fillingAcountedCategoryClearsThePlanningMarkers() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Korok Seeds", plannedCount: 900, counted: true)
        let planned = cat(repo, game, named: "Korok Seeds")!

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "korok-seeds", "name": "Korok Seeds", "type": "collectibles",
             "items": [["id": "koroks", "name": "Korok Seeds", "countTarget": 900]]],
        ]), mode: .replaceCategories(ids: [planned.id]))

        let filled = cat(repo, game, named: "Korok Seeds")
        #expect(filled?.pending == false)
        #expect(filled?.counted == false)
        #expect(filled?.plannedCount == nil)
        #expect(filled?.items.first?.countTarget == 900)
    }

    /// A blank name is a mis-tap on the Add button, not a category.
    @Test func aBlankNameIsNotACategory() {
        let (repo, game) = self.game()
        #expect(repo.addPlannedCategory(to: game, named: "   ") == false)
        #expect(repo.trackerCategories(for: game).isEmpty)
    }

    /// Progress ticked in a planned category before it was filled (possible
    /// via an imported list or a hand-added item) still follows the fill.
    @Test func planIsWrittenToTheSchemaNotJustHeldInMemory() {
        let (repo, game) = self.game()
        repo.addPlannedCategory(to: game, named: "Bosses", plannedCount: 12)

        // Re-parsed straight from stored JSON, not from a cached DTO: the
        // pending marker has to survive the round trip or it is invisible on
        // the other device.
        let stored = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
        #expect(stored.first?.pending == true)
        #expect(stored.first?.plannedCount == 12)
    }
}
