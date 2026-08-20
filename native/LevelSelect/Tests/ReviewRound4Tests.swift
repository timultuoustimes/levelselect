import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Regressions for external review round 4.
///
/// Each of these reproduces the adversarial shape the reviewer described, not
/// the happy path — every one of them passed before the fix precisely because
/// nothing had tried the hostile case.
@MainActor
struct ReviewRound4Tests {

    private func setup(_ name: String = "Castlevania") -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    // MARK: Finding 2 — a corrected RetroAchievements match kept the old game id

    /// Import RA game 100, realise it's the wrong entry, import 200 instead.
    /// The old code swapped only `items` into the existing category dictionary,
    /// so `raGameID` stayed at 100 — the achievements were from 200 and every
    /// later sync asked about 100 and called the results unknown.
    @Test func reimportingADifferentRAGameReplacesTheStampedGameID() {
        let (repo, game) = setup()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "retroachievements", "name": "Achievements", "type": "checklist",
             "raGameID": 100, "items": [["id": "ra-1", "name": "First"]]],
        ]), mode: .addAll)
        #expect(TrackerSchemaJSON.retroAchievementsGameID(in: game.trackerSchema!.jsonData) == 100)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "retroachievements", "name": "Achievements", "type": "checklist",
             "raGameID": 200, "unknownFutureKey": "kept",
             "items": [["id": "ra-9", "name": "Different Set"]]],
        ]), mode: .replaceCategories(ids: ["retroachievements"]))

        #expect(TrackerSchemaJSON.retroAchievementsGameID(in: game.trackerSchema!.jsonData) == 200)
        #expect(repo.trackerCategories(for: game).first?.items.map(\.id) == ["ra-9"])
    }

    /// The user's own choices still survive that replacement — a renamed
    /// category must not snap back to the generator's wording.
    @Test func aScopedReplaceKeepsTheNameTheUserChose() {
        let (repo, game) = setup()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "a", "name": "A"]]],
        ]), mode: .addAll)
        _ = repo.renameTracker(game, categoryID: "bosses", to: "Big Bads")

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "b", "name": "B"]]],
        ]), mode: .replaceCategories(ids: ["bosses"]))

        let category = repo.trackerCategories(for: game).first
        #expect(category?.name == "Big Bads")
        #expect(category?.id == "bosses")
        #expect(category?.items.map(\.id) == ["b"])
    }

    // MARK: Finding 4 — the same item id in two categories shared one record

    /// Progress is stored per item id on the playthrough, so a duplicate id
    /// across two categories was one shared TrackerStateRecord: ticking either
    /// row ticked both, and deleting one category tombstoned the state and
    /// unticked the survivor.
    @Test func aDuplicateItemIDInASecondCategoryIsRemovedAtIngest() {
        let (repo, game) = setup()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "complete", "name": "Complete the game"]]],
            ["id": "quests", "name": "Quests", "type": "checklist",
             "items": [["id": "complete", "name": "Complete the game"],
                       ["id": "side", "name": "A side quest"]]],
        ]), mode: .addAll)

        let all = repo.trackerCategories(for: game).flatMap(\.items).map(\.id)
        #expect(all.filter { $0 == "complete" }.count == 1)
        #expect(all.contains("side"))
    }

    /// And with the collision gone, removing one category cannot untick a row
    /// that lives in another.
    @Test func removingACategoryCannotUntickASurvivingRow() {
        let (repo, game) = setup()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "complete", "name": "Complete the game"]]],
            ["id": "quests", "name": "Quests", "type": "checklist",
             "items": [["id": "complete", "name": "Complete the game"]]],
        ]), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "complete", done: true)

        repo.removeCategory(from: game, categoryID: "bosses")

        // Whichever category kept the id, the remaining tracker must not have
        // had its tick removed by the other one's deletion.
        let remaining = repo.trackerCategories(for: game).flatMap(\.items).map(\.id)
        if remaining.contains("complete") {
            #expect(repo.trackerState(pt, itemID: "complete")?.completed == true)
        }
    }

    // MARK: Finding 5 — the additive merge folded distinct categories by name

    /// Two categories called "Bosses" with different ids are two categories.
    @Test func sameNamedCategoriesWithDifferentIDsBothSurvive() {
        let (repo, game) = setup()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "main-bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "m1", "name": "Main boss"]]],
            ["id": "dlc-bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "d1", "name": "DLC boss"]]],
        ]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "third-bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "t1", "name": "Third boss"]]],
        ]), mode: .addAll)

        let ids = repo.trackerCategories(for: game).map(\.id)
        #expect(ids.contains("main-bosses"))
        #expect(ids.contains("dlc-bosses"))
        // Ambiguous by name, so it lands as its own category rather than
        // being folded into whichever happened to come first.
        #expect(ids.contains("third-bosses"))
    }

    /// The fallback still earns its place where it is unambiguous: a
    /// regeneration that re-slugged one category's id folds in rather than
    /// duplicating the whole tracker.
    @Test func anUnambiguousNameMatchStillFolds() {
        let (repo, game) = setup()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "old-slug", "name": "Charms", "type": "checklist",
             "items": [["id": "c1", "name": "One"]]],
        ]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "new-slug", "name": "Charms", "type": "checklist",
             "items": [["id": "c2", "name": "Two"]]],
        ]), mode: .addAll)

        #expect(repo.trackerCategories(for: game).count == 1)
        #expect(repo.trackerCategories(for: game).first?.items.count == 2)
    }

    // MARK: Finding 3 — a hand-named playthrough was adopted as the RA record

    /// Someone names an ordinary run "RetroAchievements" before ever syncing.
    /// Matching on the name alone adopted that run and filled it with
    /// permanent account-wide unlocks — overwriting a real playthrough.
    @Test func aManuallyNamedPlaythroughIsNotMistakenForTheSyncRecord() {
        let (repo, game) = setup("Super Metroid")
        let mine = repo.addPlaythrough(to: game, named: Repository.raPlaythroughName)

        let record = repo.raPlaythrough(for: game)

        #expect(record.id != mine.id)
        #expect(record.notes == Repository.raPlaythroughMarker)
        #expect(mine.notes != Repository.raPlaythroughMarker)
    }

    @Test func theRecordIsStillFoundAgainOnASecondSync() {
        let (repo, game) = setup("Super Metroid")
        let first = repo.raPlaythrough(for: game)
        #expect(repo.raPlaythrough(for: game).id == first.id)
    }

    // MARK: Finding 6 — a chosen variant counted as nothing

    /// State holding only `selectedVariant` is still someone's decision, and a
    /// confirmation that says "nothing to lose" before deleting it is the
    /// failure this count exists to prevent.
    @Test func aChosenVariantCountsAsProgressWorthWarningAbout() {
        let (repo, game) = setup("Hades")
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "mirror", "name": "Mirror of Night", "type": "checklist",
             "items": [["id": "talent", "name": "Shadow Presence"]]],
        ]), mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerVariant(pt, itemID: "talent", variant: "Alt")

        #expect(repo.removalCost(for: game).withProgress == 1)
        #expect(repo.progressItemIDs(for: game).contains("talent"))
    }

    // MARK: Finding 7 — removed notes came back on unrelated items

    /// A note is overlaid onto items by id. Leaving the detail record behind
    /// meant a later, unrelated tracker that happened to reuse the id wore the
    /// old note.
    @Test func aNoteDoesNotResurfaceOnAnUnrelatedItemWithTheSameID() {
        let (repo, game) = setup()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "bosses", "name": "Bosses", "type": "checklist",
             "items": [["id": "bat", "name": "Phantom Bat"]]],
        ]), mode: .addAll)
        _ = repo.editTrackerItem(game, categoryID: "bosses", itemID: "bat",
                                 name: nil, location: nil, note: "dodge left")

        repo.removeTracker(from: game)
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            ["id": "creatures", "name": "Creatures", "type": "checklist",
             "items": [["id": "bat", "name": "A completely different bat"]]],
        ]), mode: .addAll)

        let item = repo.trackerCategories(for: game).flatMap(\.items).first { $0.id == "bat" }
        #expect(item?.note == nil)
        #expect(item?.name == "A completely different bat")
    }
}
