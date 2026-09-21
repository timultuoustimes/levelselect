import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Where a tracker's items came from: descriptors and links, never pasted
/// text (Tim, 09-21). `sourcesJSON` existed since V1 and nothing wrote it
/// (Codex, build 40 static assessment).
@MainActor
struct TrackerProvenanceTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func schema(sources: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "sources": sources,
            "categories": [["id": "c", "name": "Charms",
                            "items": [["id": "i", "name": "Wayward Compass"]]]],
        ])
    }

    private func recorded(_ game: Game) -> [TrackerProvenance] {
        game.trackerSchema?.sourcesJSON
            .flatMap { try? JSONDecoder().decode([TrackerProvenance].self, from: $0) } ?? []
    }

    @Test("A generated tracker records the guide it was built from")
    func generationRecordsItsGuide() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight")
        repo.setGeneratedSchema(for: game, jsonData: schema(sources: [
            ["type": "url", "url": "https://hollowknight.wiki/Charms"],
        ]))
        #expect(recorded(game) == [TrackerProvenance(type: "url", url: "https://hollowknight.wiki/Charms")])
    }

    /// **The rule, enforced at the boundary.** Whatever arrives beside the
    /// type and URL is dropped — so pasted text cannot reach the store even
    /// if a server change started sending it.
    @Test("Pasted text never reaches the store, whatever the payload carries")
    func pastedTextIsNeverKept() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight")
        let secret = "Grubs are behind the breakable wall in Crossroads…"
        repo.setGeneratedSchema(for: game, jsonData: schema(sources: [
            ["type": "paste", "text": secret, "body": secret, "url": "https://ignored.example"],
        ]))
        let raw = try #require(game.trackerSchema?.sourcesJSON)
        let stored = try #require(String(data: raw, encoding: .utf8))
        #expect(!stored.contains("Grubs"))
        #expect(recorded(game) == [.pasted])
        #expect(recorded(game).first?.url == nil)   // a paste has no address
    }

    @Test("A list import records a sheet by its link and a paste by the fact of it")
    func listImportsRecordTheirKind() {
        let repo = store()
        let sheetGame = repo.addGame(name: "Tunic")
        repo.applyGeneratedSchema(for: sheetGame, jsonData: schema(sources: []), mode: .addAll,
                                  provenance: [.sheet("https://docs.google.com/spreadsheets/d/abc")])
        #expect(recorded(sheetGame) == [.sheet("https://docs.google.com/spreadsheets/d/abc")])

        let pasteGame = repo.addGame(name: "Celeste")
        repo.applyGeneratedSchema(for: pasteGame, jsonData: schema(sources: []), mode: .addAll,
                                  provenance: [.pasted])
        #expect(recorded(pasteGame) == [.pasted])
    }

    /// A tracker built from a guide and then topped up from a paste says both,
    /// once each, in the order they happened.
    @Test("Provenance accumulates across merges, without repeats")
    func provenanceAccumulates() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight")
        let guide = TrackerProvenance(type: "url", url: "https://hollowknight.wiki/Charms")
        repo.setGeneratedSchema(for: game, jsonData: schema(sources: [["type": "url", "url": guide.url!]]))
        repo.applyGeneratedSchema(for: game, jsonData: schema(sources: [["type": "url", "url": guide.url!]]),
                                  mode: .addAll)
        repo.applyGeneratedSchema(for: game, jsonData: schema(sources: []), mode: .addAll,
                                  provenance: [.pasted])
        #expect(recorded(game) == [guide, .pasted])
    }

    /// A backup is filtered the same way on the way back in.
    @Test("A restored backup keeps only type and URL")
    func restoreIsFiltered() throws {
        let source = store()
        let game = source.addGame(name: "Hollow Knight")
        source.setGeneratedSchema(for: game, jsonData: schema(sources: [["type": "url", "url": "https://a.example"]]))
        try source.context.save()

        var root = try #require(try JSONSerialization.jsonObject(
            with: try LibraryExport.makeJSON(context: source.context)) as? [String: Any])
        var games = try #require(root["games"] as? [[String: Any]])
        var tracker = try #require(games[0]["trackerSchema"] as? [String: Any])
        tracker["sources"] = [["type": "paste", "text": "a whole guide, pasted"]]
        games[0]["trackerSchema"] = tracker
        root["games"] = games
        let tampered = try JSONSerialization.data(withJSONObject: root)

        let target = store()
        _ = try LibraryImport.apply(data: tampered, context: target.context)
        let restored = try #require(try target.context.fetch(FetchDescriptor<Game>()).first)
        #expect(recorded(restored) == [.pasted])
    }
}
