import Foundation
import CloudKit
import CoreData
import Observation
import os

/// Watches iCloud sync health so the app can *show* what was previously
/// silent (beta P0): synced / syncing / iCloud unavailable / local fallback.
///
/// Two signal sources:
///  - `CKContainer.accountStatus` (+ `.CKAccountChanged`) — is iCloud signed
///    in and available at all?
///  - `NSPersistentCloudKitContainer.eventChangedNotification` — SwiftData's
///    CloudKit sync is NSPersistentCloudKitContainer underneath, and its
///    import/export/setup events fire through NotificationCenter even though
///    the container itself is SwiftData-internal.
///
/// Plus `LevelSelectStore.usingLocalFallback` for the case where the store
/// itself couldn't come up CloudKit-backed.
@MainActor
@Observable
final class SyncStatusMonitor {
    static let shared = SyncStatusMonitor()

    private static let log = Logger(subsystem: "com.timultuoustimes.levelselect",
                                    category: "sync")
    private static let containerID = "iCloud.com.timultuoustimes.levelselect"

    enum State: Equatable {
        /// Store is local-only because CloudKit initialization failed.
        case localFallback
        /// No iCloud account (signed out, restricted, or unavailable).
        case accountUnavailable
        /// A sync event is currently in flight.
        case syncing
        /// Last sync activity finished cleanly.
        case synced
        /// Last sync event failed (message kept for the detail row).
        case error(String)
        /// Account check hasn't completed yet.
        case checking
    }

    private(set) var accountStatus: CKAccountStatus?
    private(set) var lastSyncedAt: Date?
    private(set) var lastSyncError: String?
    private(set) var lastSyncErrorDomain: String?
    private(set) var lastSyncErrorCode: Int?
    /// Count of in-flight import/export/setup events.
    private var eventsInFlight = 0

    /// CloudKit is rate-limiting this device (CKError.requestRateLimited).
    /// Two-device testing hit this for real: to the user it read as "sync
    /// silently dead for half an hour" when the truth was "iCloud said slow
    /// down, retrying on its own." The distinction is worth a dedicated
    /// surface — one is a bug, the other is a wait.
    var isThrottled: Bool {
        lastSyncErrorDomain == CKErrorDomain
            && lastSyncErrorCode == CKError.requestRateLimited.rawValue
    }

    private var started = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Overall state, in priority order.
    var state: State {
        if LevelSelectStore.usingLocalFallback { return .localFallback }
        switch accountStatus {
        case .none: return .checking
        case .available: break
        default: return .accountUnavailable
        }
        if eventsInFlight > 0 { return .syncing }
        if let lastSyncError { return .error(lastSyncError) }
        return .synced
    }

    /// Begin observing. Idempotent; call once from the app root.
    func start() {
        guard !started else { return }
        started = true

        Task { await refreshAccountStatus() }

        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: .CKAccountChanged, object: nil, queue: nil
        ) { _ in
            Task { @MainActor in
                await SyncStatusMonitor.shared.refreshAccountStatus()
            }
        })

        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: nil
        ) { note in
            // Notification/Event aren't Sendable — unpack to primitives before
            // hopping to the main actor.
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            let finished = event.endDate != nil
            let succeeded = event.succeeded
            let endDate = event.endDate
            let nsError = event.error.map { $0 as NSError }
            let errorText = nsError?.localizedDescription
            let errorDomain = nsError?.domain
            let errorCode = nsError?.code
            Task { @MainActor in
                SyncStatusMonitor.shared.handleEvent(
                    finished: finished, succeeded: succeeded, endDate: endDate,
                    errorText: errorText, errorDomain: errorDomain, errorCode: errorCode)
            }
        })
    }

    func refreshAccountStatus() async {
        do {
            let status = try await CKContainer(identifier: Self.containerID).accountStatus()
            accountStatus = status
            if status != .available {
                Self.log.info("iCloud account unavailable: \(status.rawValue)")
            }
        } catch {
            Self.log.error("accountStatus failed: \(String(describing: error))")
            accountStatus = .couldNotDetermine
        }
    }

    private func handleEvent(
        finished: Bool, succeeded: Bool, endDate: Date?,
        errorText: String?, errorDomain: String?, errorCode: Int?
    ) {
        if !finished {
            eventsInFlight += 1
            return
        }
        eventsInFlight = max(0, eventsInFlight - 1)
        if succeeded {
            lastSyncedAt = endDate ?? .now
            lastSyncError = nil
            lastSyncErrorDomain = nil
            lastSyncErrorCode = nil
        } else if let errorText {
            // Transient CK errors (network drops, throttles) are normal;
            // record for the detail row, log for diagnostics.
            Self.log.warning("sync event failed: \(errorText) [\(errorDomain ?? "?") \(errorCode ?? 0)]")
            lastSyncError = errorText
            lastSyncErrorDomain = errorDomain
            lastSyncErrorCode = errorCode
        }
    }
}
