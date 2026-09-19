import Testing
import Foundation
@testable import LevelSelect

/// "Summer 1998" and "the 1990s" are grains, not spans with a label.
///
/// Tim: *"I think first-class season/decade headers."* Before this the app
/// could store either only as a bare interval with no name for how wide it
/// was, so the calendar had nothing to group them by. B1, unblocked by B2's
/// grain field.
@MainActor
struct SeasonDecadeTests {

    private let cal = Memory.calendar
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: Decade

    @Test func aDecadeRunsFromTheZeroYearToTheNine() {
        let range = Memory.decadeInterval(of: date(1994, 7, 2))!
        #expect(cal.component(.year, from: range.lowerBound) == 1990)
        #expect(cal.component(.year, from: range.upperBound) == 1999)
    }

    /// 1990 is in the nineties and 2000 is not — the off-by-one everyone
    /// argues about at parties, settled the way people actually speak.
    @Test func theBoundaryYearsLandWhereTheySound() {
        #expect(cal.component(.year, from: Memory.decadeInterval(of: date(1990, 1, 1))!.lowerBound) == 1990)
        #expect(cal.component(.year, from: Memory.decadeInterval(of: date(1999, 12, 31))!.lowerBound) == 1990)
        #expect(cal.component(.year, from: Memory.decadeInterval(of: date(2000, 1, 1))!.lowerBound) == 2000)
    }

    @Test func aDecadeMemoryStoresTheWholeDecade() {
        let start = Memory.intervalStart(of: date(1994, 7, 2), precision: "decade")
        let end = Memory.intervalEnd(of: date(1994, 7, 2), precision: "decade")
        #expect(cal.component(.year, from: start) == 1990)
        #expect(cal.component(.year, from: end) == 1999)
        #expect(start < end)
    }

    @Test func theDecadeHeadingIsHowPeopleSayIt() {
        let period = JournalPeriod(start: date(1990, 1, 1), grain: .decade,
                                   entries: [], calendar: cal)
        #expect(period.title() == "The 1990s")
    }

    // MARK: Season

    @Test func aSeasonIsThreeMonths() {
        let summer = Memory.seasonInterval(of: date(1998, 7, 14))!
        #expect(cal.component(.month, from: summer.lowerBound) == 6)
        #expect(cal.component(.month, from: summer.upperBound) == 8)
    }

    /// Winter straddles a year end, so December belongs to the winter that
    /// starts in it rather than folding into the following spring.
    @Test func winterStartsInDecember() {
        let fromDecember = Memory.seasonInterval(of: date(1998, 12, 20))!
        #expect(cal.component(.year, from: fromDecember.lowerBound) == 1998)
        #expect(cal.component(.month, from: fromDecember.lowerBound) == 12)

        let fromJanuary = Memory.seasonInterval(of: date(1999, 1, 20))!
        #expect(cal.component(.year, from: fromJanuary.lowerBound) == 1998)
        #expect(cal.component(.month, from: fromJanuary.lowerBound) == 12)
    }

    // MARK: Grain

    @Test func everyPrecisionMapsToItsGrain() {
        #expect(JournalPeriod.Grain(precision: "day") == .day)
        #expect(JournalPeriod.Grain(precision: "month") == .month)
        #expect(JournalPeriod.Grain(precision: "season") == .season)
        #expect(JournalPeriod.Grain(precision: "year") == .year)
        #expect(JournalPeriod.Grain(precision: "decade") == .decade)
        // Unknown values from a later build read as a plain day rather than
        // failing — the same graceful rule the memory kinds follow.
        #expect(JournalPeriod.Grain(precision: "century") == .day)
        #expect(JournalPeriod.Grain(precision: nil) == .day)
    }

    /// Narrow to wide, which is what the ordering is for: two periods starting
    /// on the same instant sort with the more precise one first.
    @Test func grainsOrderNarrowToWide() {
        #expect(JournalPeriod.Grain.day < .month)
        #expect(JournalPeriod.Grain.month < .season)
        #expect(JournalPeriod.Grain.season < .year)
        #expect(JournalPeriod.Grain.year < .decade)
    }

    /// Neither names a day, so neither claims a square.
    @Test func neitherIsPlacedOnADay() {
        let season = Memory(title: "Summer 1998",
                            earliest: Memory.intervalStart(of: date(1998, 7, 14), precision: "season"),
                            latest: Memory.intervalEnd(of: date(1998, 7, 14), precision: "season"),
                            precision: "season", whenText: "Summer 1998")
        let decade = Memory(title: "The nineties",
                            earliest: Memory.intervalStart(of: date(1994, 7, 2), precision: "decade"),
                            latest: Memory.intervalEnd(of: date(1994, 7, 2), precision: "decade"),
                            precision: "decade")
        #expect(JournalBuilder.grain(for: season) == .season)
        #expect(JournalBuilder.grain(for: decade) == .decade)
        #expect(JournalBuilder.candidateEntries(for: season).count == 1)
        #expect(JournalBuilder.candidateEntries(for: decade).count == 1)
    }
}
