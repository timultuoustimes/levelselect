import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Regressions from the external review of 2026-08-17.
///
/// Every one of these had a passing test beside it while the bug was live. The
/// common shape: the existing test used the happy-path input the code was
/// written for — one playthrough, distinct ids, no name collisions — so it
/// proved the intention rather than the behavior. These use the boundary the
/// code actually accepts.
@MainActor
struct MergeRegressionTests {

    private func game(named name: String) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    private func category(id: String, name: String, items: [(String, String)],
                          locked: Bool = false) -> [String: Any] {
        var cat: [String: Any] = ["id": id, "name": name, "type": "checklist",
                                  "items": items.map { ["id": $0.0, "name": $0.1] }]
        if locked { cat["locked"] = true }
        return cat
    }

    // MARK: 1 — replacement must migrate EVERY playthrough

    /// The schema belongs to the game, so a regeneration affects all of its
    /// playthroughs. Migrating only the active one left every other playthrough
    /// pointing at item ids that no longer existed — progress that looked reset
    /// with no warning and no rescue.
    @Test func replaceMigratesProgressInEveryPlaythrough() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .addAll)

        let first = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(first, itemID: "hornet", done: true)

        // A second playthrough — Steel Soul, NG+, whatever — with its own tick.
        let second = repo.addPlaythrough(to: game, named: "Steel Soul")
        repo.setTrackerItem(second, itemID: "hornet", done: true)
        // `addPlaythrough` switches to it, so `second` is now the active one.

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("boss-hornet", "Hornet")]),
        ]), mode: .replace)

        // BOTH records move, not just the active playthrough's.
        #expect(outcome.migrated == 2)
        #expect(repo.trackerState(second, itemID: "boss-hornet")?.completed == true)
        #expect(repo.trackerState(first, itemID: "boss-hornet")?.completed == true)
        #expect(repo.trackerState(first, itemID: "hornet") == nil)
    }

    /// Loss has to be reported from every playthrough too, or the rescue offer
    /// silently under-counts what's about to go.
    @Test func lostProgressCountsEveryPlaythrough() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses",
                     items: [("hornet", "Hornet"), ("nosk", "Nosk")]),
        ]), mode: .addAll)

        let first = repo.ensureDefaultPlaythrough(for: game)
        let second = repo.addPlaythrough(to: game, named: "Steel Soul")
        // Only the INACTIVE playthrough has progress on the item about to go.
        repo.setTrackerItem(first, itemID: "nosk", done: true)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .replace)

        #expect(outcome.lostProgress.map(\.id) == ["nosk"])
        _ = second
    }

    @Test func rescueMovesTheRecordInEveryPlaythrough() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("nosk", "Nosk")]),
        ]), mode: .addAll)
        let first = repo.ensureDefaultPlaythrough(for: game)
        let second = repo.addPlaythrough(to: game, named: "Steel Soul")
        repo.setTrackerItem(first, itemID: "nosk", done: true)
        repo.setTrackerItem(second, itemID: "nosk", done: true)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .replace)
        #expect(repo.rescueAsPersonalGoals(outcome.lostProgress, for: game) == 1)

        #expect(repo.trackerState(first, itemID: "goal-rescued-nosk")?.completed == true)
        #expect(repo.trackerState(second, itemID: "goal-rescued-nosk")?.completed == true)
    }

    // MARK: 2 — a locked category must survive an id collision

    /// Generators reuse common slugs. If one returns a category called
    /// `achievements` and the user has a LOCKED imported category with the same
    /// id, the locked one used to be dropped — and because the diff filters
    /// locked ids out of the incoming side, the review never mentioned it.
    @Test func lockedCategorySurvivesAnIncomingIDCollision() {
        let current = schema([
            category(id: "achievements", name: "Achievements",
                     items: [("mine-1", "My pasted item"), ("mine-2", "Another")],
                     locked: true),
        ])
        let incoming = schema([
            category(id: "achievements", name: "Achievements",
                     items: [("gen-1", "Generated thing")]),
        ])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cat = TrackerSchemaJSON.categories(from: out).first { $0.id == "achievements" }

        #expect(cat?.items.map(\.name) == ["My pasted item", "Another"])
        #expect(TrackerSchemaJSON.lockedCategoryIDs(in: out) == ["achievements"])
    }

    @Test func personalGoalsAlsoSurviveAnIDCollision() {
        let goals: [String: Any] = ["id": TrackerSchemaJSON.personalGoalsID,
                                    "name": "Personal Goals",
                                    "items": [["id": "goal-1", "name": "Beat it hitless"]]]
        let current = schema([goals])
        let incoming = schema([["id": TrackerSchemaJSON.personalGoalsID,
                                "name": "Personal Goals",
                                "items": [["id": "bogus", "name": "Invented goal"]]]])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cat = TrackerSchemaJSON.categories(from: out)
            .first { $0.id == TrackerSchemaJSON.personalGoalsID }

        #expect(cat?.items.map(\.name) == ["Beat it hitless"])
    }

    // MARK: 3 — a note must not travel to another category's item

    /// Two categories each containing an item called "Complete" is ordinary.
    /// A single global lookup gave one category's private note to the other
    /// category's item — the note wasn't lost, it was shown in the wrong place,
    /// which is worse.
    @Test func notesStayInTheirOwnCategory() throws {
        var current = schema([
            category(id: "story", name: "Story", items: [("story-done", "Complete")]),
            category(id: "extras", name: "Extras", items: [("extras-done", "Complete")]),
        ])
        current = try #require(TrackerSchemaJSON.editingItem(
            categoryID: "story", itemID: "story-done",
            note: "Only true of the story one", in: current))

        // Regeneration re-slugs both ids; the names still collide.
        let incoming = schema([
            category(id: "story", name: "Story", items: [("s1", "Complete")]),
            category(id: "extras", name: "Extras", items: [("e1", "Complete")]),
        ])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cats = TrackerSchemaJSON.categories(from: out)

        #expect(cats.first { $0.id == "story" }?.items.first?.note == "Only true of the story one")
        #expect(cats.first { $0.id == "extras" }?.items.first?.note == nil)
    }

    // MARK: 5 — a resumed stale session must not bank its paused time

    /// Start at 1pm, play an hour, pause for four, resume, forget to stop.
    /// Ending it at 6pm used to write `stop - start` = five hours, silently
    /// banking the four paused hours as playtime — which then synced, showed
    /// up in Stats and went into exports with nothing to suggest it was wrong.
    @Test func endingAResumedStaleSessionExcludesPausedTime() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let onePM = Date(timeIntervalSince1970: 1_700_000_000)
        let session = repo.startSession(on: pt, at: onePM)
        repo.pauseSession(session, at: onePM.addingTimeInterval(3600))        // 1h played
        repo.resumeSession(session, at: onePM.addingTimeInterval(3600 * 5))   // 4h paused

        // Forgot to stop; ends it at 6pm — one more hour of actual play.
        repo.endStaleSession(session, stoppedAt: onePM.addingTimeInterval(3600 * 6))

        #expect(session.elapsed() == 3600 * 2)   // two hours, not five
        #expect(pt.totalPlaytime() == 3600 * 2)
    }

    /// A paused session has no running segment, so ending it late must not add
    /// anything at all.
    @Test func endingAPausedStaleSessionAddsNothing() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = repo.startSession(on: pt, at: start)
        repo.pauseSession(session, at: start.addingTimeInterval(1800))   // 30 min

        repo.endStaleSession(session, stoppedAt: start.addingTimeInterval(3600 * 8))

        #expect(session.elapsed() == 1800)
    }

    // MARK: 4 — duplicate ids in one payload must not both land

    /// AI output is untrusted input, not a valid primary-key set. The
    /// seen-set was computed once before appending, so a payload containing the
    /// same id twice appended both — and since progress is keyed by item id,
    /// the two rows would then share one checkmark.
    @Test func duplicateIDsInOnePayloadAreNotBothAdded() {
        let current = schema([category(id: "bosses", name: "Bosses", items: [])])
        let incoming = schema([
            category(id: "bosses", name: "Bosses",
                     items: [("dupe", "First"), ("dupe", "Second")]),
        ])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let ids = TrackerSchemaJSON.categories(from: out).flatMap(\.items).map(\.id)

        #expect(ids.count == Set(ids).count)
        #expect(ids.filter { $0 == "dupe" }.count == 1)
    }

    /// Names guard against RE-IMPORT, not against each other. An incoming
    /// item whose name matches something already stored is the same item
    /// coming back under a fresh id and must be skipped — but two same-named
    /// items arriving together under distinct ids are legitimate data (a
    /// pasted list has "Chest" at three locations), and round 3 caught the
    /// growing name set silently swallowing all but the first.
    @Test func nameGuardBlocksReimportButNotDistinctSameNamedArrivals() {
        // Re-import shape: "False Knight" already exists; it returns re-slugged.
        let current = schema([category(id: "bosses", name: "Bosses",
                                       items: [("false-knight", "False Knight")])])
        let reimport = schema([
            category(id: "bosses", name: "Bosses", items: [("b", "false-knight")]),
        ])
        let afterReimport = TrackerMerge.merged(current: current, incoming: reimport, mode: .addAll)
        #expect(TrackerSchemaJSON.categories(from: afterReimport).flatMap(\.items).count == 1)

        // Legitimate shape: three distinct chests sharing a display name.
        let empty = schema([category(id: "chests", name: "Chests", items: [])])
        let chests = schema([
            category(id: "chests", name: "Chests",
                     items: [("c1", "Chest"), ("c2", "Chest"), ("c3", "Chest")]),
        ])
        let afterChests = TrackerMerge.merged(current: empty, incoming: chests, mode: .addAll)
        #expect(TrackerSchemaJSON.categories(from: afterChests).flatMap(\.items).count == 3)
    }
}

