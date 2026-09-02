import WidgetKit
import SwiftUI
import AppIntents

struct ObjectivesLargeView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, snapshot.completionTotal > 0 {
            VStack(alignment: .leading, spacing: 10) {
                header(snapshot)
                let items = Array(snapshot.objectives.prefix(6))
                if items.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(LSWidget.green)
                            Text("All objectives complete!")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                    }
                    Spacer()
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            objectiveRow(gameID: snapshot.gameID, item: item)
                            if item.id != items.last?.id {
                                Divider().overlay(LSTheme.separator)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyObjectives(snapshot: snapshot)
        }
    }

    private func header(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 11) {
            CoverPoster(image: loadCover(s.coverFileName))
                .frame(width: 40, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.gameName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ProgressView(value: Double(s.completionDone), total: Double(max(1, s.completionTotal)))
                        .tint(LSWidget.torch)
                        .frame(maxWidth: 130)
                    Text("\(s.completionDone)/\(s.completionTotal)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func objectiveRow(gameID: String, item: WidgetObjective) -> some View {
        Button(intent: ToggleObjectiveIntent(gameID: gameID, itemID: item.id)) {
            HStack(spacing: 10) {
                Image(systemName: item.done ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(item.done ? LSWidget.green : .white.opacity(0.45))
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(item.done ? .white.opacity(0.45) : .white.opacity(0.92))
                    .strikethrough(item.done, color: .white.opacity(0.4))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyObjectives: View {
    let snapshot: WidgetSnapshot?
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 26))
                .foregroundStyle(LSWidget.accent)
            Text(snapshot == nil ? "No active game" : "No tracker yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            if let snapshot {
                Text(snapshot.gameName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(snapshot.map { WidgetShared.gameURL($0.gameID) } ?? WidgetShared.homeURL)
    }
}

struct ObjectivesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LSObjectives", provider: ContinuePlayingProvider()) { entry in
            ObjectivesLargeView(snapshot: entry.snapshot)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Objectives")
        .description("Check off your next objectives right from the Home Screen.")
        .supportedFamilies([.systemLarge])
    }
}
