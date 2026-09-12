import WidgetKit
import SwiftUI

/// Home Screen stats widgets — the Stats tab's two most glanceable cards.

// MARK: - Heatmap (medium)

/// Sixteen weeks of days, GitHub-shaped: columns are weeks, rows weekdays,
/// intensity is minutes played. The one widget that shows the habit rather
/// than the totals.
struct HeatmapWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        let daily = snapshot?.dailyMinutes ?? []
        let streak = WidgetMath.streak(dailyMinutes: daily)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LSWidget.torch)
                Text("STREAK")
                    .font(.system(size: 10, weight: .bold)).tracking(0.7)
                    .foregroundStyle(.secondary)
                Text("\(streak) day\(streak == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                Spacer()
                if let total = snapshot?.weeklyTotalSeconds, total > 0 {
                    Text("\(lsHours(total)) this week")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            grid(daily)
        }
        .widgetURL(WidgetShared.statsURL)
    }

    private func grid(_ daily: [Double]) -> some View {
        // Trailing 16 weeks, aligned so today sits in the last column.
        let days = Array(daily.suffix(112))
        let weeks = stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
        return HStack(alignment: .top, spacing: 2.5) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 2.5) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, minutes in
                        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                            .fill(heat(minutes))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heat(_ minutes: Double) -> Color {
        switch minutes {
        case ..<1:   LSTheme.cardFill
        case ..<20:  LSWidget.accent.opacity(0.30)
        case ..<60:  LSWidget.accent.opacity(0.55)
        case ..<120: LSWidget.accent.opacity(0.80)
        default:     LSWidget.accent
        }
    }
}

struct HeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Heatmap", provider: ContinuePlayingProvider()) { entry in
            HeatmapWidgetView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Play Heatmap")
        .description("Sixteen weeks of play, one square per day — the habit at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Beaten share (small)

/// The library-wide completion ring — the whole shelf's "how far along am I",
/// where the existing ring is one game's.
struct BeatenShareView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        let done = snapshot?.completedCount ?? 0
        let total = max(snapshot?.libraryCount ?? 0, 1)
        VStack(spacing: 6) {
            RingView(progress: Double(done) / Double(total), lineWidth: 8)
                .frame(width: 74, height: 74)
                .overlay {
                    VStack(spacing: 0) {
                        Text("\(Int((Double(done) / Double(total) * 100).rounded()))%")
                            .font(.system(size: 17, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("\(done)/\(total)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            // "Beaten" — the app's own word for this exact figure. StatsView
            // labels the same percentage that way, and a widget that renames
            // it makes the Home Screen and the Stats page look like two
            // products reporting different numbers. Codex P1.
            Text("Beaten")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetShared.statsURL)
    }
}

struct BeatenShareWidget: Widget {
    var body: some WidgetConfiguration {
        // **The `kind` moves too, and now is the moment.**
        //
        // This string identifies a placed widget, so changing it orphans any
        // that already exist — someone's Home Screen keeps a tile that no
        // longer updates until they replace it. Tim: *"could probably be
        // changed since it would only potentially affect a couple people, as
        // opposed to changing later when we have actual users."* A handful of
        // testers re-adding one tile now is the cheapest this ever gets.
        StaticConfiguration(kind: "BeatenShare", provider: ContinuePlayingProvider()) { entry in
            BeatenShareView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Beaten Share")
        .description("How much of the whole library you've beaten.")
        .supportedFamilies([.systemSmall])
    }
}
