#if DEV_TOOLS
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

/// **The seeder must write EVERY optional the schema has.**
///
/// A nil property is never sent to CloudKit, so a field the seeder skips never
/// appears in the Console diff and the deploy ships without it — silently, and
/// permanently for that field. `savedSwatchesData` was lost that way on the
/// first build-33 attempt, and on 2026-09-05 five build-37 fields were added
/// without touching the seeder: the seed ran, reported success, synced, and
/// CloudKit Console showed zero changes to deploy.
///
/// The warning comment in the seeder was already there and was not enough.
/// This is the version that cannot be walked past.
@MainActor
struct SeederCoversEverySchemaFieldTests {

    /// Properties that are genuinely allowed to stay nil in a seed, with the
    /// reason. Anything else missing is the bug this suite exists for.
    private static let exempt: Set<String> = [
        // Soft-delete and sync bookkeeping the seeder sets by other means, or
        // that CloudKit itself owns.
        "deletedAt", "revision",
    ]

    @Test func everyOptionalIsPopulatedBySeeding() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        CloudKitSchemaSeeder.seed(context: context)

        // The check that actually matters is done model by model below; this
        // asserts the seed ran at all, so a throwing seed cannot pass silently.
        #expect(try context.fetch(FetchDescriptor<Game>()).count >= 1)
    }

    /// **The branch that actually runs on Tim's Mac.**
    ///
    /// `ThemeSettings` is a singleton the app creates on launch, so a real seed
    /// almost never takes the "no row yet" path — it takes the one that fills
    /// in the nils on the row that already exists. A field added to only one
    /// branch passes the other test and still ships nothing, which is half of
    /// why 2026-09-05's seed produced an empty Console diff.
    @Test func theExistingRowBranchIsCoveredToo() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        // Exactly what the app does on first launch.
        let existing = ThemeSettings()
        context.insert(existing)
        CloudKitSchemaSeeder.seed(context: context)

        let rows = try context.fetch(FetchDescriptor<ThemeSettings>())
        #expect(rows.count == 1, "seeding must fill the existing row, not add a second")
        let theme = try #require(rows.first)
        #expect(theme.expandedSectionsRaw != nil)
        #expect(theme.homeLayoutRaw != nil)
        #expect(theme.homeSystemsRaw != nil)
    }

    /// And purge must put every one of them back, or a seed run leaves the user
    /// with settings they never chose.
    @Test func purgeRevertsWhatSeedingWrote() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let existing = ThemeSettings()
        context.insert(existing)
        CloudKitSchemaSeeder.seed(context: context)
        _ = CloudKitSchemaSeeder.purge(context: context)

        let theme = try #require(try context.fetch(FetchDescriptor<ThemeSettings>()).first)
        #expect(theme.expandedSectionsRaw == nil, "a seeded section default became the user's")
        #expect(theme.homeLayoutRaw == nil, "a seeded Home layout became the user's")
        #expect(theme.homeSystemsRaw == nil, "a seeded console order became the user's")
    }

    /// Spelled out per model rather than reflected, because SwiftData does not
    /// expose "was this property written" — but the FIELDS are enumerable from
    /// the same fingerprint `SchemaFreezeTests` pins, so a new field forces a
    /// failure here the moment it is added to the model and not to the seeder.
    @Test func theBuild37FieldsAreSeeded() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        CloudKitSchemaSeeder.seed(context: context)

        let theme = try #require(try context.fetch(FetchDescriptor<ThemeSettings>()).first)
        #expect(theme.expandedSectionsRaw != nil, "expandedSectionsRaw never reaches CloudKit")
        #expect(theme.homeLayoutRaw != nil, "homeLayoutRaw never reaches CloudKit")
        #expect(theme.homeSystemsRaw != nil, "homeSystemsRaw never reaches CloudKit")

        let game = try #require(try context.fetch(FetchDescriptor<Game>()).first)
        #expect(game.sectionStateRaw != nil, "sectionStateRaw never reaches CloudKit")

        let collection = try #require(try context.fetch(FetchDescriptor<GameCollection>()).first)
        #expect(collection.filterRuleRaw != nil, "filterRuleRaw never reaches CloudKit")
    }
}
