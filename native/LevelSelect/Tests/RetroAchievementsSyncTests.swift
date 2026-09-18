import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Folding a RetroAchievements account's unlocks into a tracker.
///
/// The rule the whole feature rests on: **union, never subtraction**. RA is
/// authoritative for "you earned this" and nothing else. It has no idea you
/// played the cartridge on real hardware last week, so an unlock it doesn't
/// know about is not evidence of anything — and un-ticking on that basis would
/// be the app telling someone they didn't do a thing they did.
///
/// That matters more than it sounds, because a sync is repeatable: anything
/// this can get wrong, it gets wrong again every time it runs.
@MainActor
struct RetroAchievementsSyncTests {

    private func setup() -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Castlevania", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)
        return (repo, game)
    }

    /// Shaped like what the proxy returns: an RA category carrying the game id.
    private var schema: Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "sources": [["type": "retroachievements",
                         "url": "https://retroachievements.org/game/1462"]],
            "categories": [[
                "id": "retroachievements", "name": "Achievements",
                "type": "checklist", "raGameID": 1462,
                "items": [
                    ["id": "ra-1", "name": "Vampire Killer", "metadata": ["points": 5, "raID": 1]],
                    ["id": "ra-2", "name": "Stalker", "metadata": ["points": 5, "raID": 2]],
                    ["id": "ra-3", "name": "Wicked Child", "metadata": ["points": 5, "raID": 3]],
                ],
            ]],
        ])
    }

    private func unlock(_ id: String, hardcore: Bool = true, points: Int = 5)
        -> RetroAchievementsService.Unlock {
        .init(itemID: id, hardcore: hardcore, earnedAt: .now, points: points)
    }

    // MARK: The dedicated playthrough

    /// Separate from your runs, because RA has no idea a run happened.
    @Test func syncingCreatesADedicatedPlaythroughOnce() {
        let (repo, game) = setup()
        let mine = repo.ensureDefaultPlaythrough(for: game)

        let ra = repo.raPlaythrough(for: game)
        #expect(ra.id != mine.id)
        #expect(ra.name == Repository.raPlaythroughName)

        // Called again — and again on the other device — it finds the same one.
        #expect(repo.raPlaythrough(for: game).id == ra.id)
        #expect(game.livePlaythroughs.count == 2)
    }

    /// It must not hijack the timer's target. You start a session against the
    /// run you're on, not against a record of your account.
    @Test func theRAPlaythroughDoesNotBecomeCurrent() {
        let (repo, game) = setup()
        let mine = repo.ensureDefaultPlaythrough(for: game)

        _ = repo.raPlaythrough(for: game)

        #expect(game.currentPlaythroughID == mine.id)
        #expect(game.activePlaythrough?.id == mine.id)
    }

    // MARK: Union, never subtraction

    @Test func unlocksTickTheMatchingItems() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        let outcome = repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-3")], to: ra, in: game)

        #expect(outcome.newlyTicked == 2)
        #expect(repo.trackerState(ra, itemID: "ra-1")?.completed == true)
        #expect(repo.trackerState(ra, itemID: "ra-2")?.completed != true)
        #expect(repo.trackerState(ra, itemID: "ra-3")?.completed == true)
    }

    /// The load-bearing one. A tick RA doesn't know about — earned on original
    /// hardware — survives every future sync.
    @Test func aTickRADoesNotKnowAboutIsNeverRemoved() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)
        repo.setTrackerItem(ra, itemID: "ra-2", done: true)

        // RA reports only ra-1. ra-2 is absent from its answer entirely.
        repo.applyRAUnlocks([unlock("ra-1")], to: ra, in: game)

        #expect(repo.trackerState(ra, itemID: "ra-2")?.completed == true)
        #expect(repo.trackerState(ra, itemID: "ra-1")?.completed == true)
    }

    /// Repeatable: running it twice changes nothing the second time, which is
    /// what makes it safe to run on every visit.
    @Test func syncingTwiceIsNotADoubleCount() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        let first = repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-2")], to: ra, in: game)
        let second = repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-2")], to: ra, in: game)

        #expect(first.newlyTicked == 2)
        #expect(second.newlyTicked == 0)
        #expect(second.alreadyTicked == 2)
    }

    /// Your own playthrough is untouched. Someone replaying Super Metroid has
    /// a fresh run, and an account record that says they finished it in 2019 —
    /// two facts, kept apart.
    @Test func yourOwnPlaythroughIsNotTickedBySync() {
        let (repo, game) = setup()
        let mine = repo.ensureDefaultPlaythrough(for: game)
        let ra = repo.raPlaythrough(for: game)

        repo.applyRAUnlocks([unlock("ra-1"), unlock("ra-2"), unlock("ra-3")], to: ra, in: game)

        #expect(repo.trackerState(mine, itemID: "ra-1")?.completed != true)
        #expect(mine.progressPercent == 0)
    }

    /// Softcore counts. Filtering it out would be refusing to record something
    /// that happened.
    @Test func aSoftcoreUnlockStillCounts() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        repo.applyRAUnlocks([unlock("ra-1", hardcore: false)], to: ra, in: game)

        #expect(repo.trackerState(ra, itemID: "ra-1")?.completed == true)
    }

    /// An unlock for an achievement this tracker doesn't list means the set was
    /// revised after import. Counted and reported, so the app can suggest
    /// re-importing rather than dropping it in silence.
    @Test func anUnlockTheTrackerHasNeverHeardOfIsReportedNotSwallowed() {
        let (repo, game) = setup()
        let ra = repo.raPlaythrough(for: game)

        let outcome = repo.applyRAUnlocks(
            [unlock("ra-1"), unlock("ra-999")], to: ra, in: game)

        #expect(outcome.newlyTicked == 1)
        #expect(outcome.unknownToTracker == 1)
        #expect(repo.trackerState(ra, itemID: "ra-999") == nil)
    }

    // MARK: Points

    /// The importer has written `metadata.points` since the first version and
    /// nothing read it, so a 635-point set reported no points at all. Parsed
    /// off the blob, no schema version involved.
    @Test func pointsAreReadFromItemMetadata() {
        let (repo, game) = setup()
        let items = repo.trackerCategories(for: game).flatMap(\.items)

        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.points == 5 })
        #expect(items.compactMap(\.points).reduce(0, +) == 15)
    }

    /// A tracker with no notion of points reports none, rather than zero —
    /// "0 pts" on a generated tracker is noise pretending to be information.
    @Test func aTrackerWithoutPointsHasNoneRatherThanZero() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [[
                "id": "bosses", "name": "Bosses", "type": "checklist",
                "items": [["id": "hornet", "name": "Hornet"]],
            ]]]), mode: .addAll)

        let items = repo.trackerCategories(for: game).flatMap(\.items)
        #expect(items.first?.points == nil)
        #expect(items.compactMap(\.points).isEmpty)
    }

    /// The name the session controls check against has to be the one the
    /// repository actually creates, or the timer reappears on the record.
    @Test func theRecordPlaythroughIsNamedWhatTheUICheckExpects() {
        let (repo, game) = setup()
        #expect(repo.raPlaythrough(for: game).name == Repository.raPlaythroughName)
        #expect(Repository.raPlaythroughName == "RetroAchievements")
    }

    // MARK: Finding the game again

    /// Sync looks the RA game up from the tracker itself. Losing that id
    /// silently would leave a set that can never be refreshed.
    @Test func theRAGameIDSurvivesImportIntoAnExistingTracker() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Castlevania", status: .playing)

        // A generated tracker first — so the RA import merges into a root
        // whose `sources` will never mention RetroAchievements.
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [[
                "id": "stages", "name": "Stages", "type": "checklist",
                "items": [["id": "s1", "name": "Stage 1"]],
            ]]]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)

        #expect(TrackerSchemaJSON.retroAchievementsGameID(
            in: game.trackerSchema!.jsonData) == 1462)
    }

    @Test func aTrackerWithNoRAImportHasNoGameID() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [[
                "id": "bosses", "name": "Bosses", "type": "checklist",
                "items": [["id": "hornet", "name": "Hornet"]],
            ]]]), mode: .addAll)

        #expect(TrackerSchemaJSON.retroAchievementsGameID(
            in: game.trackerSchema!.jsonData) == nil)
    }

    // MARK: Which games are offered the import

    /// The console vocabulary is whatever IGDB or the user typed, so the match
    /// has to survive all three ways of naming the same machine.
    @Test func offersImportForCoveredConsoles() {
        #expect(RetroAchievementsService.mayCover(platforms: ["SNES"], ownership: []))
        #expect(RetroAchievementsService.mayCover(platforms: ["Super Nintendo"], ownership: []))
        #expect(RetroAchievementsService.mayCover(
            platforms: ["Super Nintendo Entertainment System"], ownership: []))
        #expect(RetroAchievementsService.mayCover(platforms: ["Sega Genesis"], ownership: []))
        #expect(RetroAchievementsService.mayCover(platforms: ["Game Boy Advance"], ownership: []))
    }

    /// The library stores what the user OWNS it on, not what the game was
    /// released for — so a Genesis game played through an emulator front-end
    /// records "Recalbox" and nothing else. Checking console names alone hid
    /// RetroAchievements from exactly the library it serves best, since an
    /// emulator is also what earns the unlocks in the first place.
    @Test func offersImportForEmulatedGames() {
        #expect(RetroAchievementsService.mayCover(platforms: ["Recalbox"], ownership: []))
        #expect(RetroAchievementsService.mayCover(platforms: ["RetroPie"], ownership: []))
        // Ownership answers it even when the platform name gives nothing away.
        #expect(RetroAchievementsService.mayCover(
            platforms: ["Some Handheld I Built"], ownership: [Ownership.emulated.rawValue]))
    }

    /// "PlayStation" is a prefix of every Sony console, and RA stops at
    /// PS2/PSP — modern PlayStation achievements are trophies, which are
    /// Sony's own system. A naive contains() would offer the import on a PS5
    /// game and could only ever disappoint.
    @Test func doesNotOfferImportForModernPlatforms() {
        #expect(!RetroAchievementsService.mayCover(platforms: ["PlayStation 5"], ownership: []))
        #expect(!RetroAchievementsService.mayCover(platforms: ["PlayStation 4"], ownership: []))
        #expect(!RetroAchievementsService.mayCover(platforms: ["PlayStation Vita"], ownership: []))
        #expect(!RetroAchievementsService.mayCover(
            platforms: ["PC (Microsoft Windows)"], ownership: [Ownership.digital.rawValue]))
        #expect(!RetroAchievementsService.mayCover(platforms: [], ownership: []))
        // The ones RA does cover still pass, or the exclusion went too far.
        #expect(RetroAchievementsService.mayCover(platforms: ["PlayStation 2"], ownership: []))
        #expect(RetroAchievementsService.mayCover(platforms: ["PlayStation"], ownership: []))
    }

    // MARK: Telling an authored list from a written-from-a-guide one

    /// An imported RetroAchievements set and a GENERATED "Achievements"
    /// category are indistinguishable once installed — same rows, same ticks.
    /// The plan step really does propose "Achievements" for modern games
    /// (verified against the live function for Cyberpunk 2077 and Hades), so
    /// someone could track a guessed list for weeks believing it mirrored
    /// their real account. Only the imported one carries the stamp.
    @Test func onlyRecordedSourcesAreLabelled() {
        let imported = TrackerSchemaJSON.categories(from: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [
                ["id": "retroachievements", "name": "Achievements", "type": "checklist",
                 "raGameID": 236,
                 "items": [["id": "ra-1", "name": "Bomb Torizo"]]],
            ]]))
        #expect(imported.first?.provenance == "RetroAchievements")

        let pasted = TrackerSchemaJSON.categories(from: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "categories": [
                ["id": "mine", "name": "My List", "type": "checklist", "locked": true,
                 "items": [["id": "a", "name": "A"]]],
            ]]))
        #expect(pasted.first?.provenance == "Pasted")

        // A generated category records nothing about being generated, and the
        // root's `generatedBy` belongs to the whole tracker rather than to any
        // one category — a merge keeps the CURRENT root. So the absence of a
        // stamp must stay silent rather than be read as "AI wrote this",
        // which would mislabel a hand-made list the moment anyone adds one.
        let generated = TrackerSchemaJSON.categories(from: try! JSONSerialization.data(
            withJSONObject: ["schemaVersion": 1, "generatedBy": "claude-sonnet-4-6",
                             "categories": [
                ["id": "achievements", "name": "Achievements", "type": "checklist",
                 "items": [["id": "x", "name": "Beat the game"]]],
            ]]))
        #expect(generated.first?.provenance == nil)
    }
}

