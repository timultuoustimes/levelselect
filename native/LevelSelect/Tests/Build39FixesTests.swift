import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Codex's build 39 code pass, 2026-09-15, each finding as the test that shows it
/// fixed. The counted-pin findings live with the rest of counted items, in
/// `CountedItemTests`.
@MainActor
struct Build39FixesTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: Record playthroughs

    /// Two devices each made a Steam playthrough before iCloud met them.
    @Test("Duplicate Steam record playthroughs fold into one, and playtime isn't doubled")
    func duplicateSteamRecordsMerge() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines", status: .playing)
        let mine = repo.ensureDefaultPlaythrough(for: game)
        let hours = TimeInterval(7_491 * 3600)

        let first = repo.steamPlaythrough(for: game)
        repo.setCarriedOver(hours, on: first)
        repo.setTrackerItem(first, itemID: "steam-A", done: true)

        // The other device's copy, arriving by sync.
        let second = Playthrough(name: Repository.steamPlaythroughName)
        second.notes = Repository.steamPlaythroughMarker
        repo.context.insert(second)
        second.game = game
        repo.setCarriedOver(hours, on: second)
        repo.setTrackerItem(second, itemID: "steam-A", done: true)
        repo.setTrackerItem(second, itemID: "steam-B", done: true)
        #expect(game.livePlaythroughs.reduce(0) { $0 + $1.carriedOverSeconds } == hours * 2)

        let outcome = repo.reconcile(game)
        #expect(outcome.mergedRecordPlaythroughs == 1)

        let records = game.livePlaythroughs.filter { $0.name == Repository.steamPlaythroughName }
        #expect(records.count == 1)
        #expect(game.livePlaythroughs.reduce(0) { $0 + $1.carriedOverSeconds } == hours)
        let live = (records.first?.trackerStates ?? []).filter { $0.deletedAt == nil }
        #expect(Set(live.filter(\.completed).map(\.itemID)) == ["steam-A", "steam-B"])
        #expect(live.filter { $0.itemID == "steam-A" }.count == 1)
        #expect(game.activePlaythrough?.id == mine.id)
    }

    /// The rule for everything else stands: a playthrough another device may
    /// still be filling is never deleted on a guess.
    @Test("Ordinary duplicate playthroughs are still left for the user")
    func ordinaryDuplicatesStay() {
        let repo = store()
        let game = repo.addGame(name: "Hades", status: .playing)
        _ = repo.addPlaythrough(to: game, named: "Playthrough")
        _ = repo.addPlaythrough(to: game, named: "Playthrough")
        _ = repo.reconcile(game)
        #expect(game.livePlaythroughs.count == 2)
    }

    // MARK: Plans and Update My Lists

    private var importedAndPlans: [String: Any] {
        ["schemaVersion": 1, "categories": [
            ["id": "steam", "name": "Steam Achievements", "steamAppID": 620, "type": "checklist",
             "items": [["id": "steam-A", "name": "Wake Up Call"]]],
            ["id": "plan-bosses", "name": "Bosses", "pending": true, "items": []],
            ["id": "plan-graves", "name": "Warrior Graves", "pending": true, "items": []],
        ]]
    }

    @Test("With only imported lists and plans, there's nothing for Update My Lists to update")
    func nothingToUpdate() {
        let categories = TrackerSchemaJSON.categories(from: json(importedAndPlans))
        #expect(TrackerGenerationStore.regenerationCategories(categories).isEmpty)
    }

    @Test("Replacing a tracker keeps planned categories, unless the new one already has that list")
    func replaceKeepsPlans() {
        let incoming: [String: Any] = ["schemaVersion": 1, "categories": [
            ["id": "bosses", "name": "Bosses", "type": "checklist", "items": [["id": "b1", "name": "Hornet"]]],
        ]]
        let merged = TrackerSchemaJSON.mergingPersonalGoals(from: json(importedAndPlans), into: json(incoming))
        let names = TrackerSchemaJSON.categories(from: merged).map(\.name)
        #expect(names.filter { $0 == "Bosses" }.count == 1)
        #expect(names.contains("Warrior Graves"))
        #expect(names.contains("Steam Achievements"))
    }

    // MARK: Credentials stay on their host

    @Test("A credentialed request is only redirected within its own host, over https")
    func redirectsStayOnHost() {
        let steam = URL(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=K")!
        #expect(CredentialRedirectGuard.allows(from: steam, to: URL(string: "https://api.steampowered.com/v2/")!))
        #expect(!CredentialRedirectGuard.allows(from: steam, to: URL(string: "https://elsewhere.example/?key=K")!))
        #expect(!CredentialRedirectGuard.allows(from: steam, to: URL(string: "http://api.steampowered.com/")!))
        #expect(!CredentialRedirectGuard.allows(from: nil, to: steam))
    }
}
