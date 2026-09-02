import WidgetKit
import SwiftUI
import AppIntents

/// "Choose a game for me" — the widget picks something off your shelf and
/// stands by it. Tap the cover to open the game; tap the die to re-roll
/// without opening the app.
///
/// The pick PERSISTS until re-rolled — a suggestion that churns on every
/// timeline refresh is nagging, not choosing. Each placement keeps its own
/// pick, keyed by its configuration, so "a Genesis game" and "anything from
/// the backlog" on the same page roll independently.
///
/// Wishlist and abandoned games are never in the pool at all. Completed
/// games join only when the toggle says so — a two-hour retro game is
/// endlessly replayable, but that's the owner's call, not the widget's.

// MARK: - Configuration

enum ShuffleStatusOption: String, AppEnum {
    case playing, paused, upNext, backlog, ongoing, shelved

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Statuses")
    static let caseDisplayRepresentations: [ShuffleStatusOption: DisplayRepresentation] = [
        .playing: "Playing", .paused: "Paused", .upNext: "Up Next",
        .backlog: "Backlog", .ongoing: "Always Around", .shelved: "Shelved",
    ]

    /// The Game.status raw value this option maps to.
    var statusRaw: String {
        switch self {
        case .upNext: "queued"
        default: rawValue
        }
    }
}

struct ShufflePlatformProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        ["Any"] + (WidgetSnapshot.load()?.libraryPlatforms ?? [])
    }
    func defaultResult() async -> String? { "Any" }
}

struct ShufflerConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose From"
    static let description = IntentDescription("Which games the shuffler may pick.")

    @Parameter(title: "Statuses", default: [.playing, .paused, .upNext, .backlog])
    var statuses: [ShuffleStatusOption]

    @Parameter(title: "System", optionsProvider: ShufflePlatformProvider())
    var platform: String?

    @Parameter(title: "Include finished games", default: false)
    var includeCompleted: Bool

    /// One stored pick per distinct configuration.
    var pickKey: String {
        let statusPart = statuses.map(\.rawValue).sorted().joined(separator: "+")
        return "\(statusPart)|\(platform ?? "Any")|\(includeCompleted)"
    }

    var statusRaws: Set<String> { Set(statuses.map(\.statusRaw)) }
    var platformFilter: String? {
        (platform == nil || platform == "Any") ? nil : platform
    }
}

// MARK: - Pick storage

enum ShufflePicks {
    private static let key = "shufflePicks"

    static func stored(for configKey: String) -> String? {
        UserDefaults(suiteName: WidgetShared.appGroup)?
            .dictionary(forKey: key)?[configKey] as? String
    }

    static func store(_ gameID: String, for configKey: String) {
        guard let defaults = UserDefaults(suiteName: WidgetShared.appGroup) else { return }
        var picks = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        picks[configKey] = gameID
        defaults.set(picks, forKey: key)
    }

    /// The current pick if it still qualifies, else a fresh roll (stored).
    static func resolve(config: ShufflerConfigIntent,
                        snapshot: WidgetSnapshot?) -> WidgetPoolGame? {
        let pool = WidgetPoolGame.filter(
            snapshot?.shufflePool ?? [],
            statuses: config.statusRaws,
            platform: config.platformFilter,
            includeCompleted: config.includeCompleted)
        guard !pool.isEmpty else { return nil }
        if let id = stored(for: config.pickKey),
           let current = pool.first(where: { $0.id == id }) {
            return current
        }
        let rolled = pool.randomElement()!
        store(rolled.id, for: config.pickKey)
        return rolled
    }
}

// MARK: - Re-roll intent

struct ShuffleRollIntent: AppIntent {
    static let title: LocalizedStringResource = "Shuffle"
    static let description = IntentDescription("Pick a different game.")

    @Parameter(title: "Key") var pickKey: String
    @Parameter(title: "Statuses") var statusRaws: [String]
    @Parameter(title: "System") var platform: String?
    @Parameter(title: "Include finished") var includeCompleted: Bool

    init() {
        pickKey = ""; statusRaws = []; platform = nil; includeCompleted = false
    }

    init(pickKey: String, statusRaws: [String], platform: String?, includeCompleted: Bool) {
        self.pickKey = pickKey
        self.statusRaws = statusRaws
        self.platform = platform
        self.includeCompleted = includeCompleted
    }

    func perform() async throws -> some IntentResult {
        let pool = WidgetPoolGame.filter(
            WidgetSnapshot.load()?.shufflePool ?? [],
            statuses: Set(statusRaws),
            platform: platform,
            includeCompleted: includeCompleted)
        let current = ShufflePicks.stored(for: pickKey)
        // Never re-roll the same game when there's a choice — a die that
        // repeats itself feels broken even when it's fair.
        let candidates = pool.count > 1 ? pool.filter { $0.id != current } : pool
        if let next = candidates.randomElement() {
            ShufflePicks.store(next.id, for: pickKey)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "Shuffler")
        return .result()
    }
}

