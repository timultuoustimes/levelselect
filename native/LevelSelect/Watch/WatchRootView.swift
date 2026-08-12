import SwiftUI
import SwiftData

private let watchAccent = Color(red: 0.58, green: 0.36, blue: 0.98)

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

    var body: some View {
        NavigationStack {
            List {
                if let cp = continueGame {
                    Section("Continue") {
                        NavigationLink {
                            WatchGameView(game: cp)
                        } label: {
                            WatchGameRow(game: cp, prominent: true)
                        }
                    }
                }
                if !nowPlaying.isEmpty {
                    Section("Playing") {
                        ForEach(nowPlaying) { game in
                            NavigationLink {
                                WatchGameView(game: game)
                            } label: {
                                WatchGameRow(game: game)
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
        .tint(watchAccent)
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
    var prominent = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(game.status == .playing ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.name)
                    .font(prominent ? .headline : .body)
                    .lineLimit(2)
                if game.activePlaythrough?.activeSession != nil {
                    Text(game.activePlaythrough?.activeSession?.state == .running ? "In session" : "Paused")
                        .font(.caption2)
                        .foregroundStyle(game.activePlaythrough?.activeSession?.state == .running ? .green : .orange)
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
                            .foregroundStyle(active.state == .running ? watchAccent : .primary)
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
                        .tint(watchAccent)
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
                    .tint(.green)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Session")
    }

    private func save() { try? context.save() }
}
