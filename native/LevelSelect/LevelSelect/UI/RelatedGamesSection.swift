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

    /// Cover width scales with text size, so the two-line title underneath
    /// stays readable rather than truncating to nothing at accessibility
    /// sizes. The 3:4 art ratio is derived from it rather than fixed twice.
    @ScaledMetric(relativeTo: .caption2) private var coverWidth: CGFloat = 78

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var library: [Game]
    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil },
           sort: \GameCollection.name)
    private var collections: [GameCollection]

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
        let series = RelatedGames.sameFranchise(as: game, in: library)
        let studio = series.isEmpty ? RelatedGames.sameDeveloper(as: game, in: library) : nil
        let alike = RelatedGames.similar(to: game, in: library)

        if !personalLists.isEmpty || !bundles.isEmpty
            || !series.isEmpty || studio != nil || !alike.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                if !bundles.isEmpty {
                    chips("Included In", bundles, systemImage: "shippingbox")
                }
                if !personalLists.isEmpty {
                    chips("Your Lists", personalLists, systemImage: "square.stack")
                }
                if !series.isEmpty, let franchise = game.franchise {
                    shelf("More from \(franchise)", games: series)
                }
                if let studio {
                    shelf("More from \(studio.developer)", games: studio.games)
                }
                if !alike.isEmpty {
                    shelf("Plays Like This", games: alike,
                          footnote: "Matched on genre, theme and perspective — at least two in common.")
                }
            }
        }
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
                                CoverThumb(urlString: other.coverURLString)
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
