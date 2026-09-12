import SwiftUI
import SwiftData

/// The theme, on the wrist.
///
/// The watch used to hold a single `Color(red: 0.58, green: 0.36, blue: 0.98)`
/// — a purple that stopped being the app's default two builds before this, so
/// the watch tinted itself a color that existed nowhere else in the product
/// (Codex K2). And status colors never reached it at all: a Paused game showed
/// a fixed orange dot however the user had recolored Paused (A4).
///
/// Both are fixed the same way, and the fix is not a copy of the phone's
/// palette — the watch runs the same `Repository` against the same SwiftData
/// store, so `ThemeSettings` is simply *there* to be read. `ThemePalette`
/// itself is not: it lives in the app target's UI layer, which the watch does
/// not build. So this is the small part of it the watch actually needs.
private enum WatchTheme {
    static let fallbackAccent = Color(red: 0.96, green: 0.64, blue: 0.30)

    /// The watch is always dark, so it reads the dark side of the palette.
    /// Asking for the light accent here would hand back a color chosen to sit
    /// on white.
    static func accent(_ settings: ThemeSettings?) -> Color {
        settings?.accentHex(dark: true).flatMap { Color(hex: $0) } ?? fallbackAccent
    }

    /// Defaults match `ThemePalette.defaultColor(for:)` for the two statuses
    /// the watch can show. They are duplicated rather than shared because the
    /// watch does not build the file they live in — if a default changes there
    /// and not here, the dot is wrong, so keep them together.
    static func color(_ status: GameStatus, _ settings: ThemeSettings?) -> Color {
        if let hex = settings?.statusColors[status.rawValue], let color = Color(hex: hex) {
            return color
        }
        switch status {
        case .playing: return .green
        case .paused:  return .orange
        default:       return .secondary
        }
    }
}

enum WFormat {
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t)); let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}

/// Watch home: jump into your current game, or pick from what you're playing.
struct WatchRootView: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]
    /// Oldest wins, the same rule the phone uses to settle a sync race that
    /// left two settings records behind.
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    private var settings: ThemeSettings? { themeSettings.first }

    var body: some View {
        NavigationStack {
            List {
                if let cp = continueGame {
                    Section("Continue") {
                        NavigationLink {
                            WatchGameView(game: cp)
                        } label: {
                            WatchGameRow(game: cp, settings: settings, prominent: true)
                        }
                    }
                }
                if !nowPlaying.isEmpty {
                    Section("Playing") {
                        ForEach(nowPlaying) { game in
                            NavigationLink {
                                WatchGameView(game: game)
                            } label: {
                                WatchGameRow(game: game, settings: settings)
                            }
                        }
                    }
                }
                if nowPlaying.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "gamecontroller")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text(games.isEmpty ? "No games" : "Nothing in progress")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("LevelSelect")
        }
        .tint(WatchTheme.accent(settings))
    }

    private var nowPlaying: [Game] {
        games.filter { $0.status == .playing || $0.status == .paused }
            .sorted { key($0) > key($1) }
    }

    private var continueGame: Game? {
        nowPlaying.max { key($0) < key($1) }
    }

    private func key(_ g: Game) -> Date {
        g.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? g.addedAt
    }
}

private struct WatchGameRow: View {
    let game: Game
    let settings: ThemeSettings?
    var prominent = false

    private var statusColor: Color { WatchTheme.color(game.status, settings) }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.name)
                    .font(prominent ? .headline : .body)
                    .lineLimit(2)
                if game.activePlaythrough?.activeSession != nil {
                    let running = game.activePlaythrough?.activeSession?.state == .running
                    Text(running ? "In session" : "Paused")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.color(running ? .playing : .paused, settings))
                }
            }
        }
    }
}

/// A game's session controls on the watch — start / pause / resume / stop, with
/// a live timer. Same Repository + store as the phone, so it all syncs.
struct WatchGameView: View {
    let game: Game
    @Environment(\.modelContext) private var context
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
    private var accent: Color { WatchTheme.accent(themeSettings.first) }
    private var repo: Repository { Repository(context) }
    private var playthrough: Playthrough? { game.activePlaythrough }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(game.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                if let active = playthrough?.activeSession {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(WFormat.clock(active.elapsed(asOf: ctx.date)))
                            .font(.system(.title2, design: .rounded).monospacedDigit())
                            .foregroundStyle(active.state == .running ? accent : .primary)
                    }
                    HStack(spacing: 10) {
                        Button {
                            if active.state == .running { repo.pauseSession(active) }
                            else { repo.resumeSession(active) }
                            save()
                        } label: {
                            Image(systemName: active.state == .running ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(accent)
                        Button(role: .destructive) {
                            repo.stopSession(active); save()
                        } label: {
                            Image(systemName: "stop.fill").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text(WFormat.duration(playthrough?.totalPlaytime() ?? 0) + " played")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        let pt = repo.ensureDefaultPlaythrough(for: game)
                        repo.startSession(on: pt)
                        save()
                    } label: {
                        Label("Start Session", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    // Green because it starts a session and the game becomes
                    // Playing — so it follows the Playing color, not a literal.
                    .tint(WatchTheme.color(.playing, themeSettings.first))
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Session")
    }

    private func save() { PersistenceMonitor.shared.commit(context) }
}
