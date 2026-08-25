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

// MARK: - Run field options + analytics (pure, no store)

/// The web app's per-game run pickers and AnalyticsSection, generalised.
/// These pin the three narrowing rules — category-backed, unlocked-only,
/// depends-on — and the aggregation the Analytics section renders.
struct RunFieldSupportTests {

    private func cat(_ id: String, _ items: [(String, String, String?)]) -> TrackerCategoryDTO {
        TrackerCategoryDTO(
            id: id, name: id, categoryDescription: nil, kind: nil, items: items.map {
                TrackerItemDTO(id: $0.0, name: $0.1, itemDescription: nil,
                               location: $0.2, missable: false,
                               hideUntilDiscovered: false, maxRank: nil,
                               rankNames: nil, display: nil)
            })
    }

    private var keepsakes: TrackerCategoryDTO {
        cat("hades-keepsakes", [("k1", "Old Spiked Collar", nil),
                                ("k2", "Myrmidon Bracer", nil),
                                ("k3", "Black Shawl", nil)])
    }

    private var aspects: TrackerCategoryDTO {
        cat("hades-aspects", [("a1", "Aspect of Zagreus", "Stygian Blade"),
                              ("a2", "Aspect of Nemesis", "Stygian Blade"),
                              ("a3", "Aspect of Guan Yu", "Eternal Spear")])
    }

    @Test func staticOptionsPassThrough() {
        let field = RunFieldDTO(id: "w", label: "Weapon", kind: "select",
                                options: ["Sword", "Spear"])
        let opts = RunFieldSupport.options(for: field, categories: [], progressed: [], values: [:])
        #expect(opts == ["Sword", "Spear"])
    }

    @Test func categoryBackedOptionsUseItemNames() {
        let field = RunFieldDTO(id: "k", label: "Keepsake", kind: "select",
                                options: [], optionsFrom: "hades-keepsakes")
        let opts = RunFieldSupport.options(for: field, categories: [keepsakes],
                                           progressed: [], values: [:])
        #expect(opts == ["Old Spiked Collar", "Myrmidon Bracer", "Black Shawl"])
    }

    /// The rule the user actually missed from the web: unlocked keepsakes
    /// only — but a fresh tracker offers the full list, never an empty picker.
    @Test func onlyUnlockedFiltersAndFallsBack() {
        let field = RunFieldDTO(id: "k", label: "Keepsake", kind: "select",
                                options: [], optionsFrom: "hades-keepsakes",
                                onlyUnlocked: true)
        let filtered = RunFieldSupport.options(for: field, categories: [keepsakes],
                                               progressed: ["k2"], values: [:])
        #expect(filtered == ["Myrmidon Bracer"])

        let fresh = RunFieldSupport.options(for: field, categories: [keepsakes],
                                            progressed: [], values: [:])
        #expect(fresh.count == 3)
    }

    /// Aspects narrow to the chosen weapon via the item's `location`, and
    /// offer everything when no weapon is picked yet.
    @Test func dependsOnScopesByLocation() {
        let field = RunFieldDTO(id: "a", label: "Aspect", kind: "select",
                                options: [], optionsFrom: "hades-aspects",
                                dependsOn: "weapon")
        let scoped = RunFieldSupport.options(for: field, categories: [aspects],
                                             progressed: [],
                                             values: ["weapon": "Stygian Blade"])
        #expect(scoped == ["Aspect of Zagreus", "Aspect of Nemesis"])

        let unscoped = RunFieldSupport.options(for: field, categories: [aspects],
                                               progressed: [], values: [:])
        #expect(unscoped.count == 3)
    }

    @Test func statsGroupByValueAndCountWins() {
        let weapon = RunFieldDTO(id: "weapon", label: "Weapon", kind: "select",
                                 options: ["Sword", "Spear"])
        let stats = RunFieldSupport.stats(fields: [weapon], runs: [
            (["weapon": "Sword"], true),
            (["weapon": "Sword"], false),
            (["weapon": "Sword"], true),
            (["weapon": "Spear"], false),
            (["weapon": ""], true),          // empty values never group
        ])
        #expect(stats.count == 1)
        let rows = stats[0].rows
        #expect(rows[0].value == "Sword" && rows[0].wins == 2 && rows[0].total == 3)
        #expect(rows[1].value == "Spear" && rows[1].wins == 0 && rows[1].total == 1)
    }

