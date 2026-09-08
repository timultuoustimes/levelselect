import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Smart collections: a rule instead of a list.
@MainActor
struct SmartCollectionRuleTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @Test("The rule round-trips through its stored form")
    func roundTrip() {
        let rule = SmartCollectionRule(status: .backlog, system: "SNES", ownership: .kind(.physical), tag: "metroidvania")
        let back = SmartCollectionRule.parse(rule.raw)
        #expect(back == rule)
        #expect(SmartCollectionRule.parse("") == nil)
        #expect(SmartCollectionRule.parse("status=nonsense") == nil)
        #expect(SmartCollectionRule.parse("ownership=unset")?.ownership == .unset)
    }

    @Test("A smart collection's members are whatever matches, and change with the games")
    func membersFollowTheRule() {
        let repo = store()
        let a = repo.addGame(name: "Super Metroid", status: .backlog)
        let b = repo.addGame(name: "Hades", status: .playing)
        let collection = repo.createSmartCollection(name: "Backlog", rule: SmartCollectionRule(status: .backlog))
        #expect(collection.isSmart)
        #expect(collection.members(in: [a, b]).map(\.name) == ["Super Metroid"])
        b.status = .backlog
        #expect(collection.members(in: [a, b]).count == 2)
        // A wishlisted game is not in your library, whatever the rule says.
        a.status = .wishlist
        #expect(collection.members(in: [a, b]).map(\.name) == ["Hades"])
    }

    @Test("A hand-picked collection still reads its list")
    func listCollectionsUnchanged() {
        let repo = store()
        let a = repo.addGame(name: "Celeste", status: .playing)
        let c = repo.createCollection(name: "One Sitting")
        repo.setMembership(c, game: a, member: true)
        #expect(!c.isSmart)
        #expect(c.members(in: [a]).map(\.name) == ["Celeste"])
    }
}

/// Maps: a picture with pins on it, and a pin that ticks.
@MainActor
struct Build38MapsTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    /// A real, tiny PNG so ingest has something to read.
    private var png: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
    }

    @Test("A map is a picture with the map role, and the map record points at it")
    func mapIsAPicture() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world, sourceURL: "https://hollowknight.wiki/x.png")
        #expect(map.storageType == Repository.mapImageStorageType)
        let image = repo.image(for: map)
        #expect(image?.role == .map)
        #expect(image?.id.uuidString == map.remoteStoragePath)
        #expect(map.remoteURLString == "https://hollowknight.wiki/x.png")
        // Not a gallery picture: Media leaves it alone.
        #expect(game.liveImages.filter { $0.role != .map }.isEmpty)
        #expect(repo.liveMaps(of: game).count == 1)
    }

    @Test("An unlinked pin keeps its own explored stamp")
    func unlinkedPinExplored() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        let pin = repo.addMarker(to: map, x: 0.25, y: 0.75, category: .secret, label: "Hidden wall")
        #expect(!repo.isExplored(pin, states: [:]))
        repo.setExplored(pin, true, in: game)
        #expect(pin.exploredAt != nil)
        #expect(repo.isExplored(pin, states: [:]))
        repo.setExplored(pin, false, in: game)
        #expect(pin.exploredAt == nil)
    }

    @Test("A linked pin shows the item's state, and ticking the pin ticks the item")
    func linkedPinTicksTheItem() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        let pin = repo.addMarker(to: map, x: 0.5, y: 0.5, category: .collectible,
                                 label: "Crystal Heart", linkedTrackerItemID: "crystal-heart")

        func states() -> [String: TrackerStateRecord] {
            Dictionary((pt.trackerStates ?? []).filter { $0.deletedAt == nil }.map { ($0.itemID, $0) },
                       uniquingKeysWith: { a, _ in a })
        }
        #expect(!repo.isExplored(pin, states: states()))
        repo.setExplored(pin, true, in: game)
        #expect(states()["crystal-heart"]?.completed == true)
        #expect(repo.isExplored(pin, states: states()))
        // The pin itself carries no stamp — one record, not two.
        #expect(pin.exploredAt == nil)
        #expect(repo.linkedMarkers(in: game)["crystal-heart"]?.id == pin.id)
    }

    @Test("Coordinates are clamped to the map")
    func clamped() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        let pin = repo.addMarker(to: map, x: 1.7, y: -0.2)
        #expect(pin.normalizedX == 1 && pin.normalizedY == 0)
    }

    @Test("Deleting a map takes its picture to the trash with it; markers stay attached")
    func deleteMapIsSoft() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        _ = repo.addMarker(to: map, x: 0.5, y: 0.5)
        let image = try #require(repo.image(for: map))
        repo.deleteMap(map)
        #expect(map.deletedAt != nil)
        #expect(image.deletedAt != nil)
        #expect(repo.liveMaps(of: game).isEmpty)
        #expect(repo.trashedImages().contains { $0.id == image.id })
    }

    @Test("A pin's explored stamp survives export and import")
    func exploredExports() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        let pin = repo.addMarker(to: map, x: 0.5, y: 0.5, label: "Bench")
        repo.setExplored(pin, true, in: game)
        let data = try LibraryExport.makeJSON(context: repo.context)

        let fresh = store()
        _ = try LibraryImport.apply(data: data, context: fresh.context)
        let imported = try fresh.context.fetch(FetchDescriptor<Marker>())
        #expect(imported.count == 1)
        #expect(imported.first?.exploredAt != nil)
        #expect(imported.first?.label == "Bench")
    }
}

