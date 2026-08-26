import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Filling in what a CSV import never knew — without undoing what its owner
/// has since typed.
///
/// The whole feature rests on one property: a field that already holds
/// something is never written. Tim's library is being hand-corrected while this
/// ships, so a regression here doesn't produce a wrong number on a card, it
/// quietly eats the corrections. Most of these tests exist to hold that line.
@MainActor
struct MetadataRefreshTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    /// A complete IGDB answer, so any field left empty after a fill is the
    /// fill's decision rather than a gap in the source.
    private func igdb(id: Int = 42, year: Int? = 2018) -> IGDBGame {
        IGDBGame(
            id: id,
            name: "The Messenger",
            slug: "the-messenger",
            coverImageID: "co1abc",
            franchise: "The Messenger",
            releaseYear: year,
            summary: "A ninja, a curse, and a very long night.",
            gameType: 0,
            platforms: ["Nintendo Switch", "PC (Microsoft Windows)"],
            genres: ["Platform"],
            themes: ["Action"],
            gameModes: ["Single player"],
            playerPerspectives: ["Side view"],
            developers: ["Sabotage Studio"],
            publishers: ["Devolver Digital"]
        )
    }

    // MARK: The 1969 cohort

    /// The reason this feature exists. The web-app CSV path wrote a missing
    /// release date as timestamp zero, and 119 of Tim's 164 games carry it.
    @Test func epochZeroCountsAsAMissingReleaseDate() {
        #expect(MetadataRefresh.isMissing(Date(timeIntervalSince1970: 0)))
        #expect(MetadataRefresh.isMissing(nil))
    }

    /// Two days either side, because the same stored zero lands on either side
    /// of the epoch once a timezone is applied to it.
    @Test func datesNearTheEpochAreArtifactsInBothDirections() {
        #expect(MetadataRefresh.isMissing(Date(timeIntervalSince1970: 86_400)))
        #expect(MetadataRefresh.isMissing(Date(timeIntervalSince1970: -86_400)))
    }

    /// The window has to end somewhere, and it ends before any real game.
    /// Pong is 1972; nothing legitimate lands in the first two days of 1970.
    @Test func arealReleaseDateIsNotAnArtifact() {
        let pong = Calendar.current.date(from: DateComponents(year: 1972, month: 11, day: 29))!
        #expect(!MetadataRefresh.isMissing(pong))
        #expect(!MetadataRefresh.isMissing(Date(timeIntervalSince1970: 172_801)))
    }

    /// Stats hides the epoch cohort from the year chart; this pass repairs it.
    /// If the two ever disagreed, a game could be invisible on the chart and
    /// also considered fine by the repair, and stay wrong forever.
    @Test func statsAndTheFillPassAgreeOnWhatCountsAsADate() {
        for seconds in [0.0, 86_400, -86_400, 172_801, 1_000_000_000] {
            let date = Date(timeIntervalSince1970: seconds)
            let statsWouldChart = abs(date.timeIntervalSince1970) > 172_800
            #expect(statsWouldChart == !MetadataRefresh.isMissing(date))
        }
    }

    @Test func fillRepairsAnEpochDateBecauseItReadsAsEmpty() {
        let repo = self.repo()
        let game = repo.addGame(name: "The Messenger")
        game.firstReleaseDate = Date(timeIntervalSince1970: 0)

        let filled = MetadataRefresh.fill(game, from: igdb())

        #expect(filled.contains(.releaseDate))
        let year = Calendar.current.component(.year, from: game.firstReleaseDate!)
        #expect(year == 2018)
    }

    // MARK: The line that must not move

    /// The load-bearing test. Every field already holding something keeps it,
    /// even though IGDB offered a different answer for all of them.
    @Test func nonEmptyFieldsAreNeverOverwritten() {
        let repo = self.repo()
        let game = repo.addGame(name: "The Messenger")
        let mine = Calendar.current.date(from: DateComponents(year: 1998, month: 3, day: 4))!
        repo.edit(game) {
            $0.firstReleaseDate = mine
            $0.coverImageID = "my-own-cover"
            $0.coverURLString = "https://example.com/mine.jpg"
            $0.genres = ["Metroidvania"]
            $0.themes = ["Comedy"]
            $0.gameModes = ["Co-op, sort of"]
            $0.playerPerspectives = ["Sideways"]
            $0.developers = ["Sabotage"]
            $0.publishers = ["Devolver"]
            $0.franchise = "Messenger"
            $0.summary = "My own words about this game."
            $0.igdbSlug = "my-slug"
        }

        let filled = MetadataRefresh.fill(game, from: igdb())

        #expect(filled.isEmpty)
        #expect(game.firstReleaseDate == mine)
        #expect(game.coverImageID == "my-own-cover")
        #expect(game.genres == ["Metroidvania"])
        #expect(game.themes == ["Comedy"])
        #expect(game.gameModes == ["Co-op, sort of"])
        #expect(game.playerPerspectives == ["Sideways"])
        #expect(game.developers == ["Sabotage"])
        #expect(game.publishers == ["Devolver"])
        #expect(game.franchise == "Messenger")
        #expect(game.summary == "My own words about this game.")
        #expect(game.igdbSlug == "my-slug")
    }

    /// Platforms are the exact field being hand-corrected — "Switch" versus
    /// IGDB's "Nintendo Switch" — and today the field conflates "released on"
    /// with "I own it on". This pass stays out of it entirely, including when
    /// the game has none.
    @Test func platformsAreNeverTouchedEvenWhenEmpty() {
        let repo = self.repo()
        let renamed = repo.addGame(name: "Renamed")
        repo.edit(renamed) { $0.platforms = ["Switch"] }
        let bare = repo.addGame(name: "Bare")

        MetadataRefresh.fill(renamed, from: igdb())
        MetadataRefresh.fill(bare, from: igdb())

        #expect(renamed.platforms == ["Switch"])
        #expect(bare.platforms.isEmpty)
        #expect(!MetadataRefresh.Field.allCases.contains { $0.rawValue == "platforms" })
    }

    /// User data isn't metadata, and a refresh has no business near it.
    @Test func userDataSurvivesAFill() {
        let repo = self.repo()
        let game = repo.addGame(name: "A Name I Chose", status: .completed)
        repo.edit(game) {
            $0.rating = 5
            $0.review = "Best of the year."
            $0.notes = "Save file on the SD card."
            $0.userTags = ["cozy"]
            $0.ownership = ["physical"]
        }

        MetadataRefresh.fill(game, from: igdb())

        #expect(game.name == "A Name I Chose")
        #expect(game.status == .completed)
        #expect(game.rating == 5)
        #expect(game.review == "Best of the year.")
        #expect(game.notes == "Save file on the SD card.")
        #expect(game.userTags == ["cozy"])
        #expect(game.ownership == ["physical"])
    }

    @Test func emptyFieldsAreFilledAndReported() {
        let repo = self.repo()
        let game = repo.addGame(name: "The Messenger")

        let filled = MetadataRefresh.fill(game, from: igdb())

        #expect(filled.contains(.releaseDate))
        #expect(filled.contains(.genres))
        #expect(filled.contains(.developers))
        #expect(filled.contains(.cover))
        #expect(game.genres == ["Platform"])
        #expect(game.developers == ["Sabotage Studio"])
        #expect(game.coverURLString?.contains("co1abc") == true)
    }

    /// Nothing writes an empty answer over an empty field and calls it work.
    @Test func afieldIGDBHasNothingForIsLeftAloneAndNotCounted() {
        let repo = self.repo()
        let game = repo.addGame(name: "Obscure")
        let thin = IGDBGame(
            id: 9, name: "Obscure", slug: nil, coverImageID: nil, franchise: nil,
            releaseYear: nil, summary: nil, gameType: 0, platforms: [], genres: [],
            themes: [], gameModes: [], playerPerspectives: [], developers: [], publishers: [])

        let filled = MetadataRefresh.fill(game, from: thin)

        #expect(filled.isEmpty)
        #expect(game.firstReleaseDate == nil)
        #expect(game.coverURLString == nil)
    }

    /// The web app stored IGDB summaries capped at 200 characters. That is a
    /// truncation artifact, not a value, and the game page already heals it one
    /// game at a time — so the bulk pass treats it the same way. Safe only
    /// because `summary` is fetched and never typed.
    @Test func atwoHundredCharacterSummaryIsATruncationArtifact() {
        let capped = String(repeating: "a", count: 200)
        #expect(MetadataRefresh.isMissing(summary: capped))
        #expect(MetadataRefresh.isMissing(summary: ""))
        #expect(MetadataRefresh.isMissing(summary: nil))
        #expect(!MetadataRefresh.isMissing(summary: String(repeating: "a", count: 201)))
        #expect(!MetadataRefresh.isMissing(summary: "Short but real."))
    }

    // MARK: Planning

    @Test func planSeparatesWorkFromGuessworkFromDone() {
        let repo = self.repo()

        let fillable = repo.addGame(name: "Has an id, missing a date")
        repo.edit(fillable) {
            $0.igdbID = 42
            $0.firstReleaseDate = Date(timeIntervalSince1970: 0)
        }

        let unmatched = repo.addGame(name: "No id at all")

        let complete = repo.addGame(name: "Nothing missing")
        repo.edit(complete) {
            $0.igdbID = 7
            $0.firstReleaseDate = Date(timeIntervalSince1970: 1_000_000_000)
            $0.coverImageID = "c"
            $0.genres = ["Platform"]; $0.themes = ["Action"]
            $0.gameModes = ["Single player"]; $0.playerPerspectives = ["Side view"]
            $0.developers = ["Dev"]; $0.publishers = ["Pub"]
            $0.franchise = "F"; $0.summary = "S"; $0.igdbSlug = "s"
        }

        let plan = MetadataRefresh.plan(for: [fillable, unmatched, complete])

        #expect(plan.fillable.map(\.name) == ["Has an id, missing a date"])
        #expect(plan.unmatched.map(\.name) == ["No id at all"])
        #expect(plan.complete == 1)
        #expect(plan.missingCounts[.releaseDate] == 2)
    }

    /// A game without an `igdbID` is counted, never matched by title. Guessing
    /// between two games that share a name is what put The Messenger on a
    /// different game from 2000.
    @Test func gamesWithoutAnIDAreNeverPutInTheWorkList() {
        let repo = self.repo()
        let nameless = repo.addGame(name: "The Messenger")

        let plan = MetadataRefresh.plan(for: [nameless])

        #expect(plan.fillable.isEmpty)
        #expect(plan.unmatched.count == 1)
    }

    /// Deletion is soft here, so a row on its way out must not cost a lookup.
    @Test func deletedGamesAreNotWork() {
        let repo = self.repo()
        let gone = repo.addGame(name: "Deleted")
        repo.edit(gone) { $0.igdbID = 42; $0.deletedAt = .now }

        let plan = MetadataRefresh.plan(for: [gone])

        #expect(plan.isEmpty)
        #expect(plan.unmatched.isEmpty)
        #expect(plan.complete == 0)
    }

    @Test func reportableCountsLeadWithReleaseDatesAndDropZeroes() {
        let repo = self.repo()
        let game = repo.addGame(name: "Missing everything")
        repo.edit(game) { $0.igdbID = 42 }

        let counts = MetadataRefresh.plan(for: [game]).reportableCounts

        #expect(counts.first?.0 == .releaseDate)
        #expect(counts.allSatisfy { $0.1 > 0 })
    }

    // MARK: Quota arithmetic

    /// The proxy allows 60 requests per minute per install. A per-game loop
    /// would have cost 164 requests for Tim's library; batching costs four.
    @Test func awholeLibraryFitsInAHandfulOfRequests() {
        let library = Array(1...164)

        let chunks = MetadataRefresh.chunks(of: library)

        #expect(chunks.count == 4)
        #expect(chunks.map(\.count) == [50, 50, 50, 14])
        #expect(chunks.flatMap { $0 }.count == 164)
    }

    /// Two library rows can point at one IGDB id — sync duplicates, or the same
    /// game held on two platforms. Paying twice for one answer is the single
    /// thing a quota-bounded pass must not do.
    @Test func duplicateIDsCostOneLookupNotTwo() {
        let chunks = MetadataRefresh.chunks(of: [7, 7, 7, 9])

        #expect(chunks == [[7, 9]])
    }

    @Test func chunkingIsStableAndSorted() {
        #expect(MetadataRefresh.chunks(of: [3, 1, 2], size: 2) == [[1, 2], [3]])
        #expect(MetadataRefresh.chunks(of: []) == [])
    }

    /// Past the per-run budget, the rest is deferred rather than dropped —
    /// and reported, so "done" never means "gave up quietly".
    @Test func aLibraryPastTheBudgetIsDeferredNotDropped() {
        let over = MetadataRefresh.Budget.maxGamesPerRun + 137
        let (run, deferred) = MetadataRefresh.scheduledChunks(of: Array(1...over))

        #expect(run.count == MetadataRefresh.Budget.maxChunksPerRun)
        #expect(deferred == 137)
        #expect(run.flatMap { $0 }.count + deferred == over)
    }

    @Test func anOrdinaryLibraryDefersNothing() {
        let (run, deferred) = MetadataRefresh.scheduledChunks(of: Array(1...164))

        #expect(run.count == 4)
        #expect(deferred == 0)
    }

    /// One run's worth of requests has to leave the app able to search for the
    /// next thing the user adds — the same proxy backs Add Game — and someone
    /// who taps it repeatedly must not burn the day's allowance either.
    @Test func onerunStaysWellInsideTheProxysAllowances() {
        let perMinuteLimit = 60          // igdb-proxy: { install, 60s, 60 }
        let perDayLimit = 2_000          // igdb-proxy: { install, 86400s, 2000 }
        let budget = MetadataRefresh.Budget.maxChunksPerRun

        // At most a third of a minute's requests, so a run never rate-limits
        // the search box behind it.
        #expect(budget * 3 <= perMinuteLimit)
        // Ten full runs in one day still leave 90% of the daily allowance.
        #expect(budget * 10 <= perDayLimit / 10)
    }

    /// The point of batching: one run's request budget has to cover a whole
    /// library in a single pass, or "resumable" turns into "run it five times".
    @Test func onerunCoversFarMoreThanARealLibrary() {
        #expect(MetadataRefresh.Budget.maxGamesPerRun >= 1_000)
    }

    /// The proxy rejects queries over 2,000 characters outright, so a chunk
    /// size that outgrew the cap would fail the whole run rather than degrade.
    /// Checked against a real query built from seven-digit ids, not an estimate.
    @Test func afullChunkQueryFitsUnderTheProxysCap() {
        let proxyQueryCap = 2_000        // igdb-proxy: MAX_QUERY_LENGTH
        let proxyBodyCap = 4_000         // igdb-proxy: maxBodyBytes
        let wideIDs = (0..<MetadataRefresh.Budget.chunkSize).map { 9_000_000 + $0 }

        let query = IGDBService.idQuery(wideIDs)

        #expect(query.count < proxyQueryCap)
        #expect(query.utf8.count < proxyBodyCap)
    }

    /// IGDB defaults to ten results. Without an explicit limit a chunk of fifty
    /// silently returns ten, and the other forty look like ids IGDB has never
    /// heard of — a wrong "needs a re-match" on forty games.
    @Test func themultiIDQueryAsksForAsManyResultsAsItSendsIDs() {
        let query = IGDBService.idQuery([1, 2, 3])

        #expect(query.contains("where id = (1,2,3);"))
        #expect(query.hasSuffix("limit 3;"))
    }

    // MARK: The run

    /// Nothing to do means nothing is asked of the network.
    @Test func acompleteLibraryMakesNoRequests() async {
        let repo = self.repo()
        let game = repo.addGame(name: "Nothing missing")
        repo.edit(game) {
            $0.igdbID = 7
            $0.firstReleaseDate = Date(timeIntervalSince1970: 1_000_000_000)
            $0.coverImageID = "c"
            $0.genres = ["Platform"]; $0.themes = ["Action"]
            $0.gameModes = ["Single player"]; $0.playerPerspectives = ["Side view"]
            $0.developers = ["Dev"]; $0.publishers = ["Pub"]
            $0.franchise = "F"; $0.summary = "S"; $0.igdbSlug = "s"
        }

        let result = await repo.fillMissingMetadata(in: [game])

        #expect(result.chunksRun == 0)
        #expect(result.gamesAttempted == 0)
        #expect(!result.didAnything)
    }

    /// A run that fetched nothing has to say WHY. Every one of these used to
    /// collapse into a bare "a batch failed", which reads as "IGDB had nothing
    /// for you" and sends someone off to re-check their library instead of
    /// waiting a minute for a quota window to roll over.
    @Test func everyProxyFailureIsToldApart() {
        #expect(IGDBError.rateLimited != IGDBError.unavailable)
        #expect(IGDBError.rejected(status: 500) != IGDBError.rejected(status: 502))
        #expect(IGDBError.offline != IGDBError.malformed)
    }

    /// Rate limiting is the one failure worth stopping the run for: the quota
    /// is per install and per minute, so the remaining chunks would each spend
    /// a request to be refused — burning more of the allowance that is already
    /// gone, and pushing the window that has to roll over further out.
    @Test func rateLimitingIsTheFailureThatShouldStopARun() {
        // The behaviour lives in the run loop; this pins the decision itself
        // so a future edit can't quietly downgrade it to "keep trying".
        let stopsTheRun: (IGDBError) -> Bool = { $0 == .rateLimited }

        #expect(stopsTheRun(.rateLimited))
        #expect(!stopsTheRun(.offline))
        #expect(!stopsTheRun(.malformed))
        #expect(!stopsTheRun(.rejected(status: 502)))
    }

    /// A library of nothing but unmatchable games still makes no request, and
    /// still reports why it did nothing.
    @Test func alibraryWithNoIDsReportsRatherThanGuessing() async {
        let repo = self.repo()
        let game = repo.addGame(name: "No id at all")

        let result = await repo.fillMissingMetadata(in: [game])

        #expect(result.chunksRun == 0)
        #expect(result.unmatched == 1)
        #expect(!result.didAnything)
    }
}

