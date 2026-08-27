import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 31 — the notebook batch: spans on beaten records, star names,
/// previously-owned, game-page section arranging, and the tag vocabulary
/// tools. Each test pins the behaviour the feature's note promised.
@MainActor
struct Build31Tests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    // MARK: Spans

    @Test func spanTextReadsStartArrowFinish() {
        let event = CompletionEvent(date: date(2026, 1, 15))
        event.datePrecision = "month"
        event.startedDate = date(2025, 12, 1)
        event.startedPrecision = "month"
        #expect(event.spanText == "Dec 2025 → Jan 2026")
    }

    @Test func spanWithoutStartIsJustTheFinish() {
        let event = CompletionEvent(date: date(2026, 1, 15))
        event.datePrecision = "year"
        #expect(event.spanText == "2026")
    }

    /// "Jan 2026 → Jan 2026" says less than "Jan 2026" does — a degenerate
    /// span collapses to the plain (wide-month) finish text.
    @Test func degenerateSpanCollapsesToFinish() {
        let event = CompletionEvent(date: date(2026, 1, 20))
        event.datePrecision = "month"
        event.startedDate = date(2026, 1, 2)
        event.startedPrecision = "month"
        #expect(event.spanText == event.dateText)
    }

    /// A record from before the fields reads exactly as it always did.
    @Test func recordsWithoutStartFieldsAreUnchanged() {
        let event = CompletionEvent(date: date(2011, 11, 11))
        #expect(event.startedDate == nil)
        #expect(event.spanText == event.dateText)
    }

    @Test func startRoundTripsThroughExportAndImport() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Ball x Pit", status: .completed)
        repo.addCompletion(to: game, date: date(2026, 1, 10), precision: "month",
                           startedDate: date(2025, 12, 1), startedPrecision: "month")

        let data = try LibraryExport.makeJSON(context: context)
        let fresh = makeContext()
        _ = try LibraryImport.apply(data: data, context: fresh)

        let events = try fresh.fetch(FetchDescriptor<CompletionEvent>())
            .filter { $0.deletedAt == nil }
        #expect(events.count == 1)
        #expect(events.first?.startedPrecision == "month")
        #expect(events.first?.startedDate != nil)
        #expect(events.first?.spanText == "Dec 2025 → Jan 2026")
    }

    // MARK: Star names

    @Test func starNamesFallBackToBuiltInsPerSlot() {
        let theme = ThemeSettings()
        theme.starNames = ["", "", "Comfort game", "", ""]
        #expect(theme.starName(for: 3) == "Comfort game")
        #expect(theme.starName(for: 5) == nil)   // blank → built-in label
    }

    @Test func allBlankStarNamesStoreNothing() {
        let theme = ThemeSettings()
        theme.starNames = ["A"]
        #expect(theme.starNamesData != nil)
        theme.starNames = ["", "  ", "", "", ""]
        #expect(theme.starNamesData == nil)
    }

    // MARK: Previously owned

    /// New case in a String-raw enum — the free path. The label and icon
    /// exist, and the raw value round-trips.
    @Test func previouslyOwnedIsARealOwnership() {
        #expect(Ownership(rawValue: "previouslyOwned") == .previouslyOwned)
        #expect(Ownership.previouslyOwned.label == "Previously Owned")
        #expect(Ownership.allCases.contains(.previouslyOwned))
    }

    // MARK: Game page sections

    @Test func sectionOrderDefaultsWhenNothingStored() {
        #expect(GamePageSection.resolveOrder(stored: "") == Array(GamePageSection.allCases))
    }

    /// A stored order from an older build slots unknown-to-it sections back
    /// in at their default position — new sections are never silently hidden.
    @Test func unknownSectionsSlotBackIntoStoredOrder() {
        // A stored order that predates .media entirely.
        let stored = GamePageSection.allCases
            .filter { $0 != .media }
            .map(\.rawValue).joined(separator: ",")
        let resolved = GamePageSection.resolveOrder(stored: stored)
        #expect(resolved.count == GamePageSection.allCases.count)
        // .media re-inserts right after its default predecessor, .about.
        let aboutIndex = try! #require(resolved.firstIndex(of: .about))
        #expect(resolved[aboutIndex + 1] == .media)
    }

    @Test func garbageTokensAreDroppedNotFatal() {
        let resolved = GamePageSection.resolveOrder(stored: "notes,garbage,sessions")
        #expect(resolved.first == .notes)
        #expect(resolved.count == GamePageSection.allCases.count)
    }

    // MARK: Tags

    @Test func tagCountsAreDerivedMostUsedFirst() {
        let context = makeContext()
        let repo = Repository(context)
        repo.addGame(name: "A", status: .backlog).userTags = ["roguelike", "cozy"]
        repo.addGame(name: "B", status: .backlog).userTags = ["roguelike"]
        repo.addGame(name: "C", status: .backlog).userTags = ["Roguelike"]

        let counts = repo.tagCounts()
        #expect(counts.first?.tag == "roguelike")
        #expect(counts.first?.count == 2)
        // Case variants are distinct rows — merging them is the user's call,
        // made with the numbers in front of them, never automatic.
        #expect(counts.contains { $0.tag == "Roguelike" && $0.count == 1 })
    }

    @Test func renameOntoExistingTagMergesWithoutDuplicates() {
        let context = makeContext()
        let repo = Repository(context)
        let both = repo.addGame(name: "Both", status: .backlog)
        both.userTags = ["rogue-like", "roguelike"]
        let one = repo.addGame(name: "One", status: .backlog)
        one.userTags = ["rogue-like"]

        let changed = repo.renameTag("rogue-like", to: "roguelike")
        #expect(changed == 2)
        // The game holding both ends with ONE copy, not a duplicate.
        #expect(both.userTags == ["roguelike"])
        #expect(one.userTags == ["roguelike"])
        #expect(!repo.tagCounts().contains { $0.tag == "rogue-like" })
    }

    @Test func removeTagReportsHowManyGamesItTouched() {
        let context = makeContext()
        let repo = Repository(context)
        repo.addGame(name: "A", status: .backlog).userTags = ["retro"]
        repo.addGame(name: "B", status: .backlog).userTags = ["retro", "cozy"]
        repo.addGame(name: "C", status: .backlog).userTags = ["cozy"]

        #expect(repo.removeTag("retro") == 2)
        #expect(repo.tagCounts().map(\.tag) == ["cozy"])
    }

    // MARK: Theming

    @Test func newPageBackgroundsDecodeAndUnknownFallsBack() {
        #expect(ThemePageBackground(rawValue: "accent") == .accent)
        #expect(ThemePageBackground(rawValue: "plain") == .plain)
        // An OLD build reading a NEW value gets nil — ThemePalette.refresh
        // nil-coalesces that to .cover, so nothing crashes or blanks.
        #expect(ThemePageBackground(rawValue: "somethingNewer") == nil)
    }

    // MARK: Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
