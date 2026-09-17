import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// PlayStation and Xbox, read and fitted into a tracker the way Steam and
/// RetroAchievements already are. Fixtures follow psn-api, the community
/// PlayStation Trophies docs and Microsoft's Xbox Live reference — not a live
/// account.
@MainActor
struct PlayStationXboxTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    // MARK: PlayStation sign-in

    @Test func anNPSSOIsReadBareOrFromSonysPage() {
        let token = String(repeating: "aB3", count: 21) + "x"
        #expect(PlayStationService.npssoValue(from: token) == token)
        #expect(PlayStationService.npssoValue(from: "{\"npsso\":\"\(token)\"}") == token)
        #expect(PlayStationService.npssoValue(from: "  \"\(token)\" ") == token)
        #expect(PlayStationService.npssoValue(from: "not a token") == nil)
        #expect(PlayStationService.npssoValue(from: "{\"npsso\":\"\"}") == nil)
    }

    @Test func theAccessCodeComesFromTheRedirect() {
        #expect(PlayStationService.code(
            fromLocation: "com.scee.psxandroid.scecompcall://redirect/?code=v3.ABC123&cid=xyz") == "v3.ABC123")
        #expect(PlayStationService.code(fromLocation: "com.scee.psxandroid.scecompcall://redirect/?error=login_required") == nil)
        #expect(PlayStationService.code(fromLocation: nil) == nil)
    }

    @Test func tokensCarryTheirExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tokens = try #require(PlayStationService.tokens(from: [
            "access_token": "access", "expires_in": 3599,
            "refresh_token": "refresh", "refresh_token_expires_in": 5_183_999,
        ], now: now))
        #expect(tokens.access == "access")
        #expect(tokens.refresh == "refresh")
        #expect(tokens.accessExpiry == now.addingTimeInterval(3539))
        #expect(tokens.refreshExpiry == now.addingTimeInterval(5_183_999))
        #expect(PlayStationService.tokens(from: ["error": "invalid_grant"], now: now) == nil)
    }

    // MARK: PlayStation trophies

    private var ghostTitle: PlayStationService.TrophyTitle {
        PlayStationService.TrophyTitle(id: "NPWR20188_00", service: "trophy2", name: "Ghost of Tsushima",
                                       platform: "PS5", defined: 3, earned: 1)
    }

    @Test func trophyTitlesAddUpTheirGrades() {
        let titles = PlayStationService.trophyTitles(from: ["trophyTitles": [[
            "npCommunicationId": "NPWR20188_00", "npServiceName": "trophy2",
            "trophyTitleName": "Ghost of Tsushima", "trophyTitlePlatform": "PS5",
            "definedTrophies": ["bronze": 40, "silver": 10, "gold": 1, "platinum": 1],
            "earnedTrophies": ["bronze": 12, "silver": 2, "gold": 0, "platinum": 0],
        ]]])
        #expect(titles.first?.defined == 52)
        #expect(titles.first?.earned == 14)
        #expect(titles.first?.service == "trophy2")
    }

    private var trophyList: [String: Any] {
        ["trophies": [
            ["trophyId": 0, "trophyHidden": false, "trophyType": "platinum",
             "trophyName": "Ghost of Tsushima", "trophyDetail": "Obtain all trophies",
             "trophyIconUrl": "https://img/0.png", "trophyGroupId": "default"],
            ["trophyId": 1, "trophyHidden": true, "trophyType": "bronze", "trophyName": "", "trophyGroupId": "default"],
        ]]
    }

    @Test func aTrophyListBecomesOneStampedCategory() throws {
        let set = try #require(PlayStationService.importedSet(title: ghostTitle, from: trophyList))
        #expect(set.count == 2)
        let categories = TrackerSchemaJSON.categories(from: set.schema)
        let category = try #require(categories.first)
        #expect(category.id == PlayStationService.categoryID)
        #expect(category.psnTitleID == "NPWR20188_00")
        #expect(category.psnService == "trophy2")
        #expect(category.provenance == "PlayStation")
        #expect(category.isImportedSet)
        #expect(category.items.map(\.id) == ["psn-0", "psn-1"])
        #expect(category.items.last?.name == "Trophy 1")

        let title = try #require(TrackerSchemaJSON.playStationTitle(in: set.schema))
        #expect(title.id == "NPWR20188_00" && title.service == "trophy2")
        #expect(TrackerSchemaJSON.importedSourceCategoryIDs(in: set.schema) == [PlayStationService.categoryID])
        #expect(TrackerGenerationStore.regenerationCategories(categories).isEmpty)
    }

    @Test func earnedTrophiesKeepSonysDates() {
        let progress = PlayStationService.progress(from: ["trophies": [
            ["trophyId": 0, "earned": false],
            ["trophyId": 1, "earned": true, "earnedDateTime": "2021-02-06T05:52:47Z"],
        ]])
        #expect(progress.total == 2)
        #expect(progress.unlocked.map(\.itemID) == ["psn-1"])
        #expect(progress.unlocked.first?.earnedAt == Date(timeIntervalSince1970: 1_612_590_767))
    }

    // MARK: PlayStation games and playtime

    @Test func playDurationsBecomeMinutes() {
        #expect(PlayStationService.minutes(fromISODuration: "PT41H4M39S") == 2465)
        #expect(PlayStationService.minutes(fromISODuration: "P1DT2H") == 1560)
        #expect(PlayStationService.minutes(fromISODuration: "PT30S") == 1)
        #expect(PlayStationService.minutes(fromISODuration: nil) == 0)
        #expect(PlayStationService.minutes(fromISODuration: "garbage") == 0)
    }

    private var played: [PlayStationService.PlayedGame] {
        PlayStationService.playedGames(from: ["titles": [
            ["titleId": "PPSA01", "name": "Ghost of Tsushima", "category": "ps5_native_game",
             "playDuration": "PT10H", "lastPlayedDateTime": "2024-01-01T00:00:00Z"],
            ["titleId": "CUSA01", "name": "Ghost of Tsushima™", "category": "ps4_game", "playDuration": "PT5H"],
            ["titleId": "CUSA02", "name": "Bloodborne", "category": "ps4_game", "playDuration": "PT2H30M"],
            ["titleId": "CUSA03", "name": "Astro Demo", "category": "ps4_game", "playDuration": "PT0S"],
        ]])
    }

    @Test func oneGameOnTwoMachinesIsOneRow() {
        let rows = PlayStationService.libraryRows(from: played, existingNames: ["bloodborne"])
        #expect(rows.map(\.name) == ["Ghost of Tsushima", "Astro Demo"])
        #expect(rows.first?.platforms == ["PlayStation 5", "PlayStation 4"])
        #expect(rows.first?.hoursPlayed == nil)
        #expect(rows.last?.skipReason != nil)
    }

    @Test func playtimeAddsUpAcrossMachines() {
        let ghost = UUID(), blood = UUID()
        let matches = PlayStationService.playtimeMatches(
            games: played, library: [(id: ghost, name: "Ghost of Tsushima"), (id: blood, name: "Bloodborne")])
        #expect(matches[ghost] == 900)
        #expect(matches[blood] == 150)
    }

    @Test func playStationPlaytimeIsCarriedOverIntoItsOwnPlaythrough() {
        let repo = store()
        let game = repo.addGame(name: "Bloodborne", status: .playing)
        #expect(repo.applyPlayStationPlaytime(minutes: 150, to: game))
        #expect(repo.applyPlayStationPlaytime(minutes: 150, to: game))
        let record = repo.existingPlayStationPlaythrough(for: game)
        #expect(record?.carriedOverSeconds == 9000)
        #expect(game.activePlaythrough?.name != Repository.playStationPlaythroughName)
    }

    // MARK: Xbox

    @Test func pkceMatchesTheRFCExample() {
        #expect(XboxService.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let verifier = XboxService.randomVerifier()
        #expect(verifier.count == 43)
        #expect(!verifier.contains("=") && !verifier.contains("+") && !verifier.contains("/"))
    }

    @Test func theSignInCodeMustAnswerOurRequest() {
        let good = URL(string: "levelselect://xbox/callback?code=M.C1_abc&state=S1")!
        #expect(XboxService.authorizationCode(from: good, expecting: "S1") == "M.C1_abc")
        #expect(XboxService.authorizationCode(from: good, expecting: "other") == nil)
        let refused = URL(string: "levelselect://xbox/callback?error=access_denied&state=S1")!
        #expect(XboxService.authorizationCode(from: refused, expecting: "S1") == nil)
    }

    @Test func anXSTSAnswerGivesTheSession() throws {
        let session = try #require(XboxService.session(fromXSTS: [
            "Token": "xsts", "NotAfter": "2026-09-17T12:00:00.1234567Z",
            "DisplayClaims": ["xui": [["uhs": "12345", "xid": "2535400000000000", "gtg": "Timultuous"]]],
        ]))
        #expect(session.userHash == "12345")
        #expect(session.xuid == "2535400000000000")
        #expect(session.gamertag == "Timultuous")
        #expect(session.expiry > Date(timeIntervalSince1970: 1_789_000_000))
        #expect(XboxService.session(fromXSTS: ["Token": "xsts"]) == nil)
    }

    @Test func titlesKeepGamesAndNameTheirMachines() {
        let titles = XboxService.titles(from: ["titles": [
            ["titleId": "219630713", "name": "Halo Infinite", "type": "Game",
             "devices": ["XboxSeries", "XboxOne", "PC"],
             "achievement": ["currentAchievements": 20, "totalAchievements": 119],
             "titleHistory": ["lastTimePlayed": "2024-05-01T10:00:00.0000000Z"]],
            ["titleId": "1", "name": "YouTube", "type": "App", "devices": ["XboxOne"]],
        ]])
        #expect(titles.count == 2)
        #expect(titles.first?.platforms == ["Xbox One", "Xbox Series X|S", "PC (Microsoft Windows)"])
        #expect(titles.first?.earned == 20 && titles.first?.total == 119)
        #expect(titles.first?.lastPlayed != nil)
        #expect(titles.last?.isGame == false)
    }

    private var achievementRows: [[String: Any]] {
        [
            ["id": "1", "name": "Tutorial", "description": "Finish the tutorial",
             "progressState": "Achieved", "progression": ["timeUnlocked": "2024-05-01T10:00:00.1234567Z"],
             "rewards": [["type": "Gamerscore", "value": "10"]],
             "mediaAssets": [["type": "Icon", "url": "https://img/1.png"]], "isSecret": false],
            ["id": "2", "name": "Secret", "description": "", "lockedDescription": "Keep playing",
             "progressState": "NotStarted", "progression": ["timeUnlocked": "0001-01-01T00:00:00.0000000Z"],
             "isSecret": true],
        ]
    }

    @Test func oneAchievementsAnswerIsTheListAndTheUnlocks() throws {
        let set = try #require(XboxService.importedSet(titleID: 219630713, titleName: "Halo Infinite",
                                                       rows: achievementRows))
        let category = try #require(TrackerSchemaJSON.categories(from: set.schema).first)
        #expect(category.id == XboxService.categoryID)
        #expect(category.xboxTitleID == 219630713)
        #expect(category.provenance == "Xbox")
        #expect(category.items.map(\.id) == ["xbox-1", "xbox-2"])
        #expect(category.items.first?.points == 10)
        #expect(TrackerSchemaJSON.xboxTitleID(in: set.schema) == 219630713)

        let progress = XboxService.progress(rows: achievementRows)
        #expect(progress.total == 2)
        #expect(progress.unlocked.map(\.itemID) == ["xbox-1"])
        #expect(progress.unlocked.first?.earnedAt != nil)
    }

    @Test func xboxLibraryRowsCarryNoHours() {
        let titles = XboxService.titles(from: ["titles": [
            ["titleId": "5", "name": "Forza Horizon 5", "type": "Game", "devices": ["XboxSeries"]],
            ["titleId": "6", "name": "Halo Infinite", "type": "Game", "devices": ["XboxSeries"]],
        ]])
        let rows = XboxService.libraryRows(from: titles, existingNames: ["halo infinite"])
        #expect(rows.map(\.name) == ["Forza Horizon 5"])
        #expect(rows.first?.platform == "Xbox Series X|S")
        #expect(rows.first?.hoursPlayed == nil)
    }

    @Test("A backward-compatible 360 game imports as a 360 game, on that console alone")
    func backwardCompatibleGamesKeepTheirConsole() {
        let titles = XboxService.titles(from: ["titles": [
            ["titleId": "7", "name": "Fallout 3", "type": "Game",
             "devices": ["XboxSeries", "XboxOne", "Xbox360"]],
            ["titleId": "8", "name": "Gears 5", "type": "Game",
             "devices": ["XboxSeries", "XboxOne", "PC"]],
        ]])
        let rows = XboxService.libraryRows(from: titles, existingNames: [])
        #expect(rows.map(\.platforms) == [["Xbox 360"], ["Xbox One"]])
        #expect(rows.first?.platform == "Xbox 360")
        #expect(rows.first?.platformChoices == ["Xbox Series X|S", "Xbox One", "Xbox 360"])
        #expect(rows.last?.platformChoices == ["Xbox Series X|S", "Xbox One", "PC (Microsoft Windows)"])
    }

    @Test("The review starts on the newest console you have, and can take several")
    func importStartsOnTheNewestOwnedConsole() {
        let titles = XboxService.titles(from: ["titles": [
            ["titleId": "7", "name": "Fallout 3", "type": "Game",
             "devices": ["XboxSeries", "XboxOne", "Xbox360"],
             "achievement": ["currentAchievements": 3, "totalAchievements": 50]],
        ]])
        let row = XboxService.libraryRows(from: titles, existingNames: [])[0]
        #expect(row.offersPlatformChoice && !row.mayBeAnApp)
        let owned: Set = [PlatformKey.canonical("Xbox 360"), PlatformKey.canonical("Xbox One")]
        let choices = CSVImport.platformChoices(for: row, matchPlatforms: [], owned: owned)
        var picked = CSVImport.preferOwnedPlatform(row, choices: choices, owned: owned)
        #expect(picked.platforms == ["Xbox One"])
        #expect(CSVImport.preferOwnedPlatform(row, choices: choices, owned: []).platforms == ["Xbox 360"])

        picked.togglePlatform("Xbox 360", order: choices)
        #expect(picked.platforms == ["Xbox One", "Xbox 360"] && picked.platform == "Xbox One")
        picked.togglePlatform("Xbox One", order: choices)
        picked.togglePlatform("Xbox 360", order: choices)   // the last one stays
        #expect(picked.platforms == ["Xbox 360"])
    }

    @Test("A console the matched game is on joins the choices when you have one")
    func ownedNonXboxConsolesAreOffered() {
        let titles = XboxService.titles(from: ["titles": [
            ["titleId": "9", "name": "Minecraft Dungeons", "type": "Game",
             "devices": ["XboxSeries", "XboxOne", "PC"]],
        ]])
        let row = XboxService.libraryRows(from: titles, existingNames: [])[0]
        #expect(row.mayBeAnApp)
        let owned: Set = [PlatformKey.canonical("Switch"), PlatformKey.canonical("PC")]
        let choices = CSVImport.platformChoices(
            for: row, matchPlatforms: ["PC (Microsoft Windows)", "Nintendo Switch", "PlayStation 4"], owned: owned)
        #expect(choices == ["Xbox Series X|S", "Xbox One", "Nintendo Switch", "PC (Microsoft Windows)"])
        #expect(CSVImport.preferOwnedPlatform(row, choices: choices, owned: owned).platforms == ["Nintendo Switch"])
    }

    @Test("A game you have gets the Xbox console added, and nothing else changes")
    func existingGamesGainTheConsole() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Minecraft Dungeons", status: .playing)
        game.platforms = ["Nintendo Switch", "PC (Microsoft Windows)"]
        game.ownedPlatforms = ["Nintendo Switch"]
        game.rating = 4
        let wished = repo.addGame(name: "Halo 3", status: .wishlist)

        let titles = XboxService.titles(from: ["titles": [
            ["titleId": "9", "name": "Minecraft Dungeons", "type": "Game", "devices": ["XboxOne", "PC"]],
            ["titleId": "10", "name": "Halo 3", "type": "Game", "devices": ["Xbox360"]],
        ]])
        let rows = XboxService.libraryRows(from: titles, existingNames: [wished.name.lowercased()],
                                           library: [TrackerMerge.matchKey(game.name): game.id])
        #expect(rows.count == 1)
        #expect(rows[0].existingGameID == game.id && !rows[0].mayBeAnApp)

        var row = rows[0]
        row.choosePlatform("Xbox One")
        let result = CSVImport.apply([(row, nil)], context: context)
        #expect(result == CSVImport.Applied(added: 0, updated: 1))
        #expect(game.ownedPlatforms == ["Nintendo Switch", "Xbox One"])
        #expect(game.platforms == ["Nintendo Switch", "PC (Microsoft Windows)", "Xbox One"])
        #expect(game.rating == 4 && game.status == .playing)
        #expect(CSVImport.apply([(row, nil)], context: context).updated == 0, "already owned there")
        game.ownedPlatforms = ["Nintendo Switch", "Xbox One", "PC (Microsoft Windows)"]
        #expect(CSVImport.dropNothingToAdd(rows, context: context).isEmpty, "a second run has nothing to offer")
        #expect(((try? context.fetch(FetchDescriptor<Game>())) ?? []).count == 2)
    }

    @Test("PlayStation and Steam add their machines to games you have")
    func playStationAndSteamGainTheirMachines() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let ghost = repo.addGame(name: "Ghost of Tsushima", status: .completed)
        ghost.platforms = ["Nintendo Switch"]
        ghost.ownedPlatforms = ["Nintendo Switch"]
        let hades = repo.addGame(name: "Hades", status: .playing)
        hades.igdbID = 113112
        hades.ownedPlatforms = ["Nintendo Switch"]
        let wished = repo.addGame(name: "Bloodborne", status: .wishlist)
        let keys = CSVImport.LibraryKeys([ghost, hades, wished])
        #expect(keys.wishlistNames == ["bloodborne"])

        let ps = CSVImport.dropNothingToAdd(
            PlayStationService.libraryRows(from: played, existingNames: keys.wishlistNames,
                                           library: keys.byName),
            context: context)
        #expect(ps.map(\.name) == ["Ghost of Tsushima", "Astro Demo"])
        #expect(ps[0].existingGameID == ghost.id && ps[0].platformsKnown)

        let steam = SteamService.libraryRows(
            from: [SteamService.OwnedGame(appID: 1145360, name: "Hades™", minutesPlayed: 600, lastPlayed: nil)],
            igdbByApp: [1145360: 113112],
            existingIGDBIDs: keys.wishlistIGDBIDs, existingNames: keys.wishlistNames,
            libraryByIGDB: keys.byIGDB, library: keys.byName)
        #expect(steam.first?.existingGameID == hades.id)

        let result = CSVImport.apply([(ps[0], nil), (steam[0], nil)], context: context)
        #expect(result.updated == 2)
        #expect(ghost.ownedPlatforms == ["Nintendo Switch", "PlayStation 5", "PlayStation 4"])
        #expect(hades.ownedPlatforms == ["Nintendo Switch", "PC (Microsoft Windows)"])
        #expect(ghost.status == .completed)
        #expect(CSVImport.dropNothingToAdd(ps + steam, context: context).map(\.name) == ["Astro Demo"])
    }

    @Test("Steam offers Mac and your Steam hardware, and a whole review can move at once")
    func steamOffersItsMachines() {
        let rows = SteamService.libraryRows(
            from: [SteamService.OwnedGame(appID: 1, name: "Hades", minutesPlayed: 60, lastPlayed: nil),
                   SteamService.OwnedGame(appID: 2, name: "Halo", minutesPlayed: 60, lastPlayed: nil)],
            igdbByApp: [:], existingIGDBIDs: [], existingNames: [])
        let owned: Set = ["Mac", "Steam Deck", "PC"]
        let hades = CSVImport.platformChoices(
            for: rows[0], matchPlatforms: ["PC (Microsoft Windows)", "Mac", "Linux", "Nintendo Switch"], owned: owned)
        #expect(hades == ["Mac", "Steam Deck", "PC (Microsoft Windows)"])
        #expect(CSVImport.preferOwnedPlatform(rows[0], choices: hades, owned: owned).platforms == ["Mac"])
        let halo = CSVImport.platformChoices(for: rows[1], matchPlatforms: ["PC (Microsoft Windows)"], owned: owned)
        #expect(halo == ["Steam Deck", "PC (Microsoft Windows)"])
        #expect(CSVImport.preferOwnedPlatform(rows[1], choices: halo, owned: owned).platforms
                == ["PC (Microsoft Windows)"], "the Deck is offered, never assumed")

        let bulk = CSVImport.bulkPlatforms([hades, halo, ["PC (Microsoft Windows)"]])
        #expect(bulk.map(\.platform) == ["Mac", "Steam Deck", "PC (Microsoft Windows)"])
        #expect(bulk.first { $0.platform == "Steam Deck" }?.rows == 2)
        #expect(bulk.first { $0.platform == "Mac" }?.rows == 1)
    }

    @Test("A PlayStation row keeps the consoles it was played on and offers the VR headset")
    func playStationOffersVR() {
        let rows = PlayStationService.libraryRows(from: played, existingNames: [])
        var ghost = CSVImportView.Candidate(row: rows[0])
        let owned: Set = [PlatformKey.canonical("PlayStation VR"), PlatformKey.canonical("PlayStation 4")]
        ghost.match = IGDBGame(id: 1, name: "Ghost of Tsushima", slug: nil, coverImageID: nil, franchise: nil,
                               releaseYear: nil, summary: nil, gameType: 0,
                               platforms: ["PlayStation 4", "PlayStation VR", "PC (Microsoft Windows)"],
                               genres: [], themes: [], gameModes: [], playerPerspectives: [],
                               developers: [], publishers: [])
        ghost.refreshPlatforms(owned: owned)
        #expect(ghost.platformChoices == ["PlayStation 5", "PlayStation 4", "PlayStation VR"])
        #expect(ghost.row.platforms == ["PlayStation 5", "PlayStation 4"], "what PlayStation reported stays")

        ghost.row.togglePlatform("PlayStation VR", order: ghost.platformChoices)
        ghost.platformsPicked = true
        ghost.refreshPlatforms(owned: owned)
        #expect(ghost.row.platforms == ["PlayStation 5", "PlayStation 4", "PlayStation VR"])
    }

    @Test("A Steam VR game offers every PC headset you have, and assumes none")
    func steamVROffersYourHeadsets() {
        let row = SteamService.libraryRows(
            from: [SteamService.OwnedGame(appID: 3, name: "Half-Life: Alyx", minutesPlayed: 60, lastPlayed: nil)],
            igdbByApp: [:], existingIGDBIDs: [], existingNames: [])[0]
        let owned: Set = ["Meta Quest", "HTC Vive", "PC"]
        let alyx = CSVImport.platformChoices(
            for: row, matchPlatforms: ["PC (Microsoft Windows)", "SteamVR"], owned: owned)
        #expect(alyx == ["HTC Vive", "Meta Quest", "PC (Microsoft Windows)"])
        #expect(CSVImport.preferOwnedPlatform(row, choices: alyx, owned: owned).platforms
                == ["PC (Microsoft Windows)"])
        let flat = CSVImport.platformChoices(for: row, matchPlatforms: ["PC (Microsoft Windows)"], owned: owned)
        #expect(flat == ["PC (Microsoft Windows)"], "no headsets for a flat game")
    }

    @Test("A title with no exact match starts on the game from the row's console")
    func matchingPrefersTheRowsConsole() {
        func game(_ id: Int, _ name: String, _ platforms: [String]) -> IGDBGame {
            IGDBGame(id: id, name: name, slug: nil, coverImageID: nil, franchise: nil,
                     releaseYear: nil, summary: nil, gameType: 0, platforms: platforms,
                     genres: [], themes: [], gameModes: [], playerPerspectives: [],
                     developers: [], publishers: [])
        }
        let hits = [
            game(1, "Call of Duty: Modern Warfare III", ["Xbox Series X|S", "PlayStation 4"]),
            game(2, "Call of Duty: Modern Warfare 3", ["PlayStation 3", "Xbox 360", "PC (Microsoft Windows)"]),
        ]
        let row = XboxService.libraryRows(from: XboxService.titles(from: ["titles": [
            ["titleId": "1", "name": "Modern Warfare® 3", "type": "Game",
             "devices": ["XboxSeries", "XboxOne", "Xbox360"]],
        ]]), existingNames: [])[0]
        let hints = CSVImport.matchHints(for: row)
        #expect(hints == ["Xbox 360"])
        let best = CSVImport.bestMatch(hits, name: row.name, hints: hints)
        #expect(best.game?.id == 2 && !best.exact)
        #expect(CSVImport.ranked(hits, hints: hints).map(\.id) == [2, 1])

        let exactElsewhere = [game(3, "Brink", ["PC (Microsoft Windows)"]), game(4, "Brink", ["Xbox 360"])]
        #expect(CSVImport.bestMatch(exactElsewhere, name: "Brink™", hints: hints).game?.id == 4)
    }

    @Test("Imports pace IGDB lookups under the proxy's per-minute limit")
    func lookupsArePaced() {
        let now = Date(timeIntervalSince1970: 1_000)
        let quiet = (0..<54).map { now.addingTimeInterval(-Double($0)) }
        #expect(CSVImport.paceDelay(now: now, recent: quiet) == 0)
        let busy = (0..<55).map { now.addingTimeInterval(-Double($0) * 0.5) }   // 55 in 27s
        #expect(CSVImport.paceDelay(now: now, recent: busy) == 33)
        let old = (0..<80).map { now.addingTimeInterval(-61 - Double($0)) }
        #expect(CSVImport.paceDelay(now: now, recent: old) == 0, "a minute ago doesn't count")
    }

    @Test("itch.io games come in for review, keep their covers, and add itch.io to games you have")
    func itchGamesAreReviewed() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let celeste = repo.addGame(name: "Celeste", status: .completed)
        celeste.ownedPlatforms = ["Nintendo Switch"]
        let keys = CSVImport.LibraryKeys([celeste])
        let rows = ItchService.libraryRows(from: [
            .init(id: 1, name: "Celeste", coverURL: "https://img.itch/celeste.png", url: nil),
            .init(id: 2, name: "A Tiny Jam Game", coverURL: "https://img.itch/tiny.png", url: nil),
            .init(id: 2, name: "A Tiny Jam Game", coverURL: nil, url: nil),
        ], existingNames: keys.wishlistNames, library: keys.byName)
        #expect(rows.map(\.name) == ["Celeste", "A Tiny Jam Game"])
        #expect(rows.allSatisfy { $0.exactMatchOnly && $0.platforms == ["itch.io"] })
        #expect(rows[0].existingGameID == celeste.id)

        let result = CSVImport.apply([(rows[0], nil), (rows[1], nil)], context: context)
        #expect(result == CSVImport.Applied(added: 1, updated: 1))
        #expect(celeste.ownedPlatforms == ["Nintendo Switch", "itch.io"])
        let jam = ((try? context.fetch(FetchDescriptor<Game>())) ?? []).first { $0.name == "A Tiny Jam Game" }
        #expect(jam?.coverURLString == "https://img.itch/tiny.png")
        #expect(jam?.ownedPlatformNames == ["itch.io"])
    }

    @Test("Titles match through trademark marks and punctuation, not through extra words")
    func titlesMatchThroughMarks() {
        #expect(CSVImport.sameTitle("Brink™", "Brink"))
        #expect(CSVImport.sameTitle("Battlefield Bad Company 2", "Battlefield: Bad Company 2"))
        #expect(CSVImport.sameTitle("Call of Duty®: Black Ops", "Call of Duty: Black Ops"))
        #expect(!CSVImport.sameTitle("Brink™", "Brink of Consciousness: Dorian Gray Syndrome"))
        #expect(CSVImport.searchName("Assassin's Creed® III") == "Assassin's Creed III")
    }

    // MARK: Record playthroughs

    @Test("Duplicate PlayStation and Xbox records fold, like Steam's")
    func duplicateRecordsFold() {
        let repo = store()
        let game = repo.addGame(name: "Minecraft", status: .playing)
        _ = repo.ensureDefaultPlaythrough(for: game)
        for (name, marker) in [(Repository.playStationPlaythroughName, Repository.playStationPlaythroughMarker),
                               (Repository.xboxPlaythroughName, Repository.xboxPlaythroughMarker)] {
            for _ in 0..<2 {
                let pt = Playthrough(name: name)
                pt.notes = marker
                repo.context.insert(pt)
                pt.game = game
            }
        }
        #expect(repo.reconcile(game).mergedRecordPlaythroughs == 2)
        #expect(game.livePlaythroughs.filter { $0.name == Repository.playStationPlaythroughName }.count == 1)
        #expect(game.livePlaythroughs.filter { $0.name == Repository.xboxPlaythroughName }.count == 1)
    }

    @Test func dateFractionsLongerThanThreeDigitsStillParse() {
        #expect(ServiceDates.parse("2024-05-01T10:00:00.1234567Z") != nil)
        #expect(ServiceDates.parse("0001-01-01T00:00:00Z") == nil)
        #expect(ServiceNames.same("Marvel's Spider-Man 2™", "Marvel’s Spider-Man 2"))
        #expect(!ServiceNames.same("Halo 2", "Halo 3"))
    }
}