/// The sheet must stop crying wolf: informational absences and
/// asked-and-answered games report without demanding lookups.
@MainActor
struct MetadataPlanNoiseTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    /// Fill a game with everything except franchise, so its only absence is
    /// the informational one.
    private func seriesless(_ repo: Repository, name: String) -> Game {
        let g = repo.addGame(name: name)
        g.igdbID = 7
        g.firstReleaseDate = Date(timeIntervalSince1970: 1_500_000_000)
        g.coverURLString = "https://example/cover.jpg"
        g.genres = ["Platformer"]; g.themes = ["Action"]
        g.gameModes = ["Single player"]; g.playerPerspectives = ["Side view"]
        g.developers = ["Dev"]; g.publishers = ["Pub"]
        g.summary = "A game."
        g.igdbSlug = "a-game"
        return g
    }

    @Test func seriesAloneIsNotWork() {
        let repo = repo()
        let g = seriesless(repo, name: "No Series")
        let plan = MetadataRefresh.plan(for: [g])
        #expect(plan.fillable.isEmpty)
        #expect(plan.informationalOnly == 1)
        // Still reported — as an informational count, not a missing one.
        #expect(plan.informationalCounts.contains { $0.0 == .franchise && $0.1 == 1 })
        #expect(!plan.reportableCounts.contains { $0.0 == .franchise })
    }

    @Test func recentlyCheckedGamesRest() {
        let repo = repo()
        let g = repo.addGame(name: "Asked Already")
        g.igdbID = 9   // genuinely missing lots — but IGDB said nothing last week
        let plan = MetadataRefresh.plan(
            for: [g],
            checked: [g.id: Date(timeIntervalSinceNow: -7 * 24 * 3600)])
        #expect(plan.fillable.isEmpty)
        #expect(plan.recentlyChecked == 1)
    }

    @Test func staleAnswersGetReAsked() {
        let repo = repo()
        let g = repo.addGame(name: "Stale Answer")
        g.igdbID = 9
        let plan = MetadataRefresh.plan(
            for: [g],
            checked: [g.id: Date(timeIntervalSinceNow: -45 * 24 * 3600)])
        #expect(plan.fillable.count == 1)
        #expect(plan.recentlyChecked == 0)
    }

    @Test func checkedStoreRoundTripsAndClears() {
        let defaults = UserDefaults(suiteName: "metadata-checked-tests-\(UUID().uuidString)")!
        let store = MetadataCheckedStore(defaults: defaults)
        let id = UUID()
        store.markChecked([id])
        #expect(store.all()[id] != nil)
        store.clear(id)
        #expect(store.all()[id] == nil)
    }
}