/// Round 2, finding 3: the seen-set dedup covered only ONE of the four ingest
/// paths — appending into an already-matched category. First generation,
/// Replace, and a wholly new Add category all still accepted duplicate
/// ids/names raw, and duplicate category ids were accepted everywhere. These
/// exercise each path with the duplicate payload the generator is allowed to
/// return.
@MainActor
struct IngestBoundaryTests {

    private func game(named name: String) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    private func category(id: String, name: String, items: [(String, String)],
                          locked: Bool = false) -> [String: Any] {
        var cat: [String: Any] = ["id": id, "name": name, "type": "checklist",
                                  "items": items.map { ["id": $0.0, "name": $0.1] }]
        if locked { cat["locked"] = true }
        return cat
    }

    private func installedItemIDs(_ game: Game) -> [String] {
        TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
            .flatMap(\.items).map(\.id)
    }

    /// FIRST generation: no existing schema, payload installed directly.
    @Test func firstGenerationRejectsDuplicateIDs() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses",
                     items: [("hornet", "Hornet"), ("hornet", "Hornet (Kingdom's Edge)")]),
        ]), mode: .addAll)

        let ids = installedItemIDs(game)
        #expect(ids.filter { $0 == "hornet" }.count == 1)
    }

    /// REPLACE adopts incoming content — it must not adopt duplicate IDs,
    /// and must NOT invent identity from display names: distinct-id items
    /// sharing a name are real data and all survive.
    @Test func replaceRejectsDuplicateIDsButKeepsDistinctSameNamedItems() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses",
                     items: [("h1", "Hornet"), ("h2", "Hornet"), ("h1", "Hornet Again")]),
        ]), mode: .replace)

        let ids = installedItemIDs(game)
        #expect(ids.count == Set(ids).count)      // duplicate id dropped
        #expect(ids.sorted() == ["h1", "h2"])     // both same-named items kept
    }

    /// A wholly NEW category in Add mode was copied wholesale.
    @Test func addNewCategoryRejectsDuplicateIDs() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
        ]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "charms", name: "Charms",
                     items: [("wayward", "Wayward Compass"), ("wayward", "Wayward Compass")]),
        ]), mode: .addAll)

        let ids = installedItemIDs(game)
        #expect(ids.filter { $0 == "wayward" }.count == 1)
    }

    /// Duplicate CATEGORY ids poison diff matching and state keying; the two
    /// occurrences fold into one category, their items deduped.
    @Test func duplicateCategoryIDsFoldIntoOne() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("hornet", "Hornet")]),
            category(id: "bosses", name: "Bosses (again)",
                     items: [("hornet", "Hornet"), ("grimm", "Grimm")]),
        ]), mode: .addAll)

        let cats = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
        #expect(cats.count == 1)
        #expect(cats.first?.items.map(\.id).sorted() == ["grimm", "hornet"])
    }

    /// Round 1 finding 4's unfinished half: an incoming payload carrying the
    /// locked category's id TWICE used to bring the "replaced" generated
    /// category straight back as a duplicate.
    @Test func lockedCategorySurvivesDoubledIncomingCollision() {
        let old = schema([
            category(id: "achievements", name: "My Pasted List",
                     items: [("mine", "My item")], locked: true),
        ])
        let incoming = schema([
            category(id: "achievements", name: "Generated A", items: [("a", "A")]),
            category(id: "achievements", name: "Generated B", items: [("b", "B")]),
        ])
        let merged = TrackerSchemaJSON.mergingPersonalGoals(from: old, into: incoming)
        let cats = TrackerSchemaJSON.categories(from: merged)
        let matching = cats.filter { $0.id == "achievements" }
        #expect(matching.count == 1)
        #expect(matching.first?.name == "My Pasted List")
        #expect(matching.first?.items.map(\.id) == ["mine"])
    }

    /// Round 3, finding 1: the paste parser's own regression fixture — three
    /// distinct chests sharing a display name — must survive the FULL
    /// preview-to-apply path. The sanitizer used to delete two of them after
    /// the preview had shown all three.
    @Test func pastedSameNamedItemsSurviveFromPreviewToInstall() throws {
        let (repo, game) = self.game(named: "Ossex")
        // Explicit location headings force three items literally named
        // "Chest" — the same-name shape the parser's fixtures treat as valid.
        let parsed = TrackerListParser.parse("""
        ## Chests
        ### Ossex
        - Chest
        ### Bone Beach
        - Chest
        ### Sandfalls
        - Chest
        """)
        let previewed = parsed.categories.flatMap(\.items)
        #expect(previewed.count == 3)                            // what preview shows
        #expect(previewed.filter { $0.name == "Chest" }.count == 3)

        let incoming = TrackerListParser.schemaData(from: parsed)
        repo.applyGeneratedSchema(for: game, jsonData: incoming, mode: .addAll)

        let installed = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
            .flatMap(\.items)
        // Install keeps EXACTLY what the preview promised — same items,
        // same ids, nothing silently dropped.
        #expect(installed.map(\.id).sorted() == previewed.map(\.id).sorted())
        #expect(installed.map(\.name) == previewed.map(\.name))
    }

    /// Same principle one level up: two distinct categories that happen to
    /// share a display name are not the same category.
    @Test func distinctSameNamedCategoriesBothSurviveIngest() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses-act1", name: "Bosses", items: [("hornet", "Hornet")]),
            category(id: "bosses-act2", name: "Bosses", items: [("grimm", "Grimm")]),
        ]), mode: .addAll)

        let cats = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
        #expect(cats.count == 2)
        #expect(Set(cats.map(\.id)) == ["bosses-act1", "bosses-act2"])
    }

    /// Two incoming categories with the same normalized name must not both
    /// claim one current category in the diff.
    @Test func diffNeverMatchesOneCurrentCategoryTwice() {
        let current = schema([category(id: "bosses", name: "Bosses",
                                       items: [("hornet", "Hornet")])])
        let incoming = schema([
            category(id: "b1", name: "Bosses", items: [("hornet", "Hornet")]),
            category(id: "b2", name: "bosses!", items: [("grimm", "Grimm")]),
        ])
        // Bypass sanitation deliberately — the diff engine itself must hold.
        let diff = TrackerMerge.diff(current: current, incoming: incoming)
        let matchedToCurrent = diff.categories.filter { $0.id == "bosses" }
        #expect(matchedToCurrent.count == 1)
    }

    /// Round 3, finding 6: the id branch had no consumed check, so duplicate
    /// incoming IDs (unsanitized input — the engine itself must hold) both
    /// claimed the same current category.
    @Test func diffNeverMatchesOneCurrentCategoryTwiceByID() {
        let current = schema([category(id: "bosses", name: "Bosses",
                                       items: [("hornet", "Hornet")])])
        let incoming = schema([
            category(id: "bosses", name: "Bosses A", items: [("hornet", "Hornet")]),
            category(id: "bosses", name: "Bosses B", items: [("grimm", "Grimm")]),
        ])
        let diff = TrackerMerge.diff(current: current, incoming: incoming)
        #expect(diff.categories.filter { !$0.isNewCategory }.count == 1)
    }

    /// And an exact id claim must not be stolen by a name match that happens
    /// to run first — the result must not depend on incoming order.
    @Test func nameMatchCannotStealACategoryAnIDMatchWillClaim() {
        let current = schema([category(id: "bosses", name: "Bosses",
                                       items: [("hornet", "Hornet")])])
        // The name-matcher ("Bosses", id b1) comes FIRST; the true id owner
        // ("bosses", renamed) comes second.
        let incoming = schema([
            category(id: "b1", name: "Bosses", items: [("x", "X")]),
            category(id: "bosses", name: "Renamed", items: [("hornet", "Hornet")]),
        ])
        let diff = TrackerMerge.diff(current: current, incoming: incoming)
        let matched = diff.categories.filter { !$0.isNewCategory }
        #expect(matched.count == 1)
        // The current category went to its id owner: "hornet" is unchanged
        // there, not reported as removed.
        #expect(matched.first?.unchangedCount == 1)
        #expect(matched.first?.removed.isEmpty == true)
    }

    /// Round 3, finding 6: folding two preserved same-id categories
    /// concatenated their item arrays raw, reintroducing duplicate item ids
    /// after the incoming payload had been sanitized.
    @Test func preservedCategoryFoldDedupsItemIDs() {
        let old = schema([
            category(id: "achievements", name: "Mine", items: [("mine", "My item")], locked: true),
            category(id: "achievements", name: "Mine too",
                     items: [("mine", "My item again"), ("extra", "Extra")], locked: true),
        ])
        let merged = TrackerSchemaJSON.mergingPersonalGoals(
            from: old, into: TrackerSchemaJSON.emptySchema())
        let cats = TrackerSchemaJSON.categories(from: merged)
        #expect(cats.count == 1)
        #expect(cats.first?.items.map(\.id) == ["mine", "extra"])
    }

    // MARK: An imported RetroAchievements set is not regenerable content

    private func raCategory(gameID: Int, items: [(String, String)]) -> [String: Any] {
        ["id": "retroachievements", "name": "Achievements", "type": "checklist",
         "raGameID": gameID, "items": items.map { ["id": $0.0, "name": $0.1] }]
    }

    /// A full Replace preserved only Personal Goals and locked categories, and
    /// the RA importer sets neither — so regenerating a game that had an
    /// imported set deleted the real, authored achievement list, along with the
    /// `raGameID` stamp that a later sync would have needed to restore it.
    @Test func replacePreservesImportedAchievementSet() {
        let (repo, game) = self.game(named: "Super Metroid")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            raCategory(gameID: 236, items: [("ra-1", "Bomb Torizo"), ("ra-2", "Spore Spawn")]),
        ]), mode: .addAll)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("ridley", "Ridley")]),
        ]), mode: .replace)

        let cats = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
        let ra = cats.first { $0.id == "retroachievements" }
        #expect(ra?.items.map(\.id) == ["ra-1", "ra-2"])
        // The generated content still installs alongside it.
        #expect(cats.contains { $0.id == "bosses" })
        // The sync link survives, or the set could not be refreshed later.
        #expect(TrackerSchemaJSON.retroAchievementsGameID(in: game.trackerSchema!.jsonData) == 236)
        // And the summary must not claim a deletion that did not happen.
        #expect(outcome.removed == 0)
    }

    /// Progress on imported achievements survives that same replace. Unlocks
    /// come from the RA account, so reporting them as lost would offer to
    /// rescue items that were never in danger.
    @Test func replaceKeepsProgressOnImportedAchievements() {
        let (repo, game) = self.game(named: "Super Metroid")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            raCategory(gameID: 236, items: [("ra-1", "Bomb Torizo")]),
        ]), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "ra-1", done: true)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category(id: "bosses", name: "Bosses", items: [("ridley", "Ridley")]),
        ]), mode: .replace)

        #expect(outcome.lostProgress.isEmpty)
        #expect(repo.trackerState(pt, itemID: "ra-1")?.completed == true)
    }

    /// The adversarial half, and the reason this is not done by marking the
    /// category `locked`: RA's own refresh is a category-scoped replace of
    /// "retroachievements", and `replacingCategories` skips locked ids. A guard
    /// that protected the set by locking it would have protected it from the
    /// one operation that is meant to update it — retired achievements would
    /// sit in the list forever and new ones would never arrive.
    @Test func reimportStillReplacesImportedAchievementSet() {
        let (repo, game) = self.game(named: "Super Metroid")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            raCategory(gameID: 236, items: [("ra-1", "Bomb Torizo"), ("ra-retired", "Retired")]),
        ]), mode: .addAll)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            raCategory(gameID: 236, items: [("ra-1", "Bomb Torizo"), ("ra-3", "Kraid")]),
        ]), mode: .replaceCategories(ids: ["retroachievements"]))

        let ra = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
            .first { $0.id == "retroachievements" }
        #expect(ra?.items.map(\.id) == ["ra-1", "ra-3"])
        // A refresh that changed the set must still say so.
        #expect(outcome.added == 1)
        #expect(outcome.removed == 1)
    }
}
