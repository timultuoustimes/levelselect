import WidgetKit
import SwiftUI

// MARK: - Rectangular (current game + next objective)

struct LockRectangularView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot {
            HStack(spacing: 9) {
                Image(systemName: snapshot.isPlaying ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.gameName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let objective = snapshot.nextObjective {
                        HStack(spacing: 4) {
                            Image(systemName: "square")
                                .font(.system(size: 9, weight: .semibold))
                            Text(objective)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .opacity(0.85)
                    } else {
                        Text(subtitle(snapshot))
                            .font(.system(size: 11))
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(WidgetShared.gameURL(snapshot.gameID))
        } else {
            Label("No active game", systemImage: "gamecontroller")
                .font(.system(size: 13, weight: .medium))
                .widgetURL(WidgetShared.homeURL)
        }
    }

    private func subtitle(_ s: WidgetSnapshot) -> String {
        if s.isPlaying { return "Session in progress" }
        if s.isPaused { return "Session paused" }
        if s.playtimeSeconds > 0 {
            let h = Int(s.playtimeSeconds) / 3600, m = (Int(s.playtimeSeconds) % 3600) / 60
            return h > 0 ? "\(h)h \(m)m played" : "\(m)m played"
        }
        return "Tap to continue"
    }
}

struct LockRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSLockRectangular", provider: ContinuePlayingProvider()) { entry in
            LockRectangularView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Current Game")
        .description("Your current game and next objective on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Inline (▶ Game · playtime, above the clock)

struct LockInlineView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot {
            Label {
                Text(inlineText(snapshot))
            } icon: {
                Image(systemName: snapshot.isPlaying ? "play.fill" : "gamecontroller.fill")
            }
            .widgetURL(WidgetShared.gameURL(snapshot.gameID))
        } else {
            Label("LevelSelect", systemImage: "gamecontroller")
                .widgetURL(WidgetShared.homeURL)
        }
    }

    private func inlineText(_ s: WidgetSnapshot) -> String {
        guard s.playtimeSeconds > 0 else { return s.gameName }
        let h = Int(s.playtimeSeconds) / 3600, m = (Int(s.playtimeSeconds) % 3600) / 60
        let t = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        return "\(s.gameName) · \(t)"
    }
}

struct LockInlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSLockInline", provider: ContinuePlayingProvider()) { entry in
            LockInlineView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Now Playing")
        .description("A one-line reminder of your current game above the clock.")
        .supportedFamilies([.accessoryInline])
    }
}
