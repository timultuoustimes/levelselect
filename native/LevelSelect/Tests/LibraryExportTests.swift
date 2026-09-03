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

/// Build 36 — memories, and the pictures on them, survive a backup.
///
/// The export carried `game.images` and no memories at all, so someone's
/// Christmas photo — and the words they wrote about it — were absent from
/// their own backup file without anything saying so. These are the tests that
/// would have caught it.
@MainActor
struct Build36MemoryExportTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// A 1×1 PNG — enough bytes that `makeImage` accepts it on the way back.
    private var pixel: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    }

    @Test("A memory, its words and its photo all survive an export and re-import")
    func memoriesRoundTrip() throws {
        let source = makeContext()
        let repo = Repository(source)

        let memory = Memory()
        memory.title = "Got my Sega Genesis for Christmas"
        memory.body = "Model 2 with Columns bundle"
        memory.place = "Twin Lakes house"
        memory.platform = "Sega Genesis"
        memory.kind = "acquired"
        let first = Memory.calendar.date(from: DateComponents(year: 1995, month: 12, day: 25))!
        let second = Memory.calendar.date(from: DateComponents(year: 1996, month: 12, day: 25))!
        _ = repo.saveMemory(memory, on: first, precision: nil,
                            words: "Christmas 1995/1996", span: first...second)
        _ = try repo.addImage(to: memory, data: pixel)

        let data = try LibraryExport.makeJSON(context: source)

        // Into an empty library, the way a restore actually happens.
        let target = makeContext()
        let outcome = try LibraryImport.apply(data: data, context: target)
        #expect(outcome.created["memories"] == 1)
        #expect(outcome.created["images"] == 1)

        let restored = try target.fetch(FetchDescriptor<Memory>())
        #expect(restored.count == 1)
        let it = try #require(restored.first)
        #expect(it.title == "Got my Sega Genesis for Christmas")
        #expect(it.body == "Model 2 with Columns bundle")
        #expect(it.place == "Twin Lakes house")
        #expect(it.platform == "Sega Genesis")
        #expect(it.kind == "acquired")
        // The words are the memory's own answer to "when" and are never
        // re-rendered from the interval — so they have to come back verbatim.
        #expect(it.whenText == "Christmas 1995/1996")
        #expect(it.precision == nil)
        #expect(it.isUncertain)
        #expect(it.earliest == first)
        #expect(it.latest == second)
        // And the photograph, which is the part that cannot be retyped.
        #expect((it.images ?? []).count == 1)
        #expect((it.images ?? []).first?.data == pixel)
    }

    @Test("A memory attached to a game comes back attached to it")
    func memoryKeepsItsGame() throws {
        let source = makeContext()
        let repo = Repository(source)
        let game = Game(name: "Sonic the Hedgehog 2")
        source.insert(game)
        let memory = Memory()
        memory.title = "Beat it at my cousin's"
        memory.game = game
        _ = repo.saveMemory(memory, on: .now, precision: "day", words: nil)

        let data = try LibraryExport.makeJSON(context: source)
        let target = makeContext()
        _ = try LibraryImport.apply(data: data, context: target)

        let restored = try #require(try target.fetch(FetchDescriptor<Memory>()).first)
        #expect(restored.game?.name == "Sonic the Hedgehog 2")
    }

    @Test("A standalone memory is exported at all")
    func standaloneMemoryIsNotNested() throws {
        // The specific shape of the original bug: memories nested under games
        // would have exported only the attached ones. "First LAN party"
        // belongs to no game.
        let source = makeContext()
        let memory = Memory()
        memory.title = "First LAN party"
        _ = Repository(source).saveMemory(memory, on: .now, precision: "day", words: nil)

        let data = try LibraryExport.makeJSON(context: source)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memories = try #require(root["memories"] as? [[String: Any]])
        #expect(memories.count == 1)
        #expect(memories.first?["title"] as? String == "First LAN party")

        let manifest = try #require(root["manifest"] as? [String: Any])
        #expect(manifest["memories"] as? Int == 1)
    }

    @Test("Deleting a memory takes its pictures out of live storage")
    func deletingAMemoryRemovesItsPictures() throws {
        let context = makeContext()
        let repo = Repository(context)
        let memory = Memory()
        memory.title = "Sold the collection"
        _ = repo.saveMemory(memory, on: .now, precision: "day", words: nil)
        let image = try repo.addImage(to: memory, data: pixel)

        repo.deleteMemory(memory)

        // The cascade rule on the relationship only fires on a hard delete, so
        // before this the picture stayed live: unreachable from any screen,
        // and still counted by the storage view as bytes in use.
        #expect(image.deletedAt != nil)
        let live = try context.fetch(FetchDescriptor<GameImage>())
            .filter { $0.deletedAt == nil }
        #expect(live.isEmpty)
    }

    @Test("A deleted memory is not exported")
    func deletedMemoriesStayOut() throws {
        let context = makeContext()
        let repo = Repository(context)
        let memory = Memory()
        memory.title = "Typo"
        _ = repo.saveMemory(memory, on: .now, precision: "day", words: nil)
        repo.deleteMemory(memory)

        let root = try #require(try JSONSerialization.jsonObject(
            with: try LibraryExport.makeJSON(context: context)) as? [String: Any])
        #expect((root["memories"] as? [[String: Any]])?.isEmpty == true)
    }
}

/// Build 36 — a backup made by an older build still restores.
///
/// `formatVersion` went to 2 for memories, and the importer's gate was
/// `version == supportedVersion`. That was correct with one version and a bug
/// with two: it refused every file made before memories existed, which is
/// precisely the backup someone restoring is most likely to be holding.
@MainActor
struct Build36ImportVersionTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private func file(version: Int) -> Data {
        Data("""
        {"manifest":{"formatVersion":\(version),"games":1},
         "games":[{"id":"\(UUID().uuidString)","name":"Sonic the Hedgehog 2"}]}
        """.utf8)
    }

    @Test("A version 1 export — made before memories existed — still imports")
    func readsTheOlderFormat() throws {
        let context = makeContext()
        let outcome = try LibraryImport.apply(data: file(version: 1), context: context)
        #expect(outcome.created["games"] == 1)
        // Nothing to restore, and nothing to complain about: v1 has no
        // memories key and the importer treats a missing key as none.
        #expect(outcome.created["memories"] == nil)
        #expect(try context.fetch(FetchDescriptor<Game>()).count == 1)
    }

    @Test("The current format imports")
    func readsItsOwnFormat() throws {
        let outcome = try LibraryImport.apply(
            data: file(version: LibraryImport.supportedVersion), context: makeContext())
        #expect(outcome.created["games"] == 1)
    }

    @Test("A file from a newer build is refused rather than silently thinned")
    func refusesTheNewerFormat() {
        // The opposite direction stays strict on purpose: a newer file carries
        // records this build has no model for, and dropping them quietly is
        // the exact failure the version bump exists to prevent.
        #expect(throws: LibraryImport.ImportError.self) {
            _ = try LibraryImport.apply(
                data: file(version: LibraryImport.supportedVersion + 1),
                context: makeContext())
        }
    }
}
