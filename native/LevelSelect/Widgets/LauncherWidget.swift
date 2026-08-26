import WidgetKit
import SwiftUI
import AppIntents

/// A door on the Home Screen: one small widget that opens straight to a
/// collection, a play-status shelf, or a system shelf. One picker holds all
/// three kinds — flattened into a single entity list — because a widget
/// config UI can't do "choose a kind, then choose a value" gracefully, and
/// one searchable list of everything you could pin does the same job better.
struct LauncherTarget: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Destination")
    static let defaultQuery = LauncherTargetQuery()

    /// "status:playing" · "platform:SNES" · "collection:<uuid>"
    let id: String
    let name: String
    let subtitle: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    var url: URL? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        var components = URLComponents()
        components.scheme = "levelselect"
        components.host = parts[0]
        components.path = "/\(parts[1])"
        return components.url
    }

    static func all() -> [LauncherTarget] {
        let snapshot = WidgetSnapshot.load()
        let statuses: [(String, String, String)] = [
            ("playing", "Now Playing", "play.fill"),
            ("paused", "Paused", "pause.fill"),
            ("queued", "Up Next", "text.line.first.and.arrowtriangle.forward"),
            ("backlog", "Backlog", "tray.full"),
            ("ongoing", "Always Around", "infinity"),
            ("completed", "Completed", "checkmark.seal"),
        ]
        var targets: [LauncherTarget] = statuses.map {
            LauncherTarget(id: "status:\($0.0)", name: $0.1, subtitle: "Status", symbol: $0.2)
        }
        for collection in snapshot?.collections ?? [] {
            targets.append(LauncherTarget(
                id: "collection:\(collection.id)",
                name: collection.name,
                subtitle: "Collection · \(collection.count) game\(collection.count == 1 ? "" : "s")",
                symbol: "square.stack.3d.up.fill"))
        }
        for platform in snapshot?.libraryPlatforms ?? [] {
            targets.append(LauncherTarget(
                id: "platform:\(platform)", name: platform,
                subtitle: "System", symbol: "gamecontroller.fill"))
        }
        return targets
    }
}

struct LauncherTargetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LauncherTarget] {
        LauncherTarget.all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [LauncherTarget] {
        LauncherTarget.all()
    }
    func defaultResult() async -> LauncherTarget? {
        try? await suggestedEntities().first
    }
}

struct LauncherConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Open To"
    static let description = IntentDescription("Where this widget takes you.")

    @Parameter(title: "Destination")
    var target: LauncherTarget?
}

// MARK: - Timeline

struct LauncherEntry: TimelineEntry {
    let date: Date
    let target: LauncherTarget?
}

struct LauncherProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now, target: nil)
    }
    func snapshot(for configuration: LauncherConfigIntent, in context: Context) async -> LauncherEntry {
        LauncherEntry(date: .now, target: configuration.target)
    }
    func timeline(for configuration: LauncherConfigIntent, in context: Context) async -> Timeline<LauncherEntry> {
        Timeline(entries: [LauncherEntry(date: .now, target: configuration.target)], policy: .never)
    }
}

// MARK: - View

struct LauncherWidgetView: View {
    let entry: LauncherEntry

    var body: some View {
        if let target = entry.target {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: target.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LSWidget.torch)
                Spacer(minLength: 0)
                Text(target.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(target.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(target.url ?? WidgetShared.homeURL)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 22))
                    .foregroundStyle(LSWidget.purple)
                Text("Pick a destination")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Long-press → Edit Widget")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .widgetURL(WidgetShared.homeURL)
        }
    }
}

struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Launcher",
                               intent: LauncherConfigIntent.self,
                               provider: LauncherProvider()) { entry in
            LauncherWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [LSWidget.navy, LSWidget.navyDeep],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Open To…")
        .description("A door straight to a collection, a status shelf, or a system.")
        .supportedFamilies([.systemSmall])
    }
}
