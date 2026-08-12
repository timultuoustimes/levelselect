import WidgetKit
import SwiftUI

struct WeekStatSmall: View {
    let snapshot: WidgetSnapshot?

    private let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        let weekly = snapshot?.weeklySeconds ?? []
        let total = weekly.reduce(0, +)
        let peak = max(weekly.max() ?? 1, 1)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LSWidget.torch)
                Text("THIS WEEK")
                    .font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(lsHours(total))
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.top, 1)
            if let n = snapshot?.gamesPlayedThisWeek, n > 0 {
                Text("\(n) game\(n == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 8)

            // 7-day bars, today last.
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(weekly.enumerated()), id: \.offset) { idx, secs in
                    let isToday = idx == weekly.count - 1
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isToday ? LSWidget.torch : LSWidget.purple.opacity(0.75))
                            .frame(height: max(3, CGFloat(secs / peak) * 42))
                        Text(dayIndexLetter(idx, count: weekly.count))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(isToday ? 0.9 : 0.4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 56, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetShared.statsURL)
    }

    /// Weekday initial for a bar, computed from "days ago" so today is correct.
    private func dayIndexLetter(_ idx: Int, count: Int) -> String {
        let daysAgo = (count - 1) - idx
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: -daysAgo, to: .now) else { return "" }
        let weekday = cal.component(.weekday, from: date) - 1  // 0=Sun
        return dayLetters[max(0, min(6, weekday))]
    }
}

struct WeekStatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSWeekStat", provider: ContinuePlayingProvider()) { entry in
            WeekStatSmall(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("This Week")
        .description("Your play time over the last 7 days.")
        .supportedFamilies([.systemSmall])
    }
}
