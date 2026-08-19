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

    /// Active session = the running session, or a paused one when nothing is
    /// running (no separate stored flag).
    ///
    /// When sync leaves more than one running session, the winner is the one
    /// the user ACTED on last (started or resumed — not the newest original
    /// start date, which loses to a deliberately resumed old session), with
    /// the id as a total tie-break. The total order matters:
    /// with timestamps alone, equal stamps let each device resolve a
    /// different winner from its own relationship order, and cross-device
    /// repair passes then need not converge. Running takes priority over paused
    /// because paused records are now deliberately preserved when a new timer
    /// starts: they accrue nothing, while hiding the running record would keep
    /// real time accruing behind a paused UI.
    var activeSession: Session? {
        let live = (sessions ?? [])
            .filter { $0.state != .stopped && $0.deletedAt == nil }
        let candidates = live.contains { $0.state == .running }
            ? live.filter { $0.state == .running }
            : live
        return candidates.max {
            ($0.lastUserAction, $0.id.uuidString) < ($1.lastUserAction, $1.id.uuidString)
        }
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
