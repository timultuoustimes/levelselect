import WidgetKit
import SwiftUI

// MARK: - Home small

struct CompletionRingSmall: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, snapshot.completionTotal > 0 {
            let progress = Double(snapshot.completionDone) / Double(snapshot.completionTotal)
            VStack(spacing: 9) {
                ZStack {
                    RingView(progress: progress, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 24, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("\(snapshot.completionDone)/\(snapshot.completionTotal)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 88, height: 88)
                Text(snapshot.gameName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(WidgetShared.gameURL(snapshot.gameID))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 22))
                    .foregroundStyle(LSWidget.accent)
                Text(snapshot == nil ? "No active game" : "No tracker yet")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let snapshot {
                    Text(snapshot.gameName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding()
            .widgetURL(snapshot.map { WidgetShared.gameURL($0.gameID) } ?? WidgetShared.homeURL)
        }
    }
}

struct CompletionRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSCompletionRing", provider: ContinuePlayingProvider()) { entry in
            CompletionRingSmall(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Completion")
        .description("Objective progress for your current game.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Lock Screen circular

struct CompletionCircularView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, snapshot.completionTotal > 0 {
            let progress = Double(snapshot.completionDone) / Double(snapshot.completionTotal)
            Gauge(value: progress) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text("\(Int((progress * 100).rounded()))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(WidgetShared.gameURL(snapshot.gameID))
        } else {
            Image(systemName: "gamecontroller.fill")
                .font(.title2)
                .widgetURL(snapshot.map { WidgetShared.gameURL($0.gameID) } ?? WidgetShared.homeURL)
        }
    }
}

struct CompletionCircularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSCompletionCircular", provider: ContinuePlayingProvider()) { entry in
            CompletionCircularView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Completion Ring")
        .description("Objective progress on the Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}
