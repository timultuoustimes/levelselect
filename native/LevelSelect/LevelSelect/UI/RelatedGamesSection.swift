import SwiftUI
import SwiftData

/// What else in the library connects to this game.
///
/// Four relationships, strongest first, and each one only appears if it has
/// something to say. The order is the point: a collection you built yourself
/// outranks a series, which outranks a studio, which outranks "these share
/// some tags" — and the weakest of them is the one worth being most careful
/// about, because a section full of obviously-wrong suggestions teaches people
/// to stop reading the section.
struct RelatedGamesSection: View {
    let game: Game
    /// A series name from a second source — Wikidata's — used only when
    /// the game carries no franchise of its own. Build 39's "series
    /// surfaced", pulled into 38: the shelf that IGDB's data could not draw.
    var seriesHint: String? = nil

    /// Cover width scales with text size, so the two-line title underneath
    /// stays readable rather than truncating to nothing at accessibility
    /// sizes. The 3:4 art ratio is derived from it rather than fixed twice.
    @ScaledMetric(relativeTo: .caption2) private var coverWidth: CGFloat = 78

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var library: [Game]
    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil },
           sort: \GameCollection.name)
    private var collections: [GameCollection]

    /// The series and studio shelves of games you DON'T have. Asked once per
    /// game page, after the library's own answers, because those are instant
    /// and this is a network call.
    @State private var connections: [SuggestionsService.Connection] = []
    @State private var addingConnection: String?
    @State private var askedConnections = false
    @AppStorage("levelselect.showConnections") private var showConnections = true

    /// Two different things that both happen to be collections.
    ///
    /// "Comfort games" is a statement you made about this game. "Mega Man X
    /// Legacy Collection" is a product someone sold you that happens to
    /// contain it. The model already separates them — `isBundle` — and running
    /// them together in one row would flatten a real distinction: one is your
    /// opinion, the other is a fact about a purchase.
    private var personalLists: [GameCollection] {
        collections.filter { $0.contains(game) && !$0.isBundle }
    }

    private var bundles: [GameCollection] {
        collections.filter { $0.contains(game) && $0.isBundle }
    }

    var body: some View {
        let seriesName = game.franchise ?? seriesHint
        let series = RelatedGames.sameFranchise(as: game, named: seriesName, in: library)
        let studio = series.isEmpty ? RelatedGames.sameDeveloper(as: game, in: library) : nil
        let alike = RelatedGames.similar(to: game, in: library)

        // The whole section, including the task, exists whatever the library
        // has to say: a game with no relations of its own is exactly the one
        // whose series and studio shelves are worth fetching.
        VStack(alignment: .leading, spacing: 18) {
            if !personalLists.isEmpty || !bundles.isEmpty
                || !series.isEmpty || studio != nil || !alike.isEmpty || !connections.isEmpty {
                if !bundles.isEmpty {
                    chips("Included in Bundles", bundles, systemImage: "shippingbox")
                }
                if !personalLists.isEmpty {
                    // "Your Collections", not "Your Lists" — the app calls
                    // these Collections everywhere else, and a second noun for
                    // one concept is how a first-time user learns there are
                    // two things when there is one.
                    chips("Your Collections", personalLists, systemImage: "square.stack")
                }
                if !series.isEmpty, let seriesName {
                    shelf("More from \(seriesName)", games: series,
                          footnote: game.franchise == nil ? "Series from Wikidata." : nil)
                }
                if let studio {
                    shelf("More from \(studio.developer)", games: studio.games)
                }
                if !alike.isEmpty {
                    shelf("Plays Like This", games: alike,
                          footnote: "Matched on genre, theme and perspective — at least two in common.")
                }
                ForEach(connections) { connection in
                    outsideShelf(connection)
                }
            }
        }
        .task(id: game.id) { await loadConnections() }
        .sheet(item: Binding(get: { addingConnection.map(NamedTarget.init) },
                             set: { addingConnection = $0?.name })) { target in
            AddGameSheet(initialSearch: target.name, defaultStatus: .wishlist).lsSheet()
        }
    }

    private struct NamedTarget: Identifiable {
        let name: String
        var id: String { name }
    }

    /// Games this one connects to that aren't yours. Tapping adds to the
    /// wishlist rather than opening a page that doesn't exist.
    private func outsideShelf(_ connection: SuggestionsService.Connection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(connection.title) — not in your library")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(connection.games) { other in
                        Button {
                            addingConnection = other.name
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncImage(url: other.coverImageID.flatMap {
                                    URL(string: "https://images.igdb.com/igdb/image/upload/t_cover_big/\($0).jpg")
                                }) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill()
                                    } else {
                                        LSTheme.accent.opacity(0.12)
                                    }
                                }
                                .frame(width: coverWidth, height: coverWidth * 4 / 3)
                                .clipShape(.rect(cornerRadius: 8))
                                Text(other.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: coverWidth, alignment: .leading)
                            }
                        }
                        .buttonStyle(PressableCardStyle())
                        .accessibilityLabel("\(other.name). Add to wishlist")
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func loadConnections() async {
        guard showConnections, !askedConnections else { return }
        askedConnections = true
        let have = Set(library.compactMap(\.igdbID))
        connections = await SuggestionsService.connections(for: game, have: have)
    }

    /// Collection membership, which nothing else on the game page tells you.
    private func chips(_ title: String, _ items: [GameCollection],
                       systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            FlowLayout(spacing: 8) {
                ForEach(items) { collection in
                    NavigationLink(value: CollectionRoute(id: collection.id)) {
                        Label(collection.name, systemImage: systemImage)
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(LSTheme.accent.opacity(0.16), in: .capsule)
                            .overlay(Capsule().strokeBorder(LSTheme.accent.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func shelf(_ title: String, games: [Game], footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.tertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(games) { other in
                        NavigationLink(value: other) {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverThumb(urlString: other.displayCoverURLString,
                                           artwork: other.resolvedArtwork(.cover),
                                           name: other.name, status: other.status)
                                    .frame(width: coverWidth, height: coverWidth * 4 / 3)
                                    .clipShape(.rect(cornerRadius: 8))
                                Text(other.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: coverWidth, alignment: .leading)
                            }
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}
