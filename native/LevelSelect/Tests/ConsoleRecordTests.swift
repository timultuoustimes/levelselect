import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The console record: created for you, corrected by you, and never quietly
/// wrong about hardware you do not own.
@MainActor
struct ConsoleRecordTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @discardableResult
    private func game(_ repo: Repository, _ name: String,
                      on platform: String,
                      _ ownership: [Ownership],
                      status: GameStatus = .backlog,
                      added: Date = .now) -> Game {
        let g = repo.addGame(name: name, status: status)
        g.ownedPlatforms = [platform]
        g.ownership = ownership.map(\.rawValue)
        g.addedAt = added
        return g
    }

    // MARK: Rule 1 — the first game makes the console

    @Test("The first game on a platform creates the console and inherits its ownership, without asking")
    func firstGameCreates() {
        let repo = store()
        let g = game(repo, "Sonic 2", on: "Sega Mega Drive/Genesis", [.emulated])
        let questions = repo.noteConsoles(for: g)

        #expect(questions.isEmpty, "nothing to disambiguate on the first game")
        let consoles = repo.liveConsoles()
        #expect(consoles.count == 1)
        #expect(consoles.first?.platform == "Genesis")
        #expect(consoles.first?.ownership == [Ownership.emulated.rawValue])
    }

    @Test("Two spellings of one platform are one console")
    func spellingsFold() {
        let repo = store()
        repo.noteConsoles(for: game(repo, "Mario Kart", on: "Nintendo Switch 2", [.digital]))
        repo.noteConsoles(for: game(repo, "Metroid", on: "Switch 2", [.digital]))

        #expect(repo.liveConsoles().count == 1)
        #expect(repo.console(forPlatform: "Nintendo Switch 2")?.platform == "Switch 2")
    }

    @Test("A wishlisted game makes no console — it says nothing about hardware you have")
    func wishlistMakesNothing() {
        let repo = store()
        let g = game(repo, "Silksong", on: "Nintendo Switch 2", [.digital], status: .wishlist)
        #expect(repo.noteConsoles(for: g).isEmpty)
        #expect(repo.liveConsoles().isEmpty)
    }

    // MARK: Rule 2 — a new ownership asks, and only once

    @Test("A physical game on an emulated console ASKS rather than assuming — a display copy is not a machine")
    func secondOwnershipAsks() {
        let repo = store()
        repo.noteConsoles(for: game(repo, "Sonic 2", on: "Genesis", [.emulated]))
        let physical = game(repo, "Gunstar Heroes", on: "Genesis", [.physical])
        let questions = repo.noteConsoles(for: physical)

        #expect(questions.count == 1)
        #expect(questions.first?.platform == "Genesis")
        #expect(questions.first?.ownership == .physical)
        // And it has NOT been applied.
        #expect(repo.console(forPlatform: "Genesis")?.ownership == [Ownership.emulated.rawValue])
    }

    @Test("Yes adds it; no is remembered and never asked again")
    func answeringSticks() {
        let repo = store()
        repo.noteConsoles(for: game(repo, "Sonic 2", on: "Genesis", [.emulated]))
        let q = repo.noteConsoles(for: game(repo, "Gunstar Heroes", on: "Genesis", [.physical])).first
        let question = try! #require(q)

        repo.answer(question, yes: false)
        #expect(repo.console(forPlatform: "Genesis")?.ownership == [Ownership.emulated.rawValue])
        // A third physical game must not raise it again.
        let again = repo.noteConsoles(for: game(repo, "Vectorman", on: "Genesis", [.physical]))
        #expect(again.isEmpty, "the refusal is remembered")

        repo.answer(question, yes: true)
        #expect(repo.console(forPlatform: "Genesis")?.ownership.contains(Ownership.physical.rawValue) == true)
    }

    @Test("The waiting questions carry a count, because one game is a display copy and eleven is a machine")
    func pendingQuestionsCount() {
        let repo = store()
        var games: [Game] = []
        games.append(game(repo, "Sonic 2", on: "Genesis", [.emulated]))
        repo.noteConsoles(for: games[0])
        for name in ["Gunstar Heroes", "Vectorman", "Ristar"] {
            games.append(game(repo, name, on: "Genesis", [.physical]))
        }
        let pending = repo.pendingConsoleQuestions(in: games)
        #expect(pending.count == 1)
        #expect(pending.first?.ownership == .physical)
        #expect(pending.first?.games == 3)
    }

    // MARK: Migration

    @Test("Back-fill creates from the EARLIEST game on each platform, inherits its ownership, and is idempotent")
    func backfill() {
        let repo = store()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let games = [
            game(repo, "Sonic 2", on: "Genesis", [.emulated], added: day),
            game(repo, "Gunstar Heroes", on: "Genesis", [.physical], added: day.addingTimeInterval(60)),
            game(repo, "Super Metroid", on: "SNES", [.physical], added: day.addingTimeInterval(120)),
        ]

        #expect(repo.backfillConsoles(in: games) == 2)
        #expect(repo.console(forPlatform: "Genesis")?.ownership == [Ownership.emulated.rawValue],
                "the earliest Genesis game was emulated")
        #expect(repo.console(forPlatform: "SNES")?.ownership == [Ownership.physical.rawValue])
        // Running again creates nothing.
        #expect(repo.backfillConsoles(in: games) == 0)
        // And the physical Genesis games are waiting as a question rather than
        // having silently marked the hardware owned.
        #expect(repo.pendingConsoleQuestions(in: games).first?.ownership == .physical)
    }

    // MARK: Deleting, and staying deleted

    @Test("A deleted console does not come back on the next pass")
    func deletionSticks() {
        let repo = store()
        let games = [game(repo, "Sonic 2", on: "Genesis", [.emulated])]
        repo.backfillConsoles(in: games)
        let console = try! #require(repo.console(forPlatform: "Genesis"))

        repo.softDelete(console)
        #expect(repo.liveConsoles().isEmpty)
        #expect(repo.dismissedConsoles().contains("Genesis"))
        #expect(repo.backfillConsoles(in: games) == 0, "the dismissal outlives the record")
        #expect(repo.noteConsoles(for: games[0]).isEmpty)
        #expect(repo.liveConsoles().isEmpty)
    }

    @Test("Restoring one, or adding it by hand, takes it off the dismissed list and never duplicates")
    func restoreAndAdd() {
        let repo = store()
        let games = [game(repo, "Sonic 2", on: "Genesis", [.emulated])]
        repo.backfillConsoles(in: games)
        let console = try! #require(repo.console(forPlatform: "Genesis"))
        repo.softDelete(console)

        repo.restore(console)
        #expect(repo.liveConsoles().count == 1)
        #expect(repo.dismissedConsoles().isEmpty)

        // Deleting again and adding by hand revives the same row rather than
        // standing a second Genesis beside the tombstone.
        repo.softDelete(console)
        let added = repo.addConsole(platform: "Sega Genesis", ownership: [.physical])
        #expect(added.id == console.id)
        #expect(repo.liveConsoles().count == 1)
        #expect(repo.trashedConsoles().isEmpty)
        #expect(repo.dismissedConsoles().isEmpty)
    }

    @Test("A console can exist with no games at all — the Dreamcast in the display case")
    func consoleWithoutGames() {
        let repo = store()
        let dc = repo.addConsole(platform: "Sega Dreamcast", ownership: [.physical])
        #expect(dc.platform == "Dreamcast")
        #expect(repo.liveConsoles().map(\.platform) == ["Dreamcast"])
        #expect(repo.pendingConsoleQuestions(in: []).isEmpty)
    }

    @Test("Ownership does not cascade: the console keeps its own answer")
    func nothingCascades() {
        let repo = store()
        let g = game(repo, "Sonic 2", on: "Genesis", [.physical])
        repo.noteConsoles(for: g)
        let console = try! #require(repo.console(forPlatform: "Genesis"))

        // Sell the games; the console is untouched.
        g.ownership = [Ownership.previouslyOwned.rawValue]
        repo.noteConsoles(for: g)
        #expect(console.ownership == [Ownership.physical.rawValue])

        // Sell the console; the games are untouched.
        repo.updateConsole(console, ownership: [.previouslyOwned])
        #expect(g.ownership == [Ownership.previouslyOwned.rawValue])
        #expect(console.ownership == [Ownership.previouslyOwned.rawValue])
    }

    @Test("The canonical fold is the identity, and it survives the move out of UI")
    func canonicalNames() {
        #expect(PlatformKey.canonical("Nintendo Switch 2") == "Switch 2")
        #expect(PlatformKey.canonical("Sega Mega Drive/Genesis") == "Genesis")
        #expect(PlatformKey.canonical("PlayStation") == "PS1")
        #expect(PlatformKey.canonical("Something Unheard Of") == "Something Unheard Of")
        // PlatformShort still answers the same, for every existing call site.
        #expect(PlatformShort.builtinName("Nintendo Switch 2") == PlatformKey.canonical("Nintendo Switch 2"))
    }
}
