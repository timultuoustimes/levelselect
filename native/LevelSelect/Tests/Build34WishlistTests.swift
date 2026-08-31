import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 34 — the wishlist's identity: it is the app's only forward-looking
/// surface, and it was rendering as an undifferentiated grid.
@MainActor
struct Build34WishlistTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    /// The split that makes the tab itself: a game you could buy this
    /// afternoon and a game arriving in February are different kinds of
    /// wanting, and only one of them is waiting.
    @Test func unreleasedGamesLeadAndAreSortedSoonestFirst() {
        let context = makeContext()
        let repo = Repository(context)

        let later = repo.addGame(name: "Pragmata", status: .wishlist)
        later.firstReleaseDate = now.addingTimeInterval(300 * 86_400)
        let sooner = repo.addGame(name: "Resident Evil Requiem", status: .wishlist)
        sooner.firstReleaseDate = now.addingTimeInterval(60 * 86_400)
        let out = repo.addGame(name: "Killer7", status: .wishlist)
        out.firstReleaseDate = Date(timeIntervalSince1970: 1_100_000_000)

        let games = [later, sooner, out]
        #expect(WishlistShelf.comingSoon(games, now: now).map(\.name)
                == ["Resident Evil Requiem", "Pragmata"])
        #expect(WishlistShelf.outNow(games, now: now).map(\.name) == ["Killer7"])
    }

    /// The epoch artifact the CSV import left on a third of the library is a
    /// MISSING date, not an announcement — it must not be read as 1970 and
    /// filed under either heading incorrectly.
    @Test func theEpochArtifactIsNotAReleaseDate() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Imported Long Ago", status: .wishlist)
        game.firstReleaseDate = Date(timeIntervalSince1970: 0)

        #expect(WishlistShelf.comingSoon([game], now: now).isEmpty)
        // It is not "coming", so it belongs with everything else.
        #expect(WishlistShelf.outNow([game], now: now).map(\.name) == ["Imported Long Ago"])
    }

    /// "We don't know when" is not the same claim as "it's coming", and only
    /// one of those should sit under a heading promising a date.
    @Test func aGameWithNoDateIsNotComingSoon() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Unknown", status: .wishlist)
        game.firstReleaseDate = nil

        #expect(WishlistShelf.comingSoon([game], now: now).isEmpty)
        #expect(WishlistShelf.outNow([game], now: now).count == 1)
    }

    /// Every game lands in exactly one of the two sections — the grid must not
    /// drop one or show it twice.
    @Test func theTwoSectionsPartitionTheWishlist() {
        let context = makeContext()
        let repo = Repository(context)
        let a = repo.addGame(name: "Future", status: .wishlist)
        a.firstReleaseDate = now.addingTimeInterval(86_400)
        let b = repo.addGame(name: "Past", status: .wishlist)
        b.firstReleaseDate = now.addingTimeInterval(-86_400)
        let c = repo.addGame(name: "Unknown", status: .wishlist)

        let games = [a, b, c]
        let soon = WishlistShelf.comingSoon(games, now: now)
        let out = WishlistShelf.outNow(games, now: now)
        #expect(soon.count + out.count == games.count)
        #expect(Set(soon.map(\.id)).isDisjoint(with: Set(out.map(\.id))))
    }

    /// IGDB stores a year-only release as 1 January, and `firstReleaseDate`
    /// carries no precision flag — so printing a day would invent precision
    /// the data does not have. Month and year is true either way.
    @Test func theDateNeverClaimsADay() {
        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 1
        let jan = Calendar(identifier: .gregorian).date(from: components)!

        let label = WishlistShelf.releaseLabel(jan)
        #expect(label.contains("2026"))
        #expect(!label.contains("1,"))
        #expect(!label.contains(" 1 "))
    }
}
