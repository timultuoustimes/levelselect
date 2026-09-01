import SwiftUI
import SwiftData

/// The year ahead, as months.
///
/// Last of the release arc. The wishlist answers "what am I waiting for" and
/// the countdown answers "how long" — neither answers *when*, which is the
/// question you have when two games land in the same fortnight and you have
/// to choose. A list sorted by date implies that shape; a calendar states it.
///
/// Months, not weeks. A release calendar with nothing in most of its cells is
/// a grid of empty boxes, and the thing worth seeing is which months are
/// crowded and which are bare.
struct ReleaseCalendarView: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    private var upcoming: [Game] {
        WishlistShelf.comingSoon(games.filter { $0.status == .wishlist })
    }

    /// Grouped by the month they land in, earliest first.
    private var months: [(start: Date, games: [Game])] {
        let cal = ReleaseCountdown.utc
        let grouped = Dictionary(grouping: upcoming) { game -> Date in
            let parts = cal.dateComponents([.year, .month], from: game.firstReleaseDate ?? .now)
            return cal.date(from: parts) ?? .now
        }
        return grouped.map { (start: $0.key, games: $0.value) }
            .sorted { $0.start < $1.start }
    }

    /// Games with no date at all — named rather than hidden, because a
    /// calendar that silently drops half your wishlist is lying about what
    /// you are waiting for.
    private var undated: [Game] {
        WishlistShelf.noDateYet(games.filter { $0.status == .wishlist })
    }

    var body: some View {
        Group {
            if months.isEmpty && undated.isEmpty {
                ContentUnavailableView(
                    "Nothing dated yet",
                    systemImage: "calendar",
                    description: Text("Wishlist games with an announced date show up here, month by month."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                        ForEach(months, id: \.start) { month in
                            Section {
                                ForEach(month.games) { game in
                                    NavigationLink(value: game) { row(game) }
                                        .buttonStyle(.plain)
                                }
                            } header: {
                                monthHeader(month.start, count: month.games.count)
                            }
                        }

                        if !undated.isEmpty {
                            Section {
                                ForEach(undated) { game in
                                    NavigationLink(value: game) { row(game) }
                                        .buttonStyle(.plain)
                                }
                            } header: {
                                monthHeader(nil, count: undated.count)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .lsBackground()
        .navigationTitle("Release Calendar")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func monthHeader(_ start: Date?, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(start.map {
                $0.formatted(Date.FormatStyle(timeZone: .gmt).month(.wide).year())
            } ?? "No date yet")
                .font(.title3.bold())
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .background(LSTheme.background)
    }

    private func row(_ game: Game) -> some View {
        HStack(spacing: 12) {
            // The day, big, because in a month view the day is the fact you
            // are scanning for.
            VStack(spacing: 1) {
                if let date = game.firstReleaseDate, !ReleaseCountdown.isYearOnly(date) {
                    Text(ReleaseCountdown.utc.component(.day, from: date), format: .number)
                        .font(.title3.bold().monospacedDigit())
                    Text(date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "calendar.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38)

            CoverThumb(urlString: game.displayCoverURLString)
                .frame(width: 40, height: 53)
                .coverGloss(cornerRadius: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(game.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let platform = game.chosenPlatform {
                    HStack(spacing: 5) {
                        PlatformIconView(platform: platform, size: 14)
                        Text(PlatformShort.name(platform))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 6)

            if let date = game.firstReleaseDate,
               let soon = ReleaseCountdown.countdown(to: date) {
                Text(soon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LSTheme.accent)
            }
        }
        .padding(10)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}
