import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// A cover you chose yourself has to appear on the shelves, not only on the
/// game page.
///
/// `ArtworkPointer` stores a picked photo as `levelselect-image:<id>`, and
/// `Game.displayCoverURLString` returns nil for that deliberately — it will
/// not substitute the fetched cover for the one you actually picked. Every
/// shelf, list and strip then asked `CoverThumb` to load a URL, got nil, and
/// drew the placeholder. The game page was the only surface that showed the
/// picture, because it goes through `resolvedArtwork` instead.
///
/// So the contract worth pinning is the pair: `displayCoverURLString` stays
/// nil (that part is correct and load-bearing), and `resolvedArtwork(.cover)`
/// carries the bytes that the URL cannot. A shelf that reads only the first
/// one is the bug.
@MainActor
struct LocalCoverVisibilityTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// A 1×1 PNG — enough to be stored and pointed at.
    private let pixel = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    @Test func aPickedCoverIsInvisibleToAUrlOnlyReader() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = Game(name: "Hollow Knight")
        context.insert(game)

        let image = try repo.addImage(to: game, data: pixel, role: .cover)
        repo.setArtwork(image.pointer, role: .cover, on: game)

        // The URL accessor is nil on purpose, and that is exactly why a
        // URL-only shelf cannot draw this cover.
        #expect(game.displayCoverURLString == nil)
        // The bytes are reachable — a shelf just has to ask for them.
        guard case .local(let data) = game.resolvedArtwork(.cover) else {
            Issue.record("a picked cover should resolve as local artwork")
            return
        }
        #expect(!data.isEmpty)
    }

    /// A fetched cover is unaffected: the URL still leads, and there is no
    /// local artwork to prefer over it.
    @Test func aFetchedCoverStillTravelsAsAUrl() {
        let context = makeContext()
        let game = Game(name: "Hades")
        game.coverURLString = "https://images.igdb.com/hades.jpg"
        context.insert(game)

        #expect(game.displayCoverURLString == "https://images.igdb.com/hades.jpg")
        // Nothing local to prefer, so the shelf falls through to the URL it
        // has always used.
        if case .local = game.resolvedArtwork(.cover) {
            Issue.record("a fetched cover should not resolve as local artwork")
        }
    }

    /// A picked cover wins over a fetched one — the precedence the shelf now
    /// applies has to match the precedence `displayCoverURLString` already
    /// applied, or the two surfaces disagree about which picture is yours.
    @Test func aPickedCoverBeatsAFetchedOne() throws {
        let context = makeContext()
        let repo = Repository(context)
        let game = Game(name: "Celeste")
        game.coverURLString = "https://images.igdb.com/celeste.jpg"
        context.insert(game)

        let image = try repo.addImage(to: game, data: pixel, role: .cover)
        repo.setArtwork(image.pointer, role: .cover, on: game)

        #expect(game.displayCoverURLString == nil)
        if case .local = game.resolvedArtwork(.cover) {} else {
            Issue.record("the picked cover should win over the fetched URL")
        }
    }
}

/// **The six call sites the first pass missed.**
///
/// `LocalCoverVisibilityTests` proved the model contract and nothing else, so
/// it could not tell that six live game-backed surfaces still asked only for a
/// URL. Codex found them on 2026-09-07. The one worth a real test is
/// `PlayerSummary`, because it is not a view — the Home header can only draw
/// what the summary hands it, so a URL-shaped summary made a picked cover
/// impossible to show no matter what the header did.
@MainActor
struct Build37SummaryArtworkTests {

    private let pixel = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func played(_ repo: Repository, _ game: Game) {
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.logManualSession(on: pt, duration: 600)
    }

    @Test func aPickedCoverReachesTheHomeRibbon() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let image = try repo.addImage(to: game, data: pixel, role: .cover)
        repo.setArtwork(image.pointer, role: .cover, on: game)
        played(repo, game)

        #expect(game.displayCoverURLString == nil)   // the old field, still nil
        let summary = PlayerSummary.make(from: [game])
        #expect(summary.recentCovers.count == 1)
        guard case .local(let data) = summary.recentCovers.first else {
            Issue.record("a picked cover should reach the summary as local bytes")
            return
        }
        #expect(!data.isEmpty)
    }

    @Test func aPickedCoverAlsoBacksTheQuietWeekFallback() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .playing)
        let image = try repo.addImage(to: game, data: pixel, role: .cover)
        repo.setArtwork(image.pointer, role: .cover, on: game)

        // Nothing played this week, so the header falls back to one game's art.
        let summary = PlayerSummary.make(from: [game])
        #expect(!summary.usesRibbon)
        guard case .local = summary.fallbackBackdrop else {
            Issue.record("the fallback should carry the picked cover")
            return
        }
        // And the header agrees there is art to draw.
        #expect(ProfileHeader.drawsArt(profile: nil, summary: summary))
    }

    /// A remote cover still resolves the way it always did.
    @Test func aFetchedCoverStillArrivesAsARemoteURL() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        game.coverURLString = "https://example.com/hades.jpg"
        played(repo, game)

        let summary = PlayerSummary.make(from: [game])
        #expect(summary.recentCovers == [.remote(URL(string: "https://example.com/hades.jpg")!)])
    }

    /// A game with no art at all contributes nothing, so the header does not
    /// reserve 190pt for an empty band.
    @Test func aGameWithNoArtIsNotCounted() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hand Added", status: .playing)
        played(repo, game)

        let summary = PlayerSummary.make(from: [game])
        #expect(summary.recentCovers.isEmpty)
        #expect(summary.fallbackBackdrop == nil)
        #expect(!ProfileHeader.drawsArt(profile: nil, summary: summary))
    }
}