/// A map and its picture leave together and come back together.
@MainActor
struct Build38MapTrashTests {
    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }
    private var png: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
    }

    @Test("Restoring a map's picture restores the map, pins and all")
    func restoreBringsTheMapBack() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        _ = repo.addMarker(to: map, x: 0.5, y: 0.5, label: "Bench")
        let image = try #require(repo.image(for: map))
        repo.deleteMap(map)
        #expect(repo.liveMaps(of: game).isEmpty)
        repo.restore(image)
        #expect(map.deletedAt == nil)
        #expect(repo.liveMaps(of: game).count == 1)
        #expect(repo.liveMarkers(of: map).count == 1)
    }

    @Test("Delete Forever on a map's picture removes the map record too")
    func deleteForeverTakesTheMap() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        let image = try #require(repo.image(for: map))
        repo.deleteMap(map)
        repo.deleteForever(image)
        #expect(((try? repo.context.fetch(FetchDescriptor<GameMap>())) ?? []).isEmpty)
        #expect(((try? repo.context.fetch(FetchDescriptor<GameImage>())) ?? []).isEmpty)
    }

    @Test("An expired map purges with its picture")
    func expiredMapPurges() throws {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let map = try repo.addMap(to: game, data: png, name: "Hallownest", kind: .world)
        repo.deleteMap(map, at: .now.addingTimeInterval(-Repository.trashRetention - 60))
        #expect(repo.purgeExpiredTrash() == 2)
        #expect(((try? repo.context.fetch(FetchDescriptor<GameMap>())) ?? []).isEmpty)
    }
}

/// Wikidata's series fills the blank IGDB left, and finds siblings by it.
@MainActor
struct Build38SeriesHintTests {
    @Test("A series name from a second source finds games that carry it as a franchise")
    func namedSeriesFindsSiblings() {
        let repo = Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
        let hollow = repo.addGame(name: "Hollow Knight", status: .playing)       // IGDB gave it no franchise
        let silksong = repo.addGame(name: "Hollow Knight: Silksong", status: .queued)
        silksong.franchise = "Hollow Knight"
        let other = repo.addGame(name: "Celeste", status: .completed)
        other.franchise = "Celeste"
        #expect(RelatedGames.sameFranchise(as: hollow, in: [hollow, silksong, other]).isEmpty)
        let named = RelatedGames.sameFranchise(as: hollow, named: "Hollow Knight", in: [hollow, silksong, other])
        #expect(named.map(\.name) == ["Hollow Knight: Silksong"])
        #expect(RelatedGames.sameFranchise(as: hollow, named: nil, in: [hollow, silksong]).isEmpty)
    }
}
