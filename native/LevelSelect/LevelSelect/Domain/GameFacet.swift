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

    /// What to call this slice on screen.
    ///
    /// IGDB writes a few genres as "Name (ABBR)" — "Role-playing (RPG)",
    /// "Real Time Strategy (RTS)", "Turn-based strategy (TBS)". In every one
    /// of those the abbreviation IS the common name, so the parenthetical is
    /// the useful half and the prose is the redundant one. Three of the
    /// twenty-one genres in a real 183-game library are of this shape; the
    /// rest are already plain words and pass through untouched.
    ///
    /// Display only. `value` stays exactly what IGDB sent, because it is what
    /// `matches(_:)` compares against and what a game record actually stores —
    /// the same split `PlatformShort` keeps between a stored platform string
    /// and the name shown for it.
    var displayName: String {
        guard value.hasSuffix(")"),
              let open = value.lastIndex(of: "("),
              open > value.startIndex
        else { return value }
        let abbreviation = value[value.index(after: open)..<value.index(before: value.endIndex)]
        // Only when it reads as an abbreviation. "Card & Board Game (and
        // similar)" should keep its full name rather than become "and similar".
        guard abbreviation.count <= 5,
              abbreviation.allSatisfy({ $0.isUppercase || $0.isNumber })
        else { return value }
        return String(abbreviation)
    }

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
            return String(ReleaseCountdown.utc.component(.year, from: date)) == value
        }
    }

    static func games(_ facet: GameFacet, in library: [Game]) -> [Game] {
        library
            .filter { $0.deletedAt == nil && facet.matches($0) }
            .sorted { ($0.firstReleaseDate ?? .distantPast, $0.name)
                    < ($1.firstReleaseDate ?? .distantPast, $1.name) }
    }
}
