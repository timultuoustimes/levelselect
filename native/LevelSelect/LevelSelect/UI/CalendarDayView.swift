import SwiftUI
import SwiftData

/// Everything that happened on one day.
///
/// **The Calendar and the Timeline disagreed about what a day contained.** The
/// Timeline groups entries by day and lists them; the Calendar linked a cell
/// straight to a single `JournalEntry`, so a day holding two games opened one
/// of them and the other could not be reached from the calendar at all.
/// 2026-03-01 showed Dead Cells *and* Sayonara Wild Hearts on the Timeline and
/// only Dead Cells through the Calendar — found by Tim, via the spoken summary,
/// which described the whole day and so did not match what tapping produced.
///
/// The fix is not a second grouping. This asks `JournalBuilder.periods` for the
/// day, which is the same call the Timeline makes, so the two cannot disagree
/// about a day's contents again.
///
/// A day with ONE thing on it still opens that thing directly — see `DayCell`.
/// A list of one is a tax, not a feature.
struct CalendarDayView: View {
    let day: Date

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]
    @Query(filter: #Predicate<Memory> { $0.deletedAt == nil && $0.game == nil })
    private var standaloneMemories: [Memory]

    /// The day's entries, from the Timeline's own grouping.
    private var entries: [JournalEntry] {
        let calendar = JournalBuilder.calendar
        let target = calendar.startOfDay(for: day)
        return JournalBuilder.periods(from: games, standalone: standaloneMemories)
            .filter { $0.grain == .day && calendar.startOfDay(for: $0.start) == target }
            .flatMap(\.entries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if entries.isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: "calendar",
                                           description: Text("This day has no entries any more."))
                        .padding(.top, 40)
                } else {
                    ForEach(entries) { entry in
                        NavigationLink(value: JournalRoute(entry: entry)) {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .lsBackground()
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Deliberately the Timeline's shape — cover, name, what happened — so a
    /// day reached through the Calendar looks like the same day reached
    /// through the Timeline.
    private func row(_ entry: JournalEntry) -> some View {
        HStack(spacing: 12) {
            // The guard used to be `let url = game.displayCoverURLString`,
            // which is nil for a locally picked cover — so choosing a photo as
            // a game's cover made it vanish from the Journal day and fall
            // through to the memory's own image. Ask for the game's artwork
            // instead of for a URL.
            if let game = entry.game,
               !game.resolvedArtwork(.cover).isEmpty {
                CoverThumb(urlString: game.displayCoverURLString,
                           artwork: game.resolvedArtwork(.cover),
                           name: game.name, status: game.status)
                    .frame(width: 44, height: 59)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let data = entry.images.first?.data {
                LocalArtworkThumb(data: data, contentMode: .fill)
                    .frame(width: 44, height: 59)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let summary = summary(entry) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
        .accessibilityElement(children: .combine)
    }

    private func summary(_ entry: JournalEntry) -> String? {
        var parts: [String] = []
        if entry.duration > 0 { parts.append(Format.duration(entry.duration)) }
        if !entry.runs.isEmpty {
            parts.append(entry.runs.count == 1 ? "1 run" : "\(entry.runs.count) runs")
        }
        if !entry.finishes.isEmpty { parts.append("Beaten") }
        if entry.kind == .memory { parts.append("Memory") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
