import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// **The Calendar and the Timeline must agree about what a day contains.**
///
/// They did not. The Timeline groups entries by day and lists them; the
/// Calendar linked a cell straight to one `JournalEntry`, so a day holding two
/// games opened one of them and the other was unreachable from the calendar.
/// Tim found it on 2026-03-01 — Dead Cells and Sayonara Wild Hearts on the
/// Timeline, only Dead Cells through the Calendar — via the spoken summary,
/// which described the whole day and so did not match what tapping produced.
///
/// This pins the shape of the bug rather than the screen: a day with two games
/// has two entries, and anything claiming to show "the day" has to show both.
@MainActor
struct CalendarDayAgreementTests {

    /// Two games played on one day, plus a third on a different day.
    private func libraryWithASharedDay() -> (ModelContext, Date) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let calendar = JournalBuilder.calendar
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_772_000_000))

        let first = repo.addGame(name: "Dead Cells", status: .playing)
        repo.logManualSession(on: repo.ensureDefaultPlaythrough(for: first),
                              duration: 3600, date: day.addingTimeInterval(43_200))

        let second = repo.addGame(name: "Sayonara Wild Hearts", status: .playing)
        repo.logManualSession(on: repo.ensureDefaultPlaythrough(for: second),
                              duration: 981, date: day.addingTimeInterval(50_000))

        // A different day, so "the day" cannot simply mean "everything".
        let other = repo.addGame(name: "Cursed to Golf", status: .playing)
        repo.logManualSession(on: repo.ensureDefaultPlaythrough(for: other),
                              duration: 600, date: day.addingTimeInterval(4 * 86_400))

        try? context.save()
        return (context, day)
    }

    /// The grouping both lenses read. If this says two, anything showing one
    /// is hiding something.
    @Test func aDayWithTwoGamesHasTwoEntries() throws {
        let (context, day) = libraryWithASharedDay()
        let games = try context.fetch(FetchDescriptor<Game>())
        let calendar = JournalBuilder.calendar

        let entries = JournalBuilder.periods(from: games)
            .filter { $0.grain == .day && calendar.startOfDay(for: $0.start) == day }
            .flatMap(\.entries)

        #expect(entries.count == 2,
                Comment(rawValue: "expected both games on the day, got \(entries.map(\.title))"))
        let names = Set(entries.compactMap { $0.game?.name })
        #expect(names == ["Dead Cells", "Sayonara Wild Hearts"])
    }

    /// The regression itself: picking one entry to represent the day drops the
    /// other. This is what the calendar cell used to link to.
    @Test func oneEntryCannotStandForADayThatHoldsTwo() throws {
        let (context, day) = libraryWithASharedDay()
        let games = try context.fetch(FetchDescriptor<Game>())
        let calendar = JournalBuilder.calendar
        let entries = JournalBuilder.periods(from: games)
            .filter { $0.grain == .day && calendar.startOfDay(for: $0.start) == day }
            .flatMap(\.entries)

        let single = try #require(entries.first)
        #expect(entries.count > 1,
                "the premise: this day holds more than the one entry a cell would have linked to")
        // Whichever one is picked, something is left out — which is why the
        // calendar now routes to the day rather than to an entry.
        let reachable = Set([single].compactMap { $0.game?.name })
        let all = Set(entries.compactMap { $0.game?.name })
        #expect(reachable != all, "a single entry silently omits the rest of the day")
    }

    /// The day view must not spill into neighboring days.
    @Test func aDayShowsOnlyItsOwnEntries() throws {
        let (context, day) = libraryWithASharedDay()
        let games = try context.fetch(FetchDescriptor<Game>())
        let calendar = JournalBuilder.calendar
        let entries = JournalBuilder.periods(from: games)
            .filter { $0.grain == .day && calendar.startOfDay(for: $0.start) == day }
            .flatMap(\.entries)

        #expect(!entries.contains { $0.game?.name == "Cursed to Golf" },
                "another day's game leaked into this one")
    }
}
