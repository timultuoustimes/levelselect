import AppIntents
import SwiftData

/// A game exposed to Shortcuts / Siri as a pickable entity.
struct GameEntity: AppEntity, Identifiable {
    var id: String          // Game.id UUID string
    var name: String

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

    private static func entity(_ g: Game) -> GameEntity {
        GameEntity(id: g.id.uuidString, name: g.name)
    }
}
