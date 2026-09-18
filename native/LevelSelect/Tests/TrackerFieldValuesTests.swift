import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// RPG rosters: a unit's class, level and party place, and any item's status,
/// recorded per playthrough with a time on every field so two devices merge
/// field by field.
@MainActor
struct TrackerFieldValuesTests {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Values round-trip through JSON, types intact")
    func roundTrip() {
        var v = TrackerFieldValues()
        v.set("class", .text("Sage"), at: t0)
        v.set("level", .number(18), at: t0)
        v.set("party", .toggle(true), at: t0)
        v.set("ring", nil, at: t0)
        v.setStatus(.inProgress, at: t0)
        let back = TrackerFieldValues(json: v.json)
        #expect(back == v)
        #expect(back.text("class") == "Sage")
        #expect(back.text("level") == "18")
        #expect(back.number("level") == 18)
        #expect(back.toggle("party"))
        #expect(back.value("ring") == nil)
        #expect(back.status == .inProgress)
        #expect(TrackerFieldValues().json == nil, "an untouched row stores nothing")
        #expect(TrackerFieldValues(json: "not json").entries.isEmpty)
    }

    @Test("Two devices' edits to different fields both survive; a later clear wins")
    func fieldByFieldMerge() {
        var phone = TrackerFieldValues()
        phone.set("class", .text("Sage"), at: t0.addingTimeInterval(10))
        phone.set("ring", .text("Marth"), at: t0)
        var pad = TrackerFieldValues()
        pad.set("level", .number(20), at: t0.addingTimeInterval(5))
        pad.set("ring", nil, at: t0.addingTimeInterval(20))
        pad.set("class", .text("Mage"), at: t0)

        let merged = phone.merged(with: pad)
        #expect(merged.text("class") == "Sage")
        #expect(merged.number("level") == 20)
        #expect(merged.value("ring") == nil, "the later clear beats the older choice")
        #expect(pad.merged(with: phone) == merged, "the answer doesn't depend on the order")
    }

    private func setup() -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Fire Emblem Engage", status: .playing)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    @Test("Fields and status are per playthrough, and a fall records where")
    func repositoryWrites() {
        let (repo, game, pt) = setup()
        repo.setTrackerField(pt, itemID: "alfred", fieldID: "class", value: .text("Avenir"))
        repo.setTrackerStatus(pt, itemID: "alfred", status: .fallen, fellIn: " Chapter 12 ")
        let values = repo.trackerState(pt, itemID: "alfred")?.fieldValues
        #expect(values?.text("class") == "Avenir")
        #expect(values?.status == .fallen)
        #expect(values?.text(TrackerFieldValues.fellInKey) == "Chapter 12")

        repo.setTrackerStatus(pt, itemID: "alfred", status: nil)
        let revived = repo.trackerState(pt, itemID: "alfred")?.fieldValues
        #expect(revived?.status == nil)
        #expect(revived?.text(TrackerFieldValues.fellInKey) == nil)

        let second = repo.addPlaythrough(to: game, named: "Maddening")
        #expect(repo.trackerState(second, itemID: "alfred")?.fieldValues.text("class") == nil)
    }

    @Test("Duplicate rows from two devices fold field by field")
    func reconcileMergesFields() {
        let (repo, game, pt) = setup()
        let context = repo.context
        let a = TrackerStateRecord(itemID: "alfred")
        var av = TrackerFieldValues(); av.set("class", .text("Avenir"), at: t0.addingTimeInterval(30))
        a.fieldValues = av
        a.updatedAt = t0.addingTimeInterval(1)
        let b = TrackerStateRecord(itemID: "alfred")
        var bv = TrackerFieldValues(); bv.set("level", .number(9), at: t0.addingTimeInterval(2))
        bv.set("class", .text("Noble"), at: t0)
        b.fieldValues = bv
        b.updatedAt = t0.addingTimeInterval(50)
        for r in [a, b] { context.insert(r); r.playthrough = pt }

        _ = repo.reconcile(game)
        let live = (pt.trackerStates ?? []).filter { $0.deletedAt == nil && $0.itemID == "alfred" }
        #expect(live.count == 1)
        #expect(live.first?.fieldValues.text("class") == "Avenir")
        #expect(live.first?.fieldValues.number("level") == 9)
        #expect(repo.progressItemIDs(for: game).contains("alfred"))
    }
}

@MainActor
struct RosterSchemaTests {
    @Test("A planned roster keeps its type, fields and party size through a fill, and your own edits through a regeneration")
    func rosterShapeSurvivesFilling() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Fire Emblem: Fortune's Weave", status: .playing)
        let fields = [TrackerFieldDTO(id: "class", name: "Class", kind: .choice, options: ["Sage"]),
                      TrackerFieldDTO(id: "party", name: "In party", kind: .toggle)]
        #expect(repo.addPlannedCategory(to: game, named: "Units", plannedCount: 40,
                                        kind: "roster", fields: fields, partySize: 14))
        var cat = try #require(TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData).first)
        #expect(cat.isRoster && cat.partySize == 14 && cat.fields == fields)
        #expect(cat.partyField?.id == "party")

        // The fill comes back as a plain checklist with no fields.
        let fill = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "units", "name": "Units", "type": "checklist",
                            "items": [["id": "alear", "name": "Alear"]]]],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: fill, mode: .replaceCategories(ids: [cat.id]))
        cat = try #require(TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
            .first { $0.name == "Units" })
        #expect(cat.items.map(\.name) == ["Alear"])
        #expect(cat.isRoster, "the roster stays a roster")
        #expect(cat.fields == fields && cat.partySize == 14)

        // You rename a field and add a unit by hand.
        #expect(repo.setListFields(game, categoryID: cat.id,
                                   fields: [TrackerFieldDTO(id: "class", name: "Job", kind: .text)] + [fields[1]]))
        let added = try #require(repo.addTrackerItem(game, categoryID: cat.id, name: "  Vander "))
        cat = try #require(TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData).first { $0.name == "Units" })
        #expect(cat.fields.first?.name == "Job")
        #expect(cat.items.last?.id == added && cat.items.last?.name == "Vander")
        #expect(repo.setListKind(game, categoryID: cat.id, kind: nil, partySize: nil))
        cat = try #require(TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData).first { $0.name == "Units" })
        #expect(!cat.isRoster && cat.partySize == nil)
    }

    @Test("Field ids never collide with the reserved status keys")
    func reservedIDsAreRefused() {
        #expect(TrackerFieldDTO(json: ["id": "_status", "name": "Hack", "type": "text"]) == nil)
        #expect(TrackerFieldDTO(json: ["id": "lvl", "name": "Level", "type": "weird"])?.kind == .text)
    }
}
