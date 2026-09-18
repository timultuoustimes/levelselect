import Foundation

/// What a tracker is for, asked before planning. Tim, 09-17: *"I don't think
/// it should automatically force them into a bigger tracker than what they
/// are wanting, since some people may actually just want a basic checklist."*
///
/// The app offers shapes by the game's genres; the server holds the
/// instruction for each (`SHAPES` in `ai-tracker-generator`). Nothing is
/// stored: a shape only steers one plan.
enum TrackerShape: String, CaseIterable, Identifiable, Sendable {
    case story, checklist, roster, completionist, collectibles, unlocks, runs, seasonal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .story: "Story only"
        case .checklist: "A simple checklist"
        case .roster: "Party & roster"
        case .completionist: "Everything for 100%"
        case .collectibles: "Collectibles"
        case .unlocks: "Unlocks"
        case .runs: "Runs & bests"
        case .seasonal: "Collections & seasons"
        }
    }

    var blurb: String {
        switch self {
        case .story: "Chapters or main quests in order, and the big bosses."
        case .checklist: "A few lists of what most players care about. Nothing more."
        case .roster: "Who you've recruited, their class and level, who's in your party."
        case .completionist: "Every set the game counts toward 100%."
        case .collectibles: "Just the things to find."
        case .unlocks: "Characters, weapons and upgrades you unlock between runs."
        case .runs: "A short list of bosses and endings. Your runs are logged separately."
        case .seasonal: "Fish, bugs, crops and friends, filtered by season and weather."
        }
    }

    var systemImage: String {
        switch self {
        case .story: "book.pages"
        case .checklist: "checklist"
        case .roster: "person.3"
        case .completionist: "star.circle"
        case .collectibles: "sparkles"
        case .unlocks: "lock.open"
        case .runs: "flag.checkered"
        case .seasonal: "leaf"
        }
    }

    /// The shapes worth offering for a game, most likely first.
    static func offered(genres: [String], themes: [String], hasRuns: Bool) -> [TrackerShape] {
        let words = (genres + themes).joined(separator: " ").lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { words.contains($0) } }
        if hasRuns || has("rogue") {
            return [.unlocks, .runs, .checklist, .completionist]
        }
        if has("simulator", "simulation", "sandbox"), !has("racing", "flight", "sport") {
            return [.seasonal, .checklist, .completionist]
        }
        if has("role-playing", "rpg", "tactical", "turn-based strategy") {
            return [.story, .checklist, .roster, .completionist]
        }
        return [.story, .checklist, .collectibles, .completionist]
    }
}
