import Foundation

/// How a run ended.
///
/// Only ever set deliberately: a run with no outcome is simply still going,
/// which is what most of them are. Nothing here is inferred from inactivity —
/// a save you haven't touched in a year might be one you'll come back to, and
/// the app doesn't get to decide it's dead.
enum PlaythroughOutcome: String, CaseIterable, Codable, Sendable {
    case finished, dropped, shelved, lost

    var label: String {
        switch self {
        case .finished: "Finished"
        case .dropped:  "Dropped"
        case .shelved:  "Shelved"
        case .lost:     "Save lost"
        }
    }

    var systemImage: String {
        switch self {
        case .finished: "flag.checkered"
        case .dropped:  "xmark.circle"
        case .shelved:  "archivebox"
        case .lost:     "exclamationmark.triangle"
        }
    }

    /// A one-line explanation of what each one means, for the picker.
    var blurb: String {
        switch self {
        case .finished: "You're done with it, on your own terms."
        case .dropped:  "You stopped and don't plan to go back."
        case .shelved:  "Set aside for now — you might return."
        case .lost:     "The save is gone, whatever the reason."
        }
    }
}
