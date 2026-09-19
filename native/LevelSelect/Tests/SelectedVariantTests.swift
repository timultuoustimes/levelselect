import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Two-form items: Hades' Mirror of Night talents, a route choice, a loadout
/// slot. `TrackerStateRecord.selectedVariant` was promoted to CloudKit
/// Production and written by nothing; the chip could only ever REVEAL the
/// alternative, never record that you were running it.
@MainActor
struct SelectedVariantTests {

    private func setup() -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        let schema = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "mirror", "name": "Mirror of Night", "type": "checklist",
                            "items": [["id": "defiance", "name": "Death Defiance",
                                       "description": "Restores health once (Alt: Stubborn Defiance — restores at 51%)"]]]],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    @Test func choosingTheAlternativeIsRemembered() {
        let (repo, _, pt) = setup()
        #expect(repo.trackerState(pt, itemID: "defiance")?.selectedVariant == nil)

        repo.setTrackerVariant(pt, itemID: "defiance", variant: AltDescription.altVariant)
        #expect(repo.trackerState(pt, itemID: "defiance")?.selectedVariant == "alt")

        repo.setTrackerVariant(pt, itemID: "defiance", variant: nil)
        #expect(repo.trackerState(pt, itemID: "defiance")?.selectedVariant == nil)
    }

    /// The choice is a property of THIS run. A new playthrough starts with
    /// its own configuration rather than inheriting the last one's.
    @Test func theChoiceIsPerPlaythrough() {
        let (repo, game, first) = setup()
        repo.setTrackerVariant(first, itemID: "defiance", variant: "alt")

        let second = repo.addPlaythrough(to: game, named: "Heat 8")

        #expect(repo.trackerState(first, itemID: "defiance")?.selectedVariant == "alt")
        #expect(repo.trackerState(second, itemID: "defiance")?.selectedVariant == nil)
    }

    /// Choosing a form says nothing about having finished the item — they are
    /// independent, and picking one must not tick it.
    @Test func choosingAFormDoesNotCompleteTheItem() {
        let (repo, _, pt) = setup()
        repo.setTrackerVariant(pt, itemID: "defiance", variant: "alt")

        #expect(repo.trackerState(pt, itemID: "defiance")?.completed == false)
        #expect(pt.progressPercent == 0)
    }

    /// The choice rides the same state record as ticks and counts, so a
    /// regeneration that re-slugs the id carries it.
    @Test func theChoiceSurvivesARenameMigration() {
        let (repo, game, pt) = setup()
        repo.setTrackerVariant(pt, itemID: "defiance", variant: "alt")

        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "categories": [["id": "mirror", "name": "Mirror of Night", "type": "checklist",
                                "items": [["id": "mirror-death-defiance", "name": "Death Defiance",
                                           "description": "Restores health once (Alt: Stubborn Defiance)"]]]],
            ]), mode: .replace)

        #expect(repo.trackerState(pt, itemID: "mirror-death-defiance")?.selectedVariant == "alt")
    }

    /// The parser that decides whether an item HAS two forms.
    @Test func descriptionsSplitIntoTheirTwoForms() {
        let parts = AltDescription.split("Restores health once (Alt: Stubborn Defiance — 51%)")
        #expect(parts?.base == "Restores health once")
        #expect(parts?.alt == "Stubborn Defiance — 51%")
        #expect(AltDescription.split("Just an ordinary description") == nil)
    }
}
