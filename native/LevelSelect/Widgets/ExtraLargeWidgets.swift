import WidgetKit
import SwiftUI
import AppIntents

/// The three iPad-only extra-large widgets. All read the same snapshot the
/// smaller families do; the shelf and progress boards additionally use the
/// per-game fields the bridge started writing for them (statusRaw, done,
/// total, wins, losses — additive, so old snapshots still decode).
///
/// Density rule, learned from the mockup round: an extra-large widget earns
/// its slab by letting one subject fill it confidently, not by scattering a
/// phone widget's furniture across four times the area.

// MARK: - Command board

/// Continue Playing hero + interactive checklist on the left; shelf over the
/// week and the completion ring on the right. Every element already existed
/// in a smaller widget — this is the "whole gaming life at one glance" board.
struct CommandBoardView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let s = snapshot {
            HStack(spacing: 0) {
                left(s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Rectangle().fill(LSTheme.separator).frame(width: 1)
                    .padding(.vertical, 2)
                right(s)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16)
            }
        } else {
            EmptyWidget()
        }
    }

    private func left(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                CoverPoster(image: loadCover(s.coverFileName))
                    .frame(width: 84, height: 114)
                VStack(alignment: .leading, spacing: 3) {
                    StatusPill(snapshot: s)
                    Text(s.gameName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let last = s.lastPlayedAt {
                        Text("Last played \(last.formatted(.relative(presentation: .named))) · \(lsPlaytime(s.playtimeSeconds))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if s.completionTotal > 0 {
                        HStack(spacing: 7) {
                            ProgressView(value: Double(s.completionDone),
                                         total: Double(max(1, s.completionTotal)))
                                .tint(LSWidget.accent)
                            Text("\(s.completionDone)/\(s.completionTotal)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(s.objectives.prefix(5))) { item in
                    Button(intent: ToggleObjectiveIntent(gameID: s.gameID, itemID: item.id)) {
                        HStack(spacing: 10) {
                            Image(systemName: "circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Text(item.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 6)

            HStack(spacing: 10) {
                bigResume(s)
                Link(destination: WidgetShared.gameURL(s.gameID) ?? WidgetShared.homeURL!) {
                    Text("Open Game")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(LSTheme.cardFill, in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(.trailing, 16)
    }

    @ViewBuilder
    private func bigResume(_ s: WidgetSnapshot) -> some View {
        if s.isPlaying {
            HStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 12, weight: .bold))
                Text("Live").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(LSWidget.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(LSWidget.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
        } else {
            Button(intent: StartSessionIntent(gameID: s.gameID)) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                    Text(s.isPaused ? "Resume" : "Start Session")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(renderingMode == .fullColor ? LSWidget.accent : .white.opacity(0.24),
                            in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
    }

    private func right(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOW PLAYING")
                .font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Array(s.nowPlaying.filter { $0.statusRaw ?? "playing" == "playing" }.prefix(5))) { game in
                    Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                        CoverPoster(image: loadCover(game.coverFileName))
                            .aspectRatio(0.72, contentMode: .fit)
                    }
                }
            }
            .frame(maxHeight: 118)
            .padding(.top, 8)

            Spacer(minLength: 8)

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("THIS WEEK")
                        .font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(lsHours(s.weeklyTotalSeconds))
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(.primary)
                        if s.gamesPlayedThisWeek > 0 {
                            Text("· \(s.gamesPlayedThisWeek) game\(s.gamesPlayedThisWeek == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    weekBars(s)
                        .padding(.top, 6)
                }
                if s.completionTotal > 0 {
                    VStack(spacing: 3) {
                        RingView(progress: Double(s.completionDone) / Double(max(1, s.completionTotal)),
                                 lineWidth: 7)
                            .frame(width: 70, height: 70)
                            .overlay {
                                Text("\(Int((Double(s.completionDone) / Double(max(1, s.completionTotal)) * 100).rounded()))%")
                                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                                    .foregroundStyle(.primary)
                            }
                        Text(s.gameName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 78)
                    }
                }
            }
        }
    }

    private func weekBars(_ s: WidgetSnapshot) -> some View {
        let weekly = s.weeklySeconds
        let peak = max(weekly.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(weekly.enumerated()), id: \.offset) { idx, secs in
                RoundedRectangle(cornerRadius: 3)
                    .fill(idx == weekly.count - 1 ? LSWidget.accent : LSWidget.accent.opacity(0.45))
                    .frame(height: max(4, CGFloat(secs / peak) * 40))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

// MARK: - The shelf

/// Twelve covers, two rows, a status dot each — nothing else. Covers are the
/// content, so the slab can't have empty space.
struct ShelfXLView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        let games = Array((snapshot?.nowPlaying ?? []).prefix(12))
        if games.isEmpty {
            EmptyWidget()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("YOUR SHELF")
                        .font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    legend
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                          spacing: 10) {
                    ForEach(games) { game in
                        Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                            ZStack(alignment: .topTrailing) {
                                CoverPoster(image: loadCover(game.coverFileName))
                                    .aspectRatio(0.72, contentMode: .fit)
                                Circle()
                                    .fill(dotColor(game))
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1))
                                    .padding(5)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot(LSWidget.green, "playing")
            legendDot(LSWidget.torch, "paused")
            legendDot(LSWidget.purple, "up next")
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func dotColor(_ game: WidgetShelfGame) -> Color {
        switch game.statusRaw {
        case "paused": LSWidget.torch
        case "queued": LSWidget.purple
        default: LSWidget.green
        }
    }
}

// MARK: - Where you stand

/// One truthful bar per game: the tracker fraction when a tracker exists,
/// the run record when the game logs runs instead.
struct WhereYouStandView: View {
    let snapshot: WidgetSnapshot?

    private struct Row: Identifiable {
        let game: WidgetShelfGame
        var id: String { game.id }
    }

    var body: some View {
        let rows = (snapshot?.nowPlaying ?? [])
            .filter { ($0.total ?? 0) > 0 || (($0.wins ?? 0) + ($0.losses ?? 0)) > 0 }
            .prefix(6)
            .map { Row(game: $0) }
        if rows.isEmpty {
            EmptyWidget()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("WHERE YOU STAND")
                    .font(.system(size: 10, weight: .bold)).tracking(0.8)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())],
                          spacing: 12) {
                    ForEach(rows) { row in
                        Link(destination: WidgetShared.gameURL(row.game.id) ?? WidgetShared.homeURL!) {
                            cell(row.game)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func cell(_ game: WidgetShelfGame) -> some View {
        HStack(spacing: 11) {
            CoverPoster(image: loadCover(game.coverFileName))
                .frame(width: 37, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let done = game.done, let total = game.total, total > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(done), total: Double(max(1, total)))
                            .tint(LSWidget.accent)
                        Text("\(done)/\(total)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                } else if let wins = game.wins, let losses = game.losses {
                    let decided = wins + losses
                    HStack(spacing: 8) {
                        ProgressView(value: Double(wins), total: Double(max(1, decided)))
                            .tint(LSWidget.green)
                        Text(decided >= 3
                             ? "\(wins)W \(losses)L · \(Int((Double(wins) / Double(decided) * 100).rounded()))%"
                             : "\(wins)W \(losses)L")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }
            }
        }
    }
}

// MARK: - Widget configurations

struct CommandBoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CommandBoard", provider: ContinuePlayingProvider()) { entry in
            CommandBoardView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Command Board")
        .description("Your current game with its next objectives, the shelf, the week, and the ring — one glance.")
        .supportedFamilies([.systemExtraLarge])
    }
}

struct ShelfXLWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShelfXL", provider: ContinuePlayingProvider()) { entry in
            ShelfXLView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Your Shelf")
        .description("Twelve covers from your shelf — playing, paused, and up next. Tap any cover to open its game.")
        .supportedFamilies([.systemExtraLarge])
    }
}

struct WhereYouStandWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WhereYouStand", provider: ContinuePlayingProvider()) { entry in
            WhereYouStandView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Where You Stand")
        .description("A progress bar for every game you're playing — tracker fractions, or the win record for roguelikes.")
        .supportedFamilies([.systemExtraLarge])
    }
}
