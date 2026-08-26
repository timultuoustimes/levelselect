import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Beta P0: the schema may only ever grow.
///
/// **What changed on 2026-08-19 (Schema V2), and why.** V1 was pinned by an
/// exact fingerprint of all 14 models, so that any edit to a shipped model
/// failed the suite. V2 adds fields to four of those models, which means the
/// V1 entry now resolves to the grown classes — an exact V1 fingerprint can no
/// longer be true.
///
/// The textbook fix is to snapshot all 14 V1 models as frozen copies nested in
/// the V1 namespace. That is ~1,000 lines of duplicated model code whose only
/// job is to never change — and which becomes its own drift risk the first
/// time someone edits the wrong copy. It buys a real staged migration, which
/// this store cannot use anyway: it is CloudKit-backed, so only additive
/// lightweight changes are possible at all.
///
/// So the guarantee is expressed directly instead of by proxy:
///
/// 1. `schemaOnlyEverGrows` — the V1 fingerprint stays here verbatim as the
///    historical record, and the CURRENT schema must be a strict superset of
///    it. Every model V1 shipped still exists; every property V1 shipped still
///    exists on it. Removing or renaming anything — the operations that
///    actually break migration and CloudKit — fails immediately.
/// 2. `schemaV2ShapeIsPinned` — the current shape is pinned exactly, exactly
///    as V1 was, so the next change is as deliberate as this one.
///
/// If you are adding a field: add it to the model, add it to the V2 list
/// below, and — before shipping a build that WRITES it — seed and promote the
/// CloudKit schema (see `CloudKitSchemaSeeder`). A field CloudKit has never
/// seen silently fails to sync.
@MainActor
struct SchemaFreezeTests {

    /// name → sorted stored-property names, as "Entity: a,b,c" lines.
    private static func fingerprint(_ versioned: any VersionedSchema.Type) -> [String] {
        Schema(versionedSchema: versioned).entities
            .map { entity in
                let props = entity.properties.map(\.name).sorted().joined(separator: ",")
                return "\(entity.name): \(props)"
            }
            .sorted()
    }

    /// The exact shape V1 shipped through TestFlight build 18, frozen
    /// 2026-08-13. Never edit these lines: they are the record of what is
    /// already in people's stores, and every one of these properties must
    /// still exist forever.
    private static let v1Fingerprint = [
        "CompletionEvent: createdAt,customLabel,date,deletedAt,game,id,label,legacyID,notes,platform,revision,updatedAt,userID",
        "Game: addedAt,completionEvents,coverImageID,coverURLString,createdAt,currentPlaythroughID,deletedAt,developers,firstReleaseDate,franchise,gameModes,genres,id,igdbID,igdbSlug,legacyID,maps,name,notes,ownership,pinned,platforms,playerPerspectives,playthroughs,publishers,rating,review,revision,status,summary,themes,trackerDisplayRaw,trackerSchema,updatedAt,userID,userTags,videos",
        "GameCollection: createdAt,deletedAt,gameIDs,id,isBundle,legacyID,name,notes,revision,sortIndex,updatedAt,userID",
        "GameMap: addedAt,createdAt,deletedAt,game,id,kind,legacyID,localCacheURL,markers,name,pixelHeight,pixelWidth,remoteStoragePath,remoteURLString,revision,storageType,updatedAt,userID",
        "GameVideo: channel,createdAt,deletedAt,game,groupName,id,kindRaw,lastWatchedAt,legacyID,notes,orderIndex,partsData,revision,thumbnailURL,title,updatedAt,urlString,userID,watchedPartIndex,watchedSeconds,youtubeID",
        "Marker: category,createdAt,deletedAt,id,label,legacyID,linkedTrackerItemID,map,normalizedX,normalizedY,notes,revision,updatedAt,userID",
        "MigrationReceipt: appVersion,countsJSON,id,importedAt,sourceDeviceID",
        "Playthrough: createdAt,deletedAt,game,id,lastPlayedAt,legacyID,name,notes,progressPercent,revision,runs,sessions,startedAt,trackerStates,updatedAt,userID",
        "Profile: appleUserIdentifier,createdAt,displayName,email,id,updatedAt",
        "Run: createdAt,deletedAt,endedAt,fieldsJSON,id,legacyID,notes,outcome,playthrough,revision,startedAt,templateID,updatedAt,userID",
        "Session: accumulatedDuration,createdAt,deletedAt,endDate,id,isManual,legacyID,notes,pausedAt,playthrough,resumedAt,revision,startDate,state,updatedAt,userID",
        "ThemeSettings: accentHex,createdAt,defaultTrackerDisplayRaw,pageBackgroundRaw,statusColorsData,updatedAt",
        "TrackerSchemaRecord: createdAt,deletedAt,engine,game,generatedAt,generatedBy,id,jsonData,legacyID,revision,schemaVersion,source,sourcesJSON,updatedAt,userID",
        "TrackerStateRecord: completed,count,createdAt,deletedAt,id,itemID,legacyID,notes,playthrough,rank,revealed,revision,updatedAt,userID",
    ]

