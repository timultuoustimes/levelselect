import SwiftUI
import SwiftData

/// A year of play at a glance, and a month of it in pictures.
///
/// **Two zooms, because they answer different questions.** A year says *when
/// was I playing* — that is a shape, and heat draws it. A month says *what did
/// I play*, which is the cover art. Cover art at year scale is twelve hundred
/// illegible specks, and heat at month scale throws away the thing worth
/// looking at, so neither view tries to be the other.
///
/// **Why a year is the home and not an endless scroll.** The first version
/// stacked every month newest-first and scrolled forever. That is fine for the
/// months you played this spring and useless for the thing this feature is
/// actually for: Tim, on thirty years of history — *"the current view is an
/// insanely long scroll."* Thirty years is 360 screens of month grid and one
/// screen of year strip.
struct JournalCalendarView: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]
    @Query(filter: #Predicate<Memory> { $0.deletedAt == nil && $0.game == nil })
    private var standaloneMemories: [Memory]

    /// nil until someone picks; the current year until then.
    @State private var year: Int?

    private var calendar: Calendar { JournalBuilder.calendar }
    private var shownYear: Int { year ?? calendar.component(.year, from: .now) }

    var body: some View {
        let periods = JournalBuilder.periods(from: games, standalone: standaloneMemories)
        let load = Self.load(from: periods, calendar: calendar)
        let populated = Set(load.keys.map { calendar.component(.year, from: $0) })
        let undated = periods.filter { $0.grain != .day }
        // **Normalised within the year on show, not across the whole library.**
        // A quiet year beside a heavy one would otherwise render as blank —
        // the calendar reporting "nothing happened" about a year that simply
        // had less in it than 2019.
        let peak = load
            .filter { calendar.component(.year, from: $0.key) == shownYear }
            .values.map(\.seconds).max() ?? 0

        VStack(spacing: 0) {
            YearStrip(years: years(earliest: populated.min()),
                      selected: shownYear,
                      populated: populated,
                      onSelect: { year = $0 })

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    YearGrid(year: shownYear, calendar: calendar, load: load, peak: peak)

                    if !undated.isEmpty {
                        undatedSection(undated)
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The entries a grid cannot hold.
    ///
    /// "Christmas 1995 or 1996" has no square, and dropping it would be the
    /// calendar quietly editing someone's history. Kept below the year the way
    /// the release calendar keeps its "no date yet" group rather than
    /// pretending it is empty.
    private func undatedSection(_ undated: [JournalPeriod]) -> some View {
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
    }

    /// Every year worth offering, oldest first.
    ///
    /// **Deliberately reaches back further than the data does.** A library with
    /// nothing older than this year would otherwise offer only this year — and
    /// the first thing someone wants to write down is the Christmas they got a
    /// Genesis, which is exactly the year the strip would not contain. 1970 is
    /// the floor `MemorySheet`'s year stepper already uses, reused rather than
    /// a second arbitrary date invented beside it.
    private func years(earliest: Int?) -> [Int] {
        let now = calendar.component(.year, from: .now)
        let start = min(earliest ?? now, 1970)
        return Array(start...max(start, now))
    }

    /// How much each day carries, keyed by the square it belongs in.
    ///
    /// Static and calendar-injected so the shape can be tested without a view.
    static func load(from periods: [JournalPeriod],
                     calendar: Calendar) -> [Date: DayLoad] {
        var result: [Date: DayLoad] = [:]
        for period in periods where period.grain == .day {
            let key = JournalBuilder.square(for: period.start,
                                            in: period.calendar,
                                            grid: calendar)
            for entry in period.entries {
                result[key, default: DayLoad()].seconds += entry.duration
                result[key, default: DayLoad()].entries += 1
            }
        }
        return result
    }
}

/// What one day is worth to the heatmap.
struct DayLoad: Equatable {
    var seconds: TimeInterval = 0
    /// Kept separately because **a day can matter with no hours on it.** A
    /// memory has no duration, and a day that holds one is not an empty day.
    var entries: Int = 0
}

/// The years, as a row you can scrub.
private struct YearStrip: View {
    let years: [Int]
    let selected: Int
    let populated: Set<Int>
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(years, id: \.self) { year in
                        Button { onSelect(year) } label: { chip(year) }
                            .buttonStyle(.plain)
                            .id(year)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    /// An empty year is dimmed but never disabled.
    ///
    /// Tim: *"something to signify what years do/don't have anything in them,
    /// but still letting me click into the year to view it and tap to add
    /// things."* A year with nothing in it is precisely the year you are about
    /// to put something in, so it stays reachable — the same mistake the
    /// greyed-out memory row made by looking unavailable when it was not.
    private func chip(_ year: Int) -> some View {
        let has = populated.contains(year)
        let isSelected = year == selected
        return Text(verbatim: String(year))
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? AnyShapeStyle(LSTheme.onAccent)
                             : has ? AnyShapeStyle(.primary)
                                   : AnyShapeStyle(.tertiary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule().fill(LSTheme.accent)
                } else if has {
                    Capsule().fill(LSTheme.cardFill)
                }
            }
    }
}

/// Twelve months of one year, as heat.
private struct YearGrid: View {
    let year: Int
    let calendar: Calendar
    let load: [Date: DayLoad]
    let peak: TimeInterval

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(months, id: \.self) { month in
                MiniMonth(month: month, calendar: calendar, load: load, peak: peak)
            }
        }
    }

    private var months: [Date] {
        (1...12).compactMap {
            calendar.date(from: DateComponents(year: year, month: $0, day: 1))
        }
    }
}

private struct MiniMonth: View {
    let month: Date
    let calendar: Calendar
    let load: [Date: DayLoad]
    let peak: TimeInterval

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 7)

    var body: some View {
        NavigationLink(value: CalendarMonth(start: month)) {
            VStack(alignment: .leading, spacing: 5) {
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption.weight(.semibold))
                // **Always six rows, even when the month needs five.** A grid
                // sized to its own weeks makes neighbouring months different
                // heights, which the enclosing LazyVGrid then centres — the
                // middle column visibly sagging below the outer two. It also
                // stops the whole year twitching as you scrub between them.
                LazyVGrid(columns: columns, spacing: 1.5) {
                    ForEach(0..<leadingBlanks, id: \.self) { index in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .id("lead\(index)")
                    }
                    ForEach(days, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(fill(for: day))
                            .aspectRatio(1, contentMode: .fit)
                    }
                    ForEach(0..<trailingBlanks, id: \.self) { index in
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .id("trail\(index)")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Accent at a strength, rather than a second colour ramp.
    ///
    /// The app is themeable, so a fixed green-to-red heat scale would be the
    /// one part of the calendar that ignored the colour you picked. Opacity on
    /// the accent keeps the ramp readable on both grounds for free.
    private func fill(for day: Date) -> Color {
        guard let entry = load[day] else { return LSTheme.cardFill }
        guard peak > 0, entry.seconds > 0 else {
            // A day carried by a memory alone. Visible, and deliberately not
            // scaled — nothing about it is a quantity.
            return LSTheme.accent.opacity(0.45)
        }
        return LSTheme.accent.opacity(0.3 + 0.7 * (entry.seconds / peak))
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
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }

    /// Whatever it takes to reach six full weeks.
    private var trailingBlanks: Int {
        max(0, 42 - leadingBlanks - days.count)
    }
}

/// One month, pushed from the year view.
struct CalendarMonth: Hashable {
    let start: Date
}

/// A month in pictures — the view the year zooms into.
struct CalendarMonthView: View {
    let month: Date

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

        ScrollView {
            MonthGrid(month: month,
                      calendar: calendar,
                      periods: byDay,
                      onCreate: { creatingOn = CreationDay(date: JournalBuilder.memoryDate(for: $0)) })
                .padding()
        }
        .scrollIndicators(.hidden)
        .lsBackground()
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $creatingOn) { day in
            MemorySheet(initialDate: day.date)
        }
    }
}

/// `sheet(item:)` wants an Identifiable, and a Date is not one.
///
/// A wrapper rather than a retroactive `Date: Identifiable` conformance:
/// extending a Foundation type for one sheet leaks into every file in the
/// module and is exactly the kind of thing another target later trips over.
struct CreationDay: Identifiable {
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
