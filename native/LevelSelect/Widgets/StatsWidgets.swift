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
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(streak) day\(streak == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                if let total = snapshot?.weeklyTotalSeconds, total > 0 {
                    Text("\(lsHours(total)) this week")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
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
        case ..<1:   .white.opacity(0.07)
        case ..<20:  LSWidget.purple.opacity(0.30)
        case ..<60:  LSWidget.purple.opacity(0.55)
        case ..<120: LSWidget.purple.opacity(0.80)
        default:     LSWidget.purple
        }
    }
}

struct HeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Heatmap", provider: ContinuePlayingProvider()) { entry in
            HeatmapWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Play Heatmap")
        .description("Sixteen weeks of play, one square per day — the habit at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Finished share (small)

/// The library-wide completion ring — the whole shelf's "how far along am I",
/// where the existing ring is one game's.
struct FinishedShareView: View {
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
                            .foregroundStyle(.white)
                        Text("\(done)/\(total)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            Text("Finished")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetShared.statsURL)
    }
}

struct FinishedShareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FinishedShare", provider: ContinuePlayingProvider()) { entry in
            FinishedShareView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Finished Share")
        .description("How much of the whole library you've finished.")
        .supportedFamilies([.systemSmall])
    }
}
