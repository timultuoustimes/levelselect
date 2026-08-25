import SwiftUI
import SwiftData

/// Stats tab: actionable summaries — totals, recent playtime, ratings,
/// status breakdown, month-by-month, a play-streak heatmap, most played,
/// and the library sliced by platform, genre, series, tag and release year.
///
/// The slice cards are navigation as much as statistics: genre, series, tag
/// and year rows push the same facet screens the game page uses, per the
/// parity doc's note that a bar you can't tap is a question the app refuses
/// to answer. Everything here is grouping over existing fields — the stats
/// expansion held out of the beta on 08-15 and un-held 2026-08-25.
/// One entry per Stats card, in default order. The page renders whatever
/// order (and subset) the user chose; new cards added in later builds append
/// at their default position via `resolveOrder`, so a stored preference from
/// an older build never hides a card it had no way to know about.
enum StatsCard: String, CaseIterable, Identifiable {
    case overview, recent, ratings, library, monthly, streak
    case mostPlayed, systems, genres, series, tags, years, completions

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .overview:    "Overview"
        case .recent:      "Recent Play"
        case .ratings:     "Ratings"
        case .library:     "Library"
        case .monthly:     "By Month"
        case .streak:      "Streak"
        case .mostPlayed:  "Most Played"
        case .systems:     "By System"
        case .genres:      "Genres"
        case .series:      "Series"
        case .tags:        "Tags"
        case .years:       "By Release Year"
        case .completions: "Completions"
        }
    }

    /// Stored order (comma-joined raw values) → full render order. Unknown
    /// tokens are dropped; cards absent from the stored order slot back in at
    /// their default position relative to the ones around them.
    static func resolveOrder(stored: String) -> [StatsCard] {
        let chosen = stored.split(separator: ",").compactMap { StatsCard(rawValue: String($0)) }
        guard !chosen.isEmpty else { return Array(allCases) }
        var result = chosen
        for (index, card) in allCases.enumerated() where !result.contains(card) {
            // Insert after the nearest already-placed predecessor.
            let predecessors = allCases.prefix(index).reversed()
            if let anchor = predecessors.first(where: { result.contains($0) }),
               let at = result.firstIndex(of: anchor) {
                result.insert(card, at: at + 1)
            } else {
                result.insert(card, at: 0)
            }
        }
        return result
    }
}

