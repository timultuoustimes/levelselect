import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The platform you picked when adding a game is the platform the app should
/// call yours.
///
/// It didn't. `addGame(from:platform:)` has always recorded the choice by
/// putting it at the front of `platforms`, but every label and every grouping
/// re-sorted that list through `PlatformPreference.sorted` — a fixed taste
/// ranking that places PC above Xbox 360. Add Skyrim on Xbox 360 and the game
/// page header, the library row, and the platform grouping all said PC.
///
/// So the adversarial shape here is deliberate throughout: a chosen platform
/// that the ranking sorts BELOW another platform the game also shipped on. A
/// test using Switch (which the ranking already prefers) would pass against
/// the broken code.
@MainActor
struct OwnedPlatformTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func igdb(_ name: String, _ platforms: [String]) -> IGDBGame {
        IGDBGame(id: 472, name: name, slug: nil, coverImageID: nil, franchise: nil,
                 releaseYear: 2011, summary: nil, gameType: nil, platforms: platforms,
                 genres: [], themes: [], gameModes: [], playerPerspectives: [],
                 developers: [], publishers: [])
    }

    /// The reported bug, exactly: Skyrim, Xbox 360 picked, PC also available.
    @Test func theChosenPlatformIsTheOwnedOneEvenWhenTheRankingPrefersAnother() {
        let repo = self.repo()
        let game = repo.addGame(
            from: igdb("The Elder Scrolls V: Skyrim",
                       ["Xbox 360", "PlayStation 3", "PC (Microsoft Windows)"]),
            platform: "Xbox 360", status: .completed)

        #expect(PlatformPreference.owned(game.platforms) == "Xbox 360")
        // And the ranking really would have said otherwise — if this stops
        // being true the test above has stopped proving anything.
        #expect(PlatformPreference.sorted(game.platforms).first == "PC (Microsoft Windows)")
    }

    /// Every other platform survives; only the ordering carries the answer.
    @Test func theOtherPlatformsAreKeptSoTheGameInfoStillListsThemAll() {
        let repo = self.repo()
        let game = repo.addGame(
            from: igdb("Skyrim", ["Xbox 360", "PlayStation 3", "PC (Microsoft Windows)"]),
            platform: "Xbox 360", status: .completed)

        #expect(game.platforms.count == 3)
        #expect(Set(game.platforms) == ["Xbox 360", "PlayStation 3", "PC (Microsoft Windows)"])
        #expect(game.platforms.first == "Xbox 360")
    }

    /// IGDB's platform lists are incomplete, so the confirm screen lets you
    /// type one. A typed platform is still your answer and must lead.
    @Test func aTypedPlatformIGDBNeverListedStillLeads() {
        let repo = self.repo()
        let game = repo.addGame(from: igdb("Sonic 2", ["PC (Microsoft Windows)"]),
                                platform: "Sega Genesis", status: .completed)

        #expect(PlatformPreference.owned(game.platforms) == "Sega Genesis")
        #expect(game.platforms.contains("PC (Microsoft Windows)"))
    }

    /// Picking one that IGDB also lists must not leave two copies of it —
    /// a duplicate would show twice in Game Info and split the grouping.
    @Test func choosingAListedPlatformDoesNotDuplicateIt() {
        let repo = self.repo()
        let game = repo.addGame(from: igdb("Skyrim", ["Xbox 360", "PlayStation 3"]),
                                platform: "Xbox 360", status: .completed)

        #expect(game.platforms.filter { $0 == "Xbox 360" }.count == 1)
        #expect(game.platforms == ["Xbox 360", "PlayStation 3"])
    }

    /// No answer given: nothing to honour, so the list stays as IGDB sent it
    /// and `owned` reports its head rather than inventing a preference.
    @Test func withNoChosenPlatformTheListIsLeftAlone() {
        let repo = self.repo()
        let game = repo.addGame(from: igdb("Skyrim", ["Xbox 360", "PC (Microsoft Windows)"]),
                                platform: nil, status: .backlog)

        #expect(game.platforms == ["Xbox 360", "PC (Microsoft Windows)"])
        #expect(PlatformPreference.owned(game.platforms) == "Xbox 360")
    }

    /// A game with no platforms at all groups as "Other" rather than crashing.
    @Test func noPlatformsIsNotAnOwnedPlatform() {
        let repo = self.repo()
        let game = repo.addGame(from: igdb("Unlisted", []), platform: nil, status: .backlog)

        #expect(PlatformPreference.owned(game.platforms) == nil)
    }

    /// Promoting a platform is how a wrong answer gets corrected — the
    /// PlatformEditor chip tap does exactly this move, and every label follows.
    @Test func promotingAPlatformChangesWhichOneIsYours() {
        let repo = self.repo()
        let game = repo.addGame(
            from: igdb("Skyrim", ["PC (Microsoft Windows)", "Xbox 360"]),
            platform: nil, status: .completed)
        #expect(PlatformPreference.owned(game.platforms) == "PC (Microsoft Windows)")

        repo.edit(game) { g in
            guard let index = g.platforms.firstIndex(of: "Xbox 360") else { return }
            g.platforms.remove(at: index)
            g.platforms.insert("Xbox 360", at: 0)
        }

        #expect(PlatformPreference.owned(game.platforms) == "Xbox 360")
        #expect(game.platforms.count == 2)
    }

    /// The ranking is still the right answer where no choice exists — ordering
    /// the picker on the confirm screen, and search results for games that
    /// aren't in the library yet. Pinned so the fix doesn't overshoot.
    @Test func theRankingIsUnchangedForChoiceFreeContexts() {
        #expect(PlatformPreference.sorted(["Xbox 360", "Nintendo Switch"]).first == "Nintendo Switch")
        #expect(PlatformPreference.sorted(["Recalbox", "Sega Genesis"]).first == "Sega Genesis")
    }
}
