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

    private func igdbAnswer(id: Int, name: String, release: Date) -> IGDBGame {
        IGDBGame(id: id, name: name, slug: "slug", coverImageID: "co1",
                 franchise: nil, releaseYear: Calendar.current.component(.year, from: release),
                 summary: "A game.", gameType: 0, platforms: [], genres: [],
                 themes: [], gameModes: [], playerPerspectives: [],
                 developers: [], publishers: [],
                 releaseTimestamp: release.timeIntervalSince1970,
                 // Explicit: without IGDB's own exact-day category the date is
                 // collapsed to 1 January, which is the whole point of the
                 // precision work — a padded timestamp is not an announcement.
                 releasePrecision: .day)
    }

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
    /// **Superseded by the three-shelf split, 2026-08-31.** The two-shelf
    /// version put this under "Coming soon"; Tim's correction is that a game
    /// merely promised this year is not the same waiting as one with a date.
    @Test func aYearOnlyDateThisYearHasNoDateYet() {
        let context = makeContext()
        let repo = Repository(context)
        var parts = DateComponents(); parts.year = 2026; parts.month = 1; parts.day = 1
        let ocarina = repo.addGame(name: "The Legend of Zelda: Ocarina of Time", status: .wishlist)
        ocarina.firstReleaseDate = Calendar.current.date(from: parts)!

        let august = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        #expect(WishlistShelf.shelf(for: ocarina, now: august) == .noDateYet)
        #expect(WishlistShelf.comingSoon([ocarina], now: august).isEmpty)
        #expect(WishlistShelf.noDateYet([ocarina], now: august).count == 1)
        // And it never prints "January", which it does not know.
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
        #expect(WishlistShelf.shelf(for: game, now: august) == .outNow)
        // A real date CAN show its day now — IGDB's own answer is kept whole,
        // so this is not a claim the data cannot support. Before the parse fix
        // every date was 1 January and a day would have been an invention.
        #expect(WishlistShelf.releaseLabel(game.firstReleaseDate!).contains("27"))
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
            releaseTimestamp: feb27.timeIntervalSince1970, releasePrecision: .day)

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

    /// Tim: *"those should get release dates added when they get announced."*
    /// A year-only date for the current year or later is upgradeable — the one
    /// deliberate exception to the fill's additive-only rule, and narrow: same
    /// year, and only because release dates are fetched, never typed.
    @Test func anAnnouncedDayUpgradesAYearOnlyDate() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Ocarina of Time", status: .wishlist)
        game.igdbID = 42
        game.firstReleaseDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 1, day: 1))!

        #expect(MetadataRefresh.awaitsAnnouncedDate(game.firstReleaseDate))
        #expect(MetadataRefresh.missingFields(of: game).contains(.releaseDate))

        let announced = Calendar.current.date(
            from: DateComponents(year: 2026, month: 11, day: 12))!
        let filled = MetadataRefresh.fill(game, from: igdbAnswer(
            id: 42, name: "Ocarina of Time", release: announced))

        #expect(filled.contains(.releaseDate))
        #expect(Calendar.current.component(.month, from: game.firstReleaseDate!) == 11)
    }

    /// Most of the retro library is year-only and none of it is going to be
    /// announced — those must not be offered as work forever.
    @Test func oldYearOnlyDatesAreNotAwaitingAnything() {
        let old = Calendar.current.date(from: DateComponents(year: 2005, month: 1, day: 1))!
        #expect(!MetadataRefresh.awaitsAnnouncedDate(old))
    }

    /// A fuzzy answer must never quietly move a game into a different year.
    @Test func anUpgradeNeverChangesTheYear() {
        let context = makeContext()
        let game = Repository(context).addGame(name: "Slipped", status: .wishlist)
        game.igdbID = 43
        game.firstReleaseDate = Calendar.current.date(
            from: DateComponents(year: 2026, month: 1, day: 1))!

        let nextYear = Calendar.current.date(
            from: DateComponents(year: 2027, month: 3, day: 4))!
        _ = MetadataRefresh.fill(game, from: igdbAnswer(id: 43, name: "Slipped", release: nextYear))

        #expect(Calendar.current.component(.year, from: game.firstReleaseDate!) == 2026)
    }

    /// IGDB pads imprecise dates to real timestamps — a year-only entry can
    /// arrive as **30 December**. The Ocarina remake came through exactly that
    /// way and the wishlist printed "Dec 30, 2026" as a launch day for a game
    /// with no announced date. Only IGDB's own exact-day category is trusted.
    @Test func aPaddedTimestampIsNotALaunchDay() {
        let dec30 = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 30))!
        let padded = IGDBGame(
            id: 9, name: "Ocarina of Time", slug: nil, coverImageID: nil, franchise: nil,
            releaseYear: 2026, summary: nil, gameType: 0, platforms: [], genres: [],
            themes: [], gameModes: [], playerPerspectives: [], developers: [], publishers: [],
            releaseTimestamp: dec30.timeIntervalSince1970, releasePrecision: .year)

        // Read in UTC, because that is what the placeholder now IS. It used to
        // be built with the local calendar, which is how Onimusha ended up
        // stored as 1 January 05:00Z and shown as "Released 2025" — a test
        // asserting in local time agreed with the bug.
        let stored = padded.storableReleaseDate!
        let parts = ReleaseCountdown.utc.dateComponents([.year, .month, .day], from: stored)
        #expect(parts.year == 2026)
        #expect(parts.month == 1)   // collapsed to the app's year-only shorthand
        #expect(parts.day == 1)
        #expect(MetadataRefresh.isYearOnly(stored))
    }

    /// A genuine day survives untouched.
    @Test func anExactDayIsKept() {
        let mar5 = Calendar.current.date(from: DateComponents(year: 2027, month: 3, day: 5))!
        let exact = IGDBGame(
            id: 10, name: "Something", slug: nil, coverImageID: nil, franchise: nil,
            releaseYear: 2027, summary: nil, gameType: 0, platforms: [], genres: [],
            themes: [], gameModes: [], playerPerspectives: [], developers: [], publishers: [],
            releaseTimestamp: mar5.timeIntervalSince1970, releasePrecision: .day)

        #expect(Calendar.current.component(.day, from: exact.storableReleaseDate!) == 5)
    }

    /// BOTH ends of the year are placeholders. 1 January is the app's own
    /// shorthand; 31 December is IGDB's, padding a year-only or Q4 release to
    /// the last day of the period. Ocarina arrived as 31 December 2026 and the
    /// wishlist printed it as a launch day.
    @Test func decemberThirtyFirstIsAlsoAYearPlaceholder() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let dec31 = utc.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let jan1 = utc.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let midYear = utc.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        #expect(MetadataRefresh.isYearOnly(dec31))
        #expect(MetadataRefresh.isYearOnly(jan1))
        #expect(!MetadataRefresh.isYearOnly(midYear))
        #expect(WishlistShelf.releaseLabel(dec31) == "2026")
    }

    /// Even when IGDB claims exact-day precision, a 31 December answer is a
    /// period boundary far more often than a launch — so it is not stored as
    /// a day.
    @Test func aPaddingDayIsNotTrustedEvenWhenIGDBClaimsExactness() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let dec31 = utc.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let claimed = IGDBGame(
            id: 11, name: "Ocarina of Time", slug: nil, coverImageID: nil, franchise: nil,
            releaseYear: 2026, summary: nil, gameType: 0, platforms: [], genres: [],
            themes: [], gameModes: [], playerPerspectives: [], developers: [], publishers: [],
            releaseTimestamp: dec31.timeIntervalSince1970, releasePrecision: .day)

        #expect(MetadataRefresh.isYearOnly(claimed.storableReleaseDate!))
    }

    // MARK: The date that matters to YOU

    /// `first_release_date` is the earliest across EVERY platform, so a game
    /// that reached PC in 2025 and arrives on Switch 2 in 2026 read as
    /// released — wrong in exactly the case the wishlist exists for.
    @Test func theStoredDateIsTheOneForYourPlatform() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let pc = utc.date(from: DateComponents(year: 2025, month: 6, day: 10))!
        let switch2 = utc.date(from: DateComponents(year: 2026, month: 11, day: 12))!

        let game = IGDBGame(
            id: 1, name: "Ported Later", slug: nil, coverImageID: nil, franchise: nil,
            releaseYear: 2025, summary: nil, gameType: 0,
            platforms: ["PC (Microsoft Windows)", "Nintendo Switch 2"],
            genres: [], themes: [], gameModes: [], playerPerspectives: [],
            developers: [], publishers: [],
            releaseTimestamp: pc.timeIntervalSince1970, releasePrecision: .day,
            platformReleases: [
                .init(platform: "PC (Microsoft Windows)", timestamp: pc.timeIntervalSince1970, precision: .day),
                .init(platform: "Nintendo Switch 2", timestamp: switch2.timeIntervalSince1970, precision: .day),
            ])

        // Bought on Switch 2 → November 2026, and still ahead.
        let mine = game.storableReleaseDate(on: "Nintendo Switch 2")!
        #expect(Calendar.current.component(.year, from: mine) == 2026)
        #expect(Calendar.current.component(.month, from: mine) == 11)

        // Bought on PC → 2025, and out.
        let onPC = game.storableReleaseDate(on: "PC (Microsoft Windows)")!
        #expect(Calendar.current.component(.year, from: onPC) == 2025)

        // No platform chosen → the aggregate, as before.
        #expect(game.storableReleaseDate(on: nil) == game.storableReleaseDate)
    }

    /// Platform names are matched on console identity, so the user's spelling
    /// does not have to match IGDB's.
    @Test func theMatchIsByConsoleNotBySpelling() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let game = IGDBGame(
            id: 2, name: "Whatever", slug: nil, coverImageID: nil, franchise: nil,
            releaseYear: 2027, summary: nil, gameType: 0, platforms: [], genres: [],
            themes: [], gameModes: [], playerPerspectives: [], developers: [], publishers: [],
            releaseTimestamp: 0, releasePrecision: .day,
            platformReleases: [.init(platform: "Nintendo Switch", timestamp: date.timeIntervalSince1970,
                                     precision: .day)])

        #expect(game.storableReleaseDate(on: "Switch") != nil)
        #expect(game.storableReleaseDate(on: "Switch") == game.storableReleaseDate(on: "Nintendo Switch"))
    }

    /// A platform IGDB lists no date for falls back rather than inventing one.
    @Test func anUndatedPlatformFallsBackToTheAggregate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let game = IGDBGame(
            id: 3, name: "Whatever", slug: nil, coverImageID: nil, franchise: nil,
            releaseYear: 2023, summary: nil, gameType: 0, platforms: [], genres: [],
            themes: [], gameModes: [], playerPerspectives: [], developers: [], publishers: [],
            releaseTimestamp: date.timeIntervalSince1970, releasePrecision: .day,
            platformReleases: [])

        #expect(game.storableReleaseDate(on: "Dreamcast") == game.storableReleaseDate)
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

