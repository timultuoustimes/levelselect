import SwiftUI
import SwiftData

/// A year of play, as pictures.
///
/// **The cell wears a picture, not a dot.** That is the idea worth stealing
/// from every journal app Tim looked at — but this app can do a better version
/// than they can. A general journal has only the photos you took; LevelSelect
/// knows what you *played*, so a day wears the cover of the game, and a
/// memory's own photo when it has one. A month of Cat Quest covers with a
/// Christmas photo sitting in December is a picture of a year that a general
/// journal cannot draw.
///
/// **An empty day is a `+`.** Adding a memory for 14 March used to mean
/// opening a sheet and setting a date; tapping the 14th is the same act with
/// the date already answered — which is what backfilling a life of gaming
/// actually needs.
struct JournalCalendarView: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]
    @Query(filter: #Predicate<Memory> { $0.deletedAt == nil && $0.game == nil })
    private var standaloneMemories: [Memory]

    @State private var creatingOn: CreationDay?

    private var calendar: Calendar { JournalBuilder.calendar }

    var body: some View {
        let periods = JournalBuilder.periods(from: games, standalone: standaloneMemories)
        let byDay = Dictionary(grouping: periods.filter { $0.grain == .day },
                               by: { JournalBuilder.square(for: $0.start, in: $0.calendar) })
        let undated = periods.filter { $0.grain != .day }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                ForEach(months(covering: byDay.keys), id: \.self) { month in
                    Section {
                        MonthGrid(month: month,
                                  calendar: calendar,
                                  periods: byDay,
                                  onCreate: { creatingOn = CreationDay(date: JournalBuilder.memoryDate(for: $0)) })
                    } header: {
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .background(LSTheme.ground(tintedBy: ThemePalette.backgroundOverride))
                    }
                }

                if !undated.isEmpty {
                    // **The entries a grid cannot hold.** "Christmas 1995 or
                    // 1996" has no square, and dropping it would be the
                    // calendar quietly editing someone's history. Kept below
                    // the months, the way the release calendar keeps its "no
                    // date yet" group rather than pretending it is empty.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No single day")
                            .font(.headline)
                        ForEach(undated) { period in
                            ForEach(period.entries) { entry in
                                NavigationLink(value: JournalRoute(entry: entry)) {
                                    HStack(spacing: 10) {
                                        Text(period.title()).font(.subheadline.weight(.medium))
                                        Text(entry.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .lsCard()
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .overlay {
            if periods.isEmpty {
                ContentUnavailableView(
                    "Nothing on the calendar yet",
                    systemImage: "calendar",
                    description: Text("Days you play fill in on their own. Tap any empty day to write down something that happened."))
            }
        }
        .sheet(item: $creatingOn) { day in
            MemorySheet(initialDate: day.date)
        }
    }

    /// Every month from the earliest entry to this one, newest first.
    ///
    /// Newest first because a journal is browsed backwards — the release
    /// calendar runs the other way for the opposite reason, since what you are
    /// waiting for is ahead of you.
    private func months(covering days: some Collection<Date>) -> [Date] {
        let thisMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now
        guard let earliest = days.min(),
              let start = calendar.dateInterval(of: .month, for: earliest)?.start
        else { return [thisMonth] }

        var result: [Date] = []
        var cursor = thisMonth
        // Guarded rather than open-ended: one bad stored date in 1200 would
        // otherwise build ten thousand months and hang the tab.
        while cursor >= start, result.count < 600 {
            result.append(cursor)
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor)
            else { break }
            cursor = previous
        }
        return result
    }
}

/// `sheet(item:)` wants an Identifiable, and a Date is not one.
///
/// A wrapper rather than a retroactive `Date: Identifiable` conformance:
/// extending a Foundation type for one sheet leaks into every file in the
/// module and is exactly the kind of thing another target later trips over.
private struct CreationDay: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct MonthGrid: View {
    let month: Date
    let calendar: Calendar
    let periods: [Date: [JournalPeriod]]
    let onCreate: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                // Blanks so the first of the month lands under its weekday.
                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 46)
                }
                ForEach(days, id: \.self) { day in
                    DayCell(day: day,
                            calendar: calendar,
                            entries: periods[day]?.flatMap(\.entries) ?? [],
                            onCreate: onCreate)
                }
            }
        }
    }

    /// Starts on whichever day the user's locale calls first — a grid that
    /// begins on Monday for someone whose week begins on Sunday is subtly
    /// wrong all month.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var result: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            result.append(calendar.startOfDay(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private var leadingBlanks: Int {
        guard let first = days.first else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}

