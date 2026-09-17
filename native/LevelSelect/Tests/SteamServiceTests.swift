import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Reading Steam's answers, and fitting them into a tracker the way the
/// RetroAchievements import already fits.
///
/// Fixtures are shaped from Valve's documented responses. Steam reports a
/// private library or profile inside a 200 as often as with a status, so the
/// cases that matter most are the empty-but-successful ones.
@MainActor
struct SteamServiceTests {

    // MARK: Which profile

    @Test func aSteamIDIsTakenAsIs() {
        #expect(SteamService.profileInput("76561197960287930") == .steamID("76561197960287930"))
    }

    @Test func aProfileLinkGivesItsSteamID() {
        #expect(SteamService.profileInput("https://steamcommunity.com/profiles/76561197960287930/")
                == .steamID("76561197960287930"))
    }

    @Test func aCustomLinkGivesItsName() {
        #expect(SteamService.profileInput("https://steamcommunity.com/id/gabelogannewell/")
                == .vanity("gabelogannewell"))
        #expect(SteamService.profileInput("  gabelogannewell ") == .vanity("gabelogannewell"))
    }

    @Test func somethingElseIsNotAProfile() {
        #expect(SteamService.profileInput("") == nil)
        #expect(SteamService.profileInput("https://store.steampowered.com/app/620") == nil)
        #expect(SteamService.profileInput("not a name!") == nil)
    }

    @Test func aVanityNameResolvesOnlyOnSuccess() {
        #expect(SteamService.resolvedSteamID(
            ["response": ["steamid": "76561197960287930", "success": 1]]) == "76561197960287930")
        #expect(SteamService.resolvedSteamID(
            ["response": ["success": 42, "message": "No match"]]) == nil)
    }

    @Test func aProfileSaysWhetherItIsPublic() {
        let profile = SteamService.profile(from: ["response": ["players": [[
            "steamid": "76561197960287930", "personaname": "Rabscuttle",
            "communityvisibilitystate": 3,
        ]]]])
        #expect(profile?.personaName == "Rabscuttle")
        #expect(profile?.isPublic == true)
        #expect(SteamService.profile(from: ["response": ["players": []]]) == nil)
    }

    // MARK: The library

    @Test func ownedGamesCarryHoursAndSortByName() {
        let games = SteamService.ownedGames(from: ["response": [
            "game_count": 2,
            "games": [
                ["appid": 620, "name": "Portal 2", "playtime_forever": 90, "rtime_last_played": 1_700_000_000],
                ["appid": 400, "name": "Portal", "playtime_forever": 0, "rtime_last_played": 0],
            ],
        ]])
        #expect(games?.map(\.appID) == [400, 620])
        #expect(games?.last?.hoursPlayed == 1.5)
        #expect(games?.first?.lastPlayed == nil)
    }

    /// A hidden library is not an empty one.
    @Test func aPrivateLibraryIsNotZeroGames() {
        #expect(SteamService.ownedGames(from: ["response": [:]]) == nil)
        #expect(SteamService.ownedGames(from: ["response": ["game_count": 0]]) == [])
    }

    // MARK: Achievements

    private var schemaResponse: [String: Any] {
        ["game": [
            "gameName": "Portal 2",
            "availableGameStats": ["achievements": [
                ["name": "ACH.WAKE_UP", "displayName": "Wake Up Call", "description": "Survive the manual override",
                 "hidden": 0, "icon": "https://cdn/wake.jpg", "icongray": "https://cdn/wake_gray.jpg"],
                ["name": "ACH.SECRET", "displayName": "", "hidden": 1],
            ]],
        ]]
    }

    @Test func anAchievementListBecomesOneStampedCategory() throws {
        let installed = try #require(SteamService.installed(appID: 620, from: schemaResponse))
        #expect(installed.title == "Portal 2")
        #expect(installed.count == 2)

        let categories = TrackerSchemaJSON.categories(from: installed.schema)
        #expect(categories.map(\.id) == [SteamService.categoryID])
        #expect(categories.first?.steamAppID == 620)
        #expect(categories.first?.items.map(\.id) == ["steam-ACH.WAKE_UP", "steam-ACH.SECRET"])
        // No display name falls back to the api name rather than a blank row.
        #expect(categories.first?.items.last?.name == "ACH.SECRET")
        #expect(categories.first?.provenance == "Steam")
    }

    @Test func aGameWithNoAchievementsInstallsNothing() {
        #expect(SteamService.installed(appID: 1, from: ["game": ["gameName": "Tool"]]) == nil)
        #expect(SteamService.installed(appID: 1, from: [:]) == nil)
    }

    @Test func onlyAchievedRowsAreUnlocks() throws {
        let progress = try #require(SteamService.progress(from: ["playerstats": [
            "success": true,
            "achievements": [
                ["apiname": "ACH.WAKE_UP", "achieved": 1, "unlocktime": 1_700_000_000],
                ["apiname": "ACH.SECRET", "achieved": 0, "unlocktime": 0],
                ["apiname": "ACH.OLD", "achieved": 1, "unlocktime": 0],
            ],
        ]]))
        #expect(progress.total == 3)
        #expect(progress.unlocked.map(\.itemID) == ["steam-ACH.WAKE_UP", "steam-ACH.OLD"])
        #expect(progress.unlocked.last?.earnedAt == nil)
    }

    @Test func aPrivateProfileIsNotProgress() {
        #expect(SteamService.progress(from: ["playerstats": [
            "success": false, "error": "Profile is not public",
        ]]) == nil)
    }

    /// The proxy's search answer: bad rows are dropped rather than shown blank.
    @Test func searchResultsKeepOnlyUsableRows() {
        let results = SteamService.searchResults(from: ["results": [
            ["id": 620, "name": "Portal 2"],
            ["id": 0, "name": "Nothing"],
            ["id": 400],
        ]])
        #expect(results == [SteamService.SearchResult(id: 620, name: "Portal 2")])
        #expect(SteamService.searchResults(from: [:]).isEmpty)
    }

    // MARK: Matching to IGDB

    @Test func onlySteamExternalIDsCount() {
        let rows: [[String: Any]] = [
            ["id": 72, "external_games": [
                ["uid": "620", "external_game_source": 1],
                ["uid": "1207658880", "external_game_source": 5],
            ]],
            // The deprecated field still reads.
            ["id": 71, "external_games": [["uid": "400", "category": 1]]],
            ["id": 9, "external_games": [["uid": "999", "external_game_source": 5]]],
        ]
        let map = SteamService.steamAppIDs(fromIGDBRows: rows)
        #expect(map[72] == [620])
        #expect(map[71] == [400])
        #expect(map[9] == nil)
    }

    // MARK: Library import

    @Test func theLibraryLeavesOutWhatIsAlreadyHere() {
        let owned = [
            SteamService.OwnedGame(appID: 620, name: "Portal 2", minutesPlayed: 90, lastPlayed: nil),
            SteamService.OwnedGame(appID: 400, name: "Portal", minutesPlayed: 0, lastPlayed: nil),
            SteamService.OwnedGame(appID: 323, name: "Portal 2 Soundtrack", minutesPlayed: 0, lastPlayed: nil),
            SteamService.OwnedGame(appID: 999, name: "Hades", minutesPlayed: 600, lastPlayed: nil),
        ]
        let rows = SteamService.libraryRows(from: owned, igdbByApp: [620: 72, 323: 72, 400: 71],
                                            existingIGDBIDs: [71], existingNames: ["hades"])
        // Portal is here by IGDB id, Hades by name, and the soundtrack is the
        // same IGDB game as Portal 2.
        #expect(rows.map(\.name) == ["Portal 2"])
        #expect(rows.first?.igdbID == 72)
        // Hours go to the Steam playthrough, not onto the row.
        #expect(rows.first?.hoursPlayed == nil)
        #expect(rows.first?.platforms == [SteamService.pcPlatform])
    }

    @Test func aGameIGDBDoesNotKnowStillComesThroughByName() {
        let rows = SteamService.libraryRows(
            from: [SteamService.OwnedGame(appID: 5, name: "Tiny Jam Game", minutesPlayed: 0, lastPlayed: nil)],
            igdbByApp: [:], existingIGDBIDs: [], existingNames: [])
        #expect(rows.map(\.name) == ["Tiny Jam Game"])
        #expect(rows.first?.igdbID == nil)
        #expect(rows.first?.hoursPlayed == nil)
    }

    @Test func playtimeFindsLibraryGamesByIGDBThenName() {
        let portal = UUID(), cities = UUID(), unplayed = UUID()
        let owned = [
            SteamService.OwnedGame(appID: 620, name: "Portal 2", minutesPlayed: 90, lastPlayed: nil),
            SteamService.OwnedGame(appID: 323, name: "Portal 2 Soundtrack", minutesPlayed: 5, lastPlayed: nil),
            SteamService.OwnedGame(appID: 255710, name: "Cities: Skylines", minutesPlayed: 6000, lastPlayed: nil),
            SteamService.OwnedGame(appID: 1, name: "Unplayed", minutesPlayed: 0, lastPlayed: nil),
        ]
        let matches = SteamService.playtimeMatches(
            owned: owned, igdbByApp: [620: 72, 323: 72],
            library: [(id: portal, igdbID: 72, name: "Portal 2"),
                      (id: cities, igdbID: nil, name: "cities: skylines"),
                      (id: unplayed, igdbID: nil, name: "Unplayed")])
        // The soundtrack is the same IGDB game: the larger number, not a sum.
        #expect(matches[portal] == 90)
        #expect(matches[cities] == 6000)
        #expect(matches[unplayed] == nil)
    }

    /// Tim, 09-15: Steam playtime into the Steam playthrough. Set, never added;
    /// the run you're on stays active; the first import's session is replaced.
    @Test func steamPlaytimeIsCarriedOverOnceIntoItsOwnPlaythrough() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "DiRT 3", status: .backlog)
        let mine = repo.ensureDefaultPlaythrough(for: game)
        _ = repo.logManualSession(on: mine, duration: 2520, notes: Repository.steamImportNote)

        #expect(repo.applySteamPlaytime(minutes: 42, to: game))
        #expect(repo.applySteamPlaytime(minutes: 42, to: game))

        let steam = repo.steamPlaythrough(for: game)
        #expect(steam.carriedOverSeconds == 2520)
        #expect(game.activePlaythrough?.id == mine.id)
        #expect((mine.sessions ?? []).filter { $0.deletedAt == nil }.isEmpty)
        #expect(!repo.applySteamPlaytime(minutes: 0, to: game))
    }

    @Test func aNewGameKeepsItsOwnRunActive() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Lone Survivor", status: .backlog)
        #expect(repo.applySteamPlaytime(minutes: 300, to: game))
        #expect(game.livePlaythroughs.count == 2)
        #expect(game.activePlaythrough?.name != Repository.steamPlaythroughName)
    }

    @Test func playedDemosArriveUnticked() {
        #expect(SteamService.looksLikeDemo("Vessel Demo"))
        #expect(SteamService.looksLikeDemo("Portal 2 (Demo)"))
        #expect(!SteamService.looksLikeDemo("Demon's Souls"))
        #expect(!SteamService.looksLikeDemo("Pandemonium"))
        let rows = SteamService.libraryRows(
            from: [SteamService.OwnedGame(appID: 7, name: "Vessel Demo", minutesPlayed: 12, lastPlayed: nil),
                   SteamService.OwnedGame(appID: 8, name: "Vessel", minutesPlayed: 12, lastPlayed: nil)],
            igdbByApp: [:], existingIGDBIDs: [], existingNames: [])
        #expect(rows.first { $0.name == "Vessel Demo" }?.skipReason != nil)
        #expect(rows.first { $0.name == "Vessel" }?.skipReason == nil)
    }

    /// Tim, 09-15: "Where you left off in Steam … 17 seconds ago" — a sync
    /// read as the last thing played. Unlocks keep the day they were earned.
    @Test func syncedUnlocksKeepTheDayTheyWereEarned() {
        let (repo, game) = trackerWithSteam()
        let steam = repo.steamPlaythrough(for: game)
        let earned = Date(timeIntervalSince1970: 1_700_000_000)
        // An earlier sync, before dates were kept, stamped its own moment.
        repo.setTrackerItem(steam, itemID: "steam-ACH.WAKE_UP", done: true)
        #expect(repo.trackerState(steam, itemID: "steam-ACH.WAKE_UP")?.completedAt != earned)

        let unlocks = [
            RAUnlock(itemID: "steam-ACH.WAKE_UP", hardcore: false, earnedAt: earned, points: 0),
            RAUnlock(itemID: "steam-ACH.SECRET", hardcore: false, earnedAt: earned, points: 0),
        ]
        let outcome = repo.applyRAUnlocks(unlocks, to: steam, in: game)
        #expect(outcome.alreadyTicked == 1)
        #expect(outcome.newlyTicked == 1)
        #expect(repo.trackerState(steam, itemID: "steam-ACH.WAKE_UP")?.completedAt == earned)
        #expect(repo.trackerState(steam, itemID: "steam-ACH.SECRET")?.completedAt == earned)
    }

    @Test func aRecordPlaythroughIsFoundWithoutBeingMade() {
        let (repo, game) = trackerWithSteam()
        #expect(repo.existingSteamPlaythrough(for: game) == nil)
        let steam = repo.steamPlaythrough(for: game)
        #expect(repo.existingSteamPlaythrough(for: game)?.id == steam.id)
        #expect(repo.existingRAPlaythrough(for: game) == nil)
    }

    @Test func namesMatchLoosely() {
        #expect(SteamService.namesMatch("Portal 2: Complete", "Portal 2"))
        #expect(SteamService.namesMatch("HADES", "Hades"))
        #expect(!SteamService.namesMatch("Celeste", "Hades"))
    }

    // MARK: In the tracker

    private func trackerWithSteam() -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Portal 2", status: .playing)
        let installed = SteamService.installed(appID: 620, from: schemaResponse)!
        repo.applyGeneratedSchema(for: game, jsonData: installed.schema, mode: .addAll)
        return (repo, game)
    }

    @Test func theTrackerKnowsItsSteamGame() throws {
        let (_, game) = trackerWithSteam()
        let data = try #require(game.trackerSchema?.jsonData)
        #expect(TrackerSchemaJSON.steamAppID(in: data) == 620)
        #expect(TrackerSchemaJSON.importedSourceCategoryIDs(in: data).contains(SteamService.categoryID))
    }

    /// Steam's list is the real one; regenerating would only replace it with a guess.
    @Test func aSteamListIsNotRegenerated() {
        let (repo, game) = trackerWithSteam()
        let categories = repo.trackerCategories(for: game)
        #expect(TrackerGenerationStore.regenerationCategories(categories).isEmpty)
    }

    @Test func syncingTicksIntoItsOwnPlaythrough() throws {
        let (repo, game) = trackerWithSteam()
        let mine = repo.ensureDefaultPlaythrough(for: game)
        let steam = repo.steamPlaythrough(for: game)
        #expect(steam.id != mine.id)
        #expect(repo.steamPlaythrough(for: game).id == steam.id)

        let progress = try #require(SteamService.progress(from: ["playerstats": [
            "success": true,
            "achievements": [["apiname": "ACH.WAKE_UP", "achieved": 1, "unlocktime": 1_700_000_000]],
        ]]))
        let outcome = repo.applyRAUnlocks(progress.unlocked, to: steam, in: game)
        #expect(outcome.newlyTicked == 1)
        #expect(repo.trackerState(steam, itemID: "steam-ACH.WAKE_UP")?.completed == true)
        #expect(repo.trackerState(mine, itemID: "steam-ACH.WAKE_UP")?.completed != true)
    }
}
