import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Which ownership chips a library uses, and the promise that hiding one is
/// not an edit.
@MainActor
struct OwnershipChipsTests {

    @Test func nothingStoredMeansTheDefaultFive() {
        #expect(ThemePalette.chips(from: nil) == Ownership.shownByDefault)
        #expect(!Ownership.shownByDefault.contains(.rented))
    }

    /// Rented is real, and off until asked for: most libraries will never
    /// record a weekend rental, and the ones that do are cataloguing a
    /// childhood rather than a subscription.
    @Test func rentedIsAvailableButNotADefault() {
        #expect(Ownership.allCases.contains(.rented))
        #expect(Ownership.rented.label == "Rented")
    }

    @Test func aStoredSetIsHonoured() {
        let chips = ThemePalette.chips(from: "physical,rented")
        #expect(chips == [.physical, .rented])
    }

    /// Stored order is ignored — the app's own order is what keeps the chips
    /// in the same places on every game page whatever order they were toggled.
    @Test func theAppsOwnOrderWins() {
        #expect(ThemePalette.chips(from: "rented,physical") == [.physical, .rented])
    }

    /// A game page with no way to say you own the game is not a state worth
    /// having, so an empty set falls back rather than rendering nothing.
    @Test func anEmptySetFallsBackToTheDefaults() {
        #expect(ThemePalette.chips(from: "") == Ownership.shownByDefault)
    }

    /// A raw value this build has never heard of — written by a later one and
    /// arriving over CloudKit — is ignored rather than breaking the row.
    ///
    /// This used to use "borrowed" as its example of a word that is not a
    /// chip, which stopped being true in build 37. "leased" is the stand-in
    /// now — and if it ever becomes a chip, this test will say so.
    @Test func anUnknownChipIsIgnored() {
        #expect(Ownership(rawValue: "leased") == nil)
        #expect(ThemePalette.chips(from: "physical,leased") == [.physical])
    }

    /// The whole set decoding to nothing known is the same as nothing stored.
    @Test func aWhollyUnknownSetFallsBack() {
        #expect(ThemePalette.chips(from: "leased,bartered") == Ownership.shownByDefault)
    }

    @Test func everyChipIsStillASingleWord() {
        for kind in Ownership.allCases {
            #expect(!kind.label.contains(" "),
                    Comment(rawValue: "\(kind.rawValue) → \"\(kind.label)\""))
        }
    }
}

/// **Chip order, and the field it hides in.**
///
/// Three orders — the app's own, most used in your library, and whatever you
/// dragged — stored inside `ownershipChipsRaw` rather than in a new field, so
/// none of this costs a CloudKit deploy. The property that makes that honest
/// is at the bottom: a build that predates the token still reads the string.
@MainActor
struct Build37ChipOrderTests {

    private func raw(_ order: OwnershipChipOrder, _ kinds: [Ownership]) -> String {
        ([order.storedToken].compactMap { $0 } + kinds.map(\.rawValue))
            .joined(separator: ",")
    }

    // MARK: Standard

    /// The default writes no token at all, so a library that never opens this
    /// setting stores exactly the string it stores today.
    @Test func standardWritesNoToken() {
        #expect(OwnershipChipOrder.standard.storedToken == nil)
        #expect(raw(.standard, [.digital, .physical]) == "digital,physical")
    }

    /// …and is still read in the app's order, whatever order it was written in.
    @Test func standardIgnoresTheStoredOrder() {
        let chips = ThemePalette.chips(from: "rented,digital,physical")
        #expect(chips == [.physical, .digital, .rented])
    }

    // MARK: Custom

