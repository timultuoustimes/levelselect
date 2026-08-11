import Foundation
import SwiftData
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Executes Live Activity button intents against the shared store
/// (LiveActivityIntent runs in the app's process).
@MainActor
enum SessionIntentHandler {
    static func stopSession(idString: String) {
        guard let session = find(idString) else { return }
        let repo = Repository(LevelSelectStore.shared.mainContext)
        repo.stopSession(session)
        try? LevelSelectStore.shared.mainContext.save()
    }

    static func togglePause(idString: String) {
        guard let session = find(idString) else { return }
        let repo = Repository(LevelSelectStore.shared.mainContext)
        switch session.state {
        case .running: repo.pauseSession(session)
        case .paused: repo.resumeSession(session)
        case .stopped: break
        }
        try? LevelSelectStore.shared.mainContext.save()
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
    #endif
}
