import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Playlists remember a position PER PART. `watchedSeconds` is a single
/// scalar, so before this a playlist could only ever hold one position across
/// every part — moving to part 3 overwrote where you were in part 2.
///
/// The positions live inside the existing `partsData` blob rather than in new
/// fields, so none of this needed a schema change.
@MainActor
struct VideoPartProgressTests {

    private func playlist() -> (Repository, GameVideo) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Mina the Hollower")
        let video = GameVideo(kind: .playlist, urlString: "https://youtube.com/playlist?list=X",
                              youtubeID: "X", title: "Walkthrough")
        context.insert(video)
        video.game = game
        repo.cachePlaylistParts(video, ids: ["a", "b", "c"],
                                titles: ["a": "Part 1", "b": "Part 2", "c": "Part 3"])
        return (repo, video)
    }

    @Test func eachPartKeepsItsOwnPosition() {
        let (repo, video) = playlist()
        repo.updateVideoProgress(video, seconds: 436, partIndex: 1)   // 7:16 into part 2
        repo.updateVideoProgress(video, seconds: 498, partIndex: 2)   // 8:18 into part 3

        #expect(video.parts[1].seconds == 436)
        #expect(video.parts[2].seconds == 498)
        // Part 2 wasn't disturbed by moving on to part 3.
        #expect(video.parts[0].seconds == 0)
    }

    /// The bug behind "individual videos within playlists don't hold their
    /// position": jumping to a part wrote 0 over its resume point at the exact
    /// moment you asked to go there.
    @Test func jumpingToAPartDoesNotWipeIt() {
        let (repo, video) = playlist()
        repo.updateVideoProgress(video, seconds: 436, partIndex: 1)

        repo.setVideoPart(video, index: 2)      // wander off
        repo.setVideoPart(video, index: 1)      // and come back

        #expect(video.parts[1].seconds == 436)
        #expect(video.watchedSeconds == 436)
        #expect(video.currentPartSeconds == 436)
    }

    /// The parts list is refetched whenever the player reports it, so a
    /// re-cache must not quietly reset every position.
    @Test func reCachingPartsPreservesPositions() {
        let (repo, video) = playlist()
        repo.updateVideoProgress(video, seconds: 436, partIndex: 1)

        repo.cachePlaylistParts(video, ids: ["a", "b", "c", "d"],
                                titles: ["a": "Part 1", "b": "Part 2",
                                         "c": "Part 3", "d": "Part 4"])

        #expect(video.parts.count == 4)
        #expect(video.parts[1].seconds == 436)
        #expect(video.parts[3].seconds == 0)
    }

    /// Rows written before per-part positions existed have two entries, not
    /// three. They must read as 0 rather than failing to parse — which would
    /// blank the whole parts list.
    @Test func legacyTwoColumnPartsStillParse() throws {
        let (repo, video) = playlist()
        video.partsData = try JSONSerialization.data(
            withJSONObject: [["a", "Part 1"], ["b", "Part 2"]])

        #expect(video.parts.count == 2)
        #expect(video.parts[0].title == "Part 1")
        #expect(video.parts[0].seconds == 0)

        // And writing a position upgrades the row in place.
        repo.updateVideoProgress(video, seconds: 120, partIndex: 0)
        #expect(video.parts[0].seconds == 120)
        #expect(video.parts[1].title == "Part 2")
    }

    /// A plain video has no parts; its position stays on the scalar.
    @Test func singleVideosAreUnaffected() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let video = GameVideo(kind: .video, urlString: "https://youtu.be/Y",
                              youtubeID: "Y", title: "Guide")
        context.insert(video)

        repo.updateVideoProgress(video, seconds: 112, partIndex: nil)

        #expect(video.parts.isEmpty)
        #expect(video.watchedSeconds == 112)
        #expect(video.currentPartSeconds == 112)
    }
}
