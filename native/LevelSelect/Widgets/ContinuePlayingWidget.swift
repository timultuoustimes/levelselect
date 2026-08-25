import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Palette (mirrors the app theme; the widget process can't read it)

enum LSWidget {
    static let torch = Color(red: 0.96, green: 0.64, blue: 0.30)
    static let purple = Color(red: 0.58, green: 0.36, blue: 0.98)
    static let navy = Color(red: 0.094, green: 0.075, blue: 0.176)
    static let navyDeep = Color(red: 0.043, green: 0.031, blue: 0.098)
    static let green = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let red = Color(red: 0.88, green: 0.33, blue: 0.25)
}

// MARK: - Timeline

struct ContinuePlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ContinuePlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinuePlayingEntry {
        ContinuePlayingEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinuePlayingEntry) -> Void) {
        completion(ContinuePlayingEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinuePlayingEntry>) -> Void) {
        let entry = ContinuePlayingEntry(date: .now, snapshot: WidgetSnapshot.load())
        // Refresh hourly as a backstop; the app pushes reloads on real changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Shared helpers

private func coverImage(_ snapshot: WidgetSnapshot) -> Image? {
    guard let url = snapshot.coverImageURL(),
          let data = try? Data(contentsOf: url),
          let ui = UIImage(data: data) else { return nil }
    return Image(uiImage: ui)
}

private func playtimeLabel(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
}

struct StatusPill: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        let (text, color): (String, Color) =
            snapshot.isPlaying ? ("Playing", LSWidget.green)
            : snapshot.isPaused ? ("Paused", LSWidget.torch)
            : ("Continue", LSWidget.torch)
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
    }
}

// MARK: - Small

struct ContinuePlayingSmall: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    // Whole cover, contained (matches the medium's poster).
                    CoverPoster(image: coverImage(snapshot))
                        .frame(width: 60, height: 82)
                    Spacer(minLength: 0)
                    control(snapshot)
                }
                Spacer(minLength: 0)
                Text(snapshot.gameName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle(snapshot))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(statusColor(snapshot))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(WidgetShared.gameURL(snapshot.gameID))
        } else {
            EmptyWidget()
        }
    }

    @ViewBuilder
    private func control(_ s: WidgetSnapshot) -> some View {
        if s.isPlaying {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(LSWidget.green)
                .frame(width: 34, height: 34)
                .background(LSWidget.green.opacity(0.16), in: Circle())
        } else {
            Button(intent: StartSessionIntent(gameID: s.gameID)) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LSWidget.navyDeep)
                    .frame(width: 34, height: 34)
                    .background(LSWidget.torch, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func subtitle(_ s: WidgetSnapshot) -> String {
        if s.isPlaying { return "Playing" }
        if s.playtimeSeconds > 0 { return playtimeLabel(s.playtimeSeconds) }
        return "Continue"
    }

    private func statusColor(_ s: WidgetSnapshot) -> Color {
        if s.isPlaying { return LSWidget.green }
        return s.playtimeSeconds > 0 ? .white.opacity(0.6) : LSWidget.torch
    }
}

/// Contained box-art poster: the whole cover fits on a navy frame (no crop),
/// so portrait, square, and landscape covers all read cleanly.
struct CoverPoster: View {
    let image: Image?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LSWidget.navyDeep)
            if let image {
                // Cover art must stay full-colour in the Clear and Tinted
                // Home Screen appearances. In those modes WidgetKit renders
                // accented widgets, and any image not opted out is flattened
                // into the tint — every cover became a solid white rounded
                // rectangle. Artwork is content, not chrome; Photos and Music
                // make the same call for theirs.
                image.resizable()
                    // Image-only modifier: must sit before scaledToFit(),
                    // which erases to `some View`.
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFit()
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LSWidget.purple.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.08)))
    }
}

// MARK: - Medium

struct ContinuePlayingMedium: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot {
            HStack(spacing: 12) {
                CoverPoster(image: coverImage(snapshot))
                    .frame(width: 74)

                VStack(alignment: .leading, spacing: 0) {
                    StatusPill(snapshot: snapshot)
                    Text(snapshot.gameName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.top, 4)
                    Text(metaLine(snapshot))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 1)

                    Spacer(minLength: 6)

                    if let objective = snapshot.nextObjective {
                        HStack(spacing: 7) {
                            if let itemID = snapshot.nextObjectiveID {
                                Button(intent: ToggleObjectiveIntent(gameID: snapshot.gameID, itemID: itemID)) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                }
                                .buttonStyle(.plain)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("NEXT")
                                    .font(.system(size: 8, weight: .bold)).tracking(0.8)
                                    .foregroundStyle(LSWidget.torch)
                                Text(objective)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            resumeButton(snapshot)
                        }
                        .padding(.top, 6)
                        .overlay(Divider().overlay(.white.opacity(0.1)), alignment: .top)
                    } else {
                        HStack {
                            Spacer()
                            resumeButton(snapshot)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(12)
            .widgetURL(WidgetShared.gameURL(snapshot.gameID))
        } else {
            EmptyWidget()
        }
    }

    private func metaLine(_ s: WidgetSnapshot) -> String {
        var parts: [String] = []
        if let last = s.lastPlayedAt {
            parts.append("Last played \(last.formatted(.relative(presentation: .named)))")
        }
        if s.playtimeSeconds > 0 { parts.append(playtimeLabel(s.playtimeSeconds)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func resumeButton(_ s: WidgetSnapshot) -> some View {
        if !s.isPlaying {
            Button(intent: StartSessionIntent(gameID: s.gameID)) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                    Text(s.isPaused ? "Resume" : "Play").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(LSWidget.navyDeep)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(LSWidget.torch, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "waveform").font(.system(size: 10, weight: .bold))
                Text("Live").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(LSWidget.green)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(LSWidget.green.opacity(0.16), in: Capsule())
        }
    }
}

// MARK: - Empty state

struct EmptyWidget: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 22))
                .foregroundStyle(LSWidget.purple)
            Text("No active game")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text("Start a session in LevelSelect")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding()
        .widgetURL(WidgetShared.homeURL)
    }
}

// MARK: - Widget

struct ContinuePlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinuePlaying", provider: ContinuePlayingProvider()) { entry in
            ContinuePlayingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Continue Playing")
        .description("Jump back into your current game — and start a session right from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ContinuePlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ContinuePlayingEntry

    var body: some View {
        switch family {
        case .systemMedium: ContinuePlayingMedium(snapshot: entry.snapshot)
        default: ContinuePlayingSmall(snapshot: entry.snapshot)
        }
    }
}
