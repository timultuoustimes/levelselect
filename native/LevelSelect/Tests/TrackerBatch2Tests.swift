import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Tracker batch 2 (2026-09-17): per-list progress, focus, lists shared
/// across playthroughs, attempts on the run engine, run lists, life-sim
/// filters, several picks in one field.
@MainActor
struct TrackerBatch2Tests {

    private func makeGame(_ categories: [[String: Any]], runFields: [[String: Any]]? = nil)
        throws -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Test Game", status: .playing)
        var root: [String: Any] = ["schemaVersion": 1, "categories": categories]
        if let runFields {
            root["runTemplate"] = ["fields": runFields, "outcomes": ["Won", "Died"]]
        }
        repo.applyGeneratedSchema(for: game, jsonData: try JSONSerialization.data(withJSONObject: root),
                                  mode: .replace)
        return (repo, game)
    }

    private func category(_ game: Game, _ id: String) throws -> TrackerCategoryDTO {
        try #require(TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData).first { $0.id == id })
    }

    private static let bosses: [String: Any] = [
        "id": "bosses", "name": "Bosses",
        "items": [["id": "b1", "name": "Hornet"], ["id": "b2", "name": "Radiance"]],
    ]
    private static let seeds: [String: Any] = [
        "id": "seeds", "name": "Korok Seeds",
        "items": [["id": "k", "name": "Korok Seeds", "countTarget": 900]],
    ]

    // MARK: 1. Per-list progress

    @Test("A list can stay out of the percentage, or give partial credit")
    func progressModes() throws {
        let (repo, game) = try makeGame([Self.bosses, Self.seeds])
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "b1", done: true)
        repo.setTrackerCount(pt, itemID: "k", count: 450, target: 900)
        // 1 of 3 items.
        #expect(abs(pt.progressPercent - 100.0 / 3) < 0.01)

        #expect(repo.setListRules(game, categoryID: "seeds", progress: .partial, carried: false, fromRuns: nil))
        #expect(abs(pt.progressPercent - 50) < 0.01, "1 + half of the seeds, of 3")

        #expect(repo.setListRules(game, categoryID: "seeds", progress: .excluded, carried: false, fromRuns: nil))
        #expect(abs(pt.progressPercent - 50) < 0.01, "1 of the 2 bosses")
        #expect(try category(game, "seeds").progress == .excluded)

        #expect(repo.setListRules(game, categoryID: "seeds", progress: .counts, carried: false, fromRuns: nil))
        let raw = try #require(try JSONSerialization.jsonObject(with: game.trackerSchema!.jsonData) as? [String: Any])
        let seeds = try #require((raw["categories"] as? [[String: Any]])?.first { $0["id"] as? String == "seeds" })
        #expect(seeds[TrackerSchemaJSON.progressKey] == nil, "the default isn't written")
    }

    @Test("Partial credit reads ranks too, and never goes past whole")
    func partialRanks() {
        let cat = TrackerCategoryDTO(
            id: "c", name: "Talents", categoryDescription: nil, kind: nil,
            items: [TrackerItemDTO(id: "t", name: "Talent", itemDescription: nil, location: nil,
                                   missable: false, hideUntilDiscovered: false, maxRank: 5,
                                   rankNames: nil, display: nil)],
            progress: .partial)
        let tally = TrackerProgress.tally(categories: [cat]) { _ in .init(completed: false, rank: 3) }
        #expect(tally.done == 0 && tally.total == 1)
        #expect(abs(tally.percent - 60) < 0.01)
        let over = TrackerProgress.tally(categories: [cat]) { _ in .init(completed: false, rank: 9) }
        #expect(over.fraction == 1)
    }

    // MARK: 3. Focus

    @Test("A playthrough's focus decides what counts, and the rest keep their ticks")
    func focus() throws {
        let (repo, game) = try makeGame([Self.bosses, Self.seeds])
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "b1", done: true)
        #expect(repo.focus(of: pt) == nil)

        repo.setFocus(["bosses"], on: pt)
        #expect(repo.focus(of: pt) == ["bosses"])
        #expect(abs(pt.progressPercent - 50) < 0.01)
        #expect(repo.trackerState(pt, itemID: "b1")?.completed == true)
        #expect(!repo.progressItemIDs(for: game).contains(TrackerSchemaJSON.focusItemID),
                "focus isn't progress a removal would warn about")

        // Another playthrough has its own focus.
        let other = Playthrough(name: "Any%")
        repo.context.insert(other)
        other.game = game
        #expect(repo.focus(of: other) == nil)

        repo.setFocus([], on: pt)
        #expect(repo.focus(of: pt) == nil)
        #expect(abs(pt.progressPercent - 100.0 / 3) < 0.01)
    }

    // MARK: 2. Across playthroughs

    @Test("A shared list's ticks live on the record and count on every playthrough")
    func carried() throws {
        let endings: [String: Any] = ["id": "endings", "name": "Endings",
                                      "items": [["id": "e1", "name": "Pacifist"], ["id": "e2", "name": "Genocide"]]]
        let (repo, game) = try makeGame([endings])
        let first = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(first, itemID: "e1", done: true)

        #expect(repo.setListRules(game, categoryID: "endings", progress: .counts, carried: true, fromRuns: nil))
        let record = try #require(repo.existingCarriedPlaythrough(for: game))
        #expect(repo.trackerState(record, itemID: "e1")?.completed == true, "what you'd seen moves to the record")
        #expect(game.activePlaythrough?.id == first.id, "the record is never the run you're on")

        let second = Playthrough(name: "Second run")
        repo.context.insert(second)
        second.game = game
        repo.setActivePlaythrough(second, for: game)
        let cat = try category(game, "endings")
        let target = repo.statePlaythrough(for: game, category: cat)
        #expect(target.id == record.id)
        repo.setTrackerItem(target, itemID: "e2", done: true)

        let seen = repo.stateMap(for: second, categories: [cat])
        #expect(seen["e1"]?.completed == true && seen["e2"]?.completed == true)
        #expect(second.progressPercent == 100)
        #expect(first.progressPercent == 100)
    }

    // MARK: 4. Attempts

    @Test("Winning with a weapon ticks it; a loss doesn't; an untick sticks until the next win")
    func ticksFromRuns() throws {
        let weapons: [String: Any] = ["id": "weapons", "name": "Weapons",
                                      "items": [["id": "w1", "name": "Stygian Blade"], ["id": "w2", "name": "Eternal Spear"]]]
        let (repo, game) = try makeGame([weapons], runFields: [
            ["id": "weapon", "label": "Weapon", "type": "select", "optionsFrom": "weapons"],
        ])
        let pt = repo.ensureDefaultPlaythrough(for: game)
        // A run from before the rule existed.
        repo.logRun(on: pt, fields: ["weapon": "Eternal Spear"], outcome: .success,
                    started: .now.addingTimeInterval(-7200), duration: 1200, notes: nil)
        #expect(repo.trackerState(pt, itemID: "w2")?.completed != true)

        #expect(repo.setListRules(game, categoryID: "weapons", progress: .counts, carried: false,
                                  fromRuns: .init(field: "weapon", winsOnly: true)))
        #expect(repo.trackerState(pt, itemID: "w2")?.completed == true, "past runs count once")

        let lost = repo.startRun(on: pt, fields: ["weapon": "stygian blade"])
        repo.endRun(lost, outcome: .failure, notes: nil)
        #expect(repo.trackerState(pt, itemID: "w1")?.completed != true)

        repo.setTrackerItem(pt, itemID: "w2", done: false)
        let other = repo.startRun(on: pt, fields: ["weapon": "Stygian Blade"])
        repo.endRun(other, outcome: .success, notes: nil)
        #expect(repo.trackerState(pt, itemID: "w1")?.completed == true, "case doesn't matter")
        #expect(repo.trackerState(pt, itemID: "w2")?.completed != true, "an untick stays")
        #expect(try category(game, "weapons").fromRuns == .init(field: "weapon", winsOnly: true))
    }

    @Test("Numbers and times: entry, storage and the best run")
    func bests() {
        #expect(RunFieldSupport.number(from: "1:23.45", time: true) == 83.45)
        #expect(RunFieldSupport.number(from: "1:02:03", time: true) == 3723)
        #expect(RunFieldSupport.number(from: "1,250", time: false) == 1250)
        #expect(RunFieldSupport.number(from: "abc", time: false) == nil)
        #expect(RunFieldSupport.timeText(83.45) == "1:23.45")
        #expect(RunFieldSupport.timeText(3723) == "1:02:03")

        let time = RunFieldDTO(id: "time", label: "Time", kind: "time", options: [], phase: "end", best: "low")
        let score = RunFieldDTO(id: "score", label: "Score", kind: "number", options: [], phase: "end", best: "high")
        let normalized = RunFieldSupport.normalized(["time": "1:30", "score": "oops", "weapon": "Bow"],
                                                    fields: [time, score])
        #expect(normalized == ["time": "90", "weapon": "Bow"])

        let now = Date.now
        let runs: [(fields: [String: String], outcome: RunOutcome, startedAt: Date)] = [
            (["time": "95", "score": "10"], .success, now.addingTimeInterval(-300)),
            (["time": "88", "score": "30"], .failure, now.addingTimeInterval(-200)),
            (["time": "90", "score": "20"], .success, now.addingTimeInterval(-100)),
            (["time": "70"], .inProgress, now),
        ]
        let fastest = RunFieldSupport.best(for: time, runs: runs)
        #expect(fastest?.value == 88 && fastest?.text == "1:28" && fastest?.setByLatest == false)
        #expect(RunFieldSupport.best(for: score, runs: runs)?.value == 30)
        let noDirection = RunFieldDTO(id: "time", label: "Time", kind: "time", options: [])
        #expect(RunFieldSupport.best(for: noDirection, runs: runs) == nil)
        #expect(!RunFieldSupport.isOptionBacked(score))
    }

    // MARK: 5. Run lists

    @Test("A run's list fills while it's live, keeps repeats, and loses one entry at a time")
    func runList() throws {
        let (repo, game) = try makeGame([Self.bosses], runFields: [
            ["id": "boons", "label": "Boons", "type": "list", "phase": "start"],
            ["id": "score", "label": "Score", "type": "number", "phase": "end", "best": "high"],
        ])
        let template = try #require(TrackerSchemaJSON.runTemplate(from: game.trackerSchema!.jsonData))
        #expect(template.fields.first?.isRunList == true)
        #expect(template.fields.first?.phase == "during", "a list is filled during the run")
        #expect(template.fields.last?.best == "high")

        let pt = repo.ensureDefaultPlaythrough(for: game)
        let run = repo.startRun(on: pt, fields: [:])
        repo.appendRunValue("Zeus", fieldID: "boons", to: run)
        repo.appendRunValue("Athena", fieldID: "boons", to: run)
        repo.appendRunValue("Zeus", fieldID: "boons", to: run)
        repo.appendRunValue("   ", fieldID: "boons", to: run)
        #expect(RunFieldSupport.entries(run.fieldsDict["boons"]) == ["Zeus", "Athena", "Zeus"])
        repo.removeRunValue(at: 0, fieldID: "boons", from: run)
        #expect(RunFieldSupport.entries(run.fieldsDict["boons"]) == ["Athena", "Zeus"])

        // The stats count each boon once per run.
        let stats = RunFieldSupport.stats(fields: [RunFieldDTO(id: "boons", label: "Boons", kind: "list",
                                                               options: ["Zeus", "Athena"])],
                                          runs: [(run.fieldsDict, true)])
        #expect(stats.first?.rows.count == 2)
    }

    @Test("Run fields save with their kinds and keep the outcomes")
    func runFieldsSave() throws {
        let (repo, game) = try makeGame([Self.bosses], runFields: [["id": "weapon", "label": "Weapon", "type": "text"]])
        let fields = [
            RunFieldDTO(id: "weapon", label: "Weapon", kind: "select", options: [], optionsFrom: "bosses"),
            RunFieldDTO(id: "time", label: "Time", kind: "time", options: [], phase: "end", best: "low"),
            RunFieldDTO(id: "jokers", label: "Jokers", kind: "list", options: ["Blueprint"], phase: "during"),
        ]
        #expect(repo.setRunFields(fields, for: game))
        let template = try #require(TrackerSchemaJSON.runTemplate(from: game.trackerSchema!.jsonData))
        #expect(template.fields == fields)
        #expect(template.outcomes.map(\.label) == ["Won", "Died"])
    }

    // MARK: 6. Life sims

    @Test("Season and weather columns become filters; All is no filter at all")
    func filtersFromSheets() throws {
        let table = """
        | Fish | Location | Season | Weather |
        |---|---|---|---|
        | Catfish | River | Spring, Fall | Rain |
        | Sardine | Ocean | Spring / Fall / Winter | Any |
        | Carp | Mountain Lake | All | Any |
        | Sturgeon | Mountain Lake | Summer / Winter | Any |
        """
        let result = TrackerListParser.parse(table)
        let items = try #require(result.categories.first?.items)
        #expect(items.first?.tags == ["Spring", "Fall", "Rain"])
        #expect(items.first?.location == "River", "a season column isn't read as a place")
        #expect(items[2].tags.isEmpty)
        let cats = TrackerSchemaJSON.categories(from: TrackerListParser.schemaData(from: result))
        #expect(cats.first?.items.first?.filters == ["Spring", "Fall", "Rain"])

        let all = try #require(cats.first?.items)
        #expect(TrackerSectionView.matching(tag: "winter", all).map(\.name) == ["Sardine", "Carp", "Sturgeon"])
        #expect(TrackerSectionView.matching(tag: "", all).count == 4)
    }

    @Test("Filters are their own key, edit in place, and survive a regeneration")
    func filtersSurvive() throws {
        let fish: [String: Any] = ["id": "fish", "name": "Fish",
                                   "items": [["id": "catfish", "name": "Catfish", "tags": ["dlc:none"]]]]
        let (repo, game) = try makeGame([fish])
        #expect(try category(game, "fish").items.first?.filters == [], "generated tags aren't filters")
        #expect(repo.setTrackerItemFilters(game, categoryID: "fish", itemID: "catfish",
                                           filters: ["Spring", " spring ", "Rain", ""]))
        #expect(try category(game, "fish").items.first?.filters == ["Spring", "Rain"])
        #expect(repo.setListRules(game, categoryID: "fish", progress: .excluded, carried: true, fromRuns: nil))

        let regenerated = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "fish", "name": "Fish", "items": [["id": "catfish", "name": "Catfish"]]]],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: regenerated, mode: .replace)
        let after = try category(game, "fish")
        #expect(after.items.first?.filters == ["Spring", "Rain"])
        #expect(after.progress == .excluded && after.carried)
    }

    // MARK: 7. Several picks

    @Test("A several-choices field keeps its cap, and its picks read back in order")
    func multiField() throws {
        let field = TrackerFieldDTO(id: "skills", name: "Skills", kind: .multi, options: ["Vantage", "Pass"], max: 2)
        let decoded = try #require(TrackerFieldDTO(json: field.json))
        #expect(decoded == field)
        #expect(TrackerFieldDTO(id: "c", name: "Class", kind: .choice, max: 3).json["max"] == nil,
                "only a several-choices field has a cap")
        #expect(TrackerFieldDTO.picks(in: "Vantage, Pass,  ") == ["Vantage", "Pass"])
        #expect(TrackerFieldDTO.Kind.multi.hasOptions)
    }
}

