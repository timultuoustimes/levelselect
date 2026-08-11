import Testing
import Foundation
import SwiftData
@testable import LevelSelect

@MainActor
struct LegacyImporterTests {

    private func newContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private func game(_ ctx: ModelContext, legacyID: String) throws -> Game {
        try #require(
            try ctx.fetch(FetchDescriptor<Game>(predicate: #Predicate { $0.legacyID == legacyID })).first
        )
    }

    @Test func importsExpectedCounts() throws {
        let ctx = newContext()
        let report = try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        #expect(report.alreadyImported == false)
        #expect(report.games == 4)
        #expect(report.playthroughs == 4)
        #expect(report.sessions == 3)          // 2 + 0 + 0 + 1 (active deduped)
        #expect(report.completionEvents == 1)
        #expect(report.maps == 1)
        #expect(report.markers == 1)
        #expect(report.trackerSchemas == 1)    // only g-obj has structuredData
        #expect(report.skipped.isEmpty)
    }

    @Test func normalizesMarkerCoordinatesTo01() throws {
        let ctx = newContext()
        try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        let marker = try #require(try ctx.fetch(FetchDescriptor<Marker>()).first)
        #expect(abs(marker.normalizedX - 0.4315) < 0.001)
        #expect(abs(marker.normalizedY - 0.6136) < 0.001)
        #expect(marker.category == .warning)
    }

    @Test func consolidatesRatingFromUserRatingOrSave() throws {
        let ctx = newContext()
        try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        #expect(try game(ctx, legacyID: "g-none").rating == 5)    // userRating
        #expect(try game(ctx, legacyID: "g-obj").rating == 5)     // userRating
        #expect(try game(ctx, legacyID: "g-active").rating == 4)  // save-level fallback
        #expect(try game(ctx, legacyID: "g-run").rating == nil)   // neither
    }

    @Test func parsesIgdbIDAsIntOrString() throws {
        let ctx = newContext()
        try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        #expect(try game(ctx, legacyID: "g-none").igdbID == 111)  // number
        #expect(try game(ctx, legacyID: "g-obj").igdbID == 222)   // string "222"
    }

    @Test func completedGameHasStatusAndEvent() throws {
        let ctx = newContext()
        try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        let g = try game(ctx, legacyID: "g-none")
        #expect(g.status == .completed)
        #expect((g.completionEvents ?? []).count == 1)
    }

    @Test func importsItemStateAsTrackerRecords() throws {
        let ctx = newContext()
        let report = try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        #expect(report.trackerStates == 1)
        let g = try game(ctx, legacyID: "g-obj")
        let pt = try #require((g.playthroughs ?? []).first)
        let state = try #require((pt.trackerStates ?? []).first { $0.itemID == "i1" })
        #expect(state.completed == true)
    }

    @Test func syncTrackerProgressBackfillsExistingLibrary() throws {
        let ctx = newContext()
        let importer = LegacyImporter(ctx)
        try importer.import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        // Wipe the imported state to simulate a library imported before
        // itemState support existed, then backfill.
        for state in try ctx.fetch(FetchDescriptor<TrackerStateRecord>()) {
            ctx.delete(state)
        }
        let n = try importer.syncTrackerProgress(data: SyntheticFixture.data)
        #expect(n == 1)
        let g = try game(ctx, legacyID: "g-obj")
        let pt = try #require((g.playthroughs ?? []).first)
        #expect((pt.trackerStates ?? []).contains { $0.itemID == "i1" && $0.completed })
    }

    @Test func trackerSchemaEngineAndSource() throws {
        let ctx = newContext()
        try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        let schema = try #require(try game(ctx, legacyID: "g-obj").trackerSchema)
        #expect(schema.engine == .objective)
        #expect(schema.source == .aiGenerated)     // generatedBy "claude"
        #expect(schema.jsonData.isEmpty == false)
        let decoded = try JSONSerialization.jsonObject(with: schema.jsonData) as? [String: Any]
        #expect((decoded?["categories"] as? [Any])?.count == 1)
    }

    @Test func activeSessionImportedAsPaused() throws {
        let ctx = newContext()
        try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        let g = try game(ctx, legacyID: "g-active")
        let pt = try #require((g.playthroughs ?? []).first)
        let s = try #require((pt.sessions ?? []).first)
        #expect(s.state == .paused)
        #expect(abs(s.accumulatedDuration - 120) < 0.001)
        #expect(pt.activeSession?.id == s.id)      // paused counts as active
    }

    @Test func manualSessionFlagPreserved() throws {
        let ctx = newContext()
        try LegacyImporter(ctx).import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        let g = try game(ctx, legacyID: "g-none")
        let pt = try #require((g.playthroughs ?? []).first)
        #expect((pt.sessions ?? []).contains { $0.isManual })
        #expect(abs(pt.totalPlaytime() - 5400) < 0.001)   // 3600 + 1800, both stopped
    }

    @Test func secondImportIsIdempotentNoOp() throws {
        let ctx = newContext()
        let importer = LegacyImporter(ctx)
        try importer.import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        let second = try importer.import(data: SyntheticFixture.data, sourceDeviceID: "dev-1")
        #expect(second.alreadyImported == true)
        #expect(second.games == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Game>()) == 4)   // not duplicated
        #expect(try ctx.fetchCount(FetchDescriptor<MigrationReceipt>()) == 1)
    }
}