/// Fix Match replaces the fetched layer and only the fetched layer.
@MainActor
struct FixMatchTests {

    @Test func rematchReplacesFetchedAndPreservesTyped() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "My Name For It", status: .playing)
        game.igdbID = 111
        game.genres = ["Wrong Genre"]
        game.summary = "The wrong game's story."
        game.franchise = "Wrong Series"
        game.rating = 5
        game.notes = "my notes"
        game.userTags = ["cozy"]
        game.platforms = ["Super Nintendo Entertainment System"]

        let right = IGDBGame(
            id: 222, name: "The Right Game", slug: "the-right-game",
            coverImageID: "co999", franchise: nil, releaseYear: 1994,
            summary: "The right story.", gameType: nil,
            platforms: ["SNES"], genres: ["Platformer"], themes: ["Action"],
            gameModes: ["Single player"], playerPerspectives: ["Side view"],
            developers: ["Dev"], publishers: ["Pub"])

        repo.rematch(game, to: right)

        // Fetched layer: replaced — including clearing what the new game lacks.
        #expect(game.igdbID == 222)
        #expect(game.genres == ["Platformer"])
        #expect(game.summary == "The right story.")
        #expect(game.franchise == nil)
        // Typed layer: untouched.
        #expect(game.name == "My Name For It")
        #expect(game.rating == 5)
        #expect(game.notes == "my notes")
        #expect(game.userTags == ["cozy"])
        #expect(game.platforms == ["Super Nintendo Entertainment System"])
    }
}