@Suite("Release countdown")
struct ReleaseCountdownTests {
    /// UTC, because a release is a calendar date and the shelf counts days.
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test("A release later today reads Today, not in 0 days")
    func today() {
        let now = day(2026, 9, 1, hour: 2)
        #expect(WishlistShelf.countdown(to: day(2026, 9, 1, hour: 23), from: now) == "Today")
    }

    /// The bug a duration-based countdown always has: at 11pm, a game landing
    /// nine hours later is under 24 hours away and would round to "Today".
    @Test("Tomorrow is the next calendar date, not 24 hours away")
    func tomorrowCrossesMidnight() {
        let now = day(2026, 9, 1, hour: 23)
        #expect(WishlistShelf.countdown(to: day(2026, 9, 2, hour: 8), from: now) == "Tomorrow")
    }

    @Test("Days, then weeks, then months")
    func units() {
        let now = day(2026, 9, 1)
        #expect(WishlistShelf.countdown(to: day(2026, 9, 7), from: now) == "in 6 days")
        #expect(WishlistShelf.countdown(to: day(2026, 9, 15), from: now) == "in 2 weeks")
        #expect(WishlistShelf.countdown(to: day(2027, 2, 27), from: now) == "in 6 months")
    }

    @Test("A date already gone counts to nothing")
    func past() {
        #expect(WishlistShelf.countdown(to: day(2026, 8, 30), from: day(2026, 9, 1)) == nil)
    }

