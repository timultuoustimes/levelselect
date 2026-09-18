import Testing
import Foundation
@testable import LevelSelect

/// News → Upcoming, per platform. Tim's 09-18 comparison with Game Informer:
/// ports and late platforms were missing, and "Your systems" had to be his
/// choice (PC off, Mac on).
struct UpcomingReleasesTests {
    private let utc = UpcomingReleases.utc
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// LEGO Batman: Legacy of the Dark Knight — PS5, Xbox and PC in May,
    /// Switch 2 on 18 September. Measured on IGDB, 09-18.
    private var legoBatman: UpcomingRelease {
        UpcomingRelease(id: 361855, name: "LEGO Batman: Legacy of the Dark Knight", rows: [
            .init(platform: "PC", date: day(2026, 5, 22), precision: .day),
            .init(platform: "PS5", date: day(2026, 5, 22), precision: .day),
            .init(platform: "Xbox Series", date: day(2026, 5, 22), precision: .day),
            .init(platform: "Switch 2", date: day(2026, 9, 18), precision: .day),
        ])
    }

    @Test func aPortCountsOnItsOwnDate() throws {
        let n = try #require(legoBatman.next(on: UpcomingReleases.mainPlatforms, from: day(2026, 9, 18)))
        #expect(n.date == day(2026, 9, 18))
        #expect(n.platforms == ["Switch 2"])
        #expect(Set(legoBatman.alreadyOut(before: day(2026, 9, 18)).map(\.platform)) == ["PC", "PS5", "Xbox Series"])
    }

    @Test func yourSystemsDecide() {
        // Tim, without a Switch 2 in his chosen systems, wouldn't see it.
        #expect(legoBatman.next(on: ["PS5", "Mac"], from: day(2026, 9, 18)) == nil)
        let pcOnly = UpcomingRelease(id: 1, name: "PC thing", rows: [.init(platform: "PC", date: day(2026, 10, 1), precision: .day)])
        #expect(pcOnly.next(on: ["Switch 2", "Mac"], from: day(2026, 9, 18)) == nil)
        #expect(pcOnly.next(on: ["PC"], from: day(2026, 9, 18)) != nil)
    }

    @Test func sameDayPlatformsAreListedTogether() throws {
        let r = UpcomingRelease(id: 2, name: "Garfield", rows: [
            .init(platform: "PS5", date: day(2026, 9, 24), precision: .day),
            .init(platform: "Switch", date: day(2026, 9, 24), precision: .day),
            .init(platform: "PC", date: day(2026, 10, 2), precision: .day),
        ])
        let n = try #require(r.next(on: UpcomingReleases.mainPlatforms, from: day(2026, 9, 18)))
        #expect(Set(n.platforms) == ["PS5", "Switch"])
    }

    @Test func yearOnlyDatesAreNotDecember() {
        let dated = UpcomingRelease(id: 3, name: "Dated", rows: [.init(platform: "PS5", date: day(2026, 12, 3), precision: .day)])
        let yearOnly = UpcomingRelease(id: 4, name: "Sometime", rows: [.init(platform: "PS5", date: day(2026, 12, 31), precision: .year)])
        let monthOnly = UpcomingRelease(id: 5, name: "November-ish", rows: [.init(platform: "PS5", date: day(2026, 11, 30), precision: .month)])
        let sections = UpcomingReleases.sections([dated, yearOnly, monthOnly], allowed: ["PS5"], from: day(2026, 9, 18))
        #expect(sections.count == 3)
        #expect(sections.last?.month == nil)
        #expect(sections.last?.items.map(\.release.id) == [4])
        #expect(sections.first?.items.map(\.release.id) == [5])
    }

    @Test func aMonthOnlyDateSortsAfterThatMonthsDatedGames() {
        let vague = UpcomingRelease(id: 6, name: "A", rows: [.init(platform: "PS5", date: day(2026, 10, 1), precision: .month)])
        let exact = UpcomingRelease(id: 7, name: "B", rows: [.init(platform: "PS5", date: day(2026, 10, 20), precision: .day)])
        let sections = UpcomingReleases.sections([vague, exact], allowed: ["PS5"], from: day(2026, 9, 18))
        #expect(sections.first?.items.map(\.release.id) == [7, 6])
    }

    @Test func buildsFromIGDBsLaunchRowsNotItsBeta() throws {
        let game = IGDBGame(id: 9, name: "Beta'd", slug: nil, coverImageID: nil, franchise: nil,
                            releaseYear: nil, summary: nil, gameType: 0, platforms: ["PlayStation 5"],
                            genres: [], themes: [], gameModes: [], playerPerspectives: [],
                            developers: [], publishers: [],
                            platformReleases: [
                                .init(platform: "PlayStation 5", timestamp: day(2026, 8, 28).timeIntervalSince1970,
                                      precision: .day, status: 2),
                                .init(platform: "PlayStation 5", timestamp: day(2026, 10, 23).timeIntervalSince1970,
                                      precision: .day, status: 6),
                            ])
        let r = try #require(UpcomingRelease(game))
        #expect(r.rows.map(\.date) == [day(2026, 10, 23)])
        #expect(r.rows.map(\.platform) == ["PS5"])
    }

    @Test func justOutIsTheLastTwoWeeksNewestFirst() {
        let today = day(2026, 9, 18)
        let lastWeek = UpcomingRelease(id: 10, name: "Last week", rows: [.init(platform: "PS5", date: day(2026, 9, 11), precision: .day)])
        let yesterday = UpcomingRelease(id: 11, name: "Yesterday", rows: [.init(platform: "Switch 2", date: day(2026, 9, 17), precision: .day)])
        let tooOld = UpcomingRelease(id: 12, name: "Old", rows: [.init(platform: "PS5", date: day(2026, 9, 1), precision: .day)])
        let today_ = UpcomingRelease(id: 13, name: "Today", rows: [.init(platform: "PS5", date: today, precision: .day)])
        let vague = UpcomingRelease(id: 14, name: "Sept-ish", rows: [.init(platform: "PS5", date: day(2026, 9, 10), precision: .month)])
        let list = UpcomingReleases.justOut([lastWeek, yesterday, tooOld, today_, vague],
                                            allowed: UpcomingReleases.mainPlatforms, today: today)
        // Today's belongs to the upcoming list, not Just Out.
        #expect(list.map(\.release.id) == [11, 10])
    }

    @Test func aPortThatJustLandedIsJustOut() {
        let r = legoBatman
        let list = UpcomingReleases.justOut([r], allowed: UpcomingReleases.mainPlatforms, today: day(2026, 9, 20))
        #expect(list.first?.next.platforms == ["Switch 2"])
    }
}