    @Test func customKeepsTheOrderYouDragged() {
        let stored = raw(.custom, [.digital, .subscription, .previouslyOwned, .physical])
        #expect(ThemePalette.chipOrder(from: stored) == .custom)
        #expect(ThemePalette.chips(from: stored)
                == [.digital, .subscription, .previouslyOwned, .physical])
    }

    /// A chip the stored order does not mention — turned on by an older build,
    /// or a case added since — lands at the end rather than vanishing.
    @Test func aChipMissingFromTheOrderIsStillShown() {
        // `emulated` is in the set but not named before the others.
        let stored = "order=custom,digital,physical,emulated"
        #expect(ThemePalette.chips(from: stored) == [.digital, .physical, .emulated])
    }

    // MARK: Most used

    @Test func mostUsedPutsTheCommonestFirst() {
        ThemePalette.refreshOwnershipUsage(from: [])
        let stored = raw(.mostUsed, [.physical, .digital, .subscription])
        // With nothing counted it falls back to the app's own order rather
        // than to an arbitrary one.
        #expect(ThemePalette.chips(from: stored) == [.physical, .digital, .subscription])
    }

    @Test func tiesFallBackToTheAppsOrder() {
        var library: [Game] = []
        for _ in 0..<3 {
            let g = Game(name: "s")
            g.ownership = [Ownership.subscription.rawValue]
            library.append(g)
        }
        let d = Game(name: "d")
        d.ownership = [Ownership.digital.rawValue]
        library.append(d)
        // physical and emulated are both unused, so they tie at zero.
        ThemePalette.refreshOwnershipUsage(from: library)

        let stored = raw(.mostUsed, [.physical, .digital, .emulated, .subscription])
        #expect(ThemePalette.chips(from: stored)
                == [.subscription, .digital, .physical, .emulated])
        ThemePalette.refreshOwnershipUsage(from: [])
    }

    // MARK: The property the whole storage trick rests on

    /// **A build that has never heard of the token still reads the string.**
    ///
    /// This reproduces the old parser exactly: split on commas, keep the
    /// entries that are valid raw values, drop the rest. The token is not a
    /// valid `Ownership`, so it falls out and the chip SET is unchanged —
    /// which is why this needed no schema deploy.
    @Test func anOlderBuildReadsTheSetAndIgnoresTheToken() {
        let stored = raw(.custom, [.digital, .subscription, .physical])
        let asOldBuildSawIt = Set(stored.split(separator: ",").map(String.init))
        let resolved = Ownership.allCases.filter { asOldBuildSawIt.contains($0.rawValue) }
        #expect(resolved == [.physical, .digital, .subscription])
        // The token is in the string and is not a chip, which is exactly why
        // the old parser drops it instead of choking on it.
        #expect(asOldBuildSawIt.contains("order=custom"))
        #expect(Ownership(rawValue: "order=custom") == nil)
    }

    /// An unknown order value is not a crash and not an empty row.
    @Test func anUnknownOrderFallsBackToStandard() {
        #expect(ThemePalette.chipOrder(from: "order=byVibes,digital,physical") == .standard)
        #expect(ThemePalette.chips(from: "order=byVibes,digital,physical")
                == [.physical, .digital])
    }

    /// Turning everything off still leaves a usable row.
    @Test func anEmptySetFallsBackToTheDefaults() {
        #expect(ThemePalette.chips(from: "order=custom") == Ownership.shownByDefault)
    }
}

/// **Borrowed and Shared, and the grid they complete.**
///
/// Four chips describe having a copy that is not yours, differing on two
/// axes — how long, and from whom. Rented and Subscription were the
/// commercial pair; Borrowed and Shared are the personal one.
@MainActor
struct Build37BorrowedAndSharedTests {

    @Test func theVocabularyHasNineChips() {
        #expect(Ownership.allCases.count == 9)
        #expect(Ownership.allCases.contains(.borrowed))
        #expect(Ownership.allCases.contains(.shared))
        #expect(Ownership.allCases.contains(.arcade))
    }

    /// Raw values are what every library already stores, so the new cases must
    /// be additions and nothing else may have moved.
    @Test func theExistingRawValuesAreUntouched() {
        #expect(Ownership.physical.rawValue == "physical")
        #expect(Ownership.digital.rawValue == "digital")
        #expect(Ownership.emulated.rawValue == "emulated")
        #expect(Ownership.subscription.rawValue == "subscription")
        #expect(Ownership.rented.rawValue == "rented")
        // Kept forever: it is what is in every library that ever used it.
        #expect(Ownership.previouslyOwned.rawValue == "previouslyOwned")
        #expect(Ownership.borrowed.rawValue == "borrowed")
        #expect(Ownership.shared.rawValue == "shared")
        #expect(Ownership.arcade.rawValue == "arcade")
    }

    /// Both are opt-in, so a row nobody configures stays five chips and still
    /// splits evenly.
    @Test func noneOfThemIsOnByDefault() {
        #expect(!Ownership.shownByDefault.contains(.borrowed))
        #expect(!Ownership.shownByDefault.contains(.shared))
        #expect(!Ownership.shownByDefault.contains(.arcade))
        #expect(Ownership.shownByDefault.count == 5)
    }

    /// An arcade game is one you can beat without ever logging a second of
    /// play — `addCompletion` hangs off the GAME, not off a session. That is
    /// the whole reason this belongs in the library rather than in Memories.
    @Test func anArcadeGameCanBeBeatenWithNoSessions() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Time Crisis", status: .completed)
        game.ownership = [Ownership.arcade.rawValue]
        repo.addCompletion(to: game, label: .cleared)

