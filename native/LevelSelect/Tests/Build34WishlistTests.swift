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

    /// The Ocarina of Time remake, added 2026-08-31. Announced for "late
    /// 2026" with no date, so IGDB carries the year alone — stored as
    /// 1 January 2026, eight months in the PAST. Compared as a day it read as
    /// already out, and the one genuinely awaited game on the wishlist was the
    /// one the feature failed to catch.
    @Test func aYearOnlyDateThisYearIsStillAhead() {
        let context = makeContext()
        let repo = Repository(context)
        var parts = DateComponents(); parts.year = 2026; parts.month = 1; parts.day = 1
        let ocarina = repo.addGame(name: "The Legend of Zelda: Ocarina of Time", status: .wishlist)
        ocarina.firstReleaseDate = Calendar.current.date(from: parts)!

        let august = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        #expect(WishlistShelf.comingSoon([ocarina], now: august).count == 1)
        // And it says only what is known — not "January".
        #expect(WishlistShelf.releaseLabel(ocarina.firstReleaseDate!) == "2026")
    }

    /// A confirmed date is an exact date in IGDB, so it compares as a day and
    /// reads as released. Resident Evil Requiem, 27 February 2026.
    @Test func aConfirmedDateInThePastIsOutNow() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Resident Evil Requiem", status: .wishlist)
        game.firstReleaseDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 2, day: 27))!

        let august = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        #expect(WishlistShelf.comingSoon([game], now: august).isEmpty)
        #expect(WishlistShelf.releaseLabel(game.firstReleaseDate!).contains("February"))
    }

    /// A year-only date from a PREVIOUS year is genuinely old — most of the
    /// retro library carries exactly this, and none of it is forthcoming.
    @Test func aYearOnlyDateFromAPastYearIsNotComingSoon() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Killer7", status: .wishlist)
        game.firstReleaseDate = Calendar.current.date(
            from: DateComponents(year: 2005, month: 1, day: 1))!

        let august = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        #expect(WishlistShelf.comingSoon([game], now: august).isEmpty)
        #expect(WishlistShelf.releaseLabel(game.firstReleaseDate!) == "2005")
    }

    /// The bug under the bug: IGDB sends `first_release_date` as a Unix
    /// timestamp, and the app kept only the YEAR of it, rebuilding 1 January.
    /// Every release date in the library was 1 January, so the split could not
    /// tell a February release from a November one.
    @Test func igdbDatesKeepTheirMonthAndDay() {
        // 27 February 2026, the Resident Evil Requiem release.
        let feb27 = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 27))!
        let game = IGDBGame(
            id: 1, name: "Resident Evil Requiem", slug: nil, coverImageID: nil,
            franchise: nil, releaseYear: 2026, summary: nil, gameType: 0,
            platforms: [], genres: [], themes: [], gameModes: [],
            playerPerspectives: [], developers: [], publishers: [],
            releaseTimestamp: feb27.timeIntervalSince1970)

        let parts = Calendar.current.dateComponents([.year, .month, .day], from: game.releaseDate!)
        #expect(parts.month == 2)
        #expect(parts.day == 27)
    }

    /// Games IGDB dates only by year still fall back to 1 January, which is
    /// what every row written before this fix carries.
    @Test func aYearOnlyAnswerStillFallsBackToJanuary() {
        let game = IGDBGame(
            id: 2, name: "Ocarina of Time", slug: nil, coverImageID: nil,
            franchise: nil, releaseYear: 2026, summary: nil, gameType: 0,
            platforms: [], genres: [], themes: [], gameModes: [],
            playerPerspectives: [], developers: [], publishers: [])

        let parts = Calendar.current.dateComponents([.year, .month, .day], from: game.releaseDate!)
        #expect(parts.year == 2026)
        #expect(parts.month == 1)
        #expect(parts.day == 1)
    }

    // MARK: Deku, and what the library already knows

    /// The duplication that was visible on one screen: "Future Knight",
    /// "Promise Mascot Agency" and "Resident Evil Requiem" in BOTH panes, and
    /// "Cities: Skylines" sitting on a list of things to buy when it is
    /// already owned.
    @Test func dekuRowsKnowWhatTheLibraryHas() {
        let context = makeContext()
        let repo = Repository(context)
        let wanted = repo.addGame(name: "Future Knight", status: .wishlist)
        let owned = repo.addGame(name: "Cities: Skylines", status: .backlog)

        let index = DekuMatch.index([wanted, owned])
        #expect(index[DekuMatch.normalize("Future Knight")] == .wishlisted)
        #expect(index[DekuMatch.normalize("Cities: Skylines")] == .inLibrary)
        #expect(index[DekuMatch.normalize("Hollow Knight")] == nil)
    }

    /// Case, spacing and punctuation are noise. Deku writes "Cities:
    /// Skylines"; the library might hold "Cities Skylines".
    @Test func punctuationAndCaseDoNotBreakAMatch() {
        #expect(DekuMatch.normalize("Cities: Skylines") == DekuMatch.normalize("cities skylines"))
        #expect(DekuMatch.normalize("Killer7") == DekuMatch.normalize("killer 7"))
        #expect(DekuMatch.normalize("Ōkami") != DekuMatch.normalize("Okami"))
    }

    /// Editions are different purchases. Collapsing them would mark a game
    /// bought that is not — the exact failure the manual-promotion rule was
    /// written to avoid.
    @Test func editionsAreNotTheSameGame() {
        #expect(DekuMatch.normalize("Resident Evil 4")
                != DekuMatch.normalize("Resident Evil 4: Separate Ways"))
    }

    /// Owning beats wanting: on a list of things to buy, the fact worth
    /// showing is that you already have it.
    @Test func owningBeatsWantingWhenBothAreTrue() {
        let context = makeContext()
        let repo = Repository(context)
        let wished = repo.addGame(name: "Hades", status: .wishlist)
        let held = repo.addGame(name: "Hades", status: .playing)

        #expect(DekuMatch.index([wished, held])[DekuMatch.normalize("Hades")] == .inLibrary)
        #expect(DekuMatch.index([held, wished])[DekuMatch.normalize("Hades")] == .inLibrary)
    }

    /// A deleted game is not in your library.
    @Test func deletedGamesDoNotMatch() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Tunic", status: .backlog)
        game.deletedAt = .now

        #expect(DekuMatch.index([game]).isEmpty)
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
