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

    /// CloudKit reports setup, incoming, and outgoing work as separate event
    /// streams. A success in one direction says nothing about the health of
    /// another, so their failures must never share one clearable slot.
    enum EventDirection: String, Sendable {
        case setup
        case importData
        case exportData

        var label: String {
            switch self {
            case .setup: "iCloud setup"
            case .importData: "Incoming changes"
            case .exportData: "Outgoing changes"
            }
        }
    }

    struct DirectionFailure: Equatable, Sendable {
        let message: String
        let domain: String?
        let code: Int?
        let occurredAt: Date

        var isThrottled: Bool {
            domain == CKErrorDomain && code == CKError.requestRateLimited.rawValue
        }
    }

    private(set) var accountStatus: CKAccountStatus?
    private(set) var lastSyncedAt: Date?
    private(set) var lastSetupAt: Date?
    private(set) var lastImportedAt: Date?
    private(set) var lastExportedAt: Date?
    private(set) var setupFailure: DirectionFailure?
    private(set) var importFailure: DirectionFailure?
    private(set) var exportFailure: DirectionFailure?
    /// Count of in-flight import/export/setup events.
    private var eventsInFlight = 0

    /// CloudKit is rate-limiting this device (CKError.requestRateLimited).
    /// Two-device testing hit this for real: to the user it read as "sync
    /// silently dead for half an hour" when the truth was "iCloud said slow
    /// down, retrying on its own." The distinction is worth a dedicated
    /// surface — one is a bug, the other is a wait.
    var isThrottled: Bool {
        let failures = currentFailures
        return !failures.isEmpty && failures.allSatisfy(\.failure.isThrottled)
    }

    /// Direction-labelled error text. If two directions are unhealthy, both
    /// remain visible; a healthy empty export can no longer make a failed
    /// import read as "Synced."
    var lastSyncError: String? {
        let failures = currentFailures
        guard !failures.isEmpty else { return nil }
        if failures.count > 1 {
            return failures.map(\.direction.label).joined(separator: " and ") + " are failing"
        }
        let only = failures[0]
        return "\(only.direction.label): \(only.failure.message)"
    }

    /// Last clean event for every direction that is currently failing. This is
    /// what the catching-up row may honestly call its last sync; an unrelated
    /// empty export is not evidence that imports are current.
    var lastRelevantSyncAt: Date? {
        let failures = currentFailures
        guard !failures.isEmpty else { return lastSyncedAt }
        let dates = failures.compactMap { lastSuccess(for: $0.direction) }
        guard dates.count == failures.count else { return nil }
        return dates.min()
    }

    private var currentFailures: [(direction: EventDirection, failure: DirectionFailure)] {
        [
            setupFailure.map { (.setup, $0) },
            importFailure.map { (.importData, $0) },
            exportFailure.map { (.exportData, $0) },
        ].compactMap { $0 }
    }

    private var started = false
    private var observers: [NSObjectProtocol] = []

    /// Internal for deterministic event-routing tests; production uses shared.
    init() {}

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
            let direction: EventDirection
            switch event.type {
            case .setup: direction = .setup
            case .import: direction = .importData
            case .export: direction = .exportData
            @unknown default: return
            }
            let nsError = event.error.map { $0 as NSError }
            let errorText = nsError?.localizedDescription
            let errorDomain = nsError?.domain
            let errorCode = nsError?.code
            Task { @MainActor in
                SyncStatusMonitor.shared.handleEvent(
                    direction: direction, finished: finished,
                    succeeded: succeeded, endDate: endDate,
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

    func handleEvent(
        direction: EventDirection, finished: Bool,
        succeeded: Bool, endDate: Date?,
        errorText: String?, errorDomain: String?, errorCode: Int?
    ) {
        if !finished {
            eventsInFlight += 1
            return
        }
        eventsInFlight = max(0, eventsInFlight - 1)
        if succeeded {
            let completedAt = endDate ?? .now
            lastSyncedAt = completedAt
            setLastSuccess(completedAt, for: direction)
            setFailure(nil, for: direction)
        } else if let errorText {
            // Transient CK errors (network drops, throttles) are normal;
            // record for the detail row, log for diagnostics.
            Self.log.warning("\(direction.rawValue) sync event failed: \(errorText) [\(errorDomain ?? "?") \(errorCode ?? 0)]")
            setFailure(DirectionFailure(
                message: errorText,
                domain: errorDomain,
                code: errorCode,
                occurredAt: endDate ?? .now
            ), for: direction)
        }
    }

    private func setFailure(_ failure: DirectionFailure?, for direction: EventDirection) {
        switch direction {
        case .setup: setupFailure = failure
        case .importData: importFailure = failure
        case .exportData: exportFailure = failure
        }
    }

    private func setLastSuccess(_ date: Date, for direction: EventDirection) {
        switch direction {
        case .setup: lastSetupAt = date
        case .importData: lastImportedAt = date
        case .exportData: lastExportedAt = date
        }
    }

    private func lastSuccess(for direction: EventDirection) -> Date? {
        switch direction {
        case .setup: lastSetupAt
        case .importData: lastImportedAt
        case .exportData: lastExportedAt
        }
    }
}
