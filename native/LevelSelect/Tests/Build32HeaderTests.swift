import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 32 — the game page header, and the menu vocabulary the 2026-08-28
/// audit found had drifted apart.
@MainActor
struct Build32HeaderTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    // MARK: Header stats

    /// The regression that started this: the page could only ever show the
    /// ACTIVE playthrough's time, so a second playthrough made the number on
    /// screen smaller than the truth.
    @Test func playtimeCountsEveryPlaythroughNotJustTheActiveOne() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)

        let first = repo.ensureDefaultPlaythrough(for: game)
        _ = repo.logManualSession(on: first, duration: 3600)
        let second = repo.addPlaythrough(to: game, named: "Second run")
        _ = repo.logManualSession(on: second, duration: 1800)
        repo.setActivePlaythrough(second, for: game)

        // The active playthrough alone would report 1800.
        #expect(game.activePlaythrough?.totalPlaytime().rounded() == 1800)
        #expect(game.lifetimePlaytime().rounded() == 5400)
        #expect(game.lifetimeSessionCount == 2)
    }

    /// A deleted playthrough's time leaves with it — the total is what you
    /// still have, not what you ever had.
    @Test func deletedPlaythroughsDropOutOfTheTotal() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .playing)

        let keep = repo.ensureDefaultPlaythrough(for: game)
        _ = repo.logManualSession(on: keep, duration: 600)
        let scrap = repo.addPlaythrough(to: game, named: "Mistake")
        _ = repo.logManualSession(on: scrap, duration: 9000)
        repo.deletePlaythrough(scrap, from: game)

        #expect(game.lifetimePlaytime().rounded() == 600)
        #expect(game.lifetimeSessionCount == 1)
    }

    @Test func beatenCountIgnoresDeletedRecords() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Outer Wilds", status: .completed)
        repo.addCompletion(to: game, date: .now, precision: "day")
        repo.addCompletion(to: game, date: .now, precision: "day")
        #expect(game.liveCompletionEvents.count == 2)

        if let first = game.liveCompletionEvents.first {
            repo.removeCompletion(first)
        }
        #expect(game.liveCompletionEvents.count == 1)
    }

    /// A game nobody has timed reports zero rather than crashing on an empty
    /// relationship — the common case for a library that's logged, not played.
    @Test func anUntouchedGameReportsZeroForEverything() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Pitfall!", status: .backlog)
        #expect(game.lifetimePlaytime() == 0)
        #expect(game.lifetimeSessionCount == 0)
        #expect(game.lifetimeRunCount == 0)
        #expect(game.liveCompletionEvents.isEmpty)
    }

    // MARK: Status vocabulary

    /// The audit's finding #4: the game menu said "Playing / Queued /
    /// Ongoing" in raw enum order while every other surface said "Now Playing
    /// / Up Next / Always Around". `label` was `rawValue.capitalized`; it is
    /// now the one public vocabulary.
    @Test func statusLabelIsTheShelfVocabularyEverywhere() {
        #expect(GameStatus.playing.label == "Now Playing")
        #expect(GameStatus.queued.label == "Up Next")
        #expect(GameStatus.ongoing.label == "Always Around")
        for status in GameStatus.allCases {
            #expect(status.label == status.sectionTitle)
        }
    }

    /// Menus iterate `displayOrder`, so it has to cover the enum — a status
    /// missing from it would be unreachable from every menu at once.
    @Test func displayOrderCoversEveryStatusExactlyOnce() {
        #expect(Set(GameStatus.displayOrder) == Set(GameStatus.allCases))
        #expect(GameStatus.displayOrder.count == GameStatus.allCases.count)
    }
}

/// Build 33 — the game page header became a choice rather than a decree.
@MainActor
struct GamePageLayoutTests {

    @Test func defaultsToShowcaseWhenNothingIsStored() {
        let theme = ThemeSettings()
        #expect(theme.gamePageLayoutRaw == nil)
        ThemePalette.refresh(from: theme)
        #expect(ThemePalette.gamePageLayout == .showcase)
    }

    @Test func aStoredChoiceIsHonoured() {
        let theme = ThemeSettings()
        theme.gamePageLayoutRaw = GamePageLayout.classic.rawValue
        ThemePalette.refresh(from: theme)
        #expect(ThemePalette.gamePageLayout == .classic)
    }

    /// An OLD build writing a value this one has never heard of, or a value
    /// corrupted in transit, must not blank the page — it falls back to the
    /// default the same way `ThemePageBackground` does.
    @Test func anUnknownStoredValueFallsBackRatherThanFailing() {
        let theme = ThemeSettings()
        theme.gamePageLayoutRaw = "somethingNewer"
        ThemePalette.refresh(from: theme)
        #expect(ThemePalette.gamePageLayout == .showcase)
    }

    /// The seeder writes a marker into every optional so CloudKit creates the
    /// field; purge puts it back to nil. A marker left behind would otherwise
    /// silently become the user's stored preference.
    @Test func theSeedMarkerIsNotAValidLayout() {
        #expect(GamePageLayout(rawValue: "levelselect-schema-seed") == nil)
    }

    @Test func everyLayoutSaysWhatItIsAndWhatItDoes() {
        for layout in GamePageLayout.allCases {
            #expect(!layout.label.isEmpty)
            // The blurb exists because "Showcase" and "Classic" name nothing.
            #expect(layout.blurb.count > 20)
        }
    }
}
