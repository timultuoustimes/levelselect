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
    /// Cached playlist parts: JSON `[[id, title, seconds]]` (filled on first
    /// load/play). The trailing seconds is each part's OWN resume position —
    /// `watchedSeconds` is a single scalar, so without this a playlist could
    /// only ever remember one position across all its parts. Kept inside this
    /// existing blob rather than as new fields, so it needs no schema change.
    /// Rows written before per-part positions existed have only two entries
    /// and read as 0.
    var partsData: Data?

    var game: Game?

    /// Decoded playlist parts, in playlist order.
    var parts: [(id: String, title: String, seconds: Double)] {
        guard let data = partsData,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]]
        else { return [] }
        return raw.compactMap { row in
            guard row.count >= 2, let id = row[0] as? String, let title = row[1] as? String
            else { return nil }
            let seconds = row.count >= 3 ? ((row[2] as? NSNumber)?.doubleValue ?? 0) : 0
            return (id: id, title: title, seconds: seconds)
        }
    }

    /// Where to resume the part currently selected.
    var currentPartSeconds: Double {
        guard kind == .playlist, parts.indices.contains(watchedPartIndex)
        else { return watchedSeconds }
        return parts[watchedPartIndex].seconds
    }

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
