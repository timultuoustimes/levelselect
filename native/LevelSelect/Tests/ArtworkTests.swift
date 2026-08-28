import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 32 — artwork roles, user-added images, and the guarantees around
/// them: what fills a role, what happens when a picture is removed, and that
/// the export really does carry the bytes back.
@MainActor
struct ArtworkTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// A 2x2 red PNG — small, real, and decodable by ImageIO.
    private var samplePNG: Data {
        Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg==")!
    }

    // MARK: Pointers

    @Test func localPointersRoundTripAndRemoteOnesDont() {
        let id = UUID()
        let local = ArtworkPointer.local(id)
        #expect(ArtworkPointer.localID(local) == id)
        #expect(ArtworkPointer.remoteURL(local) == nil)

        let remote = "https://images.igdb.com/x.jpg"
        #expect(ArtworkPointer.localID(remote) == nil)
        #expect(ArtworkPointer.remoteURL(remote)?.absoluteString == remote)
    }

    // MARK: Role resolution

    @Test func coverFallsBackToTheFetchedArtButAChoiceWins() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Mina the Hollower", status: .playing)
        game.coverURLString = "https://images.igdb.com/fetched.jpg"

        #expect(game.resolvedArtwork(.cover) == .remote(URL(string: "https://images.igdb.com/fetched.jpg")!))

        repo.setArtwork("https://example.com/chosen.jpg", role: .cover, on: game)
        #expect(game.resolvedArtwork(.cover) == .remote(URL(string: "https://example.com/chosen.jpg")!))
        // The fetched field is never touched, so "use the default" always works.
        #expect(game.coverURLString == "https://images.igdb.com/fetched.jpg")
    }

    /// The backdrop's whole point: it prefers a 16:9 artwork, and only falls
    /// back to the portrait cover when there isn't one.
    @Test func backdropFallsBackToTheCover() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Lone Ruin", status: .playing)
        game.coverURLString = "https://images.igdb.com/cover.jpg"

        #expect(game.resolvedArtwork(.backdrop) == .remote(URL(string: "https://images.igdb.com/cover.jpg")!))

        repo.setArtwork("https://images.igdb.com/artwork.jpg", role: .backdrop, on: game)
        #expect(game.resolvedArtwork(.backdrop) == .remote(URL(string: "https://images.igdb.com/artwork.jpg")!))
    }

    /// A logo has NO image fallback — the name in text is the fallback, and
    /// that belongs to the view. A cover standing in for a wordmark would be
    /// worse than plain text.
    @Test func logoHasNoImageFallback() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .playing)
        game.coverURLString = "https://images.igdb.com/cover.jpg"
        #expect(game.resolvedArtwork(.logo) == .none)
    }

    // MARK: User images

    @Test func addingAnImageStoresBytesAndDimensions() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)

        let image = try repo.addImage(to: game, data: samplePNG, role: .gallery)
        #expect(image.data?.isEmpty == false)
        #expect(image.pixelWidth == 2)
        #expect(image.pixelHeight == 2)
        #expect(image.byteCount == image.data?.count)
        #expect(game.liveImages.count == 1)
    }

    @Test func aChosenLocalImageFillsItsRole() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        let image = try repo.addImage(to: game, data: samplePNG, role: .cover)
        repo.setArtwork(image.pointer, role: .cover, on: game)

        guard case .local(let data) = game.resolvedArtwork(.cover) else {
            Issue.record("expected local artwork"); return
        }
        #expect(!data.isEmpty)
    }

    /// Removing a picture must also release any role aimed at it. A role
    /// pointing at a deleted image would render its fallback while still
    /// reporting itself as set — the menu would say "Change Cover" forever.
    @Test func deletingAnImageClearsRolesPointingAtIt() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        game.coverURLString = "https://images.igdb.com/cover.jpg"
        let image = try repo.addImage(to: game, data: samplePNG, role: .cover)
        repo.setArtwork(image.pointer, role: .cover, on: game)
        #expect(game.pointer(for: .cover) != nil)

        repo.softDelete(image)
        #expect(game.pointer(for: .cover) == nil)
        #expect(game.liveImages.isEmpty)
        // …and the fetched cover comes back rather than a blank.
        #expect(game.resolvedArtwork(.cover) == .remote(URL(string: "https://images.igdb.com/cover.jpg")!))
    }

    /// A local cover deliberately does NOT fall through to the fetched URL in
    /// `displayCoverURLString`. Quietly showing different art because that
    /// accessor can't express bytes would be a lie about which picture is set.
    @Test func displayCoverURLIsNilForALocalChoice() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        game.coverURLString = "https://images.igdb.com/cover.jpg"
        let image = try repo.addImage(to: game, data: samplePNG, role: .cover)
        repo.setArtwork(image.pointer, role: .cover, on: game)
        #expect(game.displayCoverURLString == nil)
    }

    // MARK: Ingest

    @Test func ingestRejectsThingsThatArentImages() {
        #expect(throws: ImageIngest.Failure.unreadable) {
            _ = try ImageIngest.prepare(Data("not an image".utf8), role: .gallery)
        }
    }

    /// Logos keep their alpha channel — a wordmark re-encoded as JPEG picks up
    /// a black box, which is the one place transparency is load-bearing.
    @Test func logoIngestKeepsPNG() throws {
        let result = try ImageIngest.prepare(samplePNG, role: .logo)
        // PNG magic number.
        #expect(result.data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    // MARK: Export round trip — the promise that matters

    @Test func imagesAndArtworkChoicesSurviveExportAndImport() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Mina the Hollower", status: .playing)
        game.coverURLString = "https://images.igdb.com/fetched.jpg"
        let image = try repo.addImage(to: game, data: samplePNG, role: .cover,
                                      caption: "the cart I traded away")
        repo.setArtwork(image.pointer, role: .cover, on: game)
        repo.setArtwork("https://example.com/logo.png", role: .logo, on: game)
        repo.setArtwork("https://example.com/art.jpg", role: .backdrop, on: game)

        let data = try LibraryExport.makeJSON(context: context)
        let fresh = makeContext()
        _ = try LibraryImport.apply(data: data, context: fresh)

        let restored = try #require(
            try fresh.fetch(FetchDescriptor<Game>()).first { $0.deletedAt == nil })
        #expect(restored.logoURLString == "https://example.com/logo.png")
        #expect(restored.backdropURLString == "https://example.com/art.jpg")

        let restoredImage = try #require(restored.liveImages.first)
        #expect(restoredImage.caption == "the cart I traded away")
        #expect(restoredImage.data == image.data)
        // The pointer names the same id, so the role still resolves to bytes.
        guard case .local = restored.resolvedArtwork(.cover) else {
            Issue.record("cover should still resolve to the local image"); return
        }
    }

    /// An image record with no bytes is skipped rather than created: a
    /// picture that renders nothing is worse than an absent one, because it
    /// occupies a gallery slot and a role pointer while showing a fallback.
    @Test func importSkipsImageRecordsWithNoBytes() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        _ = try repo.addImage(to: game, data: samplePNG, role: .gallery)

        var root = try #require(
            try JSONSerialization.jsonObject(with: try LibraryExport.makeJSON(context: context))
            as? [String: Any])
        var games = try #require(root["games"] as? [[String: Any]])
        var images = try #require(games[0]["images"] as? [[String: Any]])
        images[0].removeValue(forKey: "data")
        games[0]["images"] = images
        root["games"] = games
        let stripped = try JSONSerialization.data(withJSONObject: root)

        let fresh = makeContext()
        _ = try LibraryImport.apply(data: stripped, context: fresh)
        let restored = try #require(
            try fresh.fetch(FetchDescriptor<Game>()).first { $0.deletedAt == nil })
        #expect(restored.liveImages.isEmpty)
    }

    // MARK: Backdrop intensity

    @Test func backdropIntensityDecodesAndBoldBlursLess() {
        #expect(BackdropIntensity(rawValue: "bold") == .bold)
        // Bold shows the art rather than a smear of its average colour.
        #expect(BackdropIntensity.bold.blurRadius < BackdropIntensity.subtle.blurRadius)
        #expect(BackdropIntensity.bold.opacity > BackdropIntensity.subtle.opacity)
        #expect(BackdropIntensity.off.opacity == 0)
    }
}

