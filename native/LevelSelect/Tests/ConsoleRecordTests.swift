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

    // MARK: The shelf, and the round trip

    @Test("A console with no games still stands on the shelf — that is what the record is for")
    func shelfIncludesGamelessConsoles() {
        let repo = store()
        let games = [game(repo, "Sonic 2", on: "Genesis", [.emulated])]
        repo.backfillConsoles(in: games)
        repo.addConsole(platform: "Sega Dreamcast", ownership: [.physical])

        let groups = HomeSystems.folded(games, consoles: repo.liveConsoles().map(\.platform))
        let byName = Dictionary(groups.map { (PlatformShort.builtinName($0.platform), $0.count) },
                                uniquingKeysWith: { a, _ in a })
        #expect(byName["Genesis"] == 1)
        #expect(byName["Dreamcast"] == 0, "owned, nothing logged on it, still on the shelf")
        // And it does not double a console that DOES have games.
        #expect(groups.filter { PlatformShort.builtinName($0.platform) == "Genesis" }.count == 1)
    }

    @Test("Consoles survive a backup and a restore, including the questions already answered")
    func exportRoundTrip() throws {
        let repo = store()
        let console = repo.addConsole(platform: "Sega Mega Drive/Genesis", ownership: [.physical, .emulated])
        repo.updateConsole(console, variant: "Model 1", acquiredAt: .some(Date(timeIntervalSince1970: 800_000_000)), notes: "My brother's")
        console.declinedOwnership = [Ownership.digital.rawValue]

        let data = try LibraryExport.makeJSON(context: repo.context)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let consoles = try #require(root["consoles"] as? [[String: Any]])
        #expect(consoles.count == 1)
        #expect(consoles[0]["platform"] as? String == "Genesis")
        #expect(consoles[0]["variant"] as? String == "Model 1")
        #expect((consoles[0]["declinedOwnership"] as? [String]) == [Ownership.digital.rawValue])

        // Into an empty library.
        let fresh = store()
        _ = try LibraryImport.apply(data: data, context: fresh.context)
        let restored = try #require(fresh.liveConsoles().first)
        #expect(restored.platform == "Genesis")
        #expect(Set(restored.ownership) == [Ownership.physical.rawValue, Ownership.emulated.rawValue])
        #expect(restored.variant == "Model 1")
        #expect(restored.notes == "My brother's")
        #expect(restored.acquiredAt != nil)
        #expect(restored.declinedOwnership == [Ownership.digital.rawValue],
                "a question already answered must not be asked again after a restore")

        // Importing the same file twice does not stand a second Genesis.
        _ = try LibraryImport.apply(data: data, context: fresh.context)
        #expect(fresh.liveConsoles().count == 1)
    }

    // MARK: A rename reaches records already written

    @Test("A console stored under an old name follows the fold, and does not stand beside its new self")
    func storedPlatformsRefold() {
        let repo = store()
        // Written before 09-08, when both names still stood on their own.
        let old = Console(platform: "Recalbox", ownership: [Ownership.physical.rawValue])
        old.createdAt = Date(timeIntervalSince1970: 1_000_000)
        repo.context.insert(old)
        let linux = Console(platform: "Linux", ownership: [Ownership.digital.rawValue])
        linux.createdAt = Date(timeIntervalSince1970: 1_000_100)
        repo.context.insert(linux)

        repo.backfillConsoles(in: [])

        let names = repo.liveConsoles().map(\.platform).sorted()
        #expect(names == ["PC", "Raspberry Pi"])
        // The record kept its ownership through the rename; nothing was
        // recreated empty beside it.
        #expect(repo.console(forPlatform: "Raspberry Pi")?.ownership
                    == [Ownership.physical.rawValue])
        #expect(repo.console(forPlatform: "Recalbox")?.id == old.id)
    }

    @Test("Where a fold merges two records the older one wins, and no duplicate is left behind")
    func refoldMergesCollidingRecords() {
        let repo = store()
        let pc = Console(platform: "PC", ownership: [Ownership.physical.rawValue])
        pc.createdAt = Date(timeIntervalSince1970: 1_000_000)
        pc.notes = "the tower under the desk"
        repo.context.insert(pc)
        let linux = Console(platform: "Linux", ownership: [Ownership.digital.rawValue])
        linux.createdAt = Date(timeIntervalSince1970: 2_000_000)
        repo.context.insert(linux)

        repo.backfillConsoles(in: [])

        #expect(repo.liveConsoles().map(\.platform) == ["PC"])
        #expect(repo.console(forPlatform: "PC")?.notes == "the tower under the desk")
        // And a second pass changes nothing.
        repo.backfillConsoles(in: [])
        #expect(repo.liveConsoles().count == 1)
    }

    // MARK: Which one to draw

    @Test("Choosing a model changes the picture and nothing else")
    func variantChangesArtNotIdentity() {
        defer { PlatformIcon.variantOverrides = [:] }
        PlatformIcon.variantOverrides = [:]
        #expect(PlatformIcon.artName("Saturn") == "platform-saturn")

        PlatformIcon.variantOverrides = ["Saturn": "jp"]
        #expect(PlatformIcon.artName("Saturn") == "variant-saturn-jp")
        #expect(PlatformIcon.artName("Sega Saturn") == "variant-saturn-jp",
                "every spelling folds to the same choice")

        // **Identity, year and maker must not move.** `assetName` is the key a
        // console is filed under; if the shell someone owns changed it, two
        // libraries would disagree about what a Saturn is.
        #expect(PlatformIcon.assetName("Saturn") == "platform-saturn")
        #expect(PlatformIcon.consoleKey("Sega Saturn") == PlatformIcon.consoleKey("Saturn"))
        #expect(PlatformEra.releaseYear("Saturn") == 1995)
        #expect(PlatformMaker.of("Saturn") == "Sega")
    }

    @Test("A stored key this build has no art for draws the default rather than nothing")
    func unknownVariantFallsBack() {
        defer { PlatformIcon.variantOverrides = [:] }
        PlatformIcon.variantOverrides = ["Saturn": "a-model-from-a-newer-build"]
        #expect(PlatformIcon.artName("Saturn") == "platform-saturn")
        // And a console with no variants at all is untouched by any of it.
        PlatformIcon.variantOverrides = ["Dreamcast": "whatever"]
        #expect(PlatformIcon.artName("Dreamcast") == "platform-dreamcast")
        #expect(PlatformVariant.variants(for: "Dreamcast").isEmpty)
    }

    @Test("Every variant names art that exists, and the first is the shipped one")
    func theVariantCatalogueIsHonest() {
        for (platform, list) in PlatformVariant.catalog {
            #expect(list.count > 1,
                    Comment(rawValue: "\(platform) offers a choice of one"))
            #expect(list.first?.asset == nil,
                    Comment(rawValue: "\(platform)'s default must defer to assetName"))
            #expect(PlatformIcon.assetName(platform) != nil,
                    Comment(rawValue: "\(platform) has no base art"))
            var keys = Set<String>()
            for variant in list {
                #expect(keys.insert(variant.key).inserted,
                        Comment(rawValue: "\(platform) repeats the key \(variant.key)"))
            }
            // Variant art lives OUTSIDE the platform- namespace, so the
            // art-to-years and art-to-makers invariants never see it.
            for variant in list.dropFirst() {
                #expect(variant.asset?.hasPrefix("variant-") == true,
                        Comment(rawValue: "\(variant.key) is not in the variant namespace"))
            }
        }
    }

    @Test("The lineage rides in the variant map without changing its shape")
    func lineageStoresBesideTheIconChoice() {
        var map: [String: String] = [:]

        // Nothing ticked: the drawn one still stands alone, because it is on
        // the shelf and the page must not contradict the tile.
        #expect(PlatformVariant.owned(for: "Mac", in: map).map(\.key) == ["mini"])

        PlatformVariant.setOwned(["compact", "imac-g3"], for: "Mac", in: &map)
        // **Oldest first** — a lineage reads forward in time — and the drawn
        // machine is folded in whether or not it was ticked.
        #expect(PlatformVariant.owned(for: "Mac", in: map).map(\.key)
                == ["compact", "imac-g3", "mini"])

        // The icon choice is untouched by any of it, and still a single key.
        map["Mac"] = "imac-g3"
        #expect(PlatformIcon.artName("Mac") == "platform-mac",
                "artName reads the override cache, not this map")
        #expect(map["Mac"] == "imac-g3")

        // **The shape an older build decodes is unchanged.** Every value is a
        // String, and the lineage hides under a key no platform can be called.
        #expect(map.keys.contains { $0.hasPrefix("#") })
        #expect(PlatformKey.canonical("#had:Mac") == "#had:Mac",
                "the marker must never collide with a real platform name")
        for (_, value) in map { #expect(!value.isEmpty) }

        // Unticking everything removes the entry rather than leaving a blank.
        PlatformVariant.setOwned([], for: "Mac", in: &map)
        #expect(!map.keys.contains { $0.hasPrefix("#had:") })
        #expect(map["Mac"] == "imac-g3", "and takes nothing else with it")

        // A console with one machine has no lineage to show.
        #expect(PlatformVariant.owned(for: "Dreamcast", in: map).isEmpty)
    }

    @Test("A lineage reads forward in time whichever end the default is")
    func lineageIsOldestFirstEvenWhenTheDefaultIsOldest() {
        // The GBA, SNES and NES default to their ORIGINAL machine, so their
        // catalogs run oldest-first — the opposite of the Mac's. Reversing
        // the catalog read the GBA as SP, then the one it replaced.
        var map: [String: String] = [:]
        PlatformVariant.setOwned(["agb", "sp"], for: "GBA", in: &map)
        #expect(PlatformVariant.owned(for: "GBA", in: map).map(\.key) == ["agb", "sp"])
        PlatformVariant.setOwned(["original", "jr"],
                                 for: "Super Nintendo Entertainment System", in: &map)
        #expect(PlatformVariant.owned(for: "SNES", in: map).map(\.key) == ["original", "jr"])
        PlatformVariant.setOwned(["top-loader"], for: "NES", in: &map)
        #expect(PlatformVariant.owned(for: "NES", in: map).map(\.key)
                == ["front-loader", "top-loader"])

        // And every dated catalog, fully ticked, comes out in year order.
        for (platform, list) in PlatformVariant.catalog {
            var all: [String: String] = [:]
            PlatformVariant.setOwned(Set(list.map(\.key)), for: platform, in: &all)
            let years = PlatformVariant.owned(for: platform, in: all).compactMap(\.year)
            #expect(years == years.sorted(),
                    Comment(rawValue: "\(platform) reads \(years)"))
        }
    }

    // MARK: The photograph

    @Test("A console keeps photographs, and they survive a backup")
    func consolePhotosRoundTrip() throws {
        let repo = store()
        let console = repo.addConsole(platform: "Sega Dreamcast", ownership: [.physical])
        let png = try #require(Self.onePixelPNG)
        try repo.addImage(to: console, data: png, caption: "on the shelf")

        let saved = repo.liveConsoles().first { $0.platform == "Dreamcast" }
        #expect((saved?.images ?? []).count == 1)
        #expect((saved?.images ?? []).first?.caption == "on the shelf")

        let data = try LibraryExport.makeJSON(context: repo.context)
        let into = store()
        let outcome = try LibraryImport.apply(data: data, context: into.context)
        #expect(outcome.created["consoles"] == 1)
        #expect(outcome.created["images"] == 1)

        let restored = into.liveConsoles().first { $0.platform == "Dreamcast" }
        #expect((restored?.images ?? []).count == 1)
        #expect((restored?.images ?? []).first?.caption == "on the shelf")
    }

    @Test("Removing a photograph removes it — the bytes are the point")
    func removingAPhotoIsNotATombstone() throws {
        let repo = store()
        let console = repo.addConsole(platform: "Genesis")
        let png = try #require(Self.onePixelPNG)
        let image = try repo.addImage(to: console, data: png)
        #expect((console.images ?? []).count == 1)
        repo.removeImage(image, from: console)
        #expect((console.images ?? []).filter { $0.deletedAt == nil }.isEmpty)
    }

    /// The smallest thing `ImageIngest` will accept, so these tests exercise
    /// the real ingest path rather than a stub.
    static let onePixelPNG: Data? = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
}