struct StatsTab: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    /// Which decades are open in the By Release Year card.
    @State private var expandedDecades: Set<Int> = []

    /// Card order and hidden set — device-local like the Home shelves, and
    /// for the same reason: how you read stats on the phone in your pocket
    /// isn't obviously the same answer as on the iPad on the desk.
    @AppStorage("statsCardOrder") private var cardOrderRaw = ""
    @AppStorage("statsHiddenCards") private var hiddenCardsRaw = ""
    @State private var arranging = false

    private var cardOrder: [StatsCard] { StatsCard.resolveOrder(stored: cardOrderRaw) }
    private var hiddenCards: Set<StatsCard> {
        Set(hiddenCardsRaw.split(separator: ",").compactMap { StatsCard(rawValue: String($0)) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Each computed once per body pass. As properties they
                    // were re-derived on every reference — allSessions
                    // re-flattened the whole library three times and topPlayed
                    // re-sorted it three times per render.
                    let sessions = allSessions
                    let top = topPlayed
                    let visible = cardOrder.filter { !hiddenCards.contains($0) }
                    ForEach(visible) { card in
                        switch card {
                        case .overview:    overviewCard(sessions: sessions)
                        case .recent:      recentCard(sessions: sessions)
                        case .ratings:     if ratedCount > 0 { ratingsCard }
                        case .library:     statusBreakdownCard
                        case .monthly:     monthlyCard(sessions: sessions)
                        case .streak:      heatmapCard(sessions: sessions)
                        case .mostPlayed:  if !top.isEmpty { topPlayedCard(top) }
                        case .systems:     platformsCard
                        case .genres:      sliceCard("Genres", icon: "theatermasks.fill", rows: topCounts(\.genres, limit: 8), kind: .genre)
                        case .series:      franchisesCard
                        case .tags:        sliceCard("Tags", icon: "tag.fill", rows: topCounts(\.userTags, limit: 12), kind: .tag)
                        case .years:       releaseYearsCard
                        case .completions: if !completionsByYear.isEmpty { completionsCard }
                        }
                    }
                    if visible.isEmpty {
                        ContentUnavailableView("All cards hidden",
                                               systemImage: "rectangle.dashed",
                                               description: Text("Bring some back from Arrange."))
                    }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            .lsBackground()
            .navigationTitle("Stats")
            .toolbar {
                Button {
                    arranging = true
                } label: {
                    Label("Arrange", systemImage: "slider.horizontal.3")
                }
            }
            .sheet(isPresented: $arranging) {
                StatsArrangeSheet(orderRaw: $cardOrderRaw, hiddenRaw: $hiddenCardsRaw)
            }
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameFacet.self) { FacetGamesView(facet: $0) }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
        }
    }

    // MARK: Cards

    private func overviewCard(sessions: [Session]) -> some View {
        HStack(spacing: 0) {
            stat(number: "\(games.count)", label: "Games")
            divider
            stat(number: Format.duration(sessions.reduce(0) { $0 + $1.elapsed() }), label: "Played")
            divider
            stat(number: "\(sessions.count)", label: "Sessions")
            divider
            // Completed share of the library — the web's headline number.
            stat(number: "\(Int((completionRate * 100).rounded()))%", label: "Finished")
        }
        .frame(maxWidth: .infinity)
        .lsCard()
    }

    private func recentCard(sessions: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Play", systemImage: "clock.fill")
                .font(.headline)
            HStack(spacing: 0) {
                stat(number: Format.duration(playtime(in: sessions, since: startOfWeek)), label: "This week")
                divider
                stat(number: Format.duration(playtime(in: sessions, since: startOfMonth)), label: "This month")
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private var statusBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Library", systemImage: "books.vertical.fill")
                .font(.headline)
            ForEach(GameStatus.displayOrder, id: \.self) { status in
                let count = statusCounts[status] ?? 0
                if count > 0 {
                    HStack(spacing: 10) {
                        Image(systemName: status.systemImage)
                            .foregroundStyle(status.color)
                            .frame(width: 22)
                        Text(status.sectionTitle)
                            .font(.subheadline)
                        Spacer()
                        Text("\(count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    bar(fraction: Double(count) / Double(max(games.count, 1)), color: status.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private func topPlayedCard(_ top: [(Game, TimeInterval)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Most Played", systemImage: "trophy.fill")
                .font(.headline)
            let maxTime = top.first?.1 ?? 1
            ForEach(top, id: \.0.id) { game, time in
                NavigationLink(value: game) {
                    HStack(spacing: 10) {
                        CoverThumb(urlString: game.coverURLString)
                            .frame(width: 30, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.name).font(.subheadline)
                            bar(fraction: time / maxTime, color: LSTheme.accent)
                        }
                        Spacer()
                        Text(Format.duration(time))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    private var completionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Completions", systemImage: "checkmark.seal.fill")
                .font(.headline)
            ForEach(completionsByYear, id: \.0) { year, count in
                HStack {
                    Text(String(year)).font(.subheadline)
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    /// Average with its denominator beside it — most libraries rate a
    /// minority of their games, and "4.8" over three ratings would read as a
    /// library of masterpieces. The distribution answers whether the average
    /// means anything.
    private var ratingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ratings", systemImage: "star.fill")
                .font(.headline)
            HStack(spacing: 6) {
                Text(String(format: "%.1f", averageRating))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(LSTheme.accent)
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(LSTheme.accent)
                Text("· \(ratedCount) of \(games.count) rated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let dist = ratingDistribution
            let maxCount = dist.map(\.1).max() ?? 1
            ForEach(dist, id: \.0) { stars, count in
                HStack(spacing: 10) {
                    Text("\(stars)★")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                    bar(fraction: Double(count) / Double(max(maxCount, 1)), color: LSTheme.accent)
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    /// Hours and finishes for the last six months, oldest first so the eye
    /// reads toward now.
    private func monthlyCard(sessions: [Session]) -> some View {
        let months = lastMonths(6)
        let byMonth = monthlyRollup(sessions: sessions, months: months)
        let maxSeconds = byMonth.map(\.seconds).max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Label("By Month", systemImage: "calendar")
                .font(.headline)
            ForEach(byMonth, id: \.label) { row in
                HStack(spacing: 10) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    bar(fraction: row.seconds / max(maxSeconds, 1), color: LSTheme.accent)
                    Text(row.seconds > 0 ? Format.duration(row.seconds) : "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                    Text(row.completions > 0 ? "✓\(row.completions)" : " ")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.green)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    /// Fifteen weeks of days, GitHub-shaped: columns are weeks, rows are
    /// weekdays, intensity is minutes played. The one card that shows the
    /// *habit* rather than the totals.
    private func heatmapCard(sessions: [Session]) -> some View {
        let cells = heatmapCells(sessions: sessions, weeks: 15)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Streak", systemImage: "flame.fill")
                .font(.headline)
            HStack(alignment: .top, spacing: 3) {
                ForEach(cells, id: \.first?.day) { week in
                    VStack(spacing: 3) {
                        ForEach(week, id: \.day) { cell in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(heatColor(cell.minutes))
                                .frame(width: 13, height: 13)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 6) {
                Text("Less").font(.caption2).foregroundStyle(.tertiary)
                ForEach([0.0, 20, 60, 120], id: \.self) { m in
                    RoundedRectangle(cornerRadius: 2).fill(heatColor(m)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    /// Games per system, the way the library groups them — by the platform
    /// you recorded, normalised to its preferred name.
    private var platformsCard: some View {
        let rows = platformCounts
        let maxCount = rows.first?.1 ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Label("By System", systemImage: "gamecontroller.fill")
                .font(.headline)
            ForEach(rows.prefix(8), id: \.0) { name, count in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.subheadline)
                        bar(fraction: Double(count) / Double(max(maxCount, 1)), color: LSTheme.accent)
                    }
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lsCard()
    }

    /// A counted slice of the library where every row is a door — tapping a
    /// genre or tag opens the same facet screen the game page uses.
    private func sliceCard(_ title: String, icon: String,
                           rows: [(String, Int)], kind: GameFacet.Kind) -> some View {
        Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: icon)
                        .font(.headline)
                    FlowCountRows(rows: rows, kind: kind)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lsCard()
            }
        }
    }

    private var franchisesCard: some View {
        let rows = franchiseCounts
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Series", systemImage: "square.stack.3d.up.fill")
                        .font(.headline)
                    ForEach(rows.prefix(10), id: \.0) { name, count in
                        NavigationLink(value: GameFacet(kind: .franchise, value: name)) {
                            HStack {
                                Text(name).font(.subheadline)
                                Spacer()
                                Text("\(count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lsCard()
            }
        }
    }

    /// Decades by default, years on demand. A forty-year library made the
    /// by-year list the longest card on the page; a decade row summarises it
    /// and expands in place to the same tappable year facets as before.
    private var releaseYearsCard: some View {
        let decades = releaseDecadeGroups
        let maxDecade = decades.map(\.total).max() ?? 1
        return Group {
            if releaseYearCounts.count >= 3 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("By Release Year", systemImage: "calendar.badge.clock")
                        .font(.headline)
                    ForEach(decades, id: \.decade) { group in
                        let expanded = expandedDecades.contains(group.decade)
                        Button {
                            withAnimation(.snappy) {
                                if expanded { expandedDecades.remove(group.decade) }
                                else { expandedDecades.insert(group.decade) }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(String(group.decade))s")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, alignment: .leading)
                                bar(fraction: Double(group.total) / Double(max(maxDecade, 1)), color: LSTheme.accent)
                                Text("\(group.total)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 26, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(expanded ? 90 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        if expanded {
                            let maxYear = group.years.map(\.1).max() ?? 1
                            ForEach(group.years, id: \.0) { year, count in
                                NavigationLink(value: GameFacet(kind: .year, value: String(year))) {
                                    HStack(spacing: 10) {
                                        Text(String(year))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 44, alignment: .trailing)
                                        bar(fraction: Double(count) / Double(max(maxYear, 1)), color: LSTheme.accent.opacity(0.7))
                                        Text("\(count)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 26, alignment: .trailing)
                                        Spacer().frame(width: 13)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 10)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .lsCard()
            }
        }
    }

    private struct DecadeGroup {
        let decade: Int
        let total: Int
        let years: [(Int, Int)]
    }

    private var releaseDecadeGroups: [DecadeGroup] {
        let byDecade = Dictionary(grouping: releaseYearCounts) { ($0.0 / 10) * 10 }
        return byDecade
            .map { DecadeGroup(decade: $0.key,
                               total: $0.value.reduce(0) { $0 + $1.1 },
                               years: $0.value.sorted { $0.0 > $1.0 }) }
            .sorted { $0.decade > $1.decade }
    }

    // MARK: Pieces

    private func stat(number: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(number)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(LSTheme.accent)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 34)
    }

    private func bar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.06))
                Capsule()
                    .fill(LinearGradient(colors: [color, color.opacity(0.55)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
    }

    // MARK: Derived data

    private var allSessions: [Session] {
        games
            .flatMap { $0.livePlaythroughs.flatMap { $0.sessions ?? [] } }
            .filter { $0.deletedAt == nil }
    }

    private func playtime(in sessions: [Session], since date: Date) -> TimeInterval {
        sessions.filter { $0.startDate >= date }.reduce(0) { $0 + $1.elapsed() }
    }

    private var startOfWeek: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    private var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    }

    private var statusCounts: [GameStatus: Int] {
        Dictionary(grouping: games, by: \.status).mapValues(\.count)
    }

    private var topPlayed: [(Game, TimeInterval)] {
        games
            .map { g in (g, g.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() }) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }

    private var completionRate: Double {
        guard !games.isEmpty else { return 0 }
        return Double(games.filter { $0.status == .completed }.count) / Double(games.count)
    }

    private var ratedCount: Int { games.filter { ($0.rating ?? 0) > 0 }.count }

    private var averageRating: Double {
        let ratings = games.compactMap(\.rating).filter { $0 > 0 }
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    /// 5★ first — the shelf people want to see is the top one.
    private var ratingDistribution: [(Int, Int)] {
        let counts = Dictionary(grouping: games.compactMap(\.rating).filter { $0 > 0 }) { $0 }
            .mapValues(\.count)
        return (1...5).reversed().map { ($0, counts[$0] ?? 0) }
    }

    private struct MonthRow { let label: String; let seconds: TimeInterval; let completions: Int }

    private func lastMonths(_ n: Int) -> [Date] {
        let cal = Calendar.current
        let thisMonth = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        return (0..<n).reversed().compactMap { cal.date(byAdding: .month, value: -$0, to: thisMonth) }
    }

    private func monthlyRollup(sessions: [Session], months: [Date]) -> [MonthRow] {
        let cal = Calendar.current
        let events = games.flatMap { $0.completionEvents ?? [] }
        let fmt = Date.FormatStyle().month(.abbreviated)
        return months.map { start in
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
            let seconds = sessions
                .filter { $0.startDate >= start && $0.startDate < end }
                .reduce(0) { $0 + $1.elapsed() }
            let done = events.filter { $0.date >= start && $0.date < end }.count
            return MonthRow(label: start.formatted(fmt), seconds: seconds, completions: done)
        }
    }

    private struct DayCell: Hashable { let day: Date; let minutes: Double }

    /// Columns of weekday cells, oldest week first, today in the last column.
    private func heatmapCells(sessions: [Session], weeks: Int) -> [[DayCell]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var minutesByDay: [Date: Double] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: s.startDate)
            minutesByDay[day, default: 0] += s.elapsed() / 60
        }
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return (0..<weeks).reversed().map { back in
            let weekStart = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) ?? thisWeek
            return (0..<7).compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: offset, to: weekStart),
                      day <= today else { return nil }
                return DayCell(day: day, minutes: minutesByDay[day] ?? 0)
            }
        }
    }

    private func heatColor(_ minutes: Double) -> Color {
        switch minutes {
        case ..<1:    Color.white.opacity(0.06)
        case ..<20:   LSTheme.accent.opacity(0.30)
        case ..<60:   LSTheme.accent.opacity(0.55)
        case ..<120:  LSTheme.accent.opacity(0.80)
        default:      LSTheme.accent
        }
    }

    /// Counted like the library groups: one preferred platform per game.
    private var platformCounts: [(String, Int)] {
        let names = games.map { PlatformShort.name(PlatformPreference.owned($0.platforms) ?? "Other") }
        return Dictionary(grouping: names) { $0 }.mapValues(\.count)
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
    }

    private func topCounts(_ keyPath: KeyPath<Game, [String]>, limit: Int) -> [(String, Int)] {
        Dictionary(grouping: games.flatMap { $0[keyPath: keyPath] }) { $0 }
            .mapValues(\.count)
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit).map { ($0.key, $0.value) }
    }

    /// A series of one is just a game; two is where a shelf begins.
    private var franchiseCounts: [(String, Int)] {
        Dictionary(grouping: games.compactMap(\.franchise)) { $0 }
            .mapValues(\.count)
            .filter { $0.value >= 2 }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { ($0.key, $0.value) }
    }

    private var releaseYearCounts: [(Int, Int)] {
        let years = games.compactMap { g -> Int? in
            // CSV-era imports stored missing release dates as timestamp zero,
            // which renders as 1969 and once put a 119-game bar on this card.
            // The test for that lives with the pass that fixes it, so a game
            // hidden from this chart is exactly a game "Fill in missing game
            // info" will try to repair.
            guard let date = g.firstReleaseDate,
                  !MetadataRefresh.isMissing(date) else { return nil }
            return Calendar.current.component(.year, from: date)
        }
        return Dictionary(grouping: years) { $0 }.mapValues(\.count)
            .sorted { $0.key > $1.key }
    }

    private var completionsByYear: [(Int, Int)] {
        let events = games.flatMap { $0.completionEvents ?? [] }
        let byYear = Dictionary(grouping: events) { Calendar.current.component(.year, from: $0.date) }
        return byYear.mapValues(\.count).sorted { $0.key > $1.key }
    }
}


// MARK: - Chip flow

/// Wrapping chips for the genre and tag slices — twenty list rows of "Indie
/// · 12" would double the page for its least-read cards. Each chip pushes
/// the matching facet screen.
private struct FlowCountRows: View {
    let rows: [(String, Int)]
    let kind: GameFacet.Kind

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(rows, id: \.0) { name, count in
                NavigationLink(value: GameFacet(kind: kind, value: name)) {
                    HStack(spacing: 5) {
                        Text(name).font(.caption)
                        Text("\(count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.07)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}



// MARK: - Arrange

/// Reorder and hide the Stats cards. Drag to reorder, switch to show or
/// hide; the page re-renders live behind the sheet. "Reset" clears both
/// preferences rather than writing a copy of the defaults, so a future
/// build's new cards appear for reset users exactly as they do for fresh
/// installs.
struct StatsArrangeSheet: View {
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss

    private var order: [StatsCard] { StatsCard.resolveOrder(stored: orderRaw) }
    private var hidden: Set<StatsCard> {
        Set(hiddenRaw.split(separator: ",").compactMap { StatsCard(rawValue: String($0)) })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(order) { card in
                    HStack {
                        Toggle(isOn: visibilityBinding(card)) {
                            Text(card.displayName)
                        }
                        .tint(LSTheme.accent)
                    }
                }
                .onMove { from, to in
                    var cards = order
                    cards.move(fromOffsets: from, toOffset: to)
                    orderRaw = cards.map(\.rawValue).joined(separator: ",")
                }
            }
            #if !os(macOS)
            // Keep the drag handles visible without an Edit button; macOS
            // has no editMode and reorders List rows natively.
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle("Arrange Stats")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        orderRaw = ""
                        hiddenRaw = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func visibilityBinding(_ card: StatsCard) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(card) },
            set: { visible in
                var set = hidden
                if visible { set.remove(card) } else { set.insert(card) }
                // Preserve canonical order in storage so the raw string is
                // stable and diffable rather than insertion-ordered.
                hiddenRaw = StatsCard.allCases.filter(set.contains)
                    .map(\.rawValue).joined(separator: ",")
            })
    }
}
