import Foundation
import SwiftData

/// Versioned from V1 (roadmap §7f.1) so the native app never repeats the web
/// app's unversioned schema drift — even though V1 has no migration stage yet.
///
/// ⚠️ V1 IS FROZEN (2026-08-13, beta P0). Do not add/remove/rename models or
/// stored properties here — SchemaFreezeTests pins the exact shape and will
/// fail. New fields go in a LevelSelectSchemaV2 with a migration stage in
/// LevelSelectMigrationPlan.
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
            GameVideo.self,
            GameCollection.self,
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
    /// The container everything in the app process uses — app UI, notification
    /// actions, Live Activity intents.
    ///
    /// Computed rather than stored because the demo library swaps it wholesale
    /// (see `LibrarySwitcher`). Call sites don't need to care which library is
    /// open; they just want the current one.
    @MainActor
    static var shared: ModelContainer { LibrarySwitcher.shared.container }

    /// True when the container fell back to a LOCAL (non-CloudKit) store
    /// because CloudKit failed to initialize. The sync status UI surfaces
    /// this — the fallback itself must never be silent again (beta P0).
    @MainActor
    static private(set) var usingLocalFallback = false

    /// Where the demo library lives — a *separate file* from the real one.
    ///
    /// The point of a second store rather than a hidden-flag on each record:
    /// the real library isn't filtered or marked, it simply isn't open, so no
    /// filtering bug can show or delete the wrong rows. And demo records never
    /// exist in the CloudKit store at all, so they can't sync to other devices
    /// or need purging afterwards.
    @MainActor
    static var demoStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "demo.store")
    }

    @MainActor
    static func makeContainer(inMemory: Bool = false, demo: Bool = false) -> ModelContainer {
        let schema = Schema(versionedSchema: LevelSelectSchemaV1.self)
        // Never use CloudKit under XCTest (the app is the test host) or in-memory.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let memory = inMemory || underTest

        if memory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, migrationPlan: LevelSelectMigrationPlan.self, configurations: [config])
        }

        if demo {
            // Application Support isn't guaranteed to exist on iOS until
            // something creates it, and a store URL inside a missing directory
            // just fails — which would silently drop the demo library to the
            // in-memory fallback below and lose it on every relaunch.
            try? FileManager.default.createDirectory(
                at: URL.applicationSupportDirectory, withIntermediateDirectories: true)

            // Deliberately CloudKit-free. Screenshot fodder has no business in
            // anyone's iCloud, and keeping it local means switching back leaves
            // nothing behind to clean up.
            let config = ModelConfiguration(schema: schema, url: demoStoreURL,
                                            cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema,
                                                   migrationPlan: LevelSelectMigrationPlan.self,
                                                   configurations: [config]) {
                return container
            }
            // Falling back to the real library would be the one genuinely
            // dangerous outcome here — seeding demo data into it is exactly
            // what this feature exists to prevent. In-memory instead: the demo
            // is disposable by nature.
            let memoryOnly = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema,
                                       migrationPlan: LevelSelectMigrationPlan.self,
                                       configurations: [memoryOnly])
        }

        // App: SwiftData + CloudKit (`.automatic`) → automatic iCloud sync, no auth.
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, migrationPlan: LevelSelectMigrationPlan.self, configurations: [config])
        } catch {
            // Resilience: if CloudKit is unavailable, keep working from a local store.
            let local = ModelConfiguration(schema: schema)
            if let container = try? ModelContainer(for: schema, migrationPlan: LevelSelectMigrationPlan.self, configurations: [local]) {
                usingLocalFallback = true
                return container
            }
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
