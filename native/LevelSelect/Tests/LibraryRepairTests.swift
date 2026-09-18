import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// `LibraryRepair` against small in-memory libraries. The 09-17 plan itself is
/// checked by `appliesARealPlan` only when `LS_REPAIR_DIR` points at a copy
/// of the damaged store and the plan (personal data, never committed).
@MainActor
struct LibraryRepairTests {

    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: LevelSelectSchemaV3.self)
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                                cloudKitDatabase: .none)])
    }

    private func plan(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test("Hides what the plan names, restores fields, and stamps both newer")
    func hidesAndRestores() throws {
        let context = ModelContext(try container())
        let real = Game(name: "Skyrim")
        let junk = Game(name: "Active Test")
        let state = TrackerStateRecord(itemID: "boss")
        context.insert(real); context.insert(junk); context.insert(state)
        let old = Date(timeIntervalSince1970: 0)
        real.updatedAt = old; junk.updatedAt = old; state.updatedAt = old
        try context.save()

        let now = Date(timeIntervalSince1970: 1_000_000)
        let outcome = try LibraryRepair.apply(plan: plan([
            "hide": ["Game": [junk.id.uuidString]],
            "set": [
                "Game": [real.id.uuidString: [
                    "deletedAt": "2026-09-09T01:12:13.826Z",
                    "ownership": ["physical"],
                    "rating": 5,
                    "status": "completed",
                    "wikidataID": NSNull(),
                ]],
                "TrackerStateRecord": [state.id.uuidString: [
                    "completed": true, "completedAt": "2026-09-01T00:00:00Z",
                ]],
            ],
        ]), context: context, at: now)

        #expect(outcome.hidden == 1 && outcome.updated == 2)
        #expect(outcome.missing.isEmpty && outcome.unknownFields.isEmpty)
        #expect(junk.deletedAt == now && junk.updatedAt == now)
        #expect(real.deletedAt != nil && real.ownership == ["physical"] && real.rating == 5)
        #expect(real.status == .completed && real.updatedAt == now && real.revision == 1)
        #expect(state.completed && state.completedAt != nil && state.updatedAt == now)
    }

    @Test("A schema moved to another game goes back, and the theme and handles return")
    func relationshipsAndSingletons() throws {
        let context = ModelContext(try container())
        let game = Game(name: "Hollow Knight")
        let impostor = Game(name: "Hollow Knight")
        let schema = TrackerSchemaRecord()
        let theme = ThemeSettings()
        let profile = PlayerProfile()
        [game, impostor].forEach(context.insert)
        context.insert(schema); context.insert(theme); context.insert(profile)
        schema.game = impostor
        theme.appearanceRaw = "light"
        try context.save()

        let handles = Data("six handles".utf8)
        let outcome = try LibraryRepair.apply(plan: plan([
            "hide": ["Game": [impostor.id.uuidString]],
            "set": ["Game": [game.id.uuidString: ["trackerSchemaID": schema.id.uuidString]]],
            "theme": ["ZAPPEARANCERAW": "dark", "ZPALETTELINKED": 0, "ZHOMESYSTEMSRAW": "sort=custom,Switch 2"],
            "profile": ["ZHANDLESDATA": handles.base64EncodedString()],
        ]), context: context)

        #expect(outcome.unknownFields.isEmpty)
        #expect(game.trackerSchema?.id == schema.id)
        #expect(impostor.trackerSchema == nil)
        #expect(theme.appearanceRaw == "dark" && !theme.paletteLinked)
        #expect(theme.homeSystemsRaw == "sort=custom,Switch 2")
        #expect(profile.handlesData == handles)
    }

    @Test("An id the library doesn't have is reported, not invented")
    func missingIsReported() throws {
        let context = ModelContext(try container())
        let outcome = try LibraryRepair.apply(plan: plan([
            "hide": ["Session": [UUID().uuidString]],
            "set": ["Game": [UUID().uuidString: ["rating": 3]]],
        ]), context: context)
        #expect(outcome.missing.count == 2)
        #expect(throws: LibraryRepair.RepairError.self) {
            try LibraryRepair.apply(plan: Data("{}".utf8), context: context)
        }
    }

    /// Opens `$LS_REPAIR_DIR/work/default.store` (a copy of the damaged store),
    /// applies `$LS_REPAIR_DIR/repair-plan.json`, and saves, so the result can
    /// be compared with the pre-damage copy outside the test.
    @Test("The 09-17 plan applies cleanly to a copy of the damaged store")
    func appliesARealPlan() throws {
        guard let dir = ProcessInfo.processInfo.environment["LS_REPAIR_DIR"] else { return }
        let base = URL(filePath: dir)
        let schema = Schema(versionedSchema: LevelSelectSchemaV3.self)
        let store = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, url: base.appending(path: "work/default.store"),
                cloudKitDatabase: .none)])
        let data = try Data(contentsOf: base.appending(path: "repair-plan.json"))
        let outcome = try LibraryRepair.apply(plan: data, context: ModelContext(store))
        try outcome.summary.write(to: base.appending(path: "work/outcome.txt"), atomically: true, encoding: .utf8)
        #expect(outcome.missing.isEmpty, "\(outcome.missing)")
        #expect(outcome.unknownFields.isEmpty, "\(outcome.unknownFields)")
    }
}