private struct DayCell: View {
    let day: Date
    let calendar: Calendar
    let entries: [JournalEntry]
    let onCreate: (Date) -> Void

    /// What the cell wears. A memory's own photo first — someone chose to
    /// attach that — then the cover of whatever was played longest.
    private var art: (data: Data?, url: String?)? {
        if let photo = entries.compactMap({ $0.images.first }).first, let data = photo.data {
            return (data, nil)
        }
        let longest = entries.filter { $0.kind == .play }
            .max { $0.duration < $1.duration }
        if let url = longest?.game?.displayCoverURLString { return (nil, url) }
        return nil
    }

    private var isToday: Bool { calendar.isDateInToday(day) }
    private var isFuture: Bool { day > calendar.startOfDay(for: .now) }

    var body: some View {
        Group {
            if entries.isEmpty {
                Button { onCreate(day) } label: { empty }
                    .buttonStyle(.plain)
                    // A day that has not happened cannot be written about.
                    .disabled(isFuture)
                    .opacity(isFuture ? 0.35 : 1)
            } else if let first = entries.first {
                NavigationLink(value: JournalRoute(entry: first)) { filled }
                    .buttonStyle(.plain)
            }
        }
    }

    private var empty: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LSTheme.cardFill)
            .frame(height: 46)
            .overlay {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .overlay(alignment: .topLeading) { number.padding(3) }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(LSTheme.accent, lineWidth: 1.5)
                }
            }
    }

    /// **One clip, outermost.** Cover art is drawn to fill and overflows
    /// whatever size it is proposed; when each layer rounded its own corners
    /// the art escaped the 46pt cell and August's rows sat on top of each
    /// other. Clipping the composed cell — rather than asking every layer to
    /// behave — is the version that cannot come apart when a layer is added.
    private var filled: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LSTheme.elevatedFill)
            .frame(height: 46)
            .overlay {
                if let art {
                    if let data = art.data {
                        LocalArtworkThumb(data: data, contentMode: .fill)
                    } else if let url = art.url {
                        CoverThumb(urlString: url)
                    }
                }
            }
            .overlay {
                // The scrim exists to keep the number readable over bright
                // cover art. With no art there is nothing to darken, and
                // laying it on anyway made a photo-less memory a murky grey
                // box — darker than an empty day, which read as *less* there
                // rather than more.
                if art != nil {
                    LinearGradient(colors: [LSTheme.artScrim, .clear],
                                   startPoint: .top, endPoint: .center)
                }
            }
            .overlay {
                // A memory with no picture wears its own mark. Tim: *"these
                // memories/journal entries should have their own icon that's
                // not in a game art frame."*
                if art == nil, let kind = entries.first?.kind {
                    Image(systemName: kind.icon)
                        .font(.caption)
                        .foregroundStyle(LSTheme.accent)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(art == nil ? AnyShapeStyle(.secondary)
                                                : AnyShapeStyle(Color.white))
                    .padding(3)
            }
            .overlay(alignment: .bottomTrailing) {
                if entries.count > 1 {
                    Text("\(entries.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(art == nil ? AnyShapeStyle(.secondary)
                                                    : AnyShapeStyle(Color.white))
                        .padding(2)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(LSTheme.accent, lineWidth: 1.5)
                }
            }
    }

    private var number: some View {
        Text("\(calendar.component(.day, from: day))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
