// Shared between the app and the widget extension. LiveActivityIntent
// executes in the APP's process, so the real work is compiled only there
// (the extension just needs the intent's type to render its button).
import Foundation
#if !os(macOS)
import AppIntents

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
