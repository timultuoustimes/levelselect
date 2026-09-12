import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// A memory with no day stops being filed on 1 January.
///
/// `precision == nil` carried two different answers: "Christmas 1995 or 1996"
/// knows the day and doubts only the year; "sometime in 1995 or 1996" has no
/// day in it. Both stored nil, so the app invented 1 January for the second —
/// which reads on the calendar as a New Year's Day memory nobody wrote. Tim:
/// *"It also means the app stops making stuff up on it's own about a user's
/// memory, so I'd rather that be the case."*
@MainActor
struct DaylessMemoryTests {

    private func saved(dayKnown: Bool, from: Int, to: Int,
                       month: Int = 12, day: Int = 25) -> Memory {
        let repo = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let cal = Memory.calendar
        let start = dayKnown
            ? cal.date(from: DateComponents(year: from, month: month, day: day))!
            : cal.date(from: DateComponents(year: from, month: 1, day: 1))!
        let end = dayKnown
            ? cal.date(from: DateComponents(year: to, month: month, day: day))!
            : cal.date(from: DateComponents(year: to, month: 12, day: 31))!
        let m = Memory(title: "Something")
        return repo.saveMemory(m, on: start, precision: nil,
                               words: "sometime around then",
                               span: start...end, dayKnown: dayKnown)
    }

    @Test func aDaylessMemoryIsNotPlacedOnADay() {
        let m = saved(dayKnown: false, from: 1995, to: 1996)
        #expect(m.hasKnownDay == false)
        #expect(JournalBuilder.grain(for: m) != .day)
        // And it does not multiply into candidate days either.
        #expect(JournalBuilder.candidateEntries(for: m).count == 1)
    }

    @Test func aKnownDayIsStillADay() {
        let m = saved(dayKnown: true, from: 1995, to: 1996)
        #expect(m.hasKnownDay)
        #expect(JournalBuilder.grain(for: m) == .day)
        #expect(JournalBuilder.candidateEntries(for: m).count == 2)
    }

    /// The calendar already keeps an area above the grid for entries that name
    /// no day. A dayless memory belongs there rather than on a square.
    @Test func aDaylessMemoryReachesTheYearsUndatedArea() {
        let m = saved(dayKnown: false, from: 1995, to: 1996)
        let periods = JournalBuilder.periods(from: [], standalone: [m])
        let undated = JournalCalendarView.undatedByYear(from: periods)
        #expect(undated[1995]?.isEmpty == false)

        let load = JournalCalendarView.load(from: periods,
                                            calendar: JournalBuilder.calendar)
        // Nothing on any square — least of all New Year's Day.
        #expect(load.isEmpty)
    }

    // MARK: Rows written before the field existed

    /// The old sheet stored 1 January when there was no day, and the real
    /// month/day when there was. That is the only signal a legacy row carries,
    /// and it is the one the heuristic reads.
    @Test func aLegacyRowOn1JanuaryIsTreatedAsDayless() {
        let cal = Memory.calendar
        let m = Memory(title: "Sometime in the nineties",
                       earliest: cal.date(from: DateComponents(year: 1995, month: 1, day: 1))!,
                       latest: cal.date(from: DateComponents(year: 1996, month: 12, day: 31))!,
                       precision: nil)
        #expect(m.dayKnownRaw == nil)
        #expect(m.hasKnownDay == false)
    }

    @Test func aLegacyChristmasKeepsItsDay() {
        let cal = Memory.calendar
        let m = Memory(title: "Christmas",
                       earliest: cal.date(from: DateComponents(year: 1995, month: 12, day: 25))!,
                       latest: cal.date(from: DateComponents(year: 1996, month: 12, day: 25))!,
                       precision: nil)
        #expect(m.dayKnownRaw == nil)
        #expect(m.hasKnownDay)
        #expect(JournalBuilder.candidateEntries(for: m).count == 2)
    }

    /// An explicit answer always beats the heuristic — including the one case
    /// the heuristic gets wrong, an uncertain memory that really did happen on
    /// a 1 January.
    @Test func anExplicitAnswerBeatsTheHeuristic() {
        let cal = Memory.calendar
        let m = Memory(title: "New Year's Day, one of those years",
                       earliest: cal.date(from: DateComponents(year: 1999, month: 1, day: 1))!,
                       latest: cal.date(from: DateComponents(year: 2000, month: 1, day: 1))!,
                       precision: nil)
        m.dayKnownRaw = true
        #expect(m.hasKnownDay)
        #expect(JournalBuilder.candidateEntries(for: m).count == 2)
    }

    @Test func aPreciseDateIsUnaffected() {
        let repo = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let day = Memory.calendar.date(from: DateComponents(year: 2024, month: 3, day: 15))!
        let m = repo.saveMemory(Memory(title: "A day"), on: day,
                                precision: "day", words: nil)
        #expect(m.dayKnownRaw == true)
        #expect(JournalBuilder.grain(for: m) == .day)

        let year = repo.saveMemory(Memory(title: "A year"), on: day,
                                   precision: "year", words: nil)
        #expect(year.dayKnownRaw == false)
        #expect(JournalBuilder.grain(for: year) == .year)
    }
}
