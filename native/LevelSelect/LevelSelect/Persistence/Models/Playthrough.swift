import Foundation
import SwiftData

/// A playthrough (legacy `saves[]`). CloudKit-compatible.
@Model
final class Playthrough {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var name: String = "Playthrough"
    var notes: String?
    var progressPercent: Double = 0
    var startedAt: Date?
    var lastPlayedAt: Date?

    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Session.playthrough)
    var sessions: [Session] = []
    @Relationship(deleteRule: .cascade, inverse: \TrackerStateRecord.playthrough)
    var trackerStates: [TrackerStateRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \Run.playthrough)
    var runs: [Run] = []

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
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name
        self.progressPercent = progressPercent
        self.startedAt = startedAt
    }
}
