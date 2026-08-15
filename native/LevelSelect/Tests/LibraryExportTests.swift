import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// An export is only worth having if it's complete. These tests assert that
/// what goes into the store comes back out of the file — the manifest counts
/// match reality, nested history survives, and deleted records don't leak.
@MainActor
struct LibraryExportTests {

    private func populated() -> (ModelContext, Repository) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)

        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        game.rating = 5
        game.review = "Best in class."
        game.ownership = [Ownership.digital.rawValue]
        game.platforms = ["Nintendo Switch"]

        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.logManualSession(on: pt, duration: 3600)
        repo.logManualSession(on: pt, duration: 1800)
        repo.setTrackerItem(pt, itemID: "boss-1", done: true)
        repo.setTrackerRank(pt, itemID: "nail", rank: 2, maxRank: 4)
        repo.logRun(on: pt, fields: ["weapon": "Blade"], outcome: .success,
                    started: .now, duration: 900, notes: "clean")
        repo.addCompletion(to: game, label: .completed)

        let second = repo.addGame(name: "Celeste", status: .completed)
        let collection = repo.createCollection(name: "Comfort Games")
        repo.setMembership(collection, game: second, member: true)

        return (context, repo)
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func manifestCountsMatchTheLibrary() throws {
        let (context, _) = populated()
        let root = try decode(try LibraryExport.makeJSON(context: context))
        let manifest = try #require(root["manifest"] as? [String: Any])

        #expect(manifest["formatVersion"] as? Int == LibraryExport.formatVersion)
        #expect(manifest["games"] as? Int == 2)
        #expect(manifest["sessions"] as? Int == 2)
        #expect(manifest["runs"] as? Int == 1)
        #expect(manifest["trackerStates"] as? Int == 2)
        #expect(manifest["completions"] as? Int == 1)
        #expect(manifest["collections"] as? Int == 1)

        // totalRecords must actually be the sum, or it's a useless checksum.
        let parts = ["games", "playthroughs", "sessions", "runs", "trackerStates",
                     "trackerSchemas", "completions", "videos", "collections"]
        let sum = parts.reduce(0) { $0 + (manifest[$1] as? Int ?? 0) }
        #expect(manifest["totalRecords"] as? Int == sum)
    }

    @Test func nestedHistorySurvives() throws {
        let (context, _) = populated()
        let root = try decode(try LibraryExport.makeJSON(context: context))
        let games = try #require(root["games"] as? [[String: Any]])
        let hk = try #require(games.first { $0["name"] as? String == "Hollow Knight" })

        #expect(hk["rating"] as? Int == 5)
        #expect(hk["review"] as? String == "Best in class.")

        let playthroughs = try #require(hk["playthroughs"] as? [[String: Any]])
        let pt = try #require(playthroughs.first)
        #expect((pt["sessions"] as? [[String: Any]])?.count == 2)
        #expect((pt["runs"] as? [[String: Any]])?.count == 1)

        // Ranks and completion flags both have to round-trip, not just names.
        let progress = try #require(pt["trackerProgress"] as? [[String: Any]])
        let nail = try #require(progress.first { $0["itemID"] as? String == "nail" })
        #expect(nail["rank"] as? Int == 2)
        let boss = try #require(progress.first { $0["itemID"] as? String == "boss-1" })
        #expect(boss["completed"] as? Bool == true)
    }

    /// Deleted things are gone from the user's view, so they must be gone from
    /// the export too — otherwise an import would resurrect them.
    @Test func deletedRecordsAreExcluded() throws {
        let (context, repo) = populated()
        let games = try context.fetch(FetchDescriptor<Game>())
        let celeste = try #require(games.first { $0.name == "Celeste" })
        repo.softDelete(celeste)

        let root = try decode(try LibraryExport.makeJSON(context: context))
        let exported = try #require(root["games"] as? [[String: Any]])
        #expect(exported.count == 1)
        #expect(exported.first?["name"] as? String == "Hollow Knight")
    }

    @Test func clearingSessionsLeavesGamesAndTrackers() throws {
        let (context, repo) = populated()
        let cleared = repo.clearAllSessions()
        #expect(cleared == 2)

        let root = try decode(try LibraryExport.makeJSON(context: context))
        let manifest = try #require(root["manifest"] as? [String: Any])
        #expect(manifest["sessions"] as? Int == 0)
        #expect(manifest["games"] as? Int == 2)          // games survive
        #expect(manifest["trackerStates"] as? Int == 2)  // progress survives
    }

    @Test func clearingTrackerProgressLeavesSessions() throws {
        let (context, repo) = populated()
        let cleared = repo.clearAllTrackerProgress()
        #expect(cleared == 3)   // 2 state rows + 1 run

        let root = try decode(try LibraryExport.makeJSON(context: context))
        let manifest = try #require(root["manifest"] as? [String: Any])
        #expect(manifest["trackerStates"] as? Int == 0)
        #expect(manifest["runs"] as? Int == 0)
        #expect(manifest["sessions"] as? Int == 2)       // playtime survives
    }
}