    /// A year-only date is a placeholder, and counting to 31 December would
    /// invent a precision the app deliberately refuses elsewhere.
    @Test("A year with no day never counts down")
    func yearOnly() {
        #expect(WishlistShelf.countdown(to: day(2026, 12, 31), from: day(2026, 9, 1)) == nil)
        #expect(WishlistShelf.countdown(to: day(2027, 1, 1), from: day(2026, 9, 1)) == nil)
    }
}

@Suite("A date nobody has announced yet")
struct AwaitingDateTests {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// The bug Onimusha hit: asked yesterday, answered with a year, marked
    /// checked — and under one interval for everything it would have stayed
    /// "No date yet" through its own launch.
    @Test("A game awaiting a date is asked again the next day")
    func awaitingDateRechecksSoon() {
        let game = Game(name: "Onimusha: Way of the Sword")
        game.igdbID = 1
        game.firstReleaseDate = date(2026, 1, 1)     // IGDB's year-only answer
        let askedYesterday = [game.id: Date(timeIntervalSinceNow: -36 * 3600)]

        let plan = MetadataRefresh.plan(for: [game], checked: askedYesterday)
        #expect(plan.fillable.contains { $0.id == game.id })
        #expect(plan.recentlyChecked == 0)
    }

    @Test("A game missing something else still waits a month")
    func othersKeepTheMonth() {
        let game = Game(name: "Killer7")
        game.igdbID = 2
        game.firstReleaseDate = date(2005, 6, 9)     // a real day, long past
        let askedYesterday = [game.id: Date(timeIntervalSinceNow: -36 * 3600)]

        let plan = MetadataRefresh.plan(for: [game], checked: askedYesterday)
        #expect(!plan.fillable.contains { $0.id == game.id })
    }

