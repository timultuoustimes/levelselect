import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// `installMissing` only fills a gap — it never overwrites an existing
/// schema, so generating an AI tracker over a game that ships a real
/// built-in one used to be a one-way door. `useBuiltinSchema` is the
/// deliberate undo; these cover that it finds the right built-in, survives
/// swapping over an AI schema, keeps Personal Goals, and is a clean no-op
/// for a game with no built-in at all.
@MainActor
struct BuiltinTrackerSwapTests {

    private func game(named name: String, igdbID: Int? = nil) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: name, status: .playing)
        game.igdbID = igdbID
        return (repo, game)
    }

    @Test func matchesByIgdbIDAndInstallsRealContent() throws {
        // 113112 is Supergiant's Hades — the same id the demo library pins.
        let (repo, game) = self.game(named: "Some Renamed Edition", igdbID: 113112)
        #expect(game.trackerSchema == nil)

        #expect(repo.useBuiltinSchema(for: game) == true)

        let schema = try #require(game.trackerSchema)
        #expect(schema.source == .builtIn)
        let categories = TrackerSchemaJSON.categories(from: schema.jsonData)
        #expect(categories.contains { $0.name == "Weapon Aspects" })
    }

    @Test func swapsOverAnAIGeneratedSchemaAndKeepsPersonalGoals() throws {
        let (repo, game) = self.game(named: "Hades", igdbID: 113112)

        // A goal added before any schema exists, then an AI schema generated
        // over it — the real sequence a player would hit.
        repo.addPersonalGoal(to: game, named: "No-hit a boss")
        let fakeAI = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "made-up", "name": "Made Up", "items": []]],
        ])
        repo.setGeneratedSchema(for: game, jsonData: fakeAI)
        #expect(game.trackerSchema?.source == .aiGenerated)

        #expect(repo.useBuiltinSchema(for: game) == true)

        let schema = try #require(game.trackerSchema)
        #expect(schema.source == .builtIn)
        let categories = TrackerSchemaJSON.categories(from: schema.jsonData)
        #expect(categories.contains { $0.name == "Weapon Aspects" })
        // The goal survived being generated over AND swapped to built-in.
        #expect(categories.first { $0.id == TrackerSchemaJSON.personalGoalsID }?
            .items.contains { $0.name == "No-hit a boss" } == true)
    }

    @Test func noBuiltinExistsIsACleanNoOp() throws {
        let (repo, game) = self.game(named: "A Game Nobody Made a Tracker For")
        let fakeAI = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "stuff", "name": "Stuff", "items": []]],
        ])
        repo.setGeneratedSchema(for: game, jsonData: fakeAI)

        #expect(repo.useBuiltinSchema(for: game) == false)
        // Untouched — still the AI schema, not silently cleared.
        #expect(game.trackerSchema?.source == .aiGenerated)
        let categories = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
        #expect(categories.contains { $0.name == "Stuff" })
    }
}
