import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Palette (mirrors the app theme; the widget process can't read it)

enum LSWidget {
    /// Control colors that survive the accented Home Screen appearances.
    /// In Clear and Tinted, EVERY color is flattened into the tint — a
    /// navyDeep glyph on a torch circle becomes white-on-white. Opacity is
    /// the only contrast that survives, so accented controls become a
    /// translucent plate with a full-opacity glyph.
    static func controlFG(_ mode: WidgetRenderingMode) -> Color {
        mode == .fullColor ? navyDeep : .white
    }
    static func controlBG(_ mode: WidgetRenderingMode) -> Color {
        mode == .fullColor ? torch : .white.opacity(0.24)
    }

    static let torch = Color(red: 0.96, green: 0.64, blue: 0.30)
    static let purple = Color(red: 0.58, green: 0.36, blue: 0.98)

    /// The accent a widget should tint with.
    ///
    /// Widgets used a fixed purple, so choosing an accent changed the app and
    /// left the Home Screen alone — and once the default became torch, a Lock
    /// Screen timer was a different colour from the app that started it. The
    /// snapshot carries the chosen accent now, and `nil` means "no choice",
    /// which resolves to the same default the app uses rather than to a stale
    /// copy of whatever that default was on the day this shipped.
    ///
    /// Read as a static rather than threaded through the views because two
    /// places that need it cannot be reached from a snapshot: the Live
    /// Activity has attributes and no snapshot, and `ShufflerEntry` carries
    /// only its pick. Cached against the snapshot file's modification date, so
    /// a render costs one `stat` rather than a JSON decode, and changing your
    /// accent invalidates it the moment the app rewrites the file.
    nonisolated(unsafe) private static var cachedAccent: (stamp: Date, color: Color)?

    static var accent: Color {
        guard let url = WidgetShared.snapshotURL,
              let stamp = (try? FileManager.default
                  .attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return torch }
        if let cached = cachedAccent, cached.stamp == stamp { return cached.color }
        let colour = WidgetSnapshot.load()?.accentHex.flatMap { Color(hex: $0) } ?? torch
        cachedAccent = (stamp, colour)
        return colour
    }
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
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, renderingMode == .vibrant {
            // Lock Screen (vibrant): art flattens into wallpaper-tinted fog
            // with no opt-out, so the layout leads with what vibrant does
            // well — a bold control, the name, the numbers.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: snapshot.isPlaying ? "waveform" : "play.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                    Spacer()
                }
                Spacer(minLength: 0)
                Text(snapshot.gameName)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if snapshot.playtimeSeconds > 0 {
                        Text(lsPlaytime(snapshot.playtimeSeconds))
                    }
                    if snapshot.completionTotal > 0 {
                        Text("· \(Int((Double(snapshot.completionDone) / Double(max(1, snapshot.completionTotal)) * 100).rounded()))%")
                    }
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .opacity(0.7)
                if let objective = snapshot.nextObjective {
                    HStack(spacing: 5) {
                        Image(systemName: "circle").font(.system(size: 10, weight: .semibold))
                        Text(objective).font(.system(size: 10)).lineLimit(1)
                    }
                    .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(WidgetShared.gameURL(snapshot.gameID))
        } else if let snapshot {
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
                    .foregroundStyle(LSWidget.controlFG(renderingMode))
                    .frame(width: 34, height: 34)
                    .background(LSWidget.controlBG(renderingMode), in: Circle())
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

/// Full-bleed box art: the cover fills its frame edge to edge, cropped
/// minimally (IGDB covers are a uniform 3:4, so the crop is a sliver).
///
/// This replaces the earlier letterboxed "poster on a navy plate" look. The
/// plate was chrome, so the accented Home Screen appearances painted it —
/// white bars around every cover in Clear and Tinted, dark bars otherwise,
/// exactly where the art should have been. The plate now survives only
/// behind the placeholder glyph, where there is no art to crop.
struct CoverPoster: View {
    let image: Image?
    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    image.resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LSWidget.navyDeep)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(LSWidget.accent.opacity(0.6))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LSTheme.hairline))
    }
}

// MARK: - Medium

struct ContinuePlayingMedium: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot {
            HStack(spacing: 12) {
                CoverPoster(image: coverImage(snapshot))
                    .frame(width: 74, height: 101)

                VStack(alignment: .leading, spacing: 0) {
                    StatusPill(snapshot: snapshot)
                    Text(snapshot.gameName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.top, 4)
                    Text(metaLine(snapshot))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)

                    Spacer(minLength: 6)

                    if let objective = snapshot.nextObjective {
                        HStack(spacing: 7) {
                            if let itemID = snapshot.nextObjectiveID {
                                Button(intent: ToggleObjectiveIntent(gameID: snapshot.gameID, itemID: itemID)) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(LSTheme.hairline, lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                }
                                .buttonStyle(.plain)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(LSTheme.hairline, lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text("NEXT")
                                    .font(.system(size: 8, weight: .bold)).tracking(0.8)
                                    .foregroundStyle(LSWidget.torch)
                                Text(objective)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                // What's next tells you where to go; what you
                                // last ticked tells you where you were, which
                                // is the half that goes missing over weeks.
                                if let last = snapshot.lastTicked {
                                    Text("Left off: \(last)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            resumeButton(snapshot)
                        }
                        .padding(.top, 6)
                        .overlay(Divider().overlay(LSTheme.separator), alignment: .top)
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
                .foregroundStyle(LSWidget.controlFG(renderingMode))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(LSWidget.controlBG(renderingMode), in: Capsule())
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
                .foregroundStyle(LSWidget.accent)
            Text("No active game")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Start a session in LevelSelect")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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
                .lsWidgetSurface()
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
