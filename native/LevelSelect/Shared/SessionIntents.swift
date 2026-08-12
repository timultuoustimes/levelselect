// Shared between the app and the widget extension. LiveActivityIntent
// executes in the APP's process, so the real work is compiled only there
// (the extension just needs the intent's type to render its button).
import Foundation
#if !os(macOS)
import AppIntents

/// Start a play session for a game straight from a Home Screen widget button.
/// Conforms to `LiveActivityIntent` so `perform()` runs in the APP's process
/// (same trick the session controls use) — it can therefore touch the shared
/// SwiftData/CloudKit store, which a plain widget intent cannot.
struct StartSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Session"
    static let description = IntentDescription("Starts a play session for a game.")

    @Parameter(title: "Game ID")
    var gameID: String

    init() {}
    init(gameID: String) {
        self.gameID = gameID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        SessionIntentHandler.startSession(gameIDString: gameID)
        #endif
        return .result()
    }
}

struct StopSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Session"
    static let description = IntentDescription("Stops the running play session.")

    @Parameter(title: "Session ID")
    var sessionID: String

    init() {}
    init(sessionID: String) {
        self.sessionID = sessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        SessionIntentHandler.stopSession(idString: sessionID)
        #endif
        return .result()
    }
}

struct PauseResumeSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Session"
    static let description = IntentDescription("Pauses or resumes the play session.")

    @Parameter(title: "Session ID")
    var sessionID: String

    init() {}
    init(sessionID: String) {
        self.sessionID = sessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        SessionIntentHandler.togglePause(idString: sessionID)
        #endif
        return .result()
    }
}

#endif