    /// A multi field counts each of its values once per run.
    @Test func multiFieldsSplitAndDeduplicate() {
        let gods = RunFieldDTO(id: "gods", label: "Gods", kind: "multi",
                               options: ["Zeus", "Athena", "Ares"])
        let stats = RunFieldSupport.stats(fields: [gods], runs: [
            (["gods": "Zeus, Athena"], true),
            (["gods": "Zeus"], false),
        ])
        let rows = Dictionary(uniqueKeysWithValues: stats[0].rows.map { ($0.value, $0) })
        #expect(rows["Zeus"]?.total == 2 && rows["Zeus"]?.wins == 1)
        #expect(rows["Athena"]?.total == 1 && rows["Athena"]?.wins == 1)
    }

    /// Free-text fields never aggregate — typos would fragment every group.
    @Test func textFieldsProduceNoStats() {
        let heat = RunFieldDTO(id: "heat", label: "Heat", kind: "text", options: [])
        let stats = RunFieldSupport.stats(fields: [heat], runs: [(["heat": "4"], true)])
        #expect(stats.isEmpty)
    }

    /// The new schema keys survive the JSON round trip the app actually uses.
    @Test func runTemplateParsesPickerKeys() throws {
        let json = """
        {"runTemplate": {"fields": [
            {"id": "k", "label": "Keepsake", "type": "select",
             "optionsFrom": "hades-keepsakes", "onlyUnlocked": true},
            {"id": "d", "label": "Fell in", "type": "select",
             "options": ["Styx"], "phase": "end"}
        ], "outcomes": [{"id": "w", "label": "Escaped", "result": "success"}]}}
        """
        let template = try #require(TrackerSchemaJSON.runTemplate(from: Data(json.utf8)))
        #expect(template.fields[0].optionsFrom == "hades-keepsakes")
        #expect(template.fields[0].onlyUnlocked == true)
        #expect(template.fields[0].isEndPhase == false)
        #expect(template.fields[1].isEndPhase == true)
    }
}

/// End-phase fields merge into the run's stored loadout when it ends.
@MainActor
struct EndRunFieldMergeTests {

    @Test func endRunMergesExtraFields() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let run = repo.startRun(on: pt, fields: ["weapon": "Sword"])

        repo.endRun(run, outcome: .failure, notes: nil,
                    extraFields: ["deathLocation": "Styx", "gods": ""])

        #expect(run.fieldsDict["weapon"] == "Sword")
        #expect(run.fieldsDict["deathLocation"] == "Styx")
        // Empty entries must not overwrite or appear.
        #expect(run.fieldsDict["gods"] == nil)
    }
}

/// Stats card order survives builds that add cards: stored preferences from
/// an older build must surface new cards, not silently hide them.
struct StatsCardOrderTests {
    @Test func emptyStoredOrderIsDefault() {
        #expect(StatsCard.resolveOrder(stored: "") == Array(StatsCard.allCases))
    }

    @Test func storedOrderWins() {
        let stored = StatsCard.allCases.reversed().map(\.rawValue).joined(separator: ",")
        #expect(StatsCard.resolveOrder(stored: stored) == Array(StatsCard.allCases.reversed()))
    }

    @Test func unknownCardsAppearAtTheirDefaultNeighborhood() {
        // A stored order missing `streak` and `years` (as if saved by a build
        // that predates them): both must reappear, after the card that
        // precedes them in the default order.
        let stored = StatsCard.allCases
            .filter { $0 != .streak && $0 != .years }
            .map(\.rawValue).joined(separator: ",")
        let resolved = StatsCard.resolveOrder(stored: stored)
        #expect(resolved.count == StatsCard.allCases.count)
        #expect(resolved.firstIndex(of: .streak)! == resolved.firstIndex(of: .monthly)! + 1)
        #expect(resolved.firstIndex(of: .years)! == resolved.firstIndex(of: .tags)! + 1)
    }

    @Test func garbageTokensAreDropped() {
        let resolved = StatsCard.resolveOrder(stored: "overview,notacard,streak")
        #expect(resolved.count == StatsCard.allCases.count)
        #expect(resolved.first == .overview)
    }
}