/// The shuffle pool's filter: what the die may land on.
struct ShufflePoolTests {

    private func pool() -> [WidgetPoolGame] {
        [
            .init(id: "a", name: "A", coverFileName: nil, statusRaw: "playing", platform: "Switch"),
            .init(id: "b", name: "B", coverFileName: nil, statusRaw: "backlog", platform: "Genesis"),
            .init(id: "c", name: "C", coverFileName: nil, statusRaw: "completed", platform: "Genesis"),
            .init(id: "d", name: "D", coverFileName: nil, statusRaw: "shelved", platform: "SNES"),
        ]
    }

    @Test func statusesGate() {
        let picked = WidgetPoolGame.filter(pool(), statuses: ["playing", "backlog"],
                                           platform: nil, includeCompleted: false)
        #expect(Set(picked.map(\.id)) == ["a", "b"])
    }

    @Test func completedJoinsOnlyByToggle() {
        let without = WidgetPoolGame.filter(pool(), statuses: ["backlog"],
                                            platform: nil, includeCompleted: false)
        #expect(!without.contains { $0.id == "c" })
        let with = WidgetPoolGame.filter(pool(), statuses: ["backlog"],
                                         platform: nil, includeCompleted: true)
        #expect(with.contains { $0.id == "c" })
    }

