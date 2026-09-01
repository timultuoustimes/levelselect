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
        return Array(all.prefix(family == .systemSmall ? 1 : family == .systemMedium ? 3 : 6))
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
    private func single(_ game: WidgetUpcomingGame) -> some View {
        Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
            VStack(alignment: .leading, spacing: 7) {
                header
                CoverPoster(image: loadCover(game.coverFileName))
                    .aspectRatio(0.72, contentMode: .fit)
                    .frame(maxHeight: .infinity)
                Text(countdown(game))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LSWidget.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(game.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(games) { game in
                Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                    HStack(spacing: 9) {
                        CoverPoster(image: loadCover(game.coverFileName))
                            .frame(width: 26, height: 35)
                        Text(game.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(countdown(game))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LSWidget.accent)
                            .lineLimit(1)
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
            .foregroundStyle(.white.opacity(0.55))
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
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Coming Soon")
        .description("The games on your wishlist that have not come out yet, and how long the wait is.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
