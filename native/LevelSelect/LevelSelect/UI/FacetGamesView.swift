import SwiftUI
import SwiftData

/// Every game in the library matching one facet — a studio, a genre, a year.
///
/// Pushed rather than filtered in place, on purpose. The library's filter menu
/// is already three pickers deep, and adding developer, publisher, genre,
/// theme, perspective, mode and year to it would make the common case worse to
/// serve the rare one. Arriving from the thing you tapped is both fewer taps
/// and clearer about where you are.
struct FacetGamesView: View {
    let facet: GameFacet

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var library: [Game]

    private var games: [Game] { GameFacet.games(facet, in: library) }

    var body: some View {
        ScrollView {
            if games.isEmpty {
                ContentUnavailableView {
                    Label("Nothing here", systemImage: facet.kind.systemImage)
                } description: {
                    Text("No games in your library match \(facet.value).")
                }
                .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(games.count) \(games.count == 1 ? "game" : "games") · \(facet.kind.label)",
                          systemImage: facet.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)],
                              spacing: 16) {
                        ForEach(games) { game in
                            NavigationLink(value: game) {
                                LibraryGridCell(game: game, size: .medium)
                            }
                            .buttonStyle(PressableCardStyle())
                            .gameContextMenu(game)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .scrollIndicators(.hidden)
        .lsBackground()
        .navigationTitle(facet.value)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A tappable value in the game-info panel.
///
/// Looks like the plain text it replaces until you touch it — the panel is a
/// reference table first, and turning every field into an obvious button would
/// make it read like a menu.
struct FacetLink<Label: View>: View {
    let facet: GameFacet
    @ViewBuilder var label: Label

    var body: some View {
        NavigationLink(value: facet) { label }
            .buttonStyle(.plain)
    }
}