    @Test func schemaVersionsAreDeclared() {
        #expect(LevelSelectSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(LevelSelectSchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
        #expect(LevelSelectMigrationPlan.schemas.count == 2,
                "Adding V3? Record it here too — this list is the written history of the shape.")
    }

    /// An existing store must still open after the schema grows.
    ///
    /// This is the shape of the bug that took King Kai down on 2026-08-19: a
    /// staged `SchemaMigrationPlan` could not identify the model already on
    /// disk and refused to open the store, which is fatal at launch. The
    /// in-memory suite cannot reproduce it — every test store is born at the
    /// current schema — so this asserts the property that made the crash
    /// possible: the container must open a FILE-backed store with no
    /// migration plan involved, twice, the second time against a store the
    /// first run created.
    @Test func aFileBackedStoreReopensWithTheCurrentSchema() throws {
        let dir = URL.temporaryDirectory.appending(path: "ls-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "reopen.store")
        let schema = Schema(versionedSchema: LevelSelectSchemaV2.self)

        let first = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(first)
        context.insert(Game(name: "Reopen me"))
        try context.save()

        // Reopening is where a migration plan would be consulted.
        let second = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let games = try ModelContext(second).fetch(FetchDescriptor<Game>())
        #expect(games.map(\.name) == ["Reopen me"])
    }

    /// Nothing V1 shipped may ever disappear or be renamed — the two things
    /// that break a CloudKit-backed lightweight migration, and the reason
    /// people's existing libraries keep opening.
    @Test func schemaOnlyEverGrows() {
        var current: [String: Set<String>] = [:]
        for line in Self.fingerprint(LevelSelectSchemaV2.self) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            current[parts[0]] = Set(parts[1].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            })
        }

        for line in Self.v1Fingerprint {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            let entity = parts[0]
            let properties = Set(parts[1].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            })
            guard let currentProps = current[entity] else {
                Issue.record("Model '\(entity)' shipped in V1 and is gone. Nothing may be removed.")
                continue
            }
            let missing = properties.subtracting(currentProps).sorted()
            #expect(missing.isEmpty,
                    "'\(entity)' lost V1 properties \(missing). Removing or renaming breaks migration for every existing library — add a new property instead.")
        }
    }

    /// The current shape, pinned exactly. Changing it means changing this list
    /// deliberately — and promoting the CloudKit schema before shipping.
    @Test func schemaV2ShapeIsPinned() {
        let expected = [
            // datePrecision + playthrough added 2026-08-26 (fuzzy beaten
            // dates; the run a beaten moment capped). One seed-and-promote
            // covers both before any build that writes them ships.
            "CompletionEvent: createdAt,customLabel,date,datePrecision,deletedAt,game,id,label,legacyID,notes,platform,playthrough,revision,updatedAt,userID",
            "EarnedBadge: badgeID,createdAt,deletedAt,detailJSON,earnedAt,gameID,id,legacyID,revision,updatedAt,userID",
            "Game: addedAt,completionEvents,coverImageID,coverOverrideURLString,coverURLString,createdAt,currentPlaythroughID,deletedAt,developers,firstReleaseDate,franchise,gameModes,genres,id,igdbID,igdbSlug,legacyID,maps,name,notes,ownership,pinned,platforms,playerPerspectives,playthroughs,publishers,rating,review,revision,status,summary,themes,trackerDisplayRaw,trackerItemDetails,trackerSchema,updatedAt,userID,userTags,videos",
            "GameCollection: createdAt,deletedAt,gameIDs,id,isBundle,legacyID,name,notes,revision,sortIndex,updatedAt,userID",
            "GameMap: addedAt,createdAt,deletedAt,game,id,kind,legacyID,localCacheURL,markers,name,pixelHeight,pixelWidth,remoteStoragePath,remoteURLString,revision,storageType,updatedAt,userID",
            "GameVideo: channel,createdAt,deletedAt,game,groupName,id,kindRaw,lastWatchedAt,legacyID,notes,orderIndex,partsData,revision,thumbnailURL,title,updatedAt,urlString,userID,watchedPartIndex,watchedSeconds,youtubeID",
            "Marker: category,createdAt,deletedAt,id,label,legacyID,linkedTrackerItemID,map,normalizedX,normalizedY,notes,revision,updatedAt,userID",
            "MigrationReceipt: appVersion,countsJSON,id,importedAt,sourceDeviceID",
            "Playthrough: completionEvents,createdAt,deletedAt,game,id,lastPlayedAt,legacyID,name,notes,progressPercent,revision,runs,sessions,startedAt,trackerStates,updatedAt,userID",
            "Profile: appleUserIdentifier,createdAt,displayName,email,id,updatedAt",
            "Run: createdAt,deletedAt,endedAt,fieldsJSON,id,legacyID,notes,outcome,playthrough,revision,startedAt,templateID,updatedAt,userID",
            "Session: accumulatedDuration,createdAt,deletedAt,endDate,id,isManual,legacyID,notes,originDevice,pausedAt,playthrough,resumedAt,revision,startDate,state,updatedAt,userID",
            "ThemeSettings: accentHex,createdAt,defaultMergeModeRaw,defaultTrackerDisplayRaw,dekuWishlistURLString,overlappingTimerPolicyRaw,pageBackgroundRaw,platformIconVariantsData,showItemHints,statusColorsData,updatedAt",
            "TrackerItemDetail: chosenName,createdAt,deletedAt,game,id,itemID,legacyID,note,revision,sourceName,updatedAt,userID",
            "TrackerSchemaRecord: createdAt,deletedAt,engine,game,generatedAt,generatedBy,id,jsonData,legacyID,revision,schemaVersion,source,sourcesJSON,updatedAt,userID",
            "TrackerStateRecord: completed,count,createdAt,deletedAt,id,itemID,legacyID,notes,playthrough,rank,revealed,revision,selectedVariant,updatedAt,userID",
        ]
        #expect(Self.fingerprint(LevelSelectSchemaV2.self) == expected,
                "Schema V2 changed. Intentional? Update this list AND promote the CloudKit schema (CloudKitSchemaSeeder) before shipping a build that writes the new field.")
    }
}
