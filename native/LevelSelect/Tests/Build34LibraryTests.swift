import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 34 — Library's identity pass: ownership becomes something you can
/// browse rather than a line in a menu, and the systems shelf leads somewhere.
@MainActor
struct Build34LibraryTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// A complete IGDB answer, so anything left unfilled is the fill's
    /// decision rather than a gap in the source.
    private func igdbAnswer(id: Int, name: String, platforms: [String]) -> IGDBGame {
        IGDBGame(id: id, name: name, slug: "slug", coverImageID: "co1abc",
                 franchise: nil, releaseYear: 2018, summary: "A game.",
                 gameType: 0, platforms: platforms, genres: ["Platform"],
                 themes: ["Action"], gameModes: ["Single player"],
                 playerPerspectives: ["Side view"], developers: ["Dev"],
                 publishers: ["Pub"])
    }

    // MARK: Ownership facets

    /// The case that made ownership worth putting on screen, in Tim's words:
    /// *"I both own a Sega Genesis and emulate Sega Genesis for the games I
    /// don't own physically."* Both facts are true of one game, so it is
    /// counted under both — and the counts deliberately do not sum to the
    /// size of the library.
    @Test func aGameOwnedTwoWaysIsCountedUnderBoth() {
        let context = makeContext()
        let repo = Repository(context)

        let sonic = repo.addGame(name: "Sonic the Hedgehog 2")
        sonic.ownership = [Ownership.physical.rawValue, Ownership.emulated.rawValue]
        let chrono = repo.addGame(name: "Chrono Trigger")
        chrono.ownership = [Ownership.emulated.rawValue]
        let hades = repo.addGame(name: "Hades")
        hades.ownership = [Ownership.digital.rawValue]

        let counts = OwnershipFacet.counts([sonic, chrono, hades])

        #expect(counts.byKind[.physical] == 1)
        #expect(counts.byKind[.emulated] == 2)
        #expect(counts.byKind[.digital] == 1)
        // Four chip-counts over three games. Overlap, not double-counting.
        #expect(counts.byKind.values.reduce(0, +) == 4)
        #expect(counts.unset == 0)
    }

    /// A kind nobody has recorded gets no count, which is what hides its chip
    /// — a row of four chips where three read zero is a row of dead ends.
    @Test func anUnusedOwnershipHasNoCount() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Balatro")
        game.ownership = [Ownership.digital.rawValue]

        let counts = OwnershipFacet.counts([game])

        #expect(counts.byKind[.digital] == 1)
        #expect(counts.byKind[.previouslyOwned] == nil)
        #expect(counts.byKind[.physical] == nil)
    }

    /// Ownership is not sentiment (08-31): "previously owned" is a fact about
    /// a copy, and it counts like any other rather than being filtered out of
    /// the library the way the wishlist is.
    @Test func previouslyOwnedCountsLikeAnyOtherKind() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Chrono Trigger")
        game.ownership = [Ownership.previouslyOwned.rawValue]

        #expect(OwnershipFacet.counts([game]).byKind[.previouslyOwned] == 1)
    }

    // MARK: The gap

    /// Found on Tim's real library 08-31: 143 of 160 games had no ownership
    /// recorded, so the axis was browsing a tenth of the shelf. The gap gets
    /// counted like anything else, and it is the number that makes the row
    /// worth its space until the field fills in.
    @Test func gamesWithNoOwnershipAreCountedAsTheGap() {
        let context = makeContext()
        let repo = Repository(context)

        let sonic = repo.addGame(name: "Sonic the Hedgehog 2")
        sonic.ownership = [Ownership.emulated.rawValue]
        let blank = repo.addGame(name: "Tunic")
        let alsoBlank = repo.addGame(name: "Celeste")

        let counts = OwnershipFacet.counts([sonic, blank, alsoBlank])
        #expect(counts.unset == 2)
        #expect(counts.byKind[.emulated] == 1)
    }

    /// A game with an ownership is never also part of the gap — the two are
    /// exclusive, unlike the four kinds, which overlap freely.
    @Test func theGapAndTheKindsDoNotOverlap() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Hades")
        game.ownership = [Ownership.digital.rawValue, Ownership.physical.rawValue]

        let counts = OwnershipFacet.counts([game])
        #expect(counts.unset == 0)
        #expect(counts.byKind[.digital] == 1)
        #expect(counts.byKind[.physical] == 1)
    }

    /// Tapping the gap chip has to select exactly the games that need fixing.
    @Test func theGapFilterSelectsOnlyGamesWithNothingRecorded() {
        let context = makeContext()
        let repo = Repository(context)

        let owned = repo.addGame(name: "Balatro")
        owned.ownership = [Ownership.digital.rawValue]
        let blank = repo.addGame(name: "Tunic")

        #expect(OwnershipFilter.unset.matches(blank))
        #expect(!OwnershipFilter.unset.matches(owned))
        #expect(OwnershipFilter.kind(.digital).matches(owned))
        #expect(!OwnershipFilter.kind(.digital).matches(blank))
    }

    /// "Previously owned" is a recorded fact, not an absence — selling a game
    /// is something you said, and it must not fall into the gap.
    @Test func previouslyOwnedIsNotAGap() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Chrono Trigger")
        game.ownership = [Ownership.previouslyOwned.rawValue]

        #expect(!OwnershipFilter.unset.matches(game))
        #expect(OwnershipFacet.counts([game]).unset == 0)
    }

    // MARK: The console page

    /// The tile said "Genesis 1" under an Emulated filter and the page it
    /// opened listed every Genesis game — the count and the page disagreeing
    /// about the same word. The route carries the filter now.
    @Test func theConsolePageShowsWhatItsTileCounted() {
        let context = makeContext()
        let repo = Repository(context)

        let sonic = repo.addGame(name: "Sonic the Hedgehog 2")
        sonic.platforms = ["Sega Genesis"]
        sonic.ownership = [Ownership.emulated.rawValue]
        let shining = repo.addGame(name: "Shining Force")
        shining.platforms = ["Sega Genesis"]
        shining.ownership = [Ownership.physical.rawValue]

        let platform = PlatformPreference.owned(sonic.platforms) ?? "Other"
        let emulated = [sonic, shining].filter {
            PlatformRoute.matches($0, platform: platform, ownership: .kind(.emulated))
        }
        #expect(emulated.map(\.name) == ["Sonic the Hedgehog 2"])

        // And with no filter — Home's case — the console keeps all its games.
        let all = [sonic, shining].filter {
            PlatformRoute.matches($0, platform: platform, ownership: nil)
        }
        #expect(all.count == 2)
    }

    /// Home appends the route without an ownership, so adding the field must
    /// not change what Home's shelf opens.
    @Test func aRouteWithNoOwnershipIsTheUnfilteredOne() {
        #expect(PlatformRoute(platform: "Sega Genesis").ownership == nil)
        #expect(PlatformRoute(platform: "Sega Genesis")
                == PlatformRoute(platform: "Sega Genesis", ownership: nil))
    }

    // MARK: Systems are the ones you own on

    /// Crypt of the NecroDancer lists eight platforms and Tim owns it on one.
    /// The filter menu was built from every platform every game was released
    /// for, so it offered Linux, Vita and PS2 — systems he has never owned a
    /// game on — in a list headed by his own library. The shelf beside it had
    /// always counted the owned platform only, so the two disagreed on screen.
    @Test func theSystemsListIsWhatYouOwnOnNotWhatExists() {
        let context = makeContext()
        let repo = Repository(context)

        let necrodancer = repo.addGame(name: "Crypt of the NecroDancer")
        // Position zero is the platform chosen when adding — see
        // PlatformPreference.owned. The rest is IGDB's availability list.
        necrodancer.platforms = ["Nintendo Switch", "PlayStation 4", "Linux",
                                 "PC (Microsoft Windows)", "Mac", "PlayStation Vita"]

        let systems = PlatformShort.systems(in: [necrodancer.platforms].compactMap {
            PlatformPreference.owned($0).map { [$0] }
        })
        #expect(systems.map(\.short) == ["Switch"])
    }

    /// And the filter has to agree with that list: picking a system you merely
    /// COULD have played it on must not return the game.
    @Test func filteringByASystemYouDoNotOwnItOnFindsNothing() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Crypt of the NecroDancer")
        game.platforms = ["Nintendo Switch", "Linux", "PlayStation Vita"]

        #expect(PlatformShort.ownedMatches(game.ownedPlatformNames, short: "Switch"))
        #expect(!PlatformShort.ownedMatches(game.ownedPlatformNames, short: "Linux"))
        #expect(!PlatformShort.ownedMatches(game.ownedPlatformNames, short: "Vita"))

        // `matches` still answers the availability question, for callers that
        // genuinely mean it.
        #expect(PlatformShort.matches(game.platforms, short: "Linux"))
    }

    /// A game with no platforms at all is nobody's system.
    @Test func aGameWithNoPlatformsMatchesNoSystem() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Some Jam Game")
        game.platforms = []

        #expect(!PlatformShort.ownedMatches(game.ownedPlatformNames, short: "Switch"))
    }

    /// PS2 must be tested BEFORE the bare "playstation" check, or it falls
    /// into PS1 exactly the way Series X|S fell into the original Xbox. Vita
    /// contains "playstation" too and has the same trap.
    @Test func eachPlayStationGenerationGetsItsOwnIcon() {
        #expect(PlatformIcon.assetName("PlayStation 2") == "platform-ps2")
        #expect(PlatformIcon.assetName("PS2") == "platform-ps2")
        #expect(PlatformIcon.assetName("PlayStation Vita") == "platform-vita")
        #expect(PlatformIcon.assetName("PlayStation") == "platform-ps1")
        #expect(PlatformIcon.assetName("PlayStation 3") == "platform-ps3")
        #expect(PlatformIcon.assetName("PlayStation 5") == "platform-ps5")
    }

    /// Valve's living-room box. "Steam Machine" must not collapse into the
    /// PC icon — that test is an exact match on "steam", not a substring, but
    /// pinning it keeps the next edit honest.
    @Test func steamMachineIsItsOwnThing() {
        #expect(PlatformIcon.assetName("Steam Machine") == "platform-steammachine")
        #expect(PlatformIcon.assetName("Steam Deck") == "platform-steamdeck")
        #expect(PlatformIcon.assetName("Steam") == "platform-pc")
    }

    /// Linux is not a device, so it gets the mascot — the only unambiguous
    /// signifier, and Steam Deck already has its own platform and icon.
    @Test func linuxGetsAnIcon() {
        #expect(PlatformIcon.assetName("Linux") == "platform-linux")
    }

    /// `platform-xbox-series` art shipped but was unreachable: bare "xbox"
    /// sat above "xbox series" in a chain of substring matches, so every
    /// Series X|S drew the 2001 original's console.
    @Test func eachXboxGenerationGetsItsOwnIcon() {
        #expect(PlatformIcon.assetName("Xbox Series X|S") == "platform-xbox-series")
        #expect(PlatformIcon.assetName("Xbox 360") == "platform-xbox360")
        #expect(PlatformIcon.assetName("Xbox One") == "platform-xbox")
        #expect(PlatformIcon.assetName("Xbox") == "platform-xbox")
    }

    // MARK: Library's defaults and layouts

    /// Status-first opened the page on "Backlog (98)" — the pile, not the
    /// connection. The default is the games you actually touch.
    @Test func libraryOpensOnWhatYouHavePlayed() {
        #expect(LibrarySort(rawValue: LibrarySort.recentlyPlayed.rawValue) == .recentlyPlayed)
        #expect(LibraryViewMode.allCases.map(\.rawValue) == ["grid", "list", "shelves"])
    }

    /// Swift's sort is not stable, and most of a library has never been
    /// played — so without a second key those games shuffle between renders.
    /// Now that recently-played is the DEFAULT, that is most of what you see.
    @Test func neverPlayedGamesHoldAStableOrder() {
        let context = makeContext()
        let repo = Repository(context)
        let names = ["Tunic", "Celeste", "Animal Well", "Hades", "Balatro"]
        let games = names.map { repo.addGame(name: $0) }

        // Same key for every one of them — the tie the comparator must break.
        let keyed = games.map { ($0, Date.distantPast) }
        let sorted = keyed.sorted { ($0.1, $1.0.name) > ($1.1, $0.0.name) }.map(\.0.name)

        #expect(sorted == names.sorted())
    }

    // MARK: Recently beaten

    /// Beating a game moved it out of Now Playing and Home said nothing —
    /// the one moment the app is pointed at produced a disappearance.
    @Test func aGameBeatenThisWeekShowsOnHome() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Under the Island", status: .completed)
        let event = CompletionEvent(date: Date.now.addingTimeInterval(-2 * 86_400))
        event.game = game
        game.completionEvents = [event]
        context.insert(event)

        let beaten = RecentlyBeaten.games(from: [game])
        #expect(beaten.map { $0.game.name } == ["Under the Island"])
    }

    /// It empties itself. A finish from last year is a fact about a
    /// collection and belongs in Library's Finished shelf, not on Home.
    @Test func anOldFinishDoesNotLingerOnHome() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Chrono Trigger", status: .completed)
        let event = CompletionEvent(date: Date.now.addingTimeInterval(-400 * 86_400))
        event.game = game
        game.completionEvents = [event]
        context.insert(event)

        #expect(RecentlyBeaten.games(from: [game]).isEmpty)
    }

    /// Most recently finished first.
    @Test func recentFinishesAreOrderedNewestFirst() {
        let context = makeContext()
        let repo = Repository(context)

        let older = repo.addGame(name: "Older", status: .completed)
        let olderEvent = CompletionEvent(date: Date.now.addingTimeInterval(-20 * 86_400))
        olderEvent.game = older
        older.completionEvents = [olderEvent]
        context.insert(olderEvent)

        let newer = repo.addGame(name: "Newer", status: .completed)
        let newerEvent = CompletionEvent(date: Date.now.addingTimeInterval(-1 * 86_400))
        newerEvent.game = newer
        newer.completionEvents = [newerEvent]
        context.insert(newerEvent)

        #expect(RecentlyBeaten.games(from: [older, newer]).map { $0.game.name } == ["Newer", "Older"])
    }

    /// A deleted finish is not a finish.
    @Test func aDeletedCompletionDoesNotCount() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Tunic", status: .completed)
        let event = CompletionEvent(date: Date.now.addingTimeInterval(-86_400))
        event.game = game
        event.deletedAt = .now
        game.completionEvents = [event]
        context.insert(event)

        #expect(RecentlyBeaten.games(from: [game]).isEmpty)
    }

    // MARK: Refreshing platforms

    /// Cities: Skylines was added on Mac, knew about Mac and nothing else, and
    /// Refresh changed nothing — because refresh skipped `platforms` entirely
    /// to avoid clobbering position zero, which is the ownership record.
    @Test func refreshFillsInThePlatformsAGameShippedOn() {
        let merged = MetadataRefresh.mergedPlatforms(
            existing: ["Mac"],
            igdb: ["PC (Microsoft Windows)", "Mac", "PlayStation 4", "Xbox One", "Nintendo Switch"])

        // Yours stays first — every label and grouping reads position zero.
        #expect(merged.first == "Mac")
        #expect(merged.contains("Nintendo Switch"))
        #expect(merged.count == 5)
    }

    /// Your spelling wins on collision. "PC" and "PC (Microsoft Windows)" are
    /// one console, and two rows for one console is the exact bug
    /// `PlatformShort` exists to prevent.
    @Test func refreshDoesNotDuplicateAConsoleUnderTwoNames() {
        let merged = MetadataRefresh.mergedPlatforms(
            existing: ["PC"], igdb: ["PC (Microsoft Windows)", "Mac"])

        #expect(merged == ["PC", "Mac"])
    }

    /// Emulation and unlisted ports are real, and a refresh that quietly
    /// deleted them would punish the people most likely to press it.
    @Test func refreshKeepsPlatformsIGDBHasNeverHeardOf() {
        let merged = MetadataRefresh.mergedPlatforms(
            existing: ["Recalbox", "Mac"], igdb: ["Mac", "PC (Microsoft Windows)"])

        #expect(merged.first == "Recalbox")
        #expect(merged.contains("Mac"))
        #expect(merged.contains("PC (Microsoft Windows)"))
    }

    /// A game IGDB knows nothing about keeps whatever it has.
    @Test func aGameWithNoIGDBPlatformsIsLeftAlone() {
        #expect(MetadataRefresh.mergedPlatforms(existing: ["itch.io"], igdb: []) == ["itch.io"])
    }

    /// The fill now offers platforms, and the "mine" lock is what makes that
    /// safe: the merge may add, never move. Position zero is read everywhere
    /// as the platform you own.
    @Test func theLibraryFillNeverMovesThePlatformYouOwn() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Celeste")
        game.platforms = ["Mac"]
        game.igdbID = 7788

        #expect(MetadataRefresh.missingFields(of: game).contains(.platforms))

        let igdb = igdbAnswer(id: 7788, name: "Celeste",
                              platforms: ["Linux", "Mac", "Nintendo Switch",
                                          "PC (Microsoft Windows)", "PlayStation 4", "Xbox One"])
        let filled = MetadataRefresh.fill(game, from: igdb)

        #expect(filled.contains(.platforms))
        #expect(game.platforms.first == "Mac")
        #expect(game.platforms.contains("Nintendo Switch"))
        #expect(MetadataRefresh.missingFields(of: game).contains(.platforms) == false)
    }

    /// A one-platform exclusive merges to itself. Reporting that as filled
    /// would make the pass claim work it did not do — and the run's
    /// "asked and answered" bookkeeping is what stops it asking forever.
    @Test func anExclusiveIsNotReportedAsFilled() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Some Switch Exclusive")
        game.platforms = ["Nintendo Switch"]
        game.igdbID = 999

        let igdb = igdbAnswer(id: 999, name: "Some Switch Exclusive",
                              platforms: ["Nintendo Switch"])
        #expect(MetadataRefresh.fill(game, from: igdb).contains(.platforms) == false)
        #expect(game.platforms == ["Nintendo Switch"])
    }

    /// A game that already has a merged list is not offered as work.
    @Test func anAlreadyMergedListIsNotMissing() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Crypt of the NecroDancer")
        game.platforms = ["Nintendo Switch", "Linux", "PlayStation Vita"]

        #expect(MetadataRefresh.missingFields(of: game).contains(.platforms) == false)
    }

    // MARK: Owning a game on more than one console

    /// The limitation this field exists to remove. Ownership was position zero
    /// of `platforms`, and there is one index zero — so owning Hades on both
    /// Switch and PC was unrepresentable, and marking the second silently
    /// unmarked the first.
    @Test func aGameCanBeOwnedOnSeveralConsoles() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Hades")
        game.platforms = ["Nintendo Switch", "PC (Microsoft Windows)", "PlayStation 4"]
        game.ownedPlatforms = ["Nintendo Switch", "PC (Microsoft Windows)"]

        #expect(game.ownedPlatformNames.count == 2)
        #expect(PlatformShort.ownedMatches(game.ownedPlatformNames, short: "Switch"))
        #expect(PlatformShort.ownedMatches(game.ownedPlatformNames, short: "PC"))
        // Released on it, but not yours.
        #expect(!PlatformShort.ownedMatches(game.ownedPlatformNames, short: "PS4"))
    }

    /// The migration is the fallback, not a rewrite. Every game written before
    /// V3 has `ownedPlatforms == nil`, and position zero is exactly what the
    /// app meant by "mine" then — so nothing on disk has to change for old
    /// rows to read correctly.
    @Test func gamesFromBeforeTheSplitStillKnowWhatIsYours() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Cities: Skylines")
        game.platforms = ["Mac", "PC (Microsoft Windows)", "PlayStation 4"]
        game.ownedPlatforms = nil

        #expect(game.ownedPlatformNames == ["Mac"])
        #expect(game.primaryOwnedPlatform == "Mac")
        #expect(PlatformShort.ownedMatches(game.ownedPlatformNames, short: "Mac"))
        #expect(!PlatformShort.ownedMatches(game.ownedPlatformNames, short: "PC"))
    }

    /// An empty array is treated as "never recorded" too, not as "I own this
    /// on nothing" — a stored empty set would otherwise erase a pre-V3 game's
    /// only ownership record the first time the editor round-tripped it.
    @Test func anEmptyOwnedSetFallsBackRatherThanErasing() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Celeste")
        game.platforms = ["Mac", "Nintendo Switch"]
        game.ownedPlatforms = []

        #expect(game.ownedPlatformNames == ["Mac"])
    }

    /// A game with no platforms at all owns nothing, and must not crash or
    /// invent one.
    @Test func aGameWithNoPlatformsOwnsNothing() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Some Jam Game")
        game.platforms = []

        #expect(game.ownedPlatformNames.isEmpty)
        #expect(game.primaryOwnedPlatform == nil)
    }

    /// The console page shows a game you own on two consoles on BOTH pages.
    /// One game seen from two shelves, not a duplicate.
    @Test func aGameOwnedTwiceAppearsOnBothConsolePages() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Hades")
        game.platforms = ["Nintendo Switch", "PC (Microsoft Windows)"]
        game.ownedPlatforms = ["Nintendo Switch", "PC (Microsoft Windows)"]

        #expect(PlatformRoute.matches(game, platform: "Nintendo Switch", ownership: nil))
        #expect(PlatformRoute.matches(game, platform: "PC (Microsoft Windows)", ownership: nil))
    }

    /// Dropping a platform from the game must drop it from what you own on,
    /// or the shelf keeps counting a console the game no longer lists.
    @Test func removingAPlatformRemovesTheOwnershipToo() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Hades")
        game.platforms = ["Nintendo Switch", "PC (Microsoft Windows)"]
        game.ownedPlatforms = ["Nintendo Switch", "PC (Microsoft Windows)"]

        // What PlatformEditor's remove button does.
        game.platforms.removeAll { $0 == "PC (Microsoft Windows)" }
        game.ownedPlatforms?.removeAll { $0 == "PC (Microsoft Windows)" }

        #expect(game.ownedPlatformNames == ["Nintendo Switch"])
    }

    /// Alien: Isolation, from Tim's library: IGDB lists Switch first and Mac
    /// sixth, with four consoles he does not own in between — so the two chips
    /// that say something about HIM sat at opposite ends of two wrapped rows.
    @Test func theConsolesYouOwnComeFirst() {
        let all = ["Nintendo Switch", "PlayStation 3", "PlayStation 4", "Linux",
                   "PC (Microsoft Windows)", "Mac", "Xbox 360", "Xbox One"]
        let sorted = PlatformShort.ownedFirst(all, owned: ["Nintendo Switch", "Mac"])

        #expect(Array(sorted.prefix(2)) == ["Nintendo Switch", "Mac"])
        // Nothing gained, nothing lost, and the rest hold their order.
        #expect(sorted.count == all.count)
        #expect(Array(sorted.dropFirst(2)) == ["PlayStation 3", "PlayStation 4", "Linux",
                                               "PC (Microsoft Windows)", "Xbox 360", "Xbox One"])
    }

    /// Owning none of them leaves the list exactly as IGDB gave it.
    @Test func owningNothingChangesNothing() {
        let all = ["Nintendo Switch", "Mac"]
        #expect(PlatformShort.ownedFirst(all, owned: []) == all)
    }

    /// Sorting is display-only: the stored order still carries the pre-V3
    /// fallback, so it must not be disturbed.
    @Test func sortingDoesNotTouchTheStoredOrder() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Alien: Isolation")
        game.platforms = ["Nintendo Switch", "Mac"]
        game.ownedPlatforms = ["Mac"]

        _ = PlatformShort.ownedFirst(game.platforms, owned: game.ownedPlatformNames)
        #expect(game.platforms == ["Nintendo Switch", "Mac"])
    }

    // MARK: The menu bar

    /// ⌘1–⌘4 are assigned by tab-bar position, so the number pressed matches
    /// the position seen. If the tab order ever changes, the shortcuts follow
    /// it — this pins the order they are derived from.
    @Test func theTabsAreInTheOrderTheMenuNumbersThem() {
        #expect(LSTab.allCases == [.home, .library, .wishlist, .stats])
        #expect(LSTab.allCases.map(\.menuTitle) == ["Home", "Library", "Wishlist", "Stats"])
    }

    /// The menu lives outside the view tree that owns the sheets, so it raises
    /// a counter rather than setting a flag — pressing ⌘N twice has to open
    /// the sheet twice, and a Bool already true would swallow the second.
    @Test func repeatedMenuRequestsEachRegister() {
        let nav = AppNavigator.shared
        let before = nav.addGameRequest
        nav.requestAddGame()
        nav.requestAddGame()
        #expect(nav.addGameRequest == before + 2)
    }

    /// ⌘F focuses the field on the tab you are already on — Wishlist has its
    /// own search, and being thrown to Library mid-wishlist-search would be
    /// the wrong kind of helpful.
    @Test func findStaysOnATabThatHasItsOwnSearch() {
        let nav = AppNavigator.shared
        nav.selectedTab = .wishlist
        nav.requestSearch()
        #expect(nav.selectedTab == .wishlist)

        nav.selectedTab = .library
        nav.requestSearch()
        #expect(nav.selectedTab == .library)
    }

    /// From Home or Stats, which have no search at all, ⌘F goes to Library —
    /// so the shortcut always means "find a game" rather than sometimes
    /// meaning nothing.
    @Test func findGoesToLibraryFromATabWithNoSearch() {
        let nav = AppNavigator.shared
        for tab in [LSTab.home, .stats] {
            nav.selectedTab = tab
            nav.requestSearch()
            #expect(nav.selectedTab == .library)
        }
    }

    /// Both library commands move you to Library first: a collection created
    /// on a tab that cannot show it reads as the command having done nothing.
    @Test func theLibraryCommandsGoToLibraryFirst() {
        let nav = AppNavigator.shared
        nav.selectedTab = .stats
        nav.requestNewCollection()
        #expect(nav.selectedTab == .library)

        nav.selectedTab = .home
        nav.requestClearFilters()
        #expect(nav.selectedTab == .library)
    }
}
