import WidgetKit
import SwiftUI
import AppIntents

/// Start or stop a session from Control Center, the Lock Screen, or the Action
/// button (build 39, 09-18). On starts the game you were last playing — the
/// one the Continue Playing widget shows — and off stops what's running.
struct PlaySessionControl: ControlWidget {
    static let kind = "com.timultuoustimes.levelselect.PlaySessionControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { value in
            ControlWidgetToggle(value.gameName.isEmpty ? "Play Session" : value.gameName,
                                isOn: value.isPlaying, action: PlaySessionControlIntent()) { isOn in
                Label(isOn ? "Playing" : "Start", systemImage: isOn ? "stop.fill" : "play.fill")
            }
            .tint(.orange)
        }
        .displayName("Play Session")
        .description("Start a session for the game you were last playing, or stop the one that's running.")
    }

    struct Value {
        var isPlaying: Bool
        var gameName: String
    }

    struct Provider: ControlValueProvider {
        var previewValue: Value { Value(isPlaying: false, gameName: "Hollow Knight") }

        func currentValue() async throws -> Value {
            guard let snap = WidgetSnapshot.load() else { return Value(isPlaying: false, gameName: "") }
            return Value(isPlaying: snap.activeSessionID != nil, gameName: snap.gameName)
        }
    }
}
