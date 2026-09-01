import WidgetKit
import SwiftUI

/// The dates themselves, on the Home Screen.
///
/// The pair divides the way the app's own two surfaces do. "Coming Soon" is
/// the wishlist: covers, because what you want is a wall of things you want
/// the look of. This is the calendar: days in a column, because the question
/// it answers is *when*, and specifically whether two games land in the same
/// week.
///
/// Same snapshot, same `WishlistShelf.comingSoon` filter behind it, same
/// midnight refresh — nothing here can change until a date does.
struct ReleaseCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ReleaseCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReleaseCalendarEntry {
        ReleaseCalendarEntry(date: .now, snapshot: WidgetSnapshot.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (ReleaseCalendarEntry) -> Void) {
        completion(ReleaseCalendarEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReleaseCalendarEntry>) -> Void) {
        let entry = ReleaseCalendarEntry(date: .now, snapshot: WidgetSnapshot.load())
        let midnight = ReleaseCountdown.utc
            .date(byAdding: .day, value: 1,
                  to: ReleaseCountdown.utc.startOfDay(for: .now)) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct ReleaseCalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot?

    private var games: [WidgetUpcomingGame] {
        let all = (snapshot?.upcoming ?? [])
            .filter { ReleaseCountdown.days(until: $0.releaseDate) != nil }
        return Array(all.prefix(family == .systemLarge ? 6 : 3))
    }

    var body: some View {
        if games.isEmpty {
            EmptyWidget()
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Label("RELEASE CALENDAR", systemImage: "calendar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)

                ForEach(games) { game in
                    Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                        HStack(spacing: 9) {
                            // The date block, the way a calendar row reads:
                            // the number first, big, and the weekday under it.
                            VStack(spacing: 0) {
                                Text(ReleaseCountdown.utc
                                    .component(.day, from: game.releaseDate), format: .number)
                                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                                    .foregroundStyle(LSWidget.accent)
                                Text(game.releaseDate.formatted(
                                    Date.FormatStyle(timeZone: .gmt).month(.abbreviated)))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .frame(width: 30)

                            CoverPoster(image: loadCover(game.coverFileName))
                                .frame(width: 22, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                            Text(game.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(ReleaseCountdown.countdown(to: game.releaseDate) ?? "")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct ReleaseCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReleaseCalendar", provider: ReleaseCalendarProvider()) { entry in
            ReleaseCalendarWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Release Calendar")
        .description("The dates your wanted games land on, soonest first.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
