import Foundation
import SwiftData

/// A walkthrough video or playlist attached to a game (Play-style). Stored
/// per GAME (walkthroughs belong to the game; progress through the game is
/// per playthrough). CloudKit-compatible; resume positions sync.
@Model
final class GameVideo {
    // Sync metadata
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var kindRaw: String = VideoKind.video.rawValue
    var urlString: String = ""
    /// YouTube video id, or playlist id for kind == .playlist.
    var youtubeID: String = ""
    var title: String = ""
    var channel: String?
    var thumbnailURL: String?
    /// Group name — playlists auto-group under their title; loose videos
    /// default to "Videos"; user-editable.
    var groupName: String = "Videos"
    var orderIndex: Int = 0
    var notes: String?

    // Synced resume position (Tim's v1 requirement).
    var watchedSeconds: Double = 0
    /// For playlists: which part was last playing (0-based).
    var watchedPartIndex: Int = 0
    var lastWatchedAt: Date?

    var game: Game?

    var kind: VideoKind {
        get { VideoKind(rawValue: kindRaw) ?? .video }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: VideoKind, urlString: String, youtubeID: String, title: String) {
        self.kindRaw = kind.rawValue
        self.urlString = urlString
        self.youtubeID = youtubeID
        self.title = title
    }
}

enum VideoKind: String, Codable, Sendable {
    case video, playlist
}
