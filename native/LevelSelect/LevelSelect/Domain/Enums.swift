import Foundation

// MARK: - Domain enums (see native/DOMAIN-MODEL.md)
// All String-raw for direct SwiftData attribute storage.

/// Legacy `status` — 7 values verified against the frozen library — plus
/// `wishlist` (added 2026-08: games not yet owned, promoted from Deku Deals)
/// and `ongoing` (added 2026-08: games with no finish line).
///
/// Adding a case costs no schema version: this is stored as a String
/// attribute, so the shape on disk and in CloudKit is unchanged.
enum GameStatus: String, Codable, CaseIterable, Sendable {
    case backlog, playing, paused, completed, queued, shelved, abandoned, wishlist, ongoing
}

enum SessionState: String, Codable, Sendable {
    case running, paused, stopped
}

/// How you own a game. Multi-select (a game can be owned physically AND
/// digitally); stored on `Game.ownership` as an array of raw values.
enum Ownership: String, Codable, CaseIterable, Sendable {
    case physical, digital, emulated

    var label: String {
        switch self {
        case .physical: "Physical"
        case .digital:  "Digital"
        case .emulated: "Emulated"
        }
    }

    var systemImage: String {
        switch self {
        case .physical: "opticaldisc"
        case .digital:  "arrow.down.circle"
        case .emulated: "cpu"
        }
    }
}

/// Completion event label. `.custom` pairs with `CompletionEvent.customLabel`
/// (kept as a sibling String to avoid associated-value enums in SwiftData).
enum CompletionLabel: String, Codable, CaseIterable, Sendable {
    case completed, hundredPercent, newGamePlus, cleared, custom
}

enum TrackerSource: String, Codable, Sendable {
    case builtIn, aiGenerated
}

enum TrackerEngine: String, Codable, Sendable {
    case objective, run
}

enum RunOutcome: String, Codable, Sendable {
    case inProgress, success, failure, neutral
}

enum MapKind: String, Codable, Sendable {
    case world, area, other
}

enum MarkerCategory: String, Codable, CaseIterable, Sendable {
    case collectible, note, warning, secret
}

enum SyncOpType: String, Codable, Sendable {
    case upsert, delete
}

/// How a game presents its tracker on the game page.
enum TrackerDisplay: String, Codable, CaseIterable, Sendable {
    case inline     // embedded sections (original)
    case compact    // playthrough card + dedicated tracker page/panel

    var label: String {
        switch self {
        case .inline: "Inline"
        case .compact: "Compact"
        }
    }
}
