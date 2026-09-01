import WidgetKit
import SwiftUI
import ActivityKit

@main
struct LevelSelectWidgets: WidgetBundle {
    var body: some Widget {
        ContinuePlayingWidget()
        ShufflerWidget()
        CommandBoardWidget()
        ShelfXLWidget()
        WhereYouStandWidget()
        ObjectivesWidget()
        CompletionRingWidget()
        WeekStatWidget()
        RunTrackerWidget()
        HeatmapWidget()
        FinishedShareWidget()
        LauncherWidget()
        ReleasesWidget()
        LockRectangularWidget()
        LockInlineWidget()
        CompletionCircularWidget()
        ShuffleLockWidget()
        NextUpLockWidget()
        WeekGaugeLockWidget()
        StreakLockWidget()
        SessionLiveActivity()
    }
}

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            // Lock Screen / banner
            LockScreenSessionView(context: context)
                .activityBackgroundTint(Color(red: 0.10, green: 0.07, blue: 0.18))
                .activitySystemActionForegroundColor(LSWidget.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.gameName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundStyle(LSWidget.accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: 72)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Button(intent: PauseResumeSessionIntent(sessionID: context.attributes.sessionID)) {
                            Label(context.state.isRunning ? "Pause" : "Resume",
                                  systemImage: context.state.isRunning ? "pause.fill" : "play.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(LSWidget.accent)

                        Button(intent: StopSessionIntent(sessionID: context.attributes.sessionID)) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(LSWidget.accent)
            } compactTrailing: {
                if context.state.isRunning {
                    timer(context)
                        .font(.caption2.monospacedDigit())
                        .frame(maxWidth: 44)
                } else {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(.orange)
                }
            } minimal: {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(LSWidget.accent)
            }
        }
    }

    @ViewBuilder
    private func timer(_ context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        if context.state.isRunning {
            Text(timerInterval: context.state.startedAt...Date(timeIntervalSinceNow: 60 * 60 * 24 * 30),
                 countsDown: false)
                .multilineTextAlignment(.trailing)
        } else {
            Text(frozen(context.state.accumulated))
        }
    }

    private func frozen(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}

struct LockScreenSessionView: View {
    let context: ActivityViewContext<SessionActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.title2)
                .foregroundStyle(LSWidget.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.gameName)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.isRunning ? "Session in progress" : "Paused")
                    .font(.caption)
                    .foregroundStyle(context.state.isRunning ? .green : .orange)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if context.state.isRunning {
                    Text(timerInterval: context.state.startedAt...Date(timeIntervalSinceNow: 60 * 60 * 24 * 30),
                         countsDown: false)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 96)
                } else {
                    Text(frozenLabel)
                        .font(.title2.monospacedDigit().weight(.semibold))
                }
                HStack(spacing: 8) {
                    Button(intent: PauseResumeSessionIntent(sessionID: context.attributes.sessionID)) {
                        Image(systemName: context.state.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(LSWidget.accent)

                    Button(intent: StopSessionIntent(sessionID: context.attributes.sessionID)) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
    }

    private var frozenLabel: String {
        let s = max(0, Int(context.state.accumulated))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
