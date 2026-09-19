import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// "Christmas 1995 or 1996" belongs on both Christmases.
///
/// It used to land only on the first candidate, which is the app quietly
/// resolving an uncertainty its owner deliberately left open. Tim, asked
/// whether first-candidate was the final rule: *"I feel like it should show on
/// both candidate days."*
@MainActor
struct CandidateDayTests {

    private func memory(from: DateComponents, to: DateComponents,
                        precision: String?) -> Memory {
        let cal = Memory.calendar
        let m = Memory(title: "Christmas morning",
                       earliest: cal.date(from: from)!,
                       latest: cal.date(from: to)!,
                       precision: precision,
                       whenText: precision == nil ? "Christmas 1995 or 1996" : nil)
        return m
    }

    private func years(_ entries: [JournalEntry]) -> [Int] {
        entries.map { Memory.calendar.component(.year, from: $0.date) }.sorted()
    }

    @Test func aKnownDayInTwoPossibleYearsAppearsInBoth() {
        let m = memory(from: DateComponents(year: 1995, month: 12, day: 25),
                       to: DateComponents(year: 1996, month: 12, day: 25),
                       precision: nil)
        let entries = JournalBuilder.candidateEntries(for: m)
        #expect(entries.count == 2)
        #expect(years(entries) == [1995, 1996])
        // Same memory, shown twice — not two memories.
        #expect(entries.allSatisfy { $0.memory === m })
        // Distinct ids, or grouping folds them into one square.
        #expect(Set(entries.map { $0.id }).count == 2)
    }

    @Test func threePossibleYearsGiveThreeDays() {
        let m = memory(from: DateComponents(year: 1995, month: 6, day: 3),
                       to: DateComponents(year: 1997, month: 6, day: 3),
                       precision: nil)
        #expect(years(JournalBuilder.candidateEntries(for: m)) == [1995, 1996, 1997])
    }

    /// A span with NO known day has no candidate days to place, so it stays
    /// one entry — this is the case B2 is still open about, and it must not be
    /// silently changed here.
    @Test func aSpanWithNoKnownDayStaysASingleEntry() {
        let m = memory(from: DateComponents(year: 1995, month: 1, day: 1),
                       to: DateComponents(year: 1996, month: 12, day: 31),
                       precision: nil)
        #expect(JournalBuilder.candidateEntries(for: m).count == 1)
    }

    @Test func anExactDayIsStillOneEntry() {
        let m = memory(from: DateComponents(year: 2024, month: 3, day: 15),
                       to: DateComponents(year: 2024, month: 3, day: 15),
                       precision: "day")
        #expect(JournalBuilder.candidateEntries(for: m).count == 1)
    }

    @Test func aMonthOrYearPrecisionIsUntouched() {
        let month = memory(from: DateComponents(year: 2024, month: 3, day: 1),
                           to: DateComponents(year: 2024, month: 3, day: 31),
                           precision: "month")
        #expect(JournalBuilder.candidateEntries(for: month).count == 1)
        let year = memory(from: DateComponents(year: 2024, month: 1, day: 1),
                          to: DateComponents(year: 2024, month: 12, day: 31),
                          precision: "year")
        #expect(JournalBuilder.candidateEntries(for: year).count == 1)
    }

    /// A pathological span must not turn one memory into a wall of squares.
    @Test func aVeryWideSpanIsNotExploded() {
        let m = memory(from: DateComponents(year: 1990, month: 12, day: 25),
                       to: DateComponents(year: 2005, month: 12, day: 25),
                       precision: nil)
        #expect(JournalBuilder.candidateEntries(for: m).count == 1)
    }
}
