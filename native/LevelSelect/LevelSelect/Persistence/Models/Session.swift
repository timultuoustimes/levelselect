import Foundation
import SwiftData

/// A play session (legacy `saves[].sessions[]`). CloudKit-compatible.
/// Duration is DERIVED from timestamps — never stored as a ticking value.
@Model
final class Session {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var startDate: Date = Date.now
    var endDate: Date?
    var accumulatedDuration: TimeInterval = 0   // completed segments before the current running segment
    var resumedAt: Date?                          // anchor the current running segment counts from (nil ⇒ startDate)
    var pausedAt: Date?                           // when it was last paused (display only)
    var state: SessionState = SessionState.stopped
    var isManual: Bool = false
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
        self.createdAt = .now
        self.updatedAt = .now
        self.startDate = startDate
        self.state = state
        self.isManual = isManual
    }
}