    /// A wishlist game is owned nowhere, so the app must not let a guessed
    /// platform choose the date — that is what filed a dated game as undated.
    @Test("A platform you have not chosen never picks the date")
    func guessedPlatformDoesNotPickTheDate() {
        let game = Game(name: "Onimusha: Way of the Sword")
        game.platforms = ["PC (Microsoft Windows)", "PlayStation 5"]
        #expect(game.chosenPlatform == nil)
        #expect(game.primaryOwnedPlatform == "PC (Microsoft Windows)")

        game.ownedPlatforms = ["PlayStation 5"]
        #expect(game.chosenPlatform == "PlayStation 5")
    }
}

@Suite("Release reminders", .serialized)
@MainActor
struct ReleaseReminderTests {
    /// A release stamped at UTC midnight, the way IGDB sends them.
    private func release(_ y: Int, _ m: Int, _ d: Int) -> Date {
        ReleaseCountdown.utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// The reminder is about a DAY, so it fires in the morning of that day —
    /// not at the release instant, which for a UTC-midnight stamp is the
    /// small hours anywhere west of Greenwich.
    @Test("A day-before reminder fires at 9am the day before")
    func dayBefore() throws {
        let fire = try #require(
            NotificationManager.fireDate(for: release(2026, 9, 4), leadDays: 1))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: fire)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 3)
        #expect(parts.hour == 9)
    }

    /// The release read as a local calendar day. Reading it as an instant
    /// would land 4 September at 8pm on 3 September in Eastern time and fire
    /// the "out today" reminder a day early.
    @Test("On-the-day fires the morning of the release, in local time")
    func onTheDay() throws {
        let fire = try #require(
            NotificationManager.fireDate(for: release(2026, 9, 4), leadDays: 0))
        let parts = Calendar.current.dateComponents([.month, .day, .hour], from: fire)
        #expect(parts.month == 9)
        #expect(parts.day == 4)
        #expect(parts.hour == 9)
    }

    @Test("A week's lead crosses the month boundary correctly")
    func weekBefore() throws {
        let fire = try #require(
            NotificationManager.fireDate(for: release(2026, 9, 4), leadDays: 7))
        let parts = Calendar.current.dateComponents([.month, .day], from: fire)
        #expect(parts.month == 8)
        #expect(parts.day == 28)
    }
}