/// The backdrop's source preference and the blur scale — the two things that
/// made "prefers a 16:9 artwork" untrue in the first cut of build 32.
@MainActor
struct BackdropSourceTests {

    /// Key art and screenshots are new cases on an EXISTING String-raw field,
    /// so the library-wide preference costs no schema change and no promote.
    @Test func artworkBackgroundsDecodeAndNameTheirEndpoint() {
        #expect(ThemePageBackground(rawValue: "keyArt") == .keyArt)
        #expect(ThemePageBackground(rawValue: "screenshot") == .screenshot)
        #expect(ThemePageBackground.keyArt.igdbEndpoint == "artworks")
        #expect(ThemePageBackground.screenshot.igdbEndpoint == "screenshots")
        // Flat colours need no lookup at all.
        #expect(ThemePageBackground.plain.igdbEndpoint == nil)
        #expect(ThemePageBackground.status.igdbEndpoint == nil)
        // The cover draws art but needs no fetch — it's already on the game.
        #expect(ThemePageBackground.cover.igdbEndpoint == nil)
        #expect(ThemePageBackground.cover.usesArtwork)
        #expect(!ThemePageBackground.accent.usesArtwork)
    }

    /// An older build reading a value it doesn't know falls back to `.cover`
    /// through ThemePalette's nil-coalesce, rather than failing to draw.
    @Test func unknownBackgroundValuesDecodeToNil() {
        #expect(ThemePageBackground(rawValue: "somethingNewer") == nil)
    }

    /// The first pass used 60/44/22pt, which destroys the image before
    /// opacity matters. Tim's own mockup uses 3pt. Every setting must now sit
    /// in a range where the art is still legible AS art.
    @Test func blurIsSmallEnoughToSeeTheArt() {
        for intensity in BackdropIntensity.allCases {
            #expect(intensity.blurRadius <= 8,
                    "\(intensity.label) blurs \(intensity.blurRadius)pt — the art stops being readable well below this")
        }
        // Bold means "show me the art", so it doesn't blur at all.
        #expect(BackdropIntensity.bold.blurRadius == 0)
        #expect(BackdropIntensity.bold.opacity == 1.0)
        // …and still descends monotonically as strength rises.
        #expect(BackdropIntensity.subtle.blurRadius > BackdropIntensity.standard.blurRadius)
        #expect(BackdropIntensity.standard.blurRadius > BackdropIntensity.bold.blurRadius)
    }
}
