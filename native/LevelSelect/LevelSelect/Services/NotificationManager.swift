import Foundation
import UserNotifications

/// Local "still playing?" reminders. When a session starts (or is discovered
/// active on foreground), schedule a notification for when it crosses the
/// stale threshold; cancel on stop/pause/discard. Local notifications need no
/// server and fire even when the app is closed. Tapping opens the app, where
/// StaleSessionGuard presents the resolve prompt.
enum NotificationManager {
    private static let prefix = "stale-session-"

    /// Never touch notification APIs inside the unit-test host.
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    static func requestAuthorizationIfNeeded() {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Schedule (or reschedule) the reminder for one active session.
    static func scheduleStaleReminder(
        sessionID: UUID,
        gameName: String,
        sessionStart: Date,
        threshold: TimeInterval
    ) {
        guard enabled else { return }
        let fireIn = threshold - Date.now.timeIntervalSince(sessionStart)
        guard fireIn > 1 else { return }   // already past threshold; in-app guard handles it

        let content = UNMutableNotificationContent()
        content.title = "Still playing \(gameName)?"
        content.body = "Your session has been running for \(Int(threshold / 3600)) hours. Tap to keep it going or end it."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: prefix + sessionID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelStaleReminder(sessionID: UUID) {
        guard enabled else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [prefix + sessionID.uuidString])
    }

    /// Reconcile pending reminders against the set of currently active
    /// sessions (called on foreground). Covers sessions started on OTHER
    /// devices (arrived via CloudKit) and clears reminders for sessions that
    /// were resolved elsewhere.
    static func syncReminders(
        active: [(id: UUID, gameName: String, start: Date)],
        threshold: TimeInterval
    ) {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let pendingIDs = Set(pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            let activeIDs = Set(active.map { prefix + $0.id.uuidString })

            // Cancel reminders whose session is no longer active.
            let obsolete = pendingIDs.subtracting(activeIDs)
            if !obsolete.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))
            }

            // Schedule reminders for active sessions that lack one.
            for session in active where !pendingIDs.contains(prefix + session.id.uuidString) {
                scheduleStaleReminder(
                    sessionID: session.id,
                    gameName: session.gameName,
                    sessionStart: session.start,
                    threshold: threshold
                )
            }
        }
    }
}
