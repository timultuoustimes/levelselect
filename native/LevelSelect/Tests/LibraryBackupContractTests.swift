import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// **The backup's contract, asserted field by field.**
///
/// Two rounds of data loss motivated this file, and both were the same bug:
/// `LibraryExport` is a hand-written allowlist, someone added a model or a
/// property, and nobody added it to the allowlist. `Memory` went missing that
/// way (found by hand after build 36 shipped); `TrackerItemDetail`,
/// `PlayerProfile`, `ownedPlatforms`, `completedAt` and `selectedVariant` were
/// still missing when the build 37 assessments went looking, and the whole
/// `appearance` block was written by the exporter and read by nothing.
///
/// The existing `LibraryExportTests` could not catch any of it: its fixture
/// populates the fields its author remembered, so a field nobody remembered is
/// invisible to it. This file works the other way round — every authored value
/// gets a **distinctive sentinel**, and the round trip must return that exact
/// sentinel. A field that is dropped comes back nil or default, and the
/// comparison fails by construction rather than by anyone noticing.
///
/// **When you add a stored property that a user can author or choose, add it
/// here.** `SchemaFreezeTests` will tell you the schema changed; this tells you
/// whether the backup kept up.
@MainActor
struct LibraryBackupContractTests {

    // MARK: Sentinels

