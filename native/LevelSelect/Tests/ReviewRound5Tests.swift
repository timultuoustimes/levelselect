import Testing
import Foundation
import SwiftData
@testable import LevelSelect

@MainActor
struct ReviewRound5Tests {

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": categories,
        ])
    }

    private func categories(in data: Data) -> [[String: Any]] {
        let root = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return root["categories"] as! [[String: Any]]
    }

    @Test func additiveMergeCannotWriteIntoALockedCategory() {
        let current = schema([
            ["id": "private", "name": "My Route", "type": "checklist", "locked": true,
             "items": [["id": "mine", "name": "My note"]]],
        ])
        let incoming = schema([
            ["id": "private", "name": "My Route", "type": "checklist",
             "items": [["id": "generated", "name": "Generated guess"]]],
        ])

        let result = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let items = categories(in: result)[0]["items"] as! [[String: Any]]

        #expect(items.compactMap { $0["id"] as? String } == ["mine"])
    }

    @Test func scopedReplaceRefusesAnAmbiguousNameFallback() {
        let current = schema([
            ["id": "local-bosses", "name": "Bosses", "sourceName": "Bosses",
             "type": "checklist", "items": [["id": "mine", "name": "My boss"]]],
        ])
        let incoming = schema([
            ["id": "main-bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "main", "name": "Main boss"]]],
            ["id": "dlc-bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "dlc", "name": "DLC boss"]]],
        ])

        let result = TrackerMerge.merged(
            current: current,
            incoming: incoming,
            mode: .replaceCategories(ids: ["local-bosses"])
        )
        let items = categories(in: result)[0]["items"] as! [[String: Any]]

        #expect(items.compactMap { $0["id"] as? String } == ["mine"])
    }

    @Test func removingOneOfTwoLegacyCategoriesWithTheSameIDRefusesTheAmbiguousDeletion() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Legacy collision", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "seed", "name": "Seed", "type": "checklist",
             "items": [["id": "placeholder", "name": "Placeholder"]]],
        ]), mode: .addAll)

        // This bypasses ingest deliberately: older app versions could already
        // have synced this invalid-but-deployed shape through CloudKit.
        game.trackerSchema!.jsonData = schema([
            ["id": "duplicate", "name": "First", "type": "checklist",
             "items": [["id": "first", "name": "First row"]]],
            ["id": "duplicate", "name": "Second", "type": "checklist",
             "items": [["id": "second", "name": "Second row"]]],
        ])
        let playthrough = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(playthrough, itemID: "first", done: true)
        repo.setTrackerItem(playthrough, itemID: "second", done: true)

        let removed = repo.removeCategory(from: game, categoryID: "duplicate")

        #expect(removed == false)
        #expect(repo.trackerCategories(for: game).count == 2)
        #expect(repo.trackerState(playthrough, itemID: "first")?.completed == true)
        #expect(repo.trackerState(playthrough, itemID: "second")?.completed == true)
    }

    @Test func aStableRAUserIDIsNotPairedWithAStaleDisplayUsername() throws {
        let credentials = RACredentials.Value(
            username: "old-display-name",
            apiKey: "secret-key",
            ulid: "stable-ulid"
        )
        let url = try RetroAchievementsService.progressURL(gameID: 123, credentials: credentials)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(query["u"] == "stable-ulid")
        #expect(query["g"] == "123")
        #expect(query["y"] == "secret-key")
        #expect(query["z"] == nil)
        #expect(!url.absoluteString.contains("old-display-name"))
    }

    @Test func dismissingOnePendingMergeDoesNotStrandTheNextMerge() {
        var state = MergeReviewPresentationState()
        let first = UUID()
        let second = UUID()

        #expect(state.pendingChanged(to: first, occupyingReviewID: nil, slotIsFree: true) == first)
        #expect(state.sheetClosed(reviewID: first, pendingID: first) == nil)
        #expect(state.pendingChanged(to: first, occupyingReviewID: nil, slotIsFree: true) == nil)

        // The old Boolean stayed true while pending changed non-nil → non-nil,
        // so this distinct result (including one from another game) vanished.
        #expect(state.pendingChanged(to: second, occupyingReviewID: nil, slotIsFree: true) == second)

        // A result landing behind another sheet waits, then takes the slot as
        // soon as that unrelated presentation closes.
        _ = state.pendingChanged(to: nil, occupyingReviewID: nil, slotIsFree: false)
        #expect(state.pendingChanged(to: first, occupyingReviewID: nil, slotIsFree: false) == nil)
        #expect(state.sheetClosed(reviewID: nil, pendingID: first) == first)
    }
}
