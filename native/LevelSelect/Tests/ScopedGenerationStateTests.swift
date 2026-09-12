import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Which category is actually being generated.
///
/// Pressing Generate on one planned category spun the spinner on *every*
/// planned category — three rows claiming to be working when only one request
/// existed, because the only "busy" signal was per-game. The state below is
/// what the rows now read, so it is what has to be pinned.
///
/// These run against the shared store deliberately (it is a singleton, and the
/// bug was in its state), keyed by a fresh game id per test so no two tests can
/// see each other's entries. Each starts a request and cancels it in the same
/// turn: the store is `@MainActor` and so is the test, so there is no
/// suspension point between starting and asserting — the network task cannot
/// have run, and cancel stops it before it does.
@MainActor
struct ScopedGenerationStateTests {

    private func newGame() -> (Repository, Game, ModelContext) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: "Breath of the Wild", status: .playing), context)
    }

    @Test func onlyTheCategoryYouPressedCountsAsGenerating() {
        let (repo, game, context) = newGame()
        repo.addPlannedCategory(to: game, named: "Shrines", plannedCount: 120)
        repo.addPlannedCategory(to: game, named: "Memories", plannedCount: 18)
        let shrines = repo.trackerCategories(for: game).first { $0.name == "Shrines" }!
        let memories = repo.trackerCategories(for: game).first { $0.name == "Memories" }!

        let store = TrackerGenerationStore.shared
        store.generateCategory(shrines.id, named: shrines.name, for: game, context: context)
        defer { store.cancel(for: game.id) }

        #expect(store.isGenerating(game.id, category: shrines.id))
        #expect(store.isGenerating(game.id, category: memories.id) == false)
        // The game IS busy — that's what disables the other rows' buttons,
        // rather than spinning them.
        #expect(store.isGenerating(game.id))
    }

    @Test func awholeTrackerGenerationClaimsNoCategory() {
        let (repo, game, context) = newGame()
        repo.addPlannedCategory(to: game, named: "Shrines")
        let shrines = repo.trackerCategories(for: game).first { $0.name == "Shrines" }!

        let store = TrackerGenerationStore.shared
        store.generate(for: game, context: context)
        defer { store.cancel(for: game.id) }

        #expect(store.isGenerating(game.id))
        // A full generation is not "filling Shrines", so that row must not spin.
        #expect(store.isGenerating(game.id, category: shrines.id) == false)
    }

    @Test func cancellingClearsTheCategoryClaim() {
        let (repo, game, context) = newGame()
        repo.addPlannedCategory(to: game, named: "Shrines")
        let shrines = repo.trackerCategories(for: game).first { $0.name == "Shrines" }!

        let store = TrackerGenerationStore.shared
        store.generateCategory(shrines.id, named: shrines.name, for: game, context: context)
        store.cancel(for: game.id)

        #expect(store.isGenerating(game.id) == false)
        #expect(store.isGenerating(game.id, category: shrines.id) == false)
    }

    /// Planning is not filling. It must claim no category at all, or every
    /// placeholder on screen would spin while the shape was being worked out.
    @Test func planningClaimsNoCategoryAndSaysSoInTheKind() {
        let (repo, game, context) = newGame()
        repo.addPlannedCategory(to: game, named: "Shrines")
        let shrines = repo.trackerCategories(for: game).first!

        let store = TrackerGenerationStore.shared
        store.suggestCategories(for: game, context: context)
        defer { store.cancel(for: game.id) }

        #expect(store.isGenerating(game.id))
        #expect(store.kind(for: game.id) == .plan)
        #expect(store.isGenerating(game.id, category: shrines.id) == false)
    }

    /// The waiting card reads the kind to decide what it is allowed to claim
    /// is happening — "reading the guide" is false during a plan.
    @Test func theKindNamesTheCategoryBeingFilled() {
        let (repo, game, context) = newGame()
        repo.addPlannedCategory(to: game, named: "Memories", plannedCount: 18)
        let memories = repo.trackerCategories(for: game).first!

        let store = TrackerGenerationStore.shared
        store.generateCategory(memories.id, named: memories.name,
                               expectedCount: memories.plannedCount,
                               for: game, context: context)
        defer { store.cancel(for: game.id) }

        #expect(store.kind(for: game.id) == .category(id: memories.id, name: "Memories"))
    }

    /// A finished or cancelled run leaves no kind behind, so the next card
    /// can't inherit the last one's captions.
    @Test func theKindIsClearedWhenTheRunEnds() {
        let (_, game, context) = newGame()
        let store = TrackerGenerationStore.shared
        store.suggestCategories(for: game, context: context)
        store.cancel(for: game.id)

        #expect(store.kind(for: game.id) == .full)   // the default, not .plan
        #expect(store.isGenerating(game.id) == false)
    }

    /// Two games generating at once must not read each other's category —
    /// the state is keyed per game and has to stay that way.
    @Test func oneGamesCategoryIsNotAnothersSpinner() {
        let (repoA, gameA, contextA) = newGame()
        let (repoB, gameB, contextB) = newGame()
        repoA.addPlannedCategory(to: gameA, named: "Shrines")
        repoB.addPlannedCategory(to: gameB, named: "Shrines")
        let a = repoA.trackerCategories(for: gameA).first!
        let b = repoB.trackerCategories(for: gameB).first!

        let store = TrackerGenerationStore.shared
        store.generateCategory(a.id, named: a.name, for: gameA, context: contextA)
        defer { store.cancel(for: gameA.id); store.cancel(for: gameB.id) }

        #expect(store.isGenerating(gameA.id, category: a.id))
        #expect(store.isGenerating(gameB.id, category: b.id) == false)
        #expect(store.isGenerating(gameB.id) == false)
        _ = contextB
    }
}
