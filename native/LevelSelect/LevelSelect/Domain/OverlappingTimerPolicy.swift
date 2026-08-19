import Foundation

/// What the app does when two devices are timing the same game.
///
/// This exists because the app used to decide silently. It picked a winner by
/// a rule the user never saw, closed the other timer, and moved on — and when
/// that rule was wrong (a session deliberately resumed on one device losing to
/// a fresher one on another), the first anyone knew of it was a stopped timer
/// they were still watching. Ambiguity that belongs to the user should be
/// handed back to them.
///
/// The old automatic behaviour survives as `keepNewest` — still available,
/// still the recommended answer, but now something chosen rather than
/// something done.
enum OverlappingTimerPolicy: String, CaseIterable, Identifiable, Sendable {
    /// Show the conflict and let the user resolve it. Default.
    case ask
    /// Keep whichever timer the user acted on most recently; close the rest,
    /// crediting each only up to the survivor's segment.
    case keepNewest
    /// Leave both running. Playtime counts both — which is sometimes exactly
    /// right (two people, one account) and sometimes double-counting.
    case keepBoth

    var id: String { rawValue }

    static let fallback: OverlappingTimerPolicy = .ask

    init(raw: String?) {
        self = raw.flatMap(OverlappingTimerPolicy.init(rawValue:)) ?? .fallback
    }

    var label: String {
        switch self {
        case .ask: "Ask me"
        case .keepNewest: "Keep the most recent"
        case .keepBoth: "Keep both running"
        }
    }

    var detail: String {
        switch self {
        case .ask:
            "Shows both timers and lets you choose."
        case .keepNewest:
            "Stops the other timer, keeping the time it earned up to that point."
        case .keepBoth:
            "Leaves both running. Their time is counted separately, so a game played on two devices at once adds up twice."
        }
    }
}
