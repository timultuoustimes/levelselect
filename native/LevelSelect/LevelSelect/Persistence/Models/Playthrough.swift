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
    var sessions: [Session]?
    @Relationship(deleteRule: .cascade, inverse: \TrackerStateRecord.playthrough)
    var trackerStates: [TrackerStateRecord]?
    @Relationship(deleteRule: .cascade, inverse: \Run.playthrough)
    var runs: [Run]?

    /// Active session = the one not yet stopped (no separate stored flag).
    ///
    /// When sync leaves more than one unstopped session, the winner is the
    /// one the user ACTED on last (started, paused, or resumed — not the
    /// newest original start date, which loses to a deliberately resumed old
    /// session), with the id as a total tie-break. The total order matters:
    /// with timestamps alone, equal stamps let each device resolve a
    /// different winner from its own relationship order, and cross-device
    /// repair passes then need not converge. `Repository.reconcile` closes
    /// out the duplicates with the SAME rule; this keeps the read stable —
    /// and identical on every device — in the window before it runs.
    var activeSession: Session? {
        (sessions ?? [])
            .filter { $0.state != .stopped && $0.deletedAt == nil }
            .max { ($0.lastUserAction, $0.id.uuidString) < ($1.lastUserAction, $1.id.uuidString) }
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
