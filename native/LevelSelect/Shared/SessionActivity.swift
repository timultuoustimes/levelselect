// Shared between the app and the widget extension.
import Foundation
#if canImport(ActivityKit) && !os(macOS)
import ActivityKit

struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        /// Anchor such that (now − startedAt) == true elapsed while running.
        var startedAt: Date
        /// Frozen elapsed seconds while paused.
        var accumulated: TimeInterval
        var isRunning: Bool
    }

    var gameName: String
    var sessionID: String
}
#endif