// MARK: - Timeline

struct ShufflerEntry: TimelineEntry {
    let date: Date
    let config: ShufflerConfigIntent
    let pick: WidgetPoolGame?
    let poolCount: Int
}

struct ShufflerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShufflerEntry {
        ShufflerEntry(date: .now, config: ShufflerConfigIntent(), pick: nil, poolCount: 0)
    }

    func snapshot(for configuration: ShufflerConfigIntent, in context: Context) async -> ShufflerEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: ShufflerConfigIntent, in context: Context) async -> Timeline<ShufflerEntry> {
        // No refresh policy churn: the pick only changes when the die is
        // tapped or the pool no longer contains it. Reload on the hour keeps
        // pool counts honest as the library changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry(for: configuration)], policy: .after(next))
    }

    private func entry(for config: ShufflerConfigIntent) -> ShufflerEntry {
        let snapshot = WidgetSnapshot.load()
        let pool = WidgetPoolGame.filter(
            snapshot?.shufflePool ?? [],
            statuses: config.statusRaws,
            platform: config.platformFilter,
            includeCompleted: config.includeCompleted)
        return ShufflerEntry(
            date: .now,
            config: config,
            pick: ShufflePicks.resolve(config: config, snapshot: snapshot),
            poolCount: pool.count)
    }
}

// MARK: - Views

private struct DieButton: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let config: ShufflerConfigIntent
    var size: CGFloat = 30

    var body: some View {
        Button(intent: ShuffleRollIntent(
            pickKey: config.pickKey,
            statusRaws: Array(config.statusRaws),
            platform: config.platformFilter,
            includeCompleted: config.includeCompleted)
        ) {
            Image(systemName: "dice")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(LSWidget.controlFG(renderingMode))
                .frame(width: size, height: size)
                .background(LSWidget.controlBG(renderingMode), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ShufflerSmall: View {
    let entry: ShufflerEntry

    var body: some View {
        if let pick = entry.pick {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    CoverPoster(image: loadCover(pick.coverFileName))
                        .frame(width: 60, height: 82)
                    Spacer(minLength: 0)
                    DieButton(config: entry.config)
                }
                Spacer(minLength: 0)
                Text(pick.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("Play this · \(pick.platform)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(LSWidget.torch)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(WidgetShared.gameURL(pick.id))
        } else {
            EmptyShuffle(config: entry.config)
        }
    }
}

struct ShufflerMedium: View {
    let entry: ShufflerEntry

    var body: some View {
        if let pick = entry.pick {
            HStack(spacing: 12) {
                CoverPoster(image: loadCover(pick.coverFileName))
                    .frame(width: 74, height: 101)
                VStack(alignment: .leading, spacing: 3) {
                    Text("PLAY THIS")
                        .font(.system(size: 9, weight: .bold)).tracking(0.8)
                        .foregroundStyle(LSWidget.torch)
                    Text(pick.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitle(pick))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    HStack {
                        Text(entry.poolCount > 1
                             ? "1 of \(entry.poolCount) it could have picked"
                             : "the only one that qualifies")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        DieButton(config: entry.config, size: 34)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(2)
            .widgetURL(WidgetShared.gameURL(pick.id))
        } else {
            EmptyShuffle(config: entry.config)
        }
    }

    private func subtitle(_ pick: WidgetPoolGame) -> String {
        let status = ShuffleStatusOption.allCases
            .first { $0.statusRaw == pick.statusRaw }
            .map { ShuffleStatusOption.caseDisplayRepresentations[$0]?.title ?? "" }
        let statusText = pick.statusRaw == "completed" ? "Finished — replay it"
            : status.map(String.init(localized:)) ?? pick.statusRaw.capitalized
        return "\(statusText) · \(pick.platform)"
    }
}

private struct EmptyShuffle: View {
    let config: ShufflerConfigIntent

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "dice")
                .font(.system(size: 22))
                .foregroundStyle(LSWidget.accent)
            Text("Nothing to pick from")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Loosen the statuses or system in this widget's settings.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .widgetURL(WidgetShared.homeURL)
    }
}

struct ShufflerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShufflerEntry

    var body: some View {
        switch family {
        case .systemSmall: ShufflerSmall(entry: entry)
        default: ShufflerMedium(entry: entry)
        }
    }
}

// MARK: - Widget

struct ShufflerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Shuffler",
                               intent: ShufflerConfigIntent.self,
                               provider: ShufflerProvider()) { entry in
            ShufflerWidgetView(entry: entry)
                .lsWidgetSurface()
        }
        .configurationDisplayName("Choose a Game for Me")
        .description("Picks something off your shelf and stands by it until you roll again. Configure which statuses and system it may pick from.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
