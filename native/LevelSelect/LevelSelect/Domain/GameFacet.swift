import Foundation

/// One thing a library can be sliced by, and the route that shows the slice.
///
/// Everything in a game's info panel is really a link: "Sega Technical
/// Institute" is not a fact about this game so much as a set of games, and the
/// only reason it wasn't tappable is that nothing had defined what tapping it
/// should do. This does — and it means every facet gets a filtered view for
/// free rather than each needing its own filter control in the library's
/// already-crowded menu.
struct GameFacet: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case developer, publisher, genre, theme, perspective, mode, year, franchise, tag

        /// What to call the resulting screen — the field's own name, since the
        /// value is already the title.
        var label: String {
            switch self {
            case .developer:   "Developer"
            case .publisher:   "Publisher"
            case .genre:       "Genre"
            case .theme:       "Theme"
            case .perspective: "Perspective"
            case .mode:        "Game Mode"
            case .year:        "Released"
            case .franchise:   "Series"
            case .tag:         "Tag"
            }
        }

        var systemImage: String {
            switch self {
            case .developer:   "hammer"
            case .publisher:   "building.2"
            case .genre:       "theatermasks"
            case .theme:       "paintpalette"
            case .perspective: "eye"
            case .mode:        "person.2"
            case .year:        "calendar"
            case .franchise:   "square.stack.3d.up"
            case .tag:         "tag"
            }
        }
    }

    let kind: Kind
    let value: String

    /// Whether a game belongs in this slice.
    ///
    /// Matching is exact rather than fuzzy: these values come from IGDB and
    /// from each other, so they already agree, and a loose match here would
    /// quietly merge "Action" and "Action-Adventure" into one screen that
    /// claims to be neither.
    func matches(_ game: Game) -> Bool {
        switch kind {
        case .developer:   return game.developers.contains(value)
        case .publisher:   return game.publishers.contains(value)
        case .genre:       return game.genres.contains(value)
        case .theme:       return game.themes.contains(value)
        case .perspective: return game.playerPerspectives.contains(value)
        case .mode:        return game.gameModes.contains(value)
        case .franchise:   return game.franchise == value
        case .tag:         return game.userTags.contains(value)
        case .year:
            guard let date = game.firstReleaseDate else { return false }
            return String(Calendar.current.component(.year, from: date)) == value
        }
    }

    static func games(_ facet: GameFacet, in library: [Game]) -> [Game] {
        library
            .filter { $0.deletedAt == nil && facet.matches($0) }
            .sorted { ($0.firstReleaseDate ?? .distantPast, $0.name)
                    < ($1.firstReleaseDate ?? .distantPast, $1.name) }
    }
}
