import WidgetKit
import SwiftUI

struct RunTrackerView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let run = snapshot?.runGame {
            if renderingMode == .vibrant {
                vibrant(run)
            } else {
                switch family {
                case .systemMedium: medium(run)
                default: small(run)
                }
            }
        } else {
            empty
        }
    }

    /// Lock Screen: the record as type, the last outcomes as segments — no
    /// cover to lose to the wallpaper tint.
    private func vibrant(_ run: WidgetRunGame) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.name.uppercased())
                .font(.system(size: 10, weight: .bold))
                .opacity(0.7)
                .lineLimit(1)
            Text("\(Int((run.winRate * 100).rounded()))%")
                .font(.system(size: 28, weight: .heavy).monospacedDigit())
            Text("\(run.wins)W · \(run.losses)L")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .opacity(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                let decided = max(run.wins + run.losses, 1)
                ForEach(0..<min(decided, 7), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .opacity(index < run.wins ? 1 : 0.3)
                        .frame(height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetShared.gameURL(run.id))
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
                .foregroundStyle(.primary)
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(run.total) run\(run.total == 1 ? "" : "s") logged")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                record(run).font(.system(size: 14, weight: .bold))
            }

            Spacer(minLength: 0)

            ZStack {
                RingView(progress: run.winRate, lineWidth: 8, tint: LSWidget.green)
                VStack(spacing: 0) {
                    Text("\(Int((run.winRate * 100).rounded()))%")
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text("win")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(LSWidget.accent)
            Text("No runs tracked yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
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
                .lsWidgetSurface()
        }
        .configurationDisplayName("Run Tracker")
        .description("Win/loss record for your latest roguelike run.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