/// The account library backfill, points per list, and sync on open — the
/// three "not built yet" lines from the 2026-08-19 RA design record, pulled
/// into build 39 by Tim on 09-17.
@MainActor
struct RetroAchievementsBackfillTests {

    private let page: [String: Any] = [
        "Count": 4, "Total": 4,
        "Results": [
            ["GameID": 1, "Title": "Castlevania", "ConsoleName": "NES/Famicom",
             "NumAwarded": 12, "MaxPossible": 74, "MostRecentAwardedDate": "2026-08-19T03:12:00Z"],
            ["GameID": 2, "Title": "Super Metroid", "ConsoleName": "SNES/Super Famicom",
             "NumAwarded": 0, "MaxPossible": 60],
            ["GameID": 3, "Title": "Sonic the Hedgehog 2", "ConsoleName": "Genesis/Mega Drive",
             "NumAwarded": 30, "MaxPossible": 30, "MostRecentAwardedDate": "2026-09-01T10:00:00Z"],
            ["Title": "No id here", "NumAwarded": 5],
        ],
    ]

    @Test("A completion page reads into played games, and RA's console names fold to ours")
    func shapePlayed() throws {
        let played = RetroAchievementsService.shapePlayed(page)
        #expect(played.map(\.gameID) == [1, 2, 3])
        let castlevania = try #require(played.first)
        #expect(castlevania.awarded == 12 && castlevania.possible == 74)
        #expect(castlevania.lastPlayed != nil)
        #expect(played[1].lastPlayed == nil)

        #expect(RetroAchievementsService.platform(forConsole: "NES/Famicom") == "NES")
        #expect(RetroAchievementsService.platform(forConsole: "SNES/Super Famicom") == "SNES")
        #expect(RetroAchievementsService.platform(forConsole: "Genesis/Mega Drive") == "Genesis")
        #expect(RetroAchievementsService.platform(forConsole: "Game Boy Advance") == "GBA")
        #expect(RetroAchievementsService.platform(forConsole: "PlayStation") == "PS1")
        #expect(RetroAchievementsService.platform(forConsole: "Nintendo 64") == "N64")
        #expect(RetroAchievementsService.platform(forConsole: "Events") == nil)
        #expect(RetroAchievementsService.platform(forConsole: nil) == nil)
    }

