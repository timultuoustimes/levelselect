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
    @MainActor
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: LevelSelectSchemaV1.self)
        let config: ModelConfiguration = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: LevelSelectMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
