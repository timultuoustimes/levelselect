import SwiftUI
import SwiftData

/// Stats tab: actionable summaries (per the feature audit) — totals, recent
/// playtime, status breakdown, most-played leaderboard, completions by year.
struct StatsTab: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

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
                    overviewCard(sessions: sessions)
                    recentCard(sessions: sessions)
                    statusBreakdownCard
                    if !top.isEmpty { topPlayedCard(top) }
                    if !completionsByYear.isEmpty { completionsCard }
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            .lsBackground()
            .navigationTitle("Stats")
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

    private var completionsByYear: [(Int, Int)] {
        let events = games.flatMap { $0.completionEvents ?? [] }
        let byYear = Dictionary(grouping: events) { Calendar.current.component(.year, from: $0.date) }
        return byYear.mapValues(\.count).sorted { $0.key > $1.key }
    }
}
