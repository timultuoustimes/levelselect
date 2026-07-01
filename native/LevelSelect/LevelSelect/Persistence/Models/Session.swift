import Foundation
import SwiftData

/// A play session (legacy `saves[].sessions[]`).
/// Duration is DERIVED from timestamps — never stored as a ticking value.
@Model
final class Session {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var startDate: Date
    var endDate: Date?
    var accumulatedDuration: TimeInterval   // completed segments before the current running segment
    var resumedAt: Date?                     // anchor the current running segment counts from (nil ⇒ startDate)
    var pausedAt: Date?                       // when it was last paused (display only)
    var state: SessionState
    var isManual: Bool
    var notes: String?

    var playthrough: Playthrough?

    /// Elapsed time up to `asOf` (default now). Stopped/paused sessions use accumulated only.
    func elapsed(asOf now: Date = .now) -> TimeInterval {
        switch state {
        case .running:
            return accumulatedDuration + now.timeIntervalSince(resumedAt ?? startDate)
        case .paused, .stopped:
            return accumulatedDuration
        }
    }

    init(
        id: UUID = UUID(),
        startDate: Date = .now,
        state: SessionState = .running,
        isManual: Bool = false
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.startDate = startDate
        self.endDate = nil
        self.accumulatedDuration = 0
        self.resumedAt = nil
        self.pausedAt = nil
        self.state = state
        self.isManual = isManual
        self.notes = nil
    }
}
