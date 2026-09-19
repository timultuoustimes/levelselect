import Testing
import Foundation
@testable import LevelSelect

/// Prerequisites and gates: what you can still do, and what you're about to
/// lock yourself out of. Elden Ring questlines that end, a true ending gated
/// behind the other endings, a point of no return — all the same two
/// relationships.
struct TrackerGatingTests {

    private func item(_ id: String, _ name: String,
                      requires: [String] = [], locksOut: [String] = []) -> TrackerItemDTO {
        TrackerItemDTO(id: id, name: name, itemDescription: nil, location: nil,
                       missable: false, hideUntilDiscovered: false, maxRank: nil,
                       rankNames: nil, display: nil, requires: requires, locksOut: locksOut)
    }

    private func resolver(_ items: [TrackerItemDTO], completed: Set<String>) -> TrackerGating.Resolver {
        TrackerGating.Resolver(
            categories: [TrackerCategoryDTO(id: "c", name: "C", categoryDescription: nil,
                                            kind: nil, items: items)],
            completed: completed)
    }

    @Test func anItemWithNoRulesIsAlwaysAvailable() {
        let plain = item("a", "Anything")
        #expect(resolver([plain], completed: []).status(of: plain) == .available)
    }

    @Test func anUnmetPrerequisiteBlocksAndNamesWhatIsMissing() {
        let gate = item("intro", "Meet Ranni")
        let quest = item("quest", "Ranni's ending", requires: ["intro"])

        let before = resolver([gate, quest], completed: [])
        #expect(before.status(of: quest) == .blocked(needs: ["Meet Ranni"]))

        let after = resolver([gate, quest], completed: ["intro"])
        #expect(after.status(of: quest) == .available)
    }

    @Test func severalMissingPrerequisitesAreAllNamed() {
        let a = item("a", "Ending A")
        let b = item("b", "Ending B")
        let truth = item("true", "True ending", requires: ["a", "b"])

        let none = resolver([a, b, truth], completed: [])
        #expect(none.status(of: truth) == .blocked(needs: ["Ending A", "Ending B"]))

        let half = resolver([a, b, truth], completed: ["a"])
        #expect(half.status(of: truth) == .blocked(needs: ["Ending B"]))
    }

    /// The failure that actually costs a playthrough: finishing one thing
    /// ends another, and nothing said so.
    @Test func completingALockingItemClosesOffWhatItEnds() {
        let burn = item("burn", "Burn the Erdtree", locksOut: ["quest"])
        let quest = item("quest", "Finish the questline")

        let before = resolver([burn, quest], completed: [])
        #expect(before.status(of: quest) == .available)
        #expect(before.wouldLoseByCompleting(burn) == ["Finish the questline"])

        let after = resolver([burn, quest], completed: ["burn"])
        #expect(after.status(of: quest) == .lost(to: ["Burn the Erdtree"]))
    }

    /// The warning must not cry wolf about things already finished — doing
    /// the quest THEN hitting the point of no return costs nothing.
    @Test func nothingIsWarnedAboutIfItIsAlreadyDone() {
        let burn = item("burn", "Burn the Erdtree", locksOut: ["quest"])
        let quest = item("quest", "Finish the questline")

        let done = resolver([burn, quest], completed: ["quest"])
        #expect(done.wouldLoseByCompleting(burn).isEmpty)
    }

    /// …nor about something a previous choice already closed off.
    @Test func alreadyClosedItemsAreNotWarnedAboutTwice() {
        let first = item("first", "Side with A", locksOut: ["prize"])
        let second = item("second", "Side with B", locksOut: ["prize"])
        let prize = item("prize", "B's reward")

        let after = resolver([first, second, prize], completed: ["first"])
        #expect(after.status(of: prize) == .lost(to: ["Side with A"]))
        #expect(after.wouldLoseByCompleting(second).isEmpty)
    }

    /// A thing you already did cannot be reported as impossible, whatever the
    /// rules say now — it happened.
    @Test func aCompletedItemIsNeverBlockedOrLost() {
        let burn = item("burn", "Burn the Erdtree", locksOut: ["quest"])
        let quest = item("quest", "Finish the questline", requires: ["missing"])
        let missing = item("missing", "Never done")

        let both = resolver([burn, quest, missing], completed: ["burn", "quest"])
        #expect(both.status(of: quest) == .available)
    }

    /// Mutual exclusivity: two endings that each foreclose the other.
    @Test func mutuallyExclusiveChoicesCloseEachOther() {
        let a = item("a", "Ending A", locksOut: ["b"])
        let b = item("b", "Ending B", locksOut: ["a"])

        let open = resolver([a, b], completed: [])
        #expect(open.status(of: a) == .available)
        #expect(open.status(of: b) == .available)

        let chose = resolver([a, b], completed: ["a"])
        #expect(chose.status(of: b) == .lost(to: ["Ending A"]))
    }

    /// The relationships survive the schema round trip — they live in the
    /// tracker JSON, which is why none of this needed a schema version.
    @Test func requirementsSurviveTheSchemaRoundTrip() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "c", "name": "C", "items": [
                ["id": "quest", "name": "Questline", "requires": ["intro"],
                 "locksOut": ["other"]],
            ]]],
        ])
        let parsed = TrackerSchemaJSON.categories(from: data).flatMap(\.items).first
        #expect(parsed?.requires == ["intro"])
        #expect(parsed?.locksOut == ["other"])
    }
}