        let events = (try? context.fetch(FetchDescriptor<CompletionEvent>())) ?? []
        #expect(events.count == 1)
        #expect(game.livePlaythroughs.allSatisfy { ($0.sessions ?? []).isEmpty })
    }

    /// **The declaration order is the grouping**, because it is what Standard
    /// order and the settings list both show: the four you have, then the five
    /// you only reach. Former belongs with the first group — past ownership is
    /// still ownership — which is why it is fourth and not last.
    @Test func theDeclarationOrderIsTheGrouping() {
        #expect(Ownership.allCases == [.physical, .digital, .emulated, .previouslyOwned,
                                       .subscription, .rented, .borrowed, .shared, .arcade])
    }

    /// And the five-chip default lands the whole ownership group on row one.
    @Test func theDefaultRowSplitsOnTheGroupBoundary() {
        let shown = Ownership.shownByDefault
        #expect(shown.count == 5)
        // `balanced` splits at (count + 1) / 2 — three and two.
        #expect(Array(shown.prefix(3)) == [.physical, .digital, .emulated])
        #expect(Array(shown.dropFirst(3)) == [.previouslyOwned, .subscription])
    }

    @Test func eachHasItsOwnLabelAndIcon() {
        let labels = Set(Ownership.allCases.map(\.label))
        let icons = Set(Ownership.allCases.map(\.systemImage))
        #expect(labels.count == Ownership.allCases.count)
        #expect(icons.count == Ownership.allCases.count)
        #expect(Ownership.borrowed.label == "Borrowed")
        #expect(Ownership.shared.label == "Shared")
    }

    /// A game can carry the pair that actually co-occurs — a household copy
    /// you also play through an emulator — because this was always
    /// multi-select.
    @Test func theyCombineWithTheRest() {
        let game = Game(name: "GoldenEye 007")
        game.ownership = [Ownership.borrowed.rawValue, Ownership.emulated.rawValue]
        #expect(game.ownership.count == 2)
        ThemePalette.refreshOwnershipUsage(from: [game])
        #expect(ThemePalette.ownershipUsage["borrowed"] == 1)
        #expect(ThemePalette.ownershipUsage["emulated"] == 1)
        ThemePalette.refreshOwnershipUsage(from: [])
    }

    /// Turning one on is a vocabulary choice and survives the round trip
    /// through the stored string, token and all.
    @Test func theySurviveTheStoredString() {
        let stored = "order=custom,borrowed,shared,digital"
        #expect(ThemePalette.chips(from: stored) == [.borrowed, .shared, .digital])
    }

    // MARK: No chip left behind

    /// **Every case has to be reachable, not just the ones we remembered.**
    ///
    /// The risk this pins is a hardcoded subset appearing somewhere later —
    /// a settings list that enumerates five chips by hand, a filter that
    /// forgets the newest one. Turning each case on by itself must resolve to
    /// exactly that case, in all three orders.
    @Test func everyChipCanBeTheOnlyChip() {
        for kind in Ownership.allCases {
            for order in OwnershipChipOrder.allCases {
                let stored = ([order.storedToken].compactMap { $0 } + [kind.rawValue])
                    .joined(separator: ",")
                #expect(ThemePalette.chips(from: stored) == [kind],
                        Comment(rawValue: "\(kind.rawValue) in \(order.rawValue) order"))
            }
        }
    }

    /// And every case has to survive a custom order that names all of them —
    /// the drag-to-arrange list is built from exactly this.
    @Test func aCustomOrderCanHoldTheWholeVocabulary() {
        let reversed = Array(Ownership.allCases.reversed())
        let stored = (["order=custom"] + reversed.map(\.rawValue)).joined(separator: ",")
        #expect(ThemePalette.chips(from: stored) == reversed)
        #expect(ThemePalette.chips(from: stored).count == Ownership.allCases.count)
    }

    /// The Library filter counts by `allCases`, so a game marked with the
    /// newest chip is findable the moment it is marked.
    @Test func theLibraryFilterCountsEveryKind() {
        var library: [Game] = []
        for kind in Ownership.allCases {
            let game = Game(name: kind.rawValue)
            game.ownership = [kind.rawValue]
            library.append(game)
        }
        let counts = OwnershipFacet.counts(library)
        for kind in Ownership.allCases {
            #expect(counts.byKind[kind] == 1,
                    Comment(rawValue: "\(kind.rawValue) missing from the filter counts"))
        }
        #expect(counts.unset == 0)
    }
}
