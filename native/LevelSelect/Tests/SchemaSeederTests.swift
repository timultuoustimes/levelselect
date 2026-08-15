#if LEGACY_IMPORT
import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The seeder exists to make the CloudKit Development schema complete, so the
/// properties that matter are: it creates one of every model, it populates the
/// optional fields (the ones CloudKit otherwise never materializes), the rows
/// stay invisible to the app, and purge removes exactly them.
@MainActor
struct SchemaSeederTests {

    private func seeded() -> ModelContext {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        CloudKitSchemaSeeder.seed(context: context)
        return context
    }

    @Test func seedsEveryModelInSchemaV1() throws {
        let context = seeded()
        #expect(try context.fetch(FetchDescriptor<Game>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Playthrough>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Session>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Run>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TrackerStateRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TrackerSchemaRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CompletionEvent>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<GameVideo>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<GameMap>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Marker>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<GameCollection>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Profile>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MigrationReceipt>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ThemeSettings>()).count == 1)
    }

    /// The whole point: the optionals that stay nil in a real library — and so
    /// never appear in the CloudKit schema — must be non-nil here.
    @Test func populatesTheFieldsRealDataLeavesEmpty() throws {
        let context = seeded()
        let game = try #require(try context.fetch(FetchDescriptor<Game>()).first)
        #expect(game.review != nil)          // missing from the Aug-11 dev schema
        #expect(game.ownership.isEmpty == false)
        #expect(game.userID != nil)
        #expect(game.summary != nil)
        #expect(game.rating != nil)
        #expect(game.trackerDisplayRaw != nil)
        #expect(game.currentPlaythroughID != nil)

        let state = try #require(try context.fetch(FetchDescriptor<TrackerStateRecord>()).first)
        #expect(state.rank != nil)
        #expect(state.count != nil)
        #expect(state.notes != nil)

        let video = try #require(try context.fetch(FetchDescriptor<GameVideo>()).first)
        #expect(video.partsData != nil)
        #expect(video.lastWatchedAt != nil)
        #expect(video.channel != nil)

        let map = try #require(try context.fetch(FetchDescriptor<GameMap>()).first)
        #expect(map.pixelWidth != nil)
        #expect(map.localCacheURL != nil)
        #expect(map.remoteURLString != nil)

        let session = try #require(try context.fetch(FetchDescriptor<Session>()).first)
        #expect(session.resumedAt != nil)
        #expect(session.pausedAt != nil)
        #expect(session.notes != nil)

        let schema = try #require(try context.fetch(FetchDescriptor<TrackerSchemaRecord>()).first)
        #expect(schema.sourcesJSON != nil)
        #expect(schema.generatedAt != nil)
    }

    /// Seed rows must never show up in the library — every app query filters
    /// on deletedAt, so they carry a tombstone from birth.
    @Test func seedRowsAreInvisibleToTheApp() throws {
        let context = seeded()
        let visible = try context.fetch(
            FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil }))
        #expect(visible.isEmpty)
    }

    @Test func purgeRemovesExactlyTheSeedRows() throws {
        let context = seeded()
        // A real game alongside the seed data must survive.
        let real = Game(name: "Hades")
        context.insert(real)
        try context.save()

        CloudKitSchemaSeeder.purge(context: context)

        let games = try context.fetch(FetchDescriptor<Game>())
        #expect(games.count == 1)
        #expect(games.first?.name == "Hades")
        #expect(try context.fetch(FetchDescriptor<Run>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<GameCollection>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Profile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MigrationReceipt>()).isEmpty)
    }
}
#endif
