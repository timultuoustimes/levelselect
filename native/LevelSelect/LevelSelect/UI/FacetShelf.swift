import SwiftUI

/// A row of ways into the library, by something IGDB already told us.
///
/// **The destination existed; the front door did not.** `GameFacet` has
/// covered genre, theme, perspective, mode, year, franchise and tag since it
/// was written, `FacetGamesView` renders any of them, and a game page has
/// linked to them all along — tap "Metroidvania" on a game and you get every
/// game you own that shares it. What was missing is the index: Library lists
/// your Systems and your Collections, so it knew how to say "here are the
/// ways in", but genres and themes were reachable only if you already had a
/// game in front of you that had one.
///
/// So this is deliberately not a new browsing system. It is `SystemsRow`'s
/// shape pointed at a facet, and it stores nothing, fetches nothing and syncs
/// nothing — the values have been in every game record since it was imported.
///
/// Stage 1 of [[LevelSelect taxonomy and Wikidata spec 2026-09-07]].
struct FacetShelf: View {
    let title: String
    let kind: GameFacet.Kind
    /// Value and count, largest first. Built by the caller from the games
    /// actually on screen, so the numbers agree with the filter above them.
    let groups: [(value: String, count: Int)]
    var onOpen: (GameFacet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShelfHeader(title: title,
                        count: groups.count,
                        systemImage: kind.systemImage,
                        tint: LSTheme.accent)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(groups, id: \.value) { group in
                        BouncyTap {
                            onOpen(GameFacet(kind: kind, value: group.value))
                        } label: {
                            chip(group)
                        }
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// A word and a number.
    ///
    /// Not a tile like the systems row: a console has art worth 84 points of
    /// space, and "Science fiction" has none. A capsule sized to its own words
    /// fits far more of them on a screen, which matters when a real library
    /// has twenty-one genres rather than eight consoles.
    private func chip(_ group: (value: String, count: Int)) -> some View {
        HStack(spacing: 6) {
            Text(GameFacet(kind: kind, value: group.value).displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Text("\(group.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LSTheme.cardFill, in: .capsule)
        .overlay(Capsule().strokeBorder(LSTheme.hairline, lineWidth: 1))
        // Vertical only, like every other chip row: growing sideways would let
        // neighbours overlap and the wrong one win the tap. See `lsTapTargetTall`.
        .lsTapTargetTall()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(GameFacet(kind: kind, value: group.value).displayName), \(group.count) games")
        .accessibilityHint("Shows them")
    }
}

extension GameFacet {
    /// The values present in a set of games, counted, largest first.
    ///
    /// **Counts overlap and do not partition the library**, the same way the
    /// systems row and the ownership chips do not: a game with three genres
    /// stands in three of these. That is a fact about the games rather than a
    /// bucket sort, and the header's count is of VALUES, not of games, so
    /// nothing here claims to add up.
    ///
    /// Ties break alphabetically so the row does not reshuffle between visits.
    static func groups(of kind: Kind, in games: [Game]) -> [(value: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in games {
            for value in values(of: kind, in: game) {
                counts[value, default: 0] += 1
            }
        }
        return counts
            .map { (value: $0.key, count: $0.value) }
            .sorted { ($1.count, $0.value) < ($0.count, $1.value) }
    }

    /// The raw stored values a game carries for a kind.
    ///
    /// Only the kinds an index is offered for. The rest are reachable from a
    /// game page, which is the right place for "who published this" — a
    /// publisher row would be a hundred entries long and answer a question
    /// nobody opens Library to ask.
    private static func values(of kind: Kind, in game: Game) -> [String] {
        switch kind {
        case .genre:       game.genres
        case .theme:       game.themes
        case .perspective: game.playerPerspectives
        case .mode:        game.gameModes
        case .tag:         game.userTags
        default:           []
        }
    }
}
