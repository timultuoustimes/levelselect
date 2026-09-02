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
        } else if family == .systemLarge {
            monthGrid
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Label("RELEASE CALENDAR", systemImage: "calendar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 30)

                            CoverPoster(image: loadCover(game.coverFileName))
                                .frame(width: 22, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                            Text(game.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            Text(ReleaseCountdown.countdown(to: game.releaseDate) ?? "")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
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

extension ReleaseCalendarWidgetView {
    /// A real month, with covers standing where the numbers would be.
    ///
    /// The list says what is next; a grid says how a month is SHAPED — three
    /// games in one week and nothing for a fortnight is a fact you can only
    /// see laid out. Tim: "the calendar could be the list like you have it or
    /// an actual month's calendar grid."
    ///
    /// Which month: the one the soonest release lands in, not necessarily
    /// this one. A calendar showing an empty September while the thing you
    /// are waiting for sits in November is a grid with the answer scrolled
    /// off it.
    var monthGrid: some View {
        let cal = ReleaseCountdown.utc
        let anchorDate = games.first?.releaseDate ?? .now
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchorDate))
            ?? anchorDate
        let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        // Weekday of the 1st, as an offset into a Sunday-first row.
        let leading = (cal.component(.weekday, from: monthStart) - 1)

        // Day number → the game landing on it.
        var byDay: [Int: WidgetUpcomingGame] = [:]
        for game in (snapshot?.upcoming ?? []) where
            cal.isDate(game.releaseDate, equalTo: monthStart, toGranularity: .month) {
            byDay[cal.component(.day, from: game.releaseDate)] = game
        }

        // Whole weeks, so the rows can share the height between them.
        // A LazyVGrid sizes its rows to their content, which left the month
        // packed into the top third of a large widget with the rest empty.
        let cells = Array(repeating: 0, count: leading).map { _ in 0 }
            + Array(1...dayCount)
        let weeks = stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(monthStart.formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
                    .uppercased())
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)

            HStack(spacing: 2) {
                ForEach(cal.veryShortStandaloneWeekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 2) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if day == 0 {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let game = byDay[day] {
                            Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                                CoverPoster(image: loadCover(game.coverFileName))
                                    .aspectRatio(0.72, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(LSWidget.accent, lineWidth: 1.5))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            Text("\(day)")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ReleaseCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ReleaseCalendar", provider: ReleaseCalendarProvider()) { entry in
            ReleaseCalendarWidgetView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Release Calendar")
        .description("The dates your wanted games land on, soonest first.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
