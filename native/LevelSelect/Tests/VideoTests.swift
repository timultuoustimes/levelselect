import Testing
import Foundation
import SwiftData
@testable import LevelSelect

struct YouTubeParseTests {
    @Test func parsesWatchURL() {
        let p = YouTubeService.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(p == .init(kind: .video, id: "dQw4w9WgXcQ"))
    }

    @Test func parsesShortLink() {
        let p = YouTubeService.parse("https://youtu.be/dQw4w9WgXcQ?si=abc")
        #expect(p == .init(kind: .video, id: "dQw4w9WgXcQ"))
    }

    @Test func playlistParamWins() {
        let p = YouTubeService.parse(
            "https://www.youtube.com/watch?v=abc123&list=PLraFbwCoisJCYFqFP7e7UQnHHZL05LooV")
        #expect(p == .init(kind: .playlist, id: "PLraFbwCoisJCYFqFP7e7UQnHHZL05LooV"))
    }

    @Test func parsesPlaylistPage() {
        let p = YouTubeService.parse("youtube.com/playlist?list=PL123abc")
        #expect(p == .init(kind: .playlist, id: "PL123abc"))
    }

    @Test func parsesShorts() {
        let p = YouTubeService.parse("https://www.youtube.com/shorts/xyz789")
        #expect(p == .init(kind: .video, id: "xyz789"))
    }

    @Test func rejectsNonYouTube() {
        #expect(YouTubeService.parse("https://vimeo.com/12345") == nil)
        #expect(YouTubeService.parse("not a url") == nil)
    }
}

@MainActor
struct VideoRepositoryTests {
    private func newContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    @Test func playlistAutoGroupsAndResumePersists() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let g = repo.addGame(name: "Mina the Hollower", status: .playing)

        let playlist = repo.addVideo(
            to: g,
            parsed: .init(kind: .playlist, id: "PLIGN"),
            urlString: "https://youtube.com/playlist?list=PLIGN",
            metadata: .init(title: "IGN Walkthrough", channel: "IGN Guides", thumbnailURL: nil)
        )
        #expect(playlist.groupName == "IGN Walkthrough")   // auto-group by title

        let single = repo.addVideo(
            to: g,
            parsed: .init(kind: .video, id: "vid1"),
            urlString: "https://youtu.be/vid1",
            metadata: nil
        )
        #expect(single.groupName == "Videos")              // default group
        #expect(single.orderIndex > playlist.orderIndex)

        repo.moveVideo(single, toGroup: "Boss Guides")
        #expect(single.groupName == "Boss Guides")

        // Synced resume position (part + seconds for playlists).
        repo.updateVideoProgress(playlist, seconds: 761, partIndex: 2)
        #expect(playlist.watchedSeconds == 761)
        #expect(playlist.watchedPartIndex == 2)
        #expect(playlist.lastWatchedAt != nil)

        repo.deleteVideo(single)
        #expect(single.deletedAt != nil)
    }
}
