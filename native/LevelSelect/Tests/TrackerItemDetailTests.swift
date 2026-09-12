import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Schema V2, option 1: the user's own note and rename move OUT of the tracker
/// blob into per-item records.
///
/// The failure being fixed is round 1's finding 1 — a tracker's structure and
/// everything the user wrote about it shared one CloudKit value, so two
/// devices annotating different items meant one device's whole blob won and
/// the other's sentence was gone. These tests build that shape directly: two
/// records for two different items, as sync would deliver them, and assert
/// both survive.
@MainActor
struct TrackerItemDetailTests {

    private func game(named name: String) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    private func schema(_ items: [(String, String)]) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "bosses", "name": "Bosses", "type": "checklist",
                            "items": items.map { ["id": $0.0, "name": $0.1] }]],
        ])
    }

    private func item(_ repo: Repository, _ game: Game, _ id: String) -> TrackerItemDTO? {
        repo.trackerCategories(for: game).flatMap(\.items).first { $0.id == id }
    }

    /// THE point of the exercise: notes on two different items, written on two
    /// devices, both survive. Under the old blob-only storage one whole
    /// jsonData value won and the other note was destroyed.
    @Test func notesOnDifferentItemsBothSurvive() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ("hornet", "Hornet"), ("grimm", "Grimm"),
        ]), mode: .addAll)

        // This device annotates one boss…
        _ = repo.editTrackerItem(game, categoryID: "bosses", itemID: "hornet",
                                 name: nil, location: nil, note: "dash to dodge")
        // …the other device annotates a different one; its record arrives via
        // sync as an independent insert, which is exactly what a per-item
        // record buys.
        let synced = TrackerItemDetail(itemID: "grimm", note: "bring soul catcher")
        repo.context.insert(synced)
        synced.game = game

        #expect(item(repo, game, "hornet")?.note == "dash to dodge")
        #expect(item(repo, game, "grimm")?.note == "bring soul catcher")
    }

    /// A rename shows through the same overlay, and keeps the name it arrived
    /// with so the merge engine can still match the item next time.
    @Test func renameShowsThroughAndKeepsItsAnchor() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([("hornet", "Hornet")]),
                                  mode: .addAll)

        _ = repo.editTrackerItem(game, categoryID: "bosses", itemID: "hornet",
                                 name: "Hornet (Greenpath)", location: nil, note: nil)

        #expect(item(repo, game, "hornet")?.name == "Hornet (Greenpath)")
        #expect(item(repo, game, "hornet")?.sourceName == "Hornet")
        #expect(repo.trackerItemDetail(game, itemID: "hornet")?.chosenName == "Hornet (Greenpath)")
    }

    /// The record is authoritative. A blob whose copy of the note is stale —
    /// which is what happens after another device edits the record and this
    /// device's blob loses a last-writer-wins race — must not win the read.
    @Test func theRecordWinsOverAStaleBlobCopy() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([("hornet", "Hornet")]),
                                  mode: .addAll)
        _ = repo.editTrackerItem(game, categoryID: "bosses", itemID: "hornet",
                                 name: nil, location: nil, note: "current note")

        // Simulate the blob arriving from a device that never saw the edit.
        game.trackerSchema?.jsonData = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "bosses", "name": "Bosses", "type": "checklist",
                            "items": [["id": "hornet", "name": "Hornet",
                                       "note": "stale blob note"]]]],
        ])

        #expect(item(repo, game, "hornet")?.note == "current note")
    }

    /// Edits still land in the blob too, because a build that predates V2 can
    /// only read notes from there — blanking a tester's notes to win an
    /// architecture argument is not an acceptable trade.
    @Test func editsAreAlsoWrittenToTheBlobForOlderBuilds() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([("hornet", "Hornet")]),
                                  mode: .addAll)
        _ = repo.editTrackerItem(game, categoryID: "bosses", itemID: "hornet",
                                 name: nil, location: nil, note: "visible to v1")

        let raw = TrackerSchemaJSON.categories(from: game.trackerSchema!.jsonData)
            .flatMap(\.items).first { $0.id == "hornet" }
        #expect(raw?.note == "visible to v1")
    }

    // MARK: The lift

    /// Existing notes living only in the blob are moved into records on game
    /// open, and running it again changes nothing.
    @Test func liftMovesExistingBlobNotesAndIsIdempotent() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "categories": [["id": "bosses", "name": "Bosses", "type": "checklist",
                                "items": [
                                    ["id": "hornet", "name": "Hornet", "note": "old note"],
                                    ["id": "grimm", "name": "Grimm the Renamed",
                                     "sourceName": "Grimm"],
                                    ["id": "plain", "name": "Plain"],
                                ]]],
            ]), mode: .addAll)

        #expect(repo.liftTrackerItemDetails(for: game) == 2)   // note + rename, not "plain"
        #expect(repo.trackerItemDetail(game, itemID: "hornet")?.note == "old note")
        #expect(repo.trackerItemDetail(game, itemID: "grimm")?.chosenName == "Grimm the Renamed")
        #expect(repo.trackerItemDetail(game, itemID: "grimm")?.sourceName == "Grimm")
        #expect(repo.trackerItemDetail(game, itemID: "plain") == nil)

        #expect(repo.liftTrackerItemDetails(for: game) == 0)   // idempotent
    }

    /// The lift must never overwrite a record that already exists: the record
    /// may hold a NEWER edit than the blob it would be lifted from, so
    /// "fill gaps only" is the whole safety property.
    @Test func liftNeverOverwritesAnExistingRecord() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: try! JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "categories": [["id": "bosses", "name": "Bosses", "type": "checklist",
                                "items": [["id": "hornet", "name": "Hornet",
                                           "note": "older blob note"]]]],
            ]), mode: .addAll)

        let newer = TrackerItemDetail(itemID: "hornet", note: "newer record note")
        repo.context.insert(newer)
        newer.game = game

        #expect(repo.liftTrackerItemDetails(for: game) == 0)
        #expect(item(repo, game, "hornet")?.note == "newer record note")
    }

    /// Duplicate records for one item — a sync race — resolve under the same
    /// total order as every other duplicate read in the app, so every device
    /// shows the same note rather than whichever row it happened to list first.
    @Test func duplicateRecordsResolveByLatestActionWithATieBreak() {
        let (repo, game) = self.game(named: "Hollow Knight")
        repo.applyGeneratedSchema(for: game, jsonData: schema([("hornet", "Hornet")]),
                                  mode: .addAll)
        let t = Date(timeIntervalSince1970: 1_700_000_000)

        let older = TrackerItemDetail(itemID: "hornet", note: "older")
        repo.context.insert(older); older.game = game; older.updatedAt = t
        let newer = TrackerItemDetail(itemID: "hornet", note: "newer")
        repo.context.insert(newer); newer.game = game
        newer.updatedAt = t.addingTimeInterval(60)

        #expect(item(repo, game, "hornet")?.note == "newer")
        #expect(repo.trackerItemDetail(game, itemID: "hornet")?.note == "newer")
    }
}
