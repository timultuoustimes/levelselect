import Foundation
import SwiftData
import UserNotifications

/// Local "still playing?" reminders. When a session starts (or is discovered
/// active on foreground), schedule a notification for when it crosses the
/// stale threshold; cancel on stop/pause/discard. Local notifications need no
/// server and fire even when the app is closed. Tapping opens the app, where
/// StaleSessionGuard presents the resolve prompt.
@MainActor
enum NotificationManager {
    private static let prefix = "stale-session-"
    static let categoryID = "STALE_SESSION"
    static let actionStillPlaying = "STALE_STILL_PLAYING"
    static let actionEnd = "STALE_END"
    static let actionDiscard = "STALE_DISCARD"

    /// Never touch notification APIs inside the unit-test host.
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    static func sessionID(fromNotificationID id: String) -> UUID? {
        guard id.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(prefix.count)))
    }

    /// One-time launch setup: delegate + action buttons on the reminder.
    static func configure(container: ModelContainer) {
        guard enabled else { return }
        NotificationDelegate.shared.container = container
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared

        let still = UNNotificationAction(
            identifier: actionStillPlaying, title: "Still Playing")
        let end = UNNotificationAction(
            identifier: actionEnd, title: "End Session…",
            options: [.foreground])           // opens the app → end-time sheet
        let discard = UNNotificationAction(
            identifier: actionDiscard, title: "Discard Session",
            options: [.destructive])
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [still, end, discard],
            intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    static func requestAuthorizationIfNeeded() {
        guard enabled else { return }
        // Async notification-center APIs — the completion-handler forms capture
        // the (non-Sendable) center in @Sendable closures under Swift 6.
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
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
        content.body = "Your session has been running for \(Int(threshold / 3600)) hours. Press and hold for options."
        content.sound = .default
        content.categoryIdentifier = categoryID
        // A six-hour runaway timer is inflating real data RIGHT NOW — that's
        // what Time Sensitive exists for. Lets the reminder break through
        // silent mode and Focus (the user can veto per-app in Settings).
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: prefix + sessionID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: fireIn, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Releases

    private static let releasePrefix = "release-"

    /// How far ahead of a release to say something, in days.
    ///
    /// Device-local rather than a `ThemeSettings` field, and deliberately: a
    /// local notification is scheduled by ONE device, so which device tells
    /// you is already a per-device fact. It also costs no schema change, and
    /// this schema is additive-only with a CloudKit deploy behind every field.
    @MainActor
    static var releaseLeadDays: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "releaseLeadDays")
            return stored == 0 ? 1 : stored          // 0 means "never set"
        }
        set { UserDefaults.standard.set(newValue, forKey: "releaseLeadDays") }
    }

    @MainActor
    static var releaseRemindersOn: Bool {
        get { UserDefaults.standard.bool(forKey: "releaseRemindersOn") }
        set { UserDefaults.standard.set(newValue, forKey: "releaseRemindersOn") }
    }

    /// Reconcile release reminders against the wishlist.
    ///
    /// Rescheduled wholesale rather than diffed, the way the stale-session
    /// reminders reconcile on foreground: a release date can MOVE, and a
    /// reminder for a date that has changed is worse than no reminder. The
    /// set is small — only wishlist games with a real date still ahead — so
    /// clearing and re-adding costs nothing.
    static func syncReleaseReminders(
        upcoming: [(id: UUID, name: String, releaseDate: Date)]
    ) {
        guard enabled else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier)
                    .filter { $0.hasPrefix(releasePrefix) })

            guard releaseRemindersOn else { return }
            let lead = releaseLeadDays
            for game in upcoming {
                guard let fireAt = fireDate(for: game.releaseDate, leadDays: lead),
                      fireAt > .now else { continue }

                let content = UNMutableNotificationContent()
                content.title = lead == 0 ? "\(game.name) is out today" : "\(game.name) lands soon"
                content.body = lead == 0
                    ? "The one you were waiting for."
                    : ReleaseCountdown.countdown(to: game.releaseDate, from: fireAt)
                        .map { "Out \($0.replacingOccurrences(of: "in ", with: "in ")) — \(ReleaseCountdown.dateLabel(game.releaseDate))." }
                        ?? "Out \(ReleaseCountdown.dateLabel(game.releaseDate))."
                content.sound = .default

                let parts = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: fireAt)
                try? await center.add(UNNotificationRequest(
                    identifier: releasePrefix + game.id.uuidString,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }

    /// 9am local, `leadDays` before the release.
    ///
    /// A release date is a calendar date stamped at UTC midnight, so firing
    /// "at" it would wake someone in the small hours for a game that is not
    /// out where they are yet. Morning of the day the reminder is about is
    /// the honest reading of "tell me the day before".
    static func fireDate(for release: Date, leadDays: Int, now: Date = .now) -> Date? {
        let cal = Calendar.current
        // The release read as a LOCAL day, not a UTC instant.
        let parts = ReleaseCountdown.utc.dateComponents([.year, .month, .day], from: release)
        guard let localReleaseDay = cal.date(from: parts),
              let day = cal.date(byAdding: .day, value: -leadDays, to: localReleaseDay)
        else { return nil }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)
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
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
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
