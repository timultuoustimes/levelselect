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
///
/// `previouslyOwned` records a copy that's gone — sold, traded, lent and
/// never returned. A lifetime library holds games you no longer hold, and
/// before this case the only honest options were pretending you still owned
/// it or deleting the history. New case in a String-raw enum = no schema
/// version, the same free path `wishlist` and `ongoing` took.
enum Ownership: String, Codable, CaseIterable, Sendable {
    case physical, digital, emulated, previouslyOwned

    var label: String {
        switch self {
        case .physical: "Physical"
        case .digital:  "Digital"
        case .emulated: "Emulated"
        case .previouslyOwned: "Previously owned"
        }
    }

    var systemImage: String {
        switch self {
        case .physical: "opticaldisc"
        case .digital:  "arrow.down.circle"
        case .emulated: "cpu"
        case .previouslyOwned: "shippingbox"
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
    /// Authored content brought in from a real source — RetroAchievements
    /// today. A String-raw case costs nothing (the "ongoing" status rule);
    /// what it buys is the record agreeing with the badge: the UI has said
    /// "RetroAchievements" since the badge shipped while the DATA said an AI
    /// made it, and an export that claims Claude wrote Nintendo's achievement
    /// list is the kind of lie this app exists to not tell.
    case imported
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