    private enum S {
        static let gameName        = "Sentinel Quest"
        static let review          = "A review sentence that must survive."
        static let ownedPlatforms  = ["Nintendo Switch", "PC (Microsoft Windows)"]
        static let availablePlatforms = ["Nintendo Switch", "PC (Microsoft Windows)", "PlayStation 5"]
        static let itemID          = "collectible-42"
        static let note            = "Behind the waterfall, after the second bell."
        static let chosenName      = "The one I renamed"
        static let sourceName      = "Generated Name"
        static let variant         = "alt"
        static let displayName     = "Sentinel Player"
        static let handle          = "sentinel-handle"
        static let accentHex       = "#8A5CF6"
        static let backgroundHex   = "#F5A34D"
        static let starName        = "Adored it"
        static let statusName      = "Currently Obsessed"
        static let dekuURL         = "https://example.invalid/deku-sentinel"
        /// Deliberately not a 1×1: the avatar is the one value in the whole
        /// backup that cannot be retyped from memory.
        static let avatar          = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])
        static let completedAt     = Date(timeIntervalSince1970: 1_700_000_000)
        static let variantSetAt    = Date(timeIntervalSince1970: 1_710_000_000)
        static let accentLight     = "#996630"
        static let accentDark      = "#F5A34D"
        static let groundLight     = "#EFEAFB"
        static let groundDark      = "#241A3A"
    }

    private func emptyStore() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// A library where **every authored or user-chosen field carries a sentinel.**
    private func authored() -> ModelContext {
        let context = emptyStore()
        let repo = Repository(context)

        let game = repo.addGame(name: S.gameName, status: .playing)
        game.rating = 4
        game.review = S.review
        game.platforms = S.availablePlatforms
        game.ownedPlatforms = S.ownedPlatforms
        game.showItemHintsOverride = false
        game.userTags = ["sentinel-tag"]
        game.notes = "Game notes sentinel"

        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: S.itemID, done: true)
        if let state = (pt.trackerStates ?? []).first(where: { $0.itemID == S.itemID }) {
            state.completedAt = S.completedAt
            state.selectedVariant = S.variant
            state.selectedVariantUpdatedAt = S.variantSetAt
            state.notes = "Per-run scribble"
        }

        // Game-scoped authored content — the model the backup forgot entirely.
        let detail = TrackerItemDetail(itemID: S.itemID,
                                       note: S.note,
                                       chosenName: S.chosenName,
                                       sourceName: S.sourceName)
        context.insert(detail)
        detail.game = game

        let profile = PlayerProfile()
        profile.displayName = S.displayName
        profile.avatarData = S.avatar
        profile.useHandleAsName = true
        profile.handles = ["steam": S.handle]
        context.insert(profile)

        let theme = ThemePalette.fetchOrCreate(in: context)
        theme.accentHex = S.accentHex
        theme.accentHue = 0.42
        theme.accentSaturation = 0.66
        theme.paletteLinked = false
        theme.accentHexLight = S.accentLight
        theme.accentHexDark = S.accentDark
        theme.backgroundHexLight = S.groundLight
        theme.backgroundHexDark = S.groundDark
        theme.backgroundHex = S.backgroundHex
        theme.appearanceRaw = "light"
        theme.gamePageLayoutRaw = "classic"
        theme.pageBackgroundRaw = "screenshot"
        theme.backdropIntensityRaw = "bold"
        theme.showGameLogos = false
        theme.showItemHints = false
        theme.dekuWishlistURLString = S.dekuURL
        theme.starNames = ["", "", "", "", S.starName]
        theme.statusNames = [GameStatus.playing.rawValue: S.statusName]
        theme.statusColors = [GameStatus.playing.rawValue: "#123456"]

        try? context.save()
        return context
    }

    /// Export from one store, import into a genuinely empty one.
    private func roundTrip(_ source: ModelContext) throws -> ModelContext {
        let data = try LibraryExport.makeJSON(context: source)
        let target = emptyStore()
        _ = try LibraryImport.apply(data: data, context: target)
        return target
    }

    // MARK: The contract

    @Test func trackerNotesAndRenamesSurvive() throws {
        let restored = try roundTrip(authored())
        let details = try restored.fetch(FetchDescriptor<TrackerItemDetail>())
        let detail = try #require(details.first { $0.itemID == S.itemID },
                                  "TrackerItemDetail did not survive the round trip")
        #expect(detail.note == S.note)
        #expect(detail.chosenName == S.chosenName)
        #expect(detail.sourceName == S.sourceName)
    }

    @Test func ownedPlatformsSurvive() throws {
        let restored = try roundTrip(authored())
        let game = try #require(try restored.fetch(FetchDescriptor<Game>()).first)
        // Not `platforms` — the systems the user actually owns it on. Nil here
        // reads as pre-V3 data and silently collapses to `platforms.first`.
        #expect(game.ownedPlatforms == S.ownedPlatforms)
        #expect(game.showItemHintsOverride == false)
    }

    @Test func trackerChoiceAndChronologySurvive() throws {
        let restored = try roundTrip(authored())
        let states = try restored.fetch(FetchDescriptor<TrackerStateRecord>())
        let state = try #require(states.first { $0.itemID == S.itemID })
        #expect(state.selectedVariant == S.variant)
        #expect(state.completedAt == S.completedAt)
        #expect(state.selectedVariantUpdatedAt == S.variantSetAt)
    }

    @Test func profileAndAvatarSurvive() throws {
        let restored = try roundTrip(authored())
        let profile = try #require(try restored.fetch(FetchDescriptor<PlayerProfile>()).first,
                                   "PlayerProfile did not survive the round trip")
        #expect(profile.displayName == S.displayName)
        #expect(profile.avatarData == S.avatar)
        #expect(profile.useHandleAsName)
        #expect(profile.handles["steam"] == S.handle)
    }

    @Test func appearanceIsRestored() throws {
        let restored = try roundTrip(authored())
        let theme = try #require(try restored.fetch(FetchDescriptor<ThemeSettings>()).first)
        #expect(theme.accentHex == S.accentHex)
        #expect(theme.backgroundHex == S.backgroundHex)
        // build 37: the per-appearance palette must round trip as two pairs,
        // not collapse back to the single legacy value.
        #expect(theme.accentHue == 0.42)
        #expect(theme.accentSaturation == 0.66)
        #expect(theme.paletteLinked == false)
        #expect(theme.accentHexLight == S.accentLight)
        #expect(theme.accentHexDark == S.accentDark)
        #expect(theme.backgroundHexLight == S.groundLight)
        #expect(theme.backgroundHexDark == S.groundDark)
        #expect(theme.appearanceRaw == "light")
        #expect(theme.gamePageLayoutRaw == "classic")
        #expect(theme.pageBackgroundRaw == "screenshot")
        #expect(theme.backdropIntensityRaw == "bold")
        #expect(theme.showGameLogos == false)
        #expect(theme.showItemHints == false)
        #expect(theme.dekuWishlistURLString == S.dekuURL)
        #expect(theme.starNames.last == S.starName)
        #expect(theme.statusNames[GameStatus.playing.rawValue] == S.statusName)
        #expect(theme.statusColors[GameStatus.playing.rawValue] == "#123456")
    }

    // MARK: Partial restore

    /// The importer's stated promise: "running it after a partial disaster
    /// restores exactly the missing part". A present parent whose child went
    /// missing is precisely that case, and it used to `continue` past it.
    @Test func aPresentMemoryStillGetsItsMissingPhotoBack() throws {
        let source = emptyStore()
        let memory = Memory(title: "Sentinel memory",
                            kind: "memory",
                            earliest: S.completedAt,
                            latest: S.completedAt,
                            precision: "day",
                            whenText: nil)
        source.insert(memory)
        // Built directly rather than through `addImage`, which runs the real
        // `ImageIngest` and would reject a sentinel that isn't a decodable image.
        let image = GameImage(role: .gallery, data: S.avatar)
        source.insert(image)
        image.memory = memory
        try? source.save()

        let data = try LibraryExport.makeJSON(context: source)

        // The disaster: the memory survives, its photo does not.
        source.delete(image)
        try? source.save()
        #expect(try source.fetch(FetchDescriptor<GameImage>()).isEmpty)

        _ = try LibraryImport.apply(data: data, context: source)

        let images = try source.fetch(FetchDescriptor<GameImage>())
        #expect(images.count == 1, "a present memory must still adopt its missing photo")
        #expect(images.first?.data == S.avatar)
    }

    // MARK: Version gate

    /// v3 must not be silently thinned by an older importer, which is the same
    /// reason the Memory fix bumped v1 → v2.
    @Test func formatVersionIsCurrentAndImporterAcceptsOlderFiles() throws {
        #expect(LibraryExport.formatVersion == 3)
        #expect(LibraryImport.supportedVersion == LibraryExport.formatVersion)

        // An older file still restores: accept older, refuse newer.
        var root = try #require(
            try JSONSerialization.jsonObject(
                with: try LibraryExport.makeJSON(context: authored())) as? [String: Any])
        var manifest = try #require(root["manifest"] as? [String: Any])
        manifest["formatVersion"] = 1
        root["manifest"] = manifest
        let v1 = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: Never.self) {
            _ = try LibraryImport.apply(data: v1, context: emptyStore())
        }

        manifest["formatVersion"] = LibraryExport.formatVersion + 1
        root["manifest"] = manifest
        let future = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: (any Error).self) {
            _ = try LibraryImport.apply(data: future, context: emptyStore())
        }
    }
}
