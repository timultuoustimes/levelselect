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
