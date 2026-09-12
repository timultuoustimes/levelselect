import WidgetKit
import SwiftUI

/// What you are waiting for, on the Home Screen.
///
/// Second of the release arc, after the countdown on the wishlist card. The
/// wishlist is the only forward-looking surface in the app, and it was the
/// only one with nothing on the Home Screen — so the one thing you might
/// actually want a glance at, the date a game you want arrives, was the one
/// thing you had to open the app for.
///
/// It draws the same games the wishlist's "Coming soon" shelf draws, from the
/// same `WishlistShelf.comingSoon` filter, so it can never show something the
/// app has already moved to "No date yet".
struct ReleasesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ReleasesProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReleasesEntry {
        ReleasesEntry(date: .now, snapshot: WidgetSnapshot.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (ReleasesEntry) -> Void) {
        completion(ReleasesEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReleasesEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let entry = ReleasesEntry(date: .now, snapshot: snapshot)
        // Refresh at the next UTC midnight, not in an hour. Every number on
        // this widget is a count of whole days, so nothing it says can change
        // until the date does — and a countdown that still reads "Tomorrow" on
        // the morning of is the one way this widget can be actively wrong.
        let midnight = ReleaseCountdown.utc
            .date(byAdding: .day, value: 1,
                  to: ReleaseCountdown.utc.startOfDay(for: .now)) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct ReleasesView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot?

    private var games: [WidgetUpcomingGame] {
        let all = (snapshot?.upcoming ?? [])
            .filter { ReleaseCountdown.days(until: $0.releaseDate) != nil }
        return Array(all.prefix(family == .systemSmall ? 1 : family == .systemMedium ? 4 : 6))
    }

    var body: some View {
        if games.isEmpty {
            EmptyWidget()
        } else if family == .systemSmall, let next = games.first {
            single(next)
        } else {
            list
        }
    }

    /// The small size answers one question, so it asks one: what is next.
    ///
    /// Cover beside the name, then the wait as the largest thing on the tile
    /// with the date under it — the shape Tim pointed at: "a small release
    /// date could be a single game and its release date." The number is the
    /// headline because it is the part that changes.
    private func single(_ game: WidgetUpcomingGame) -> some View {
        Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    CoverPoster(image: loadCover(game.coverFileName))
                        .frame(width: 54, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(game.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(countdown(game))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(LSWidget.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(ReleaseCountdown.dateLabel(game.releaseDate))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Covers, with the wait written on them.
    ///
    /// This was a list: a 26pt thumbnail, a name, and a countdown in a row.
    /// That is the calendar widget's job, and doing it twice made the pair
    /// redundant — Tim: "can the other widget be brought to be more art
    /// focused?" A wishlist is a wall of things you want the look of, so the
    /// art is the content and the countdown is the label on it.
    private var list: some View {
        // Fixed columns, not flexible ones. With `.flexible()` two games
        // stretched to fill the whole width and pushed the header off the
        // top — a widget with two things in it should look like a widget with
        // two things in it, not like a poster.
        let coverWidth: CGFloat = family == .systemLarge ? 78 : 62
        return VStack(alignment: .leading, spacing: 7) {
            header
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(coverWidth), spacing: 9),
                               count: family == .systemLarge ? 3 : 4),
                alignment: .leading, spacing: 8
            ) {
                ForEach(games) { game in
                    Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                        VStack(spacing: 3) {
                            CoverPoster(image: loadCover(game.coverFileName))
                                .frame(width: coverWidth, height: coverWidth / 0.72)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(countdown(game))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LSWidget.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: coverWidth)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        Label("COMING SOON", systemImage: "calendar")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// Computed from the date at draw time rather than baked into the
    /// snapshot, because a widget can be rendered long after the app last
    /// wrote one and "in 2 days" would have quietly become wrong.
    private func countdown(_ game: WidgetUpcomingGame) -> String {
        ReleaseCountdown.countdown(to: game.releaseDate)
            ?? ReleaseCountdown.dateLabel(game.releaseDate)
    }
}

struct ReleasesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Releases", provider: ReleasesProvider()) { entry in
            ReleasesView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Coming Soon")
        .description("The games on your wishlist that have not come out yet, and how long the wait is.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