/// Planning by shape, a new run's focus, suggested run fields (09-17).
@MainActor
struct TrackerShapeTests {
    @Test("Shapes are offered by genre, most likely first")
    func offered() {
        #expect(TrackerShape.offered(genres: ["Role-playing (RPG)", "Tactical"], themes: [], hasRuns: false)
                == [.story, .checklist, .roster, .completionist])
        #expect(TrackerShape.offered(genres: ["Simulator", "Indie"], themes: ["Sandbox"], hasRuns: false).first == .seasonal)
        #expect(TrackerShape.offered(genres: ["Racing", "Simulator"], themes: [], hasRuns: false).first == .story,
                "a racing sim isn't a life sim")
        #expect(TrackerShape.offered(genres: ["Role-playing (RPG)"], themes: [], hasRuns: true).first == .unlocks,
                "a game you log runs for is played for its runs")
        #expect(TrackerShape.offered(genres: ["Platform"], themes: [], hasRuns: false).contains(.collectibles))
    }

    @Test("A plan carries the chosen shapes, and none when the planner decides")
    func planBody() {
        let body = AITrackerService.planBody(gameName: "Fire Emblem Engage", igdbID: 7, shapes: [.story, .roster])
        #expect(body["mode"] as? String == "plan")
        #expect(body["shapes"] as? [String] == ["story", "roster"])
        #expect(AITrackerService.planBody(gameName: "X", igdbID: nil, shapes: [])["shapes"] == nil)
    }

    @Test("Suggested run fields read like a tracker's own")
    func suggestedRunFields() {
        let fields = AITrackerService.runFields(from: ["runFields": ["fields": [
            ["id": "weapon", "label": "Weapon", "type": "select", "optionsFrom": "weapons"],
            ["id": "boons", "label": "Boons", "type": "list", "options": ["Zeus"]],
            ["id": "heat", "label": "Heat", "type": "number", "phase": "end", "best": "high"],
            ["label": "No id", "type": "text"],
        ]]])
        #expect(fields.map(\.id) == ["weapon", "boons", "heat"])
        #expect(fields[1].isRunList && fields[1].phase == "during")
        #expect(fields[2].isEndPhase && fields[2].best == "high")
        #expect(AITrackerService.runFields(from: [:]).isEmpty)
    }

    @Test("Lists planned for a new run become what it chases")
    func planningFocusesTheRun() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Engage", status: .playing)
        #expect(repo.addPlannedCategory(to: game, named: "Chapters", plannedCount: 26))
        let second = repo.addPlaythrough(to: game, named: "Roster run")
        #expect(repo.focus(of: second) == nil)
        // What the store does once a plan lands.
        let before = Set(repo.trackerCategories(for: game).map(\.id))
        #expect(repo.addPlannedCategory(to: game, named: "Units", plannedCount: 40, kind: "roster"))
        let added = Set(repo.trackerCategories(for: game).map(\.id)).subtracting(before)
        repo.setFocus((repo.focus(of: second) ?? []).union(added), on: second)
        let units = try #require(repo.trackerCategories(for: game).first { $0.name == "Units" })
        #expect(repo.focus(of: second) == [units.id])
    }
}
