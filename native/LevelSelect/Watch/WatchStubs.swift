// Watch-target-only no-op stubs for the iOS-only side effects that
// `Repository` fires on session changes (local notifications, Live Activities,
// the stale-session threshold). The watch reuses the exact same Repository +
// SwiftData/CloudKit store; it just doesn't do those iOS things.
import Foundation

enum NotificationManager {
    static func requestAuthorizationIfNeeded() {}
    static func scheduleStaleReminder(sessionID: UUID, gameName: String,
                                      sessionStart: Date, threshold: TimeInterval) {}
    static func cancelStaleReminder(sessionID: UUID) {}
}

enum LiveActivityManager {
    static func sessionChanged(_ session: Session, gameName: String) {}
    static func endCurrent() {}
}

enum StaleSessionGuard {
    static let threshold: TimeInterval = 6 * 3600
}
