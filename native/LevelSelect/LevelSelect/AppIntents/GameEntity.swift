import AppIntents
import CoreSpotlight
import SwiftData

/// A game exposed to Shortcuts / Siri as a pickable entity.
struct GameEntity: AppEntity, IndexedEntity, Identifiable {
    var id: String          // Game.id UUID string
    var name: String

    // What Spotlight shows and what Shortcuts' "Use Model" can read about a
    // game (build 39, 09-18). Filled from the library by `SpotlightIndex`.
    @Property(title: "Platform") var platform: String?
    @Property(title: "Status") var status: String?
    @Property(title: "Hours Played") var hoursPlayed: Double?
    @Property(title: "Rating") var rating: Int?
    @Property(title: "Last Played") var lastPlayed: Date?

    init(id: String, name: String, platform: String? = nil, status: String? = nil,
         hoursPlayed: Double? = nil, rating: Int? = nil, lastPlayed: Date? = nil) {
        self.id = id
        self.name = name
        self.platform = platform
        self.status = status
        self.hoursPlayed = hoursPlayed
        self.rating = rating
        self.lastPlayed = lastPlayed
    }

    /// "Switch · Playing · 12h" under the name in Spotlight.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.displayName = name
        var parts: [String] = []
        if let platform, !platform.isEmpty { parts.append(platform) }
        if let status, !status.isEmpty { parts.append(status) }
        if let hoursPlayed, hoursPlayed >= 1 { parts.append("\(Int(hoursPlayed.rounded()))h") }
        set.contentDescription = parts.joined(separator: " · ")
        set.keywords = [platform, status].compactMap { $0 }
        return set
    }

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Game")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = GameEntityQuery()
}

/// Resolves GameEntity values from the shared store (by id, by search, or the
/// full suggested list for the Shortcuts picker).
struct GameEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [GameEntity] {
        let ids = Set(identifiers.compactMap { UUID(uuidString: $0) })
        return fetchGames().filter { ids.contains($0.id) }.map(Self.entity)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GameEntity] {
        let q = string.lowercased()
        return fetchGames()
            .filter { $0.name.lowercased().contains(q) }
            .prefix(30)
            .map(Self.entity)
    }

    @MainActor
    func suggestedEntities() async throws -> [GameEntity] {
        // Most recently active first, so the picker leads with what you play.
        fetchGames()
            .sorted { key($0) > key($1) }
            .prefix(50)
            .map(Self.entity)
    }

    @MainActor
    private func fetchGames() -> [Game] {
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil })
        return (try? LevelSelectStore.shared.mainContext.fetch(descriptor)) ?? []
    }

    private func key(_ g: Game) -> Date {
        g.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? g.addedAt
    }

    @MainActor
    static func entity(_ g: Game) -> GameEntity {
        GameEntity(id: g.id.uuidString, name: g.name,
                   platform: g.platforms.first.map(PlatformKey.canonical),
                   status: g.status.label,
                   hoursPlayed: g.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() } / 3600,
                   rating: g.rating,
                   lastPlayed: g.livePlaythroughs.compactMap(\.lastPlayedAt).max())
    }
}

/// Your games in Spotlight (build 39, 09-18). Rebuilt from the library a
/// moment after it changes — `WidgetBridge.refresh` calls `schedule()` after
/// every mutation it already hears about — and replaced wholesale, so a
/// deleted game, or a switch to the demo library, never leaves a stale entry.
@MainActor
enum SpotlightIndex {
    private static var pending: Task<Void, Never>?

    static func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await rebuild()
        }
    }

    static func rebuild() async {
        let ctx = LevelSelectStore.shared.mainContext
        let games = ((try? ctx.fetch(FetchDescriptor<Game>())) ?? []).filter { $0.deletedAt == nil }
        let entities = games.map(GameEntityQuery.entity)
        let index = CSSearchableIndex.default()
        try? await index.deleteAppEntities(ofType: GameEntity.self)
        try? await index.indexAppEntities(entities)
    }
}
