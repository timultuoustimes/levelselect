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
    let snapshot: WidgetSnapshot?
}

struct LauncherProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now, target: nil, snapshot: nil)
    }
    func snapshot(for configuration: LauncherConfigIntent, in context: Context) async -> LauncherEntry {
        entry(configuration)
    }
    func timeline(for configuration: LauncherConfigIntent, in context: Context) async -> Timeline<LauncherEntry> {
        // Record this placement's target so the bridge caches cover art for
        // the games it shows — the same pattern as the shuffler's picks.
        if let id = configuration.target?.id,
           let defaults = UserDefaults(suiteName: WidgetShared.appGroup) {
            var targets = (defaults.array(forKey: "portalTargets") as? [String]) ?? []
            if !targets.contains(id) {
                targets.append(id)
                defaults.set(targets, forKey: "portalTargets")
            }
        }
        // Hourly so the art wall follows the library as it changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry(configuration)], policy: .after(next))
    }

    private func entry(_ configuration: LauncherConfigIntent) -> LauncherEntry {
        LauncherEntry(date: .now, target: configuration.target,
                      snapshot: WidgetSnapshot.load())
    }
}

/// The games a portal shows: id + cover pairs, most active first.
func portalGames(for target: LauncherTarget,
                 in snapshot: WidgetSnapshot?) -> [(id: String, cover: String?)] {
    guard let snapshot else { return [] }
    let parts = target.id.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return [] }
    switch parts[0] {
    case "status":
        return snapshot.shufflePool.filter { $0.statusRaw == parts[1] }
            .prefix(8).map { ($0.id, $0.coverFileName) }
    case "platform":
        return snapshot.shufflePool.filter { $0.platform == parts[1] }
            .prefix(8).map { ($0.id, $0.coverFileName) }
    case "collection":
        guard let ref = snapshot.collections.first(where: { $0.id == parts[1] })
        else { return [] }
        return zip(ref.memberIDs,
                   ref.memberCovers + Array(repeating: nil,
                                            count: max(0, ref.memberIDs.count - ref.memberCovers.count)))
            .map { ($0, $1) }
    default:
        return []
    }
}

/// The portal's identity mark: the real console icon for a system target
/// (the claymorphic art the app's shelves use), the SF symbol otherwise.
struct PortalMark: View {
    let target: LauncherTarget
    let snapshot: WidgetSnapshot?
    var size: CGFloat = 24

    var body: some View {
        if target.id.hasPrefix("platform:"),
           let asset = snapshot?.platformIcons[target.name],
           let ui = UIImage(named: asset) {
            Image(uiImage: ui)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFit()
                .frame(width: size * 1.6, height: size * 1.6)
        } else {
            Image(systemName: target.symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(LSWidget.torch)
        }
    }
}

// MARK: - View

struct LauncherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LauncherEntry

    var body: some View {
        switch family {
        case .systemMedium: LauncherPortalMedium(entry: entry)
        case .systemLarge: LauncherPortalLarge(entry: entry)
        default: LauncherSmallView(entry: entry)
        }
    }
}

/// A visual doorway: the section's own art, four covers wide (medium) or a
/// 2×4 wall (large), each cover a Link to its game, everything else opening
/// the section itself. The Now Playing shelf's idea, pointed anywhere.
struct LauncherPortalMedium: View {
    let entry: LauncherEntry

    var body: some View {
        if let target = entry.target {
            let games = portalGames(for: target, in: entry.snapshot)
            VStack(alignment: .leading, spacing: 8) {
                PortalHeader(target: target, snapshot: entry.snapshot)
                if games.isEmpty {
                    Spacer()
                    Text("Nothing here yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    HStack(spacing: 10) {
                        ForEach(Array(games.prefix(4)), id: \.id) { game in
                            Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                                CoverPoster(image: loadCover(game.cover))
                                    .aspectRatio(0.72, contentMode: .fit)
                            }
                        }
                        if games.count < 4 {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .widgetURL(target.url ?? WidgetShared.homeURL)
        } else {
            LauncherSmallView(entry: entry)
        }
    }
}

struct LauncherPortalLarge: View {
    let entry: LauncherEntry

    var body: some View {
        if let target = entry.target {
            let games = portalGames(for: target, in: entry.snapshot)
            VStack(alignment: .leading, spacing: 10) {
                PortalHeader(target: target, snapshot: entry.snapshot)
                if games.isEmpty {
                    Spacer()
                    Text("Nothing here yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                              spacing: 12) {
                        ForEach(Array(games.prefix(8)), id: \.id) { game in
                            Link(destination: WidgetShared.gameURL(game.id) ?? WidgetShared.homeURL!) {
                                CoverPoster(image: loadCover(game.cover))
                                    .aspectRatio(0.72, contentMode: .fit)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(target.url ?? WidgetShared.homeURL)
        } else {
            LauncherSmallView(entry: entry)
        }
    }
}

struct PortalHeader: View {
    let target: LauncherTarget
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(spacing: 8) {
            PortalMark(target: target, snapshot: snapshot, size: 13)
            Text(target.name.uppercased())
                .font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
    }
}

struct LauncherSmallView: View {
    let entry: LauncherEntry

    var body: some View {
        if let target = entry.target,
           target.id.hasPrefix("platform:"),
           let asset = entry.snapshot?.platformIcons[target.name],
           let ui = UIImage(named: asset) {
            // A system's small launcher is a shelf ornament: the claymorphic
            // hardware nearly fills the widget, name beneath. A row of these
            // reads as "my consoles", which is exactly the point of pinning
            // them.
            VStack(spacing: 4) {
                Image(uiImage: ui)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                Text(target.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(2)
            .widgetURL(target.url ?? WidgetShared.homeURL)
        } else if let target = entry.target {
            VStack(alignment: .leading, spacing: 0) {
                PortalMark(target: target, snapshot: entry.snapshot)
                Spacer(minLength: 0)
                Text(target.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(target.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(target.url ?? WidgetShared.homeURL)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 22))
                    .foregroundStyle(LSWidget.accent)
                Text("Pick a destination")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Long-press → Edit Widget")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
                .lsWidgetSurface()
        }
        .configurationDisplayName("Open To…")
        .description("A door straight to a collection, a status shelf, or a system.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
