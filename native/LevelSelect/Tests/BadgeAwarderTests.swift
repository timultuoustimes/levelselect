import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The ledger side of badges: written once, never twice, and quiet the first
/// time over a library that has already earned things.
@MainActor
struct BadgeAwarderTests {

    private func store() -> Repository {
        UserDefaults.standard.removeObject(forKey: "levelselect.badges.backfilled")
        return Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    /// Everything an existing library has earned lands at once, silently —
    /// otherwise build 40's first launch is fourteen celebrations deep.
    @Test("The first pass writes what's earned and celebrates none of it")
    func firstPassIsQuiet() {
        let repo = store()
        let game = repo.addGame(name: "Hades")
        repo.addCompletion(to: game, label: .cleared, date: .now)

        let result = BadgeAwarder.award(in: repo.context)
        #expect(result.wasBackfill)
        #expect(result.newlyEarned.isEmpty)
        #expect(BadgeAwarder.existing(in: repo.context).contains { $0.badgeID == "first.beaten" })
    }

    @Test("After the first pass, a new badge is returned so it can be celebrated")
    func laterBadgesCelebrate() {
        let repo = store()
        let first = repo.addGame(name: "Hades")
        repo.addCompletion(to: first, label: .cleared, date: .now)
        _ = BadgeAwarder.award(in: repo.context)     // the quiet pass

        let memory = Memory(title: "Christmas 1996", earliest: .now, precision: "year")
        repo.context.insert(memory)
        let result = BadgeAwarder.award(in: repo.context)
        #expect(!result.wasBackfill)
        #expect(result.newlyEarned.map(\.id).contains("first.memory"))
    }

    @Test("Running twice writes nothing the second time")
    func awardingIsIdempotent() {
        let repo = store()
        let game = repo.addGame(name: "Celeste")
        repo.addCompletion(to: game, label: .cleared, date: .now)
        _ = BadgeAwarder.award(in: repo.context)
        let count = BadgeAwarder.existing(in: repo.context).count
        let again = BadgeAwarder.award(in: repo.context)
        #expect(again.newlyEarned.isEmpty)
        #expect(BadgeAwarder.existing(in: repo.context).count == count)
    }

    /// The ledger's whole reason for existing: undoing the thing that earned
    /// a badge does not take the badge away.
    @Test("A badge survives the completion that earned it being removed")
    func badgesDoNotUnEarn() {
        let repo = store()
        let game = repo.addGame(name: "Tunic")
        repo.addCompletion(to: game, label: .cleared, date: .now)
        _ = BadgeAwarder.award(in: repo.context)

        for event in (game.completionEvents ?? []) { repo.removeCompletion(event) }
        _ = BadgeAwarder.award(in: repo.context)
        #expect(BadgeAwarder.existing(in: repo.context).contains { $0.badgeID == "first.beaten" })
    }

    @Test("An empty library earns nothing and writes nothing")
    func emptyLibraryWritesNothing() {
        let repo = store()
        let result = BadgeAwarder.award(in: repo.context)
        #expect(result.newlyEarned.isEmpty)
        #expect(BadgeAwarder.existing(in: repo.context).isEmpty)
    }
}
