import Foundation
import SwiftData
import UserNotifications

extension Notification.Name {
    /// Posted when the user chose "End Session…" from a notification — the UI
    /// responds by presenting the end-time sheet for that session.
    static let lsEndSessionRequested = Notification.Name("lsEndSessionRequested")
}

/// Handles action buttons on the "Still playing?" notification
/// (press-and-hold → Still Playing / End Session… / Discard).
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    var container: ModelContainer?

    // Suppress the banner if the app is frontmost — the in-app guard prompts.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        await MainActor.run {
            Self.shared.handle(action: action, notificationID: identifier)
        }
    }

    private func handle(action: String, notificationID: String) {
        guard let sessionID = NotificationManager.sessionID(fromNotificationID: notificationID),
              let container else { return }
        let context = container.mainContext
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = try? context.fetch(descriptor).first else { return }
        let repo = Repository(context)

        switch action {
        case NotificationManager.actionStillPlaying:
            // Re-arm: ask again after another full threshold from now.
            NotificationManager.scheduleStaleReminder(
                sessionID: session.id,
                gameName: session.playthrough?.game?.name ?? "A game",
                sessionStart: .now,
                threshold: StaleSessionGuard.threshold
            )
        case NotificationManager.actionDiscard:
            repo.discardSession(session)
        case NotificationManager.actionEnd, UNNotificationDefaultActionIdentifier:
            // Foreground action — the app opens; hand off to the end-time sheet.
            NotificationCenter.default.post(name: .lsEndSessionRequested, object: session.id)
        default:
            break
        }
        try? context.save()
    }
}
