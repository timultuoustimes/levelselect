import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Run logging is a capability the player turns on, not something the genre
/// decides. These cover that it can be enabled for any game, that turning it
/// off never destroys history, and that runs and sessions stay independent.
@MainActor
struct RunTrackingTests {

    private func game(named name: String) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    @Test func offByDefault() {
        let (repo, game) = self.game(named: "Dead Cells")
        #expect(repo.runTrackingEnabled(for: game) == false)
    }

    /// A game with no tracker at all must still be able to log runs — you
    /// shouldn't have to generate a tracker first just to record attempts.
    @Test func canBeEnabledOnAGameWithNoTracker() {
        let (repo, game) = self.game(named: "Ball x Pit")
        #expect(game.trackerSchema == nil)

        repo.setRunTracking(true, for: game)
        #expect(repo.runTrackingEnabled(for: game) == true)
        #expect(game.trackerSchema != nil)

        let template = TrackerSchemaJSON.runTemplate(from: game.trackerSchema!.jsonData)
        #expect(template?.outcomes.isEmpty == false)
    }

    /// Turning it off leaves the runs alone, so it's a display choice rather
    /// than a delete — and switching back on brings the history with it.
    @Test func disablingKeepsExistingRuns() throws {
        let (repo, game) = self.game(named: "Hades")
        repo.setRunTracking(true, for: game)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.logRun(on: pt, fields: ["loadout": "Blade"], outcome: .success,
                    started: .now, duration: 1800, notes: nil)
        #expect(pt.liveRuns.count == 1)

        repo.setRunTracking(false, for: game)
        #expect(repo.runTrackingEnabled(for: game) == false)
        #expect(pt.liveRuns.count == 1)          // history survives

        repo.setRunTracking(true, for: game)
        #expect(repo.runTrackingEnabled(for: game) == true)
        #expect(pt.liveRuns.count == 1)          // and comes back
    }

    /// Enabling twice shouldn't stack templates or clobber a game's existing
    /// hand-built one (Hades ships with a real template of its own).
    @Test func enablingIsIdempotentAndPreservesACustomTemplate() throws {
        let (repo, game) = self.game(named: "Hades")
        let custom: [String: Any] = [
            "schemaVersion": 1,
            "categories": [],
            "runTemplate": [
                "fields": [["id": "weapon", "label": "Weapon", "type": "text"]],
                "outcomes": [["id": "success", "label": "Escaped"]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: custom)
        repo.setGeneratedSchema(for: game, jsonData: data)

        repo.setRunTracking(true, for: game)
        repo.setRunTracking(true, for: game)

        let template = try #require(
            TrackerSchemaJSON.runTemplate(from: game.trackerSchema!.jsonData))
        // The game's own field survived rather than being replaced by the
        // generic default.
        #expect(template.fields.contains { $0.id == "weapon" })
        #expect(template.outcomes.first?.label == "Escaped")
    }

    /// The AI generator's JSON schema declares `outcomes` as an array of
    /// plain strings, while built-ins use objects. Only accepting objects
    /// meant every AI-generated roguelike tracker parsed to *no* run template
    /// — which is what made "Log Runs for This Game" look broken on
    /// Splintered Fate.
    @Test func parsesStringOutcomesFromTheAIGenerator() throws {
        let generated: [String: Any] = [
            "schemaVersion": 1,
            "categories": [],
            "runTemplate": [
                "fields": [["id": "weapon", "label": "Weapon", "type": "text"]],
                "outcomes": ["Escaped", "Died", "Abandoned"],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: generated)
        let template = try #require(TrackerSchemaJSON.runTemplate(from: data))

        #expect(template.outcomes.count == 3)
        #expect(template.outcomes.map(\.label) == ["Escaped", "Died", "Abandoned"])
        // Win/lose inferred from the wording so run stats aren't all neutral.
        #expect(template.outcomes[0].result == .success)
        #expect(template.outcomes[1].result == .failure)
        #expect(template.outcomes[2].result == .neutral)
    }

    /// A schema carrying a `runTemplate` that parses to nothing used to make
    /// the toggle a permanent no-op: `addingDefaultRunTemplate` saw the key
    /// and returned early, while the renderer saw nothing to draw.
    @Test func enablingRepairsAnUnusableRunTemplate() throws {
        let (repo, game) = self.game(named: "Splintered Fate")
        let broken: [String: Any] = [
            "schemaVersion": 1,
            "categories": [],
            "runTemplate": ["fields": [], "outcomes": []],   // parses to nil
        ]
        repo.setGeneratedSchema(
            for: game, jsonData: try JSONSerialization.data(withJSONObject: broken))
        #expect(repo.runTrackingEnabled(for: game) == false)

        repo.setRunTracking(true, for: game)

        #expect(repo.runTrackingEnabled(for: game) == true)
        let template = try #require(
            TrackerSchemaJSON.runTemplate(from: game.trackerSchema!.jsonData))
        #expect(template.outcomes.isEmpty == false)
    }

    /// Runs and sessions are separate records: logging one must not create
    /// or disturb the other.
    @Test func runsAndSessionsAreIndependent() throws {
        let (repo, game) = self.game(named: "Hades")
        repo.setRunTracking(true, for: game)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        repo.logRun(on: pt, fields: [:], outcome: .failure,
                    started: .now, duration: 600, notes: nil)
        #expect((pt.sessions ?? []).isEmpty)     // a run didn't start a timer

        repo.logManualSession(on: pt, duration: 3600)
        #expect(pt.liveRuns.count == 1)          // a session didn't add a run
        #expect((pt.sessions ?? []).count == 1)
        // Playtime comes from sessions only — runs don't inflate it.
        #expect(abs(pt.totalPlaytime() - 3600) < 1)
    }
}
