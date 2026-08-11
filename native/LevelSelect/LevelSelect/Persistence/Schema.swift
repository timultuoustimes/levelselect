import Foundation
import SwiftData

/// Versioned from V1 (roadmap §7f.1) so the native app never repeats the web
/// app's unversioned schema drift — even though V1 has no migration stage yet.
enum LevelSelectSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Profile.self,
            Game.self,
            Playthrough.self,
            Session.self,
            CompletionEvent.self,
            TrackerSchemaRecord.self,
            TrackerStateRecord.self,
            Run.self,
            GameMap.self,
            Marker.self,
            MigrationReceipt.self,
            ThemeSettings.self,
        ]
    }
}

enum LevelSelectMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LevelSelectSchemaV1.self]
    }
    static var stages: [MigrationStage] { [] }   // none yet; add on V2
}

/// Shared container builder.
/// - App: SwiftData + CloudKit (`.automatic`) → automatic iCloud sync, no auth.
/// - Tests/previews: in-memory, non-CloudKit, so they run headless without iCloud.
enum LevelSelectStore {
    /// Single shared container for the app process (app UI, notification
    /// actions, and Live Activity intents all use the same store).
    @MainActor
    static let shared: ModelContainer = makeContainer()

    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: LevelSelectSchemaV1.self)
        // Never use CloudKit under XCTest (the app is the test host) or in-memory.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let memory = inMemory || underTest

        if memory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, migrationPlan: LevelSelectMigrationPlan.self, configurations: [config])
        }

        // App: SwiftData + CloudKit (`.automatic`) → automatic iCloud sync, no auth.
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, migrationPlan: LevelSelectMigrationPlan.self, configurations: [config])
        } catch {
            // Resilience: if CloudKit is unavailable, keep working from a local store.
            let local = ModelConfiguration(schema: schema)
            if let container = try? ModelContainer(for: schema, migrationPlan: LevelSelectMigrationPlan.self, configurations: [local]) {
                return container
            }
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
