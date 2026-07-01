import Foundation
import SwiftData

/// A playthrough (legacy `saves[]`). Renamed from Save/File/Tracker File.
@Model
final class Playthrough {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var name: String
    var notes: String?
    var progressPercent: Double   // denormalized for fast lists
    var startedAt: Date?
    var lastPlayedAt: Date?

    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Session.playthrough)
    var sessions: [Session]
    @Relationship(deleteRule: .cascade, inverse: \TrackerStateRecord.playthrough)
    var trackerStates: [TrackerStateRecord]
    @Relationship(deleteRule: .cascade, inverse: \Run.playthrough)
    var runs: [Run]

    /// Active session = the one not yet stopped (no separate stored flag).
    var activeSession: Session? {
        sessions.first { $0.state != .stopped }
    }

    init(
        id: UUID = UUID(),
        name: String = "Playthrough",
        progressPercent: Double = 0,
        startedAt: Date? = .now
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.name = name
        self.notes = nil
        self.progressPercent = progressPercent
        self.startedAt = startedAt
        self.lastPlayedAt = nil
        self.sessions = []
        self.trackerStates = []
        self.runs = []
    }
}
