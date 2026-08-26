import Foundation
import SwiftData
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Executes Live Activity button intents against the shared store
/// (LiveActivityIntent runs in the app's process).
@MainActor
enum SessionIntentHandler {
    /// Start a session for a game (Home Screen widget ▶ button).
    static func startSession(gameIDString: String) {
        guard let id = UUID(uuidString: gameIDString) else { return }
        let ctx = LevelSelectStore.shared.mainContext
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.id == id })
        guard let game = try? ctx.fetch(descriptor).first else { return }
        let repo = Repository(ctx)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        if pt.activeSession == nil { repo.startSession(on: pt) }
        PersistenceMonitor.shared.commit(ctx)
        WidgetBridge.refresh()
    }

    /// Toggle a tracker objective for a game's active playthrough (widget checklist).
    static func toggleObjective(gameIDString: String, itemID: String) {
        guard let id = UUID(uuidString: gameIDString) else { return }
        let ctx = LevelSelectStore.shared.mainContext
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.id == id })
        guard let game = try? ctx.fetch(descriptor).first else { return }
        let repo = Repository(ctx)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let done = repo.trackerState(pt, itemID: itemID)?.completed ?? false
        repo.setTrackerItem(pt, itemID: itemID, done: !done)
        PersistenceMonitor.shared.commit(ctx)
        WidgetBridge.refresh()
    }

    static func stopSession(idString: String) {
        guard let session = find(idString) else { return }
        let repo = Repository(LevelSelectStore.shared.mainContext)
        repo.stopSession(session)
        PersistenceMonitor.shared.commit(LevelSelectStore.shared.mainContext)
        WidgetBridge.refresh()
    }

    static func togglePause(idString: String) {
        guard let session = find(idString) else { return }
        let repo = Repository(LevelSelectStore.shared.mainContext)
        switch session.state {
        case .running: repo.pauseSession(session)
        case .paused: repo.resumeSession(session)
        case .stopped: break
        }
        PersistenceMonitor.shared.commit(LevelSelectStore.shared.mainContext)
        WidgetBridge.refresh()
    }

    private static func find(_ idString: String) -> Session? {
        guard let id = UUID(uuidString: idString) else { return nil }
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        return try? LevelSelectStore.shared.mainContext.fetch(descriptor).first
    }
}

/// Starts/updates/ends the session Live Activity (Lock Screen + Dynamic
/// Island). Timer text derives from dates — no per-second updates pushed.
@MainActor
enum LiveActivityManager {
    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    #if canImport(ActivityKit) && os(iOS)
    // Track only the session id — Activity objects aren't Sendable, so they
    // are always resolved inside the task that uses them.
    private static var currentSessionID: String?

    static func sessionChanged(_ session: Session, gameName: String) {
        guard enabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = SessionActivityAttributes.ContentState(
            startedAt: Date.now.addingTimeInterval(-session.elapsed()),
            accumulated: session.elapsed(),
            isRunning: session.state == .running
        )
        let sid = session.id.uuidString

        switch session.state {
        case .running, .paused:
            if currentSessionID == sid {
                push(state, sessionID: sid)
            } else {
                if let old = currentSessionID { end(sessionID: old) }
                currentSessionID = sid
                let attributes = SessionActivityAttributes(gameName: gameName, sessionID: sid)
                _ = try? Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil)
                )
            }
        case .stopped:
            if currentSessionID == sid {
                currentSessionID = nil
                end(sessionID: sid)
            }
        }
    }

    static func endCurrent() {
        guard let sid = currentSessionID else { return }
        currentSessionID = nil
        end(sessionID: sid)
    }

    /// End the activity for one specific session, whether or not it's the
    /// tracked "current" one. Reconciliation closes sessions the user never
    /// touched on this device — and after a relaunch, `currentSessionID` is
    /// nil while the OS still shows the activity, so the current-only
    /// bookkeeping can't reach it.
    static func sessionResolved(_ sessionID: UUID) {
        guard enabled else { return }
        let sid = sessionID.uuidString
        if currentSessionID == sid { currentSessionID = nil }
        end(sessionID: sid)
    }

    /// Reconcile EVERY OS-side activity with the store's set of unstopped
    /// sessions: end activities whose session was stopped or discarded (on
    /// any device), and refresh the state of those still live so a remote
    /// pause/resume is reflected. Two-device testing caught the gap this
    /// closes: a timer stopped on the other device left this device's Live
    /// Activity running with dead buttons until it was swiped away by hand —
    /// the activity belongs to the OS, outlives the app process, and nothing
    /// local ever told it the session had ended.
    static func sync(unstopped: [Session]) {
        guard enabled else { return }
        let states: [String: SessionActivityAttributes.ContentState] = Dictionary(
            uniqueKeysWithValues: unstopped.map { session in
                (session.id.uuidString,
                 SessionActivityAttributes.ContentState(
                    startedAt: Date.now.addingTimeInterval(-session.elapsed()),
                    accumulated: session.elapsed(),
                    isRunning: session.state == .running))
            }, uniquingKeysWith: { first, _ in first })
        if let sid = currentSessionID, states[sid] == nil { currentSessionID = nil }
        Task.detached {
            for activity in Activity<SessionActivityAttributes>.activities {
                if let state = states[activity.attributes.sessionID] {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                } else {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }

    private static func push(_ state: SessionActivityAttributes.ContentState, sessionID: String) {
        Task.detached {
            for activity in Activity<SessionActivityAttributes>.activities
            where activity.attributes.sessionID == sessionID {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    private static func end(sessionID: String) {
        Task.detached {
            for activity in Activity<SessionActivityAttributes>.activities
            where activity.attributes.sessionID == sessionID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    #else
    static func sessionChanged(_ session: Session, gameName: String) {}
    static func endCurrent() {}
    static func sessionResolved(_ sessionID: UUID) {}
    static func sync(unstopped: [Session]) {}
    #endif
}
