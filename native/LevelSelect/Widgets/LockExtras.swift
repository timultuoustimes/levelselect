import WidgetKit
import SwiftUI
import AppIntents

/// The lock-screen set. Everything here is designed for vibrant rendering
/// first — shapes, numbers, and glyphs, never cover art, because the Lock
/// Screen flattens art into wallpaper-tinted fog and there is no opt-out.
///
/// With the completion ring that already existed, the circulars fill an
/// iPhone bar exactly: ring · die · week gauge · streak.

// MARK: - The die (lock screen)

/// Tap → the app opens on a random game. The roll happens IN THE APP at
/// launch (levelselect://shuffle), because a widget URL is baked per timeline
/// entry — app-side rolling is the only way every tap is genuinely fresh.
/// Shares the Home Screen shuffler's configuration, so a lock-screen die can
/// be "a Genesis game" too.
struct ShuffleLockView: View {
    let config: ShufflerConfigIntent

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "dice.fill")
                .font(.system(size: 26, weight: .bold))
        }
        .widgetURL(shuffleURL)
    }

    private var shuffleURL: URL? {
        var components = URLComponents()
        components.scheme = "levelselect"
        components.host = "shuffle"
        var items = [URLQueryItem(name: "s", value: config.statusRaws.sorted().joined(separator: ","))]
        if let platform = config.platformFilter {
            items.append(URLQueryItem(name: "p", value: platform))
        }
        if config.includeCompleted {
            items.append(URLQueryItem(name: "c", value: "1"))
        }
        components.queryItems = items
        return components.url
    }
}

struct ShuffleLockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ShuffleLock",
                               intent: ShufflerConfigIntent.self,
                               provider: ShufflerProvider()) { entry in
            ShuffleLockView(config: entry.config)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Surprise Me")
        .description("Opens the app on a random game — a fresh roll every tap. Configure what it may pick from.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Next Up (interactive)

/// The next objective with a REAL tick button — clear a boss from the Lock
/// Screen without unlocking. Tapping anywhere else opens the game.
struct NextUpLockView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let s = snapshot, let objective = s.nextObjective {
            HStack(spacing: 8) {
                if let itemID = s.nextObjectiveID {
                    Button(intent: ToggleObjectiveIntent(gameID: s.gameID, itemID: itemID)) {
                        Image(systemName: "circle")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("NEXT · \(s.gameName.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.7)
                        .lineLimit(1)
                    Text(objective)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if s.completionTotal > 0 {
                        Text("\(s.completionDone)/\(s.completionTotal)")
                            .font(.system(size: 11).monospacedDigit())
                            .opacity(0.6)
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(WidgetShared.gameURL(s.gameID))
        } else {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                Text("No objective queued")
                    .font(.system(size: 13, weight: .semibold))
            }
            .widgetURL(WidgetShared.homeURL)
        }
    }
}

struct NextUpLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextUpLock", provider: ContinuePlayingProvider()) { entry in
            NextUpLockView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next Up")
        .description("Your current game's next objective — tick it off right from the Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Week gauge

/// This week against your own four-week pace. The ring meaning "ahead or
/// behind MY normal" beats an arbitrary goal nobody set.
struct WeekGaugeLockView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        let thisWeek = snapshot?.weeklyTotalSeconds ?? 0
        let average = snapshot?.weeklyAverageSeconds ?? 0
        Gauge(value: WidgetMath.gaugeValue(thisWeekSeconds: thisWeek, averageSeconds: average)) {
            Text("WK")
        } currentValueLabel: {
            Text(lsHours(thisWeek))
                .font(.system(size: 12, weight: .bold).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(WidgetShared.statsURL)
    }
}

struct WeekGaugeLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekGaugeLock", provider: ContinuePlayingProvider()) { entry in
            WeekGaugeLockView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("This Week")
        .description("Hours this week, measured against your own four-week pace.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Streak

struct StreakLockView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        let streak = WidgetMath.streak(dailyMinutes: snapshot?.dailyMinutes ?? [])
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 15, weight: .bold))
                Text("\(streak)")
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                Text(streak == 1 ? "DAY" : "DAYS")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.6)
            }
        }
        .widgetURL(WidgetShared.statsURL)
    }
}

struct StreakLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakLock", provider: ContinuePlayingProvider()) { entry in
            StreakLockView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Consecutive days with a session. Today doesn't count against you until it's over.")
        .supportedFamilies([.accessoryCircular])
    }
}
