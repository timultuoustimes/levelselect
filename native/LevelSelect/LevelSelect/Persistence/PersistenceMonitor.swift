import Foundation
import SwiftData
import Observation
import os

/// The single choke point for explicit SwiftData saves (beta P0: no more
/// silent `try?` persistence).
///
/// Every mutation path — Repository, notification actions, Live Activity
/// intents, the watch — commits through here. On failure the error is kept
/// (with the context, so Retry can re-attempt the same pending changes) and
/// the UI shows a small retry banner instead of dropping the write on the
/// floor. SwiftData's autosave still runs underneath as a safety net; this
/// exists so a failure is *visible*, not to replace autosave.
@MainActor
@Observable
final class PersistenceMonitor {
    static let shared = PersistenceMonitor()

    private static let log = Logger(subsystem: "com.timultuoustimes.levelselect",
                                    category: "persistence")

    /// Human-readable description of the last failed save; nil when healthy.
    private(set) var lastErrorMessage: String?
    private(set) var lastFailedAt: Date?
    /// Bumped on every failure so the banner re-appears even for repeats.
    private(set) var failureCount = 0

    /// The context whose save failed — kept so Retry re-commits the same
    /// pending changes (SwiftData keeps them in the context until saved).
    private var pendingContext: ModelContext?

    private init() {}

    /// Commit pending changes on `context`. Success clears any prior failure
    /// state; failure records it for the banner and logs the underlying error.
    func commit(_ context: ModelContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
            if lastErrorMessage != nil { clearFailure() }
        } catch {
            Self.log.error("save failed: \(String(describing: error))")
            lastErrorMessage = friendlyMessage(for: error)
            lastFailedAt = .now
            failureCount += 1
            pendingContext = context
        }
    }

    /// Re-attempt the failed save. The pending changes are still in the
    /// context, so this is a genuine retry, not a no-op.
    func retry() {
        guard let context = pendingContext else { return }
        // commit() early-returns when hasChanges is false — which after a
        // failure can happen if autosave later succeeded. Treat that as healed.
        if !context.hasChanges { clearFailure(); return }
        commit(context)
    }

    /// Dismiss the banner without retrying (autosave keeps trying underneath).
    func dismiss() { clearFailure() }

    private func clearFailure() {
        lastErrorMessage = nil
        lastFailedAt = nil
        pendingContext = nil
    }

    private func friendlyMessage(for error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSFileWriteOutOfSpaceError, NSFileWriteVolumeReadOnlyError:
            return "Couldn't save — your device is out of storage space."
        default:
            return "Couldn't save your latest change."
        }
    }
}
