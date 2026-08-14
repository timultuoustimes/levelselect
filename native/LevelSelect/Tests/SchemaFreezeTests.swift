import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Beta P0: Schema V1 is FROZEN once external users have data.
///
/// This test pins V1's exact shape — every model and every stored property.
/// If it fails, you changed V1: revert the change and add it as Schema V2
/// with a migration stage in `LevelSelectMigrationPlan` instead.
@MainActor
struct SchemaFreezeTests {

    /// name → sorted stored-property names, as "Entity: a,b,c" lines.
    private static func fingerprint() -> [String] {
        let schema = Schema(versionedSchema: LevelSelectSchemaV1.self)
        return schema.entities
            .map { entity in
                let props = entity.properties.map(\.name).sorted().joined(separator: ",")
                return "\(entity.name): \(props)"
            }
            .sorted()
    }

    @Test func schemaV1VersionIsFrozen() {
        #expect(LevelSelectSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(LevelSelectMigrationPlan.schemas.count == 1,
                "Adding V2? Great — keep V1 in the plan and add a migration stage.")
    }

    @Test func schemaV1ShapeIsFrozen() {
        // Frozen 2026-08-13 — the shape of V1 as shipped through TestFlight
        // build 18. Do not edit this list to make the test pass; that is the
        // exact failure it exists to catch.
        let expected = [
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
        let actual = Self.fingerprint()
        #expect(actual == expected,
                "Schema V1 changed. V1 is frozen — move the change to Schema V2 with a migration stage.")
    }
}