    @Test("Rows are offered for games you earned something in, minus your wishlist")
    func libraryRows() throws {
        let played = RetroAchievementsService.shapePlayed(page)
        let rows = RetroAchievementsService.libraryRows(
            from: played,
            existingNames: ["sonic the hedgehog 2"],
            library: [:])
        #expect(rows.map(\.name) == ["Castlevania"],
                "nothing earned is not played, and a wishlist game isn't owned")
        let row = try #require(rows.first)
        #expect(row.platform == "NES" && row.offersPlatformChoice)
        #expect(row.fallbackPlatform == "NES")
        // The machine you emulate on is offered beside the original, once you
        // have one — the console menu needs more than one choice to open.
        #expect(row.ownedOnlyChoices.contains("Raspberry Pi"))
        let offered = CSVImport.platformChoices(for: row, matchPlatforms: ["NES"],
                                                owned: ["Raspberry Pi", "Switch"])
        #expect(offered.contains("NES") && offered.contains("Raspberry Pi"))
        #expect(offered.count > 1, "one choice shows as plain text with nothing to tap")
        #expect(!CSVImport.platformChoices(for: row, matchPlatforms: ["NES"], owned: [])
            .contains("Raspberry Pi"), "never offered on hardware you have no record of")

        // A game you already have gets the console added instead of skipped.
        let id = UUID()
        let owned = RetroAchievementsService.libraryRows(
            from: played, existingNames: ["sonic the hedgehog 2"],
            library: [TrackerMerge.matchKey("Sonic the Hedgehog 2"): id])
        #expect(owned.map(\.name) == ["Castlevania", "Sonic the Hedgehog 2"])
        #expect(owned.last?.existingGameID == id)
    }

    @Test("A scored list shows what it's worth; an unscored one shows nothing")
    func pointsPerList() throws {
        let scored = TrackerCategoryDTO(
            id: "achievements", name: "Achievements", categoryDescription: nil, kind: nil,
            items: [
                TrackerItemDTO(id: "a", name: "A", itemDescription: nil, location: nil, missable: false,
                               hideUntilDiscovered: false, maxRank: nil, rankNames: nil, display: nil, points: 10),
                TrackerItemDTO(id: "b", name: "B", itemDescription: nil, location: nil, missable: false,
                               hideUntilDiscovered: false, maxRank: nil, rankNames: nil, display: nil, points: 25),
            ])
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let done = TrackerStateRecord(itemID: "a")
        done.completed = true
        context.insert(done)
        let points = try #require(TrackerSectionView.points(scored, states: ["a": done]))
        #expect(points == (10, 35))

        var unscored = scored
        unscored.items = [TrackerItemDTO(id: "c", name: "C", itemDescription: nil, location: nil,
                                         missable: false, hideUntilDiscovered: false, maxRank: nil,
                                         rankNames: nil, display: nil)]
        #expect(TrackerSectionView.points(unscored, states: [:]) == nil)
    }
}
