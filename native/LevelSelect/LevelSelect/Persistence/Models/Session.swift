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
    /// Which device this session was started on ("King Kai"), stamped once at
    /// creation. Schema V2. Two-device testing made the case: when two timers
    /// disagree, "another device" is a much worse answer than the name of the
    /// thing sitting on the table — for the overlap prompts and for reading
    /// your own history later. Optional because every session recorded before
    /// V2, and any written by a build that predates it, has none.
    var originDevice: String?

    var playthrough: Playthrough?

    /// Elapsed time up to `asOf` (default now). Stopped/paused sessions use accumulated only.
    ///
    /// The running segment is clamped at zero: another device's clock can put
    /// a synced session's start/resume anchor in THIS device's future, and an
    /// unclamped interval would then subtract time — a timer counting below
    /// zero, or reconciliation writing negative playtime into history.
    func elapsed(asOf now: Date = .now) -> TimeInterval {
        switch state {
        case .running:
            return accumulatedDuration + max(0, now.timeIntervalSince(resumedAt ?? startDate))
        case .paused, .stopped:
            return accumulatedDuration
        }
    }

    /// The last moment the user demonstrably acted on this session — started,
    /// paused, or resumed it. This, not `startDate`, is what "most recent
    /// intent" means: an old session RESUMED at 17:00 is a later user action
    /// than a fresh one started at 16:00, and any duplicate-session winner
    /// picked from original start dates can stop the timer the user is
    /// actually running.
    var lastUserAction: Date {
        max(startDate, max(resumedAt ?? .distantPast, pausedAt ?? .distantPast))
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
