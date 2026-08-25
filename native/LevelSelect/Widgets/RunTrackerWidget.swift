import WidgetKit
import SwiftUI

struct RunTrackerView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let run = snapshot?.runGame {
            switch family {
            case .systemMedium: medium(run)
            default: small(run)
            }
        } else {
            empty
        }
    }

    // MARK: Small

    private func small(_ run: WidgetRunGame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                CoverPoster(image: loadCover(run.coverFileName))
                    .frame(width: 46, height: 62)
                Spacer(minLength: 0)
                if run.inProgress { inRunPill }
            }
            Spacer(minLength: 6)
            Text(run.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(spacing: 8) {
                record(run)
                Spacer(minLength: 0)
                Text("\(Int((run.winRate * 100).rounded()))%")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LSWidget.torch)
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetShared.gameURL(run.id))
    }

    // MARK: Medium

    private func medium(_ run: WidgetRunGame) -> some View {
        HStack(spacing: 14) {
            CoverPoster(image: loadCover(run.coverFileName))
                .frame(width: 78, height: 106)

            VStack(alignment: .leading, spacing: 4) {
                if run.inProgress { inRunPill } else { labelPill("RUNS", color: LSWidget.torch) }
                Text(run.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(run.total) run\(run.total == 1 ? "" : "s") logged")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 6)
                record(run).font(.system(size: 14, weight: .bold))
            }

            Spacer(minLength: 0)

            ZStack {
                RingView(progress: run.winRate, lineWidth: 8, tint: LSWidget.green)
                VStack(spacing: 0) {
                    Text("\(Int((run.winRate * 100).rounded()))%")
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("win")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 66, height: 66)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(WidgetShared.gameURL(run.id))
    }

    // MARK: Bits

    @ViewBuilder
    private func record(_ run: WidgetRunGame) -> some View {
        HStack(spacing: 6) {
            Text("\(run.wins)W").foregroundStyle(LSWidget.green)
            Text("\(run.losses)L").foregroundStyle(LSWidget.red)
        }
        .font(.system(size: 13, weight: .bold).monospacedDigit())
    }

    private var inRunPill: some View { labelPill("IN RUN", color: LSWidget.green, dot: true) }

    private func labelPill(_ text: String, color: Color, dot: Bool = false) -> some View {
        HStack(spacing: 4) {
            if dot { Circle().fill(color).frame(width: 5, height: 5) }
            Text(text).font(.system(size: 9, weight: .bold)).tracking(0.4)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 22))
                .foregroundStyle(LSWidget.purple)
            Text("No runs tracked yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding()
        .widgetURL(WidgetShared.homeURL)
    }
}

struct RunTrackerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSRunTracker", provider: ContinuePlayingProvider()) { entry in
            RunTrackerView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Run Tracker")
        .description("Win/loss record for your latest roguelike run.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