    @Test func platformScopes() {
        let genesis = WidgetPoolGame.filter(pool(), statuses: ["backlog"],
                                            platform: "Genesis", includeCompleted: true)
        #expect(Set(genesis.map(\.id)) == ["b", "c"])
        let any = WidgetPoolGame.filter(pool(), statuses: ["backlog"],
                                        platform: nil, includeCompleted: true)
        #expect(any.count == 2)
    }
}

/// Goal 3's honesty tail, pinned.
@MainActor
struct HonestyTailTests {

    private func repo() -> (Repository, ModelContext) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        return (Repository(context), context)
    }

    // MARK: One progress calculator

    /// Counted items are binary (the counter flips `completed` at target),
    /// hidden items always count toward the total. Change this HERE, in one
    /// place, deliberately — never in one of the three former copies.
    @Test func tallySemanticsPinned() {
        let items = [
            TrackerItemDTO(id: "plain", name: "Boss", itemDescription: nil, location: nil,
                           missable: false, hideUntilDiscovered: false, maxRank: nil,
                           rankNames: nil, display: nil),
            TrackerItemDTO(id: "hidden", name: "Secret", itemDescription: nil, location: nil,
                           missable: false, hideUntilDiscovered: true, maxRank: nil,
                           rankNames: nil, display: nil),
            TrackerItemDTO(id: "counter", name: "Koroks", itemDescription: nil, location: nil,
                           missable: false, hideUntilDiscovered: false, maxRank: nil,
                           rankNames: nil, display: nil),
        ]
        let done: Set<String> = ["plain"]
        let tally = TrackerProgress.tally(items: items) { done.contains($0) }
        #expect(tally.done == 1)
        #expect(tally.total == 3)   // hidden + counter both in the denominator
        #expect(abs(tally.percent - 33.3) < 1)
    }

    @Test func emptySchemaIsZeroNotStale() {
        #expect(TrackerProgress.tally(items: []) { _ in true } == .init(done: 0, total: 0))
        #expect(TrackerProgress.tally(items: []) { _ in true }.percent == 0)
    }

    // MARK: Provenance

    @Test func raOnlySchemaGetsRepairedToImported() {
        let (repo, _) = repo()
        let game = repo.addGame(name: "Super Metroid")
        let schema = """
        {"schemaVersion":1,"categories":[
          {"id":"retroachievements","name":"Achievements","raGameID":1103,
           "items":[{"id":"a1","name":"Ridley"}]}
        ]}
        """
        // The old ingest path: stamped as if Claude made it.
        repo.setGeneratedSchema(for: game, jsonData: Data(schema.utf8))
        #expect(game.trackerSchema?.source == .aiGenerated)

        repo.reconcile(game)
        #expect(game.trackerSchema?.source == .imported)
        #expect(game.trackerSchema?.generatedBy == "retroachievements")
    }

    @Test func mixedSchemaStaysGenerated() {
        let (repo, _) = repo()
        let game = repo.addGame(name: "Hollow Knight")
        let schema = """
        {"schemaVersion":1,"categories":[
          {"id":"retroachievements","name":"Achievements","raGameID":9,
           "items":[{"id":"a1","name":"X"}]},
          {"id":"bosses","name":"Bosses","items":[{"id":"b1","name":"Hornet"}]}
        ]}
        """
        repo.setGeneratedSchema(for: game, jsonData: Data(schema.utf8))
        repo.reconcile(game)
        #expect(game.trackerSchema?.source == .aiGenerated)
    }

    @Test func importedIngestStampsHonestly() {
        let (repo, _) = repo()
        let game = repo.addGame(name: "Castlevania")
        let schema = """
        {"schemaVersion":1,"categories":[
          {"id":"retroachievements","name":"Achievements","raGameID":7,
           "items":[{"id":"a1","name":"Whip"}]}
        ]}
        """
        repo.applyGeneratedSchema(for: game, jsonData: Data(schema.utf8),
                                  mode: .addAll, source: .imported,
                                  attribution: "retroachievements")
        #expect(game.trackerSchema?.source == .imported)
        #expect(game.trackerSchema?.generatedBy == "retroachievements")
    }

    // MARK: Applicability

    @Test func applicabilityRoundTripsAndClears() {
        let (repo, _) = repo()
        let game = repo.addGame(name: "Skyrim")
        repo.setGeneratedSchema(for: game, jsonData: Data(
            #"{"schemaVersion":1,"categories":[]}"#.utf8))

        repo.setApplicability(
            .init(platform: "Switch", edition: "Anniversary", notes: "no Creations"),
            for: game)
        var read = TrackerSchemaJSON.applicability(in: game.trackerSchema!.jsonData)
        #expect(read.platform == "Switch")
        #expect(read.summary == "Switch · Anniversary · no Creations")

        repo.setApplicability(.init(), for: game)
        read = TrackerSchemaJSON.applicability(in: game.trackerSchema!.jsonData)
        #expect(read.isEmpty)
    }
}

/// The deletion safety net: restore is one field, forever is really forever.
@MainActor
struct RecentlyDeletedTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @Test func softDeletedGameIsListedAndRestores() {
        let repo = repo()
        let game = repo.addGame(name: "Under the Island", status: .playing)
        repo.softDelete(game)
        #expect(repo.trashedGames().map(\.id) == [game.id])

        repo.restore(game)
        #expect(repo.trashedGames().isEmpty)
        #expect(game.deletedAt == nil)
    }

    @Test func deleteForeverCascadesChildren() {
        let repo = repo()
        let game = repo.addGame(name: "Doomed", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        _ = repo.startRun(on: pt, fields: [:])
        repo.softDelete(game)

        repo.deleteForever(game)
        #expect(repo.trashedGames().isEmpty)
        // The cascade took the playthrough (and its run) with it.
        let strays = try? repo.context.fetch(FetchDescriptor<Playthrough>())
        #expect(strays?.contains { $0.id == pt.id } != true)
    }

    /// A playthrough inside a trashed game rides the game's restore — it
    /// must not be offered separately into a trashed parent.
    @Test func playthroughInsideTrashedGameIsNotListed() {
        let repo = repo()
        let game = repo.addGame(name: "Nested", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.deletePlaythrough(pt, from: game)
        #expect(repo.trashedPlaythroughs().map(\.id) == [pt.id])

        repo.softDelete(game)
        #expect(repo.trashedPlaythroughs().isEmpty)
    }
}

/// Export → import round trip: the restore point the export always claimed
/// to be. Additive-by-id is the invariant every test leans on.
@MainActor
struct LibraryImportTests {

    private func populated() throws -> (Repository, Data) {
        let repo = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        game.rating = 5
        game.userTags = ["metroidvania"]
        let pt = repo.ensureDefaultPlaythrough(for: game)
        _ = repo.logManualSession(on: pt, duration: 3600,
                                  date: Date(timeIntervalSince1970: 1_755_000_000))
        _ = repo.startRun(on: pt, fields: ["weapon": "Nail"])
        repo.setGeneratedSchema(for: game, jsonData: Data(
            #"{"schemaVersion":1,"categories":[{"id":"bosses","name":"Bosses","items":[{"id":"b1","name":"Hornet"}]}]}"#.utf8))
        repo.setTrackerItem(pt, itemID: "b1", done: true)
        _ = repo.createCollection(name: "Comfort")
        let data = try LibraryExport.makeJSON(context: repo.context)
        return (repo, data)
    }

    @Test func roundTripRestoresIntoEmptyLibrary() throws {
        let (_, data) = try populated()
        let fresh = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))

        let preview = try LibraryImport.preview(data: data, context: fresh.context)
        #expect(preview.totalSkips == 0)
        #expect(preview.creates["games"] == 1)
        #expect(preview.problems.isEmpty)

        let outcome = try LibraryImport.apply(data: data, context: fresh.context)
        #expect(outcome.created["games"] == 1)
        #expect(outcome.created["playthroughs"] == 1)
        #expect(outcome.created["sessions"] == 1)
        #expect(outcome.created["runs"] == 1)
        #expect(outcome.created["tracker schemas"] == 1)
        #expect(outcome.created["tracker progress"] == 1)
        #expect(outcome.created["collections"] == 1)

        let games = try fresh.context.fetch(FetchDescriptor<Game>())
        let game = try #require(games.first)
        #expect(game.name == "Hollow Knight")
        #expect(game.rating == 5)
        #expect(game.userTags == ["metroidvania"])
        // Progress recomputed from restored state: 1/1 bosses done.
        #expect(game.activePlaythrough?.progressPercent == 100)
    }

    /// Running it twice is a no-op — the restore point can't duplicate.
    @Test func importIsIdempotent() throws {
        let (_, data) = try populated()
        let fresh = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        _ = try LibraryImport.apply(data: data, context: fresh.context)
        let second = try LibraryImport.apply(data: data, context: fresh.context)
        #expect(second.totalCreated == 0)
        #expect(try fresh.context.fetch(FetchDescriptor<Game>()).count == 1)
    }

    /// Partial disaster: the missing piece comes back, everything present is
    /// untouched — including field values that have since changed.
    @Test func importRestoresOnlyWhatsMissing() throws {
        let (repo, data) = try populated()
        // "Disaster": the collection vanishes; the game's rating changes.
        let collection = try #require(repo.context.fetch(
            FetchDescriptor<GameCollection>()).first)
        repo.context.delete(collection)
        let game = try #require(repo.context.fetch(FetchDescriptor<Game>()).first)
        game.rating = 2
        try repo.context.save()

        let outcome = try LibraryImport.apply(data: data, context: repo.context)
        #expect(outcome.created["collections"] == 1)
        #expect(outcome.created["games"] == nil)
        // Present record untouched: the changed rating survives the import.
        #expect(game.rating == 2)
    }

    @Test func wrongVersionAndGarbageAreRefused() throws {
        let fresh = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let wrongVersion = Data(#"{"manifest":{"formatVersion":99},"games":[]}"#.utf8)
        #expect(throws: LibraryImport.ImportError.self) {
            try LibraryImport.preview(data: wrongVersion, context: fresh.context)
        }
        #expect(throws: LibraryImport.ImportError.self) {
            try LibraryImport.preview(data: Data("not json".utf8), context: fresh.context)
        }
        #expect(throws: LibraryImport.ImportError.self) {
            try LibraryImport.preview(data: Data(#"{"games":[]}"#.utf8), context: fresh.context)
        }
    }
}
