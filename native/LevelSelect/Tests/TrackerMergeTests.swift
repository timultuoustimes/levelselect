import Testing
import Foundation
@testable import LevelSelect

/// Applying a generated tracker used to be all-or-nothing: the schema was
/// overwritten wholesale while progress stayed keyed by item id, so any
/// regeneration that re-slugged its ids silently stopped counting the user's
/// checkmarks. These cover the diff that makes that visible before it happens,
/// and the append-only merges that avoid it entirely.
struct TrackerMergeTests {

    // MARK: Fixtures

    private func schema(_ categories: [[String: Any]],
                        extra: [String: Any] = [:]) -> Data {
        var root: [String: Any] = ["schemaVersion": 1, "categories": categories]
        for (k, v) in extra { root[k] = v }
        return try! JSONSerialization.data(withJSONObject: root)
    }

    private func category(id: String, name: String,
                          items: [(String, String)]) -> [String: Any] {
        ["id": id, "name": name, "type": "checklist",
         "items": items.map { ["id": $0.0, "name": $0.1] }]
    }

    /// A stand-in for a typical generated tracker.
    private var bosses: [String: Any] {
        category(id: "bosses", name: "Bosses",
                 items: [("false-knight", "False Knight"),
                         ("hornet", "Hornet"),
                         ("soul-master", "Soul Master")])
    }

    // MARK: Diff

    @Test func identicalSchemasReportNoChanges() {
        let a = schema([bosses])
        let d = TrackerMerge.diff(current: a, incoming: a)
        #expect(d.isEmpty)
        #expect(d.unchangedCount == 3)
        #expect(d.strandedByReplace.isEmpty)
    }

    @Test func detectsAddedAndRemovedItems() {
        let current = schema([bosses])
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("false-knight", "False Knight"),
                                                ("hornet", "Hornet"),
                                                ("dung-defender", "Dung Defender")])])
        let d = TrackerMerge.diff(current: current, incoming: incoming)

        #expect(d.added.map(\.name) == ["Dung Defender"])
        #expect(d.removed.map(\.name) == ["Soul Master"])
        #expect(d.unchangedCount == 2)
    }

    /// The important one. A regeneration that returns the same content under
    /// freshly slugged ids must read as "nothing new", not as a total rewrite —
    /// otherwise the review screen tells the user to replace everything and the
    /// merge modes have nothing sensible to offer.
    @Test func resluggedIdsReadAsRenamesNotChurn() {
        let current = schema([bosses])
        let incoming = schema([category(id: "main-bosses", name: "Bosses",
                                        items: [("boss-false-knight", "False Knight"),
                                                ("boss-hornet", "Hornet"),
                                                ("boss-soul-master", "Soul Master")])])
        let d = TrackerMerge.diff(current: current, incoming: incoming)

        #expect(d.added.isEmpty)
        #expect(d.removed.isEmpty)
        #expect(d.renamed.count == 3)
        // Matched by name across a renamed category id, too.
        #expect(d.categories.count == 1)
        #expect(d.categories.first?.isNewCategory == false)
    }

    /// A renamed item survives Replace as content but loses its progress,
    /// because state records are keyed by the old id. That's the number worth
    /// putting in front of someone before they overwrite weeks of ticking.
    @Test func renamedItemsCarryingProgressCountAsStranded() {
        let current = schema([bosses])
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("boss-false-knight", "False Knight"),
                                                ("hornet", "Hornet")])])
        let d = TrackerMerge.diff(current: current, incoming: incoming,
                                  progressIDs: ["false-knight", "soul-master", "hornet"])

        let stranded = Set(d.strandedByReplace.map(\.id))
        // false-knight: same item, new id → progress orphans.
        // soul-master: gone entirely → progress orphans.
        // hornet: id unchanged → survives, must not be listed.
        #expect(stranded == ["false-knight", "soul-master"])
    }

    @Test func newCategoriesAreFlagged() {
        let current = schema([bosses])
        let incoming = schema([bosses,
                               category(id: "charms", name: "Charms",
                                        items: [("wayward-compass", "Wayward Compass")])])
        let d = TrackerMerge.diff(current: current, incoming: incoming)

        #expect(d.newCategories.map(\.name) == ["Charms"])
        #expect(d.added.map(\.name) == ["Wayward Compass"])
        #expect(d.removed.isEmpty)
    }

    /// Personal Goals are user-authored and every mode preserves them, so they
    /// must never appear in the diff as content about to be lost.
    @Test func personalGoalsAreNeverReportedAsRemoved() {
        let goals: [String: Any] = ["id": TrackerSchemaJSON.personalGoalsID,
                                    "name": "Personal Goals",
                                    "items": [["id": "goal-1", "name": "Beat it hitless"]]]
        let current = schema([bosses, goals])
        let incoming = schema([bosses])
        let d = TrackerMerge.diff(current: current, incoming: incoming)

        #expect(d.isEmpty)
        #expect(d.removed.isEmpty)
    }

    // MARK: Merge — addAll

    @Test func addAllKeepsExistingAndAppendsNew() {
        let current = schema([bosses])
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("dung-defender", "Dung Defender")]),
                               category(id: "charms", name: "Charms",
                                        items: [("wayward-compass", "Wayward Compass")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let cats = TrackerSchemaJSON.categories(from: out)

        let bossNames = cats.first { $0.id == "bosses" }?.items.map(\.name) ?? []
        #expect(bossNames == ["False Knight", "Hornet", "Soul Master", "Dung Defender"])
        #expect(cats.first { $0.id == "charms" }?.items.count == 1)
        // Nothing was dropped.
        #expect(cats.flatMap(\.items).count == 5)
    }

    /// Additive generation re-sends what it already produced, so merging the
    /// same payload twice must be a no-op. Without this, "Add more" doubles the
    /// tracker every time it's used.
    @Test func addAllIsIdempotent() {
        let current = schema([bosses])
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("dung-defender", "Dung Defender")])])
        let once = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let twice = TrackerMerge.merged(current: once, incoming: incoming, mode: .addAll)

        #expect(TrackerSchemaJSON.categories(from: twice).flatMap(\.items).count == 4)
        #expect(TrackerSchemaJSON.categories(from: once).flatMap(\.items).count == 4)
    }

    /// The same guard has to hold when the generator renames what it sends —
    /// matching on id alone would let a re-slugged repeat through as new.
    @Test func addAllSkipsItemsAlreadyPresentUnderAnotherID() {
        let current = schema([bosses])
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("boss-hornet", "Hornet"),
                                                ("dung-defender", "Dung Defender")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let names = TrackerSchemaJSON.categories(from: out).flatMap(\.items).map(\.name)

        #expect(names.filter { $0 == "Hornet" }.count == 1)
        #expect(names.contains("Dung Defender"))
    }

    @Test func addAllNeverRemovesAnything() {
        let current = schema([bosses])
        // Incoming is a strictly worse tracker — the regression Tim was worried
        // about. Additive modes must not let it delete anything.
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("false-knight", "False Knight")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)

        #expect(TrackerSchemaJSON.categories(from: out).flatMap(\.items).count == 3)
    }

    // MARK: Merge — selective

    @Test func addSelectedTakesOnlyTickedItems() {
        let current = schema([bosses])
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("dung-defender", "Dung Defender"),
                                                ("nosk", "Nosk")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming,
                                      mode: .add(itemIDs: ["nosk"]))
        let names = TrackerSchemaJSON.categories(from: out).flatMap(\.items).map(\.name)

        #expect(names.contains("Nosk"))
        #expect(!names.contains("Dung Defender"))
        #expect(names.count == 4)
    }

    /// Ticking nothing is the same as cancelling.
    @Test func addSelectedWithNoSelectionChangesNothing() {
        let current = schema([bosses])
        let incoming = schema([category(id: "charms", name: "Charms",
                                        items: [("wayward-compass", "Wayward Compass")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming,
                                      mode: .add(itemIDs: []))
        #expect(out == current)
    }

    /// A new category only partly accepted should arrive carrying just those
    /// items, not the whole thing.
    @Test func addSelectedCreatesNewCategoryWithOnlyItsAcceptedItems() {
        let current = schema([bosses])
        let incoming = schema([category(id: "charms", name: "Charms",
                                        items: [("wayward-compass", "Wayward Compass"),
                                                ("grimmchild", "Grimmchild")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming,
                                      mode: .add(itemIDs: ["grimmchild"]))
        let charms = TrackerSchemaJSON.categories(from: out).first { $0.id == "charms" }

        #expect(charms?.items.map(\.name) == ["Grimmchild"])
    }

    // MARK: Merge — replace

    @Test func replaceTakesIncomingButKeepsPersonalGoals() {
        let goals: [String: Any] = ["id": TrackerSchemaJSON.personalGoalsID,
                                    "name": "Personal Goals",
                                    "items": [["id": "goal-1", "name": "Beat it hitless"]]]
        let current = schema([bosses, goals])
        let incoming = schema([category(id: "charms", name: "Charms",
                                        items: [("wayward-compass", "Wayward Compass")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cats = TrackerSchemaJSON.categories(from: out)

        #expect(cats.contains { $0.id == "charms" })
        #expect(cats.contains { $0.id == TrackerSchemaJSON.personalGoalsID })
        // The old generated content is gone — that's what Replace means.
        #expect(!cats.contains { $0.id == "bosses" })
    }

    // MARK: Round-tripping

    /// The stored JSON carries fields the DTO parser doesn't surface. An
    /// additive merge rewrites the document, so it has to leave them intact.
    @Test func additiveMergePreservesUnknownFields() throws {
        let current = schema([bosses], extra: ["estimatedHours": 40,
                                               "completionNotes": "112% for true ending",
                                               "tags": ["metroidvania"]])
        let incoming = schema([category(id: "charms", name: "Charms",
                                        items: [("wayward-compass", "Wayward Compass")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let root = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])

        #expect((root["estimatedHours"] as? NSNumber)?.intValue == 40)
        #expect(root["completionNotes"] as? String == "112% for true ending")
        #expect((root["tags"] as? [String]) == ["metroidvania"])
    }

    /// Item-level extras matter too — `location`, `missable` and the rank
    /// fields all ride along inside the item dictionaries.
    @Test func additiveMergeKeepsItemDetailOnAcceptedItems() {
        let current = schema([bosses])
        let incoming = schema([["id": "charms", "name": "Charms", "type": "collectibles",
                                "items": [["id": "grimmchild", "name": "Grimmchild",
                                           "location": "Howling Cliffs", "missable": true,
                                           "maxRank": 4]]]])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let item = TrackerSchemaJSON.categories(from: out)
            .first { $0.id == "charms" }?.items.first

        #expect(item?.location == "Howling Cliffs")
        #expect(item?.missable == true)
        #expect(item?.maxRank == 4)
    }

    // MARK: Run template

    @Test func additiveAdoptsARunTemplateWhenThereIsNone() {
        let current = schema([bosses])
        let incoming = schema([bosses], extra: ["runTemplate": [
            "fields": [["id": "weapon", "label": "Weapon", "type": "text"]],
            "outcomes": ["Escaped", "Died"],
        ]])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)

        #expect(TrackerSchemaJSON.runTemplate(from: out) != nil)
    }

    /// A game with a hand-built template (Hades) must keep it — adopting one
    /// is additive, overwriting one is not.
    @Test func additiveNeverOverwritesAnExistingRunTemplate() throws {
        let current = schema([bosses], extra: ["runTemplate": [
            "fields": [["id": "aspect", "label": "Aspect", "type": "text"]],
            "outcomes": [["id": "escaped", "label": "Escaped", "result": "success"]],
        ]])
        let incoming = schema([bosses], extra: ["runTemplate": [
            "fields": [["id": "weapon", "label": "Weapon", "type": "text"]],
            "outcomes": ["Died"],
        ]])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .addAll)
        let template = try #require(TrackerSchemaJSON.runTemplate(from: out))

        #expect(template.fields.map(\.id) == ["aspect"])
    }

    // MARK: Robustness

    @Test func emptyIncomingSchemaIsHarmless() {
        let current = schema([bosses])
        let d = TrackerMerge.diff(current: current, incoming: TrackerSchemaJSON.emptySchema())
        // Everything would go under Replace — which is exactly what the review
        // screen needs to be able to say.
        #expect(d.removed.count == 3)

        let out = TrackerMerge.merged(current: current,
                                      incoming: TrackerSchemaJSON.emptySchema(), mode: .addAll)
        #expect(TrackerSchemaJSON.categories(from: out).flatMap(\.items).count == 3)
    }

    @Test func malformedIncomingLeavesTheTrackerAlone() {
        let current = schema([bosses])
        let junk = Data("not json".utf8)
        let out = TrackerMerge.merged(current: current, incoming: junk, mode: .addAll)
        #expect(TrackerSchemaJSON.categories(from: out).flatMap(\.items).count == 3)
    }

    // MARK: Renaming

    /// ⭐ The reason renaming keeps a `sourceName`. Tim renames "Stages" to
    /// "Achievements" because that's what the game calls them; the generator
    /// still returns "Stages". Without the original name to match on, the next
    /// regeneration imports a whole second copy of the category.
    @Test func renamingACategoryDoesNotCauseADuplicateOnRegeneration() throws {
        let original = schema([category(id: "stages", name: "Stages",
                                        items: [("stage-1", "Koala Village")])])
        let renamed = try #require(TrackerSchemaJSON.renaming(
            categoryID: "stages", itemID: nil, to: "Achievements", in: original))

        // The generator hasn't changed its mind about what to call it.
        let incoming = schema([category(id: "achievements-new", name: "Stages",
                                        items: [("stage-1-new", "Koala Village"),
                                                ("stage-2", "Kantar Lake")])])
        let diff = TrackerMerge.diff(current: renamed, incoming: incoming)

        #expect(diff.newCategories.isEmpty)
        #expect(diff.added.map(\.name) == ["Kantar Lake"])
    }

    @Test func renamingKeepsTheIDSoProgressIsNeverOrphaned() throws {
        let original = schema([bosses])
        let renamed = try #require(TrackerSchemaJSON.renaming(
            categoryID: "bosses", itemID: "hornet", to: "Hornet (Greenpath)", in: original))
        let items = TrackerSchemaJSON.categories(from: renamed).first?.items ?? []

        #expect(items.contains { $0.id == "hornet" && $0.name == "Hornet (Greenpath)" })
    }

    @Test func renamingAnItemDoesNotMakeARegenerationTreatItAsNew() throws {
        let original = schema([bosses])
        let renamed = try #require(TrackerSchemaJSON.renaming(
            categoryID: "bosses", itemID: "hornet", to: "Hornet (Greenpath)", in: original))
        // Generator re-slugs ids AND still calls it plain "Hornet".
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("boss-hornet", "Hornet")])])
        let diff = TrackerMerge.diff(current: renamed, incoming: incoming)

        #expect(diff.added.isEmpty)
        #expect(diff.renamed.count == 1)
    }

    /// The first rename records the original; later ones must not overwrite it,
    /// or the anchor for matching drifts away with each edit.
    @Test func repeatedRenamesKeepTheOriginalName() throws {
        var data = schema([bosses])
        data = try #require(TrackerSchemaJSON.renaming(
            categoryID: "bosses", itemID: nil, to: "Main Bosses", in: data))
        data = try #require(TrackerSchemaJSON.renaming(
            categoryID: "bosses", itemID: nil, to: "Story Bosses", in: data))

        let category = TrackerSchemaJSON.categories(from: data).first
        #expect(category?.name == "Story Bosses")
        #expect(category?.sourceName == "Bosses")
    }

    @Test func renamingToBlankIsRejected() {
        let data = schema([bosses])
        #expect(TrackerSchemaJSON.renaming(categoryID: "bosses", itemID: nil,
                                           to: "   ", in: data) == nil)
    }

    // MARK: User notes

    /// ⭐ The guarantee the whole hint-vs-note split rests on. A note the user
    /// wrote must survive the most destructive merge there is — otherwise
    /// writing one is a trap.
    @Test func userNotesSurviveAReplace() throws {
        var current = schema([bosses])
        current = try #require(TrackerSchemaJSON.editingItem(
            categoryID: "bosses", itemID: "hornet",
            note: "PIA. Get the Mothwing Cloak first.", in: current))

        // Regeneration returns the same boss under a fresh id.
        let incoming = schema([category(id: "bosses", name: "Bosses",
                                        items: [("boss-hornet", "Hornet")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let item = TrackerSchemaJSON.categories(from: out).first?.items.first

        #expect(item?.note == "PIA. Get the Mothwing Cloak first.")
    }

    /// The generator's own description is NOT sacred — that's the difference,
    /// and it's what lets regeneration stay useful.
    @Test func theGeneratorsDescriptionIsStillReplaceable() throws {
        var current = try #require(JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "bosses", "name": "Bosses",
                            "items": [["id": "hornet", "name": "Hornet",
                                       "description": "Old blurb"]]]],
        ]) as Data?)
        current = try #require(TrackerSchemaJSON.editingItem(
            categoryID: "bosses", itemID: "hornet", note: "Mine", in: current))

        let incoming = try #require(JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "bosses", "name": "Bosses",
                            "items": [["id": "hornet", "name": "Hornet",
                                       "description": "New blurb"]]]],
        ]) as Data?)
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let item = TrackerSchemaJSON.categories(from: out).first?.items.first

        #expect(item?.itemDescription == "New blurb")
        #expect(item?.note == "Mine")
    }

    @Test func editingLocationAndClearingItBothWork() throws {
        var data = schema([bosses])
        data = try #require(TrackerSchemaJSON.editingItem(
            categoryID: "bosses", itemID: "hornet", location: "Greenpath", in: data))
        #expect(TrackerSchemaJSON.categories(from: data).first?.items
            .first { $0.id == "hornet" }?.location == "Greenpath")

        data = try #require(TrackerSchemaJSON.editingItem(
            categoryID: "bosses", itemID: "hornet", location: "", in: data))
        #expect(TrackerSchemaJSON.categories(from: data).first?.items
            .first { $0.id == "hornet" }?.location == nil)
    }

    // MARK: Sub-headings in pasted lists

    /// Tim's format: `## Heart Coins` / `### Koala Village` / `- [ ] item`.
    /// The `###` becomes the items' LOCATION rather than a nested category —
    /// the schema is two levels deep and progress is keyed per item, so real
    /// nesting would ripple through the renderer, merge and progress maths for
    /// what is really a display problem.
    @Test func markdownSubHeadingsBecomeLocations() throws {
        let result = TrackerListParser.parse("""
        ## Heart Coins
        ### Koala Village
        - [ ] Nia's Bedroom
        - [ ] Cave behind M. Uscle's house.
        ### Kantar Lake
        - [ ] Chest
        """)
        let category = try #require(result.categories.first)

        #expect(result.categories.count == 1)
        #expect(category.name == "Heart Coins")
        #expect(category.items.map(\.name)
                == ["Nia's Bedroom", "Cave behind M. Uscle's house.", "Chest"])
        #expect(category.items.map(\.location)
                == ["Koala Village", "Koala Village", "Kantar Lake"])
    }

    @Test func taskCheckboxesAreStrippedFromNames() throws {
        let result = TrackerListParser.parse("""
        ## Bosses
        - [ ] False Knight
        - [x] Hornet
        """)
        #expect(result.categories.first?.items.map(\.name) == ["False Knight", "Hornet"])
    }

    // MARK: Locks

    private func lockedCategory(id: String, name: String,
                                items: [(String, String)]) -> [String: Any] {
        var cat = category(id: id, name: name, items: items)
        cat["locked"] = true
        return cat
    }

    /// The whole point of importing a checklist rather than flattening it into
    /// Personal Goals: it keeps its own structure AND survives a regeneration.
    @Test func lockedCategoriesSurviveAReplace() {
        let current = schema([bosses,
                              lockedCategory(id: "trinkets", name: "Trinkets",
                                             items: [("lace-glove", "Lace Glove"),
                                                     ("twill-weave", "Twill Weave")])])
        let incoming = schema([category(id: "charms", name: "Charms",
                                        items: [("wayward-compass", "Wayward Compass")])])
        let out = TrackerMerge.merged(current: current, incoming: incoming, mode: .replace)
        let cats = TrackerSchemaJSON.categories(from: out)

        // Generated content is gone, as Replace means — the import isn't.
        #expect(!cats.contains { $0.id == "bosses" })
        let trinkets = cats.first { $0.id == "trinkets" }
        #expect(trinkets?.items.count == 2)
    }

    /// A locked category isn't part of the comparison at all, so it must never
    /// show up in the review screen as about to be lost.
    @Test func lockedCategoriesAreNeverReportedAsRemoved() {
        let current = schema([bosses,
                              lockedCategory(id: "trinkets", name: "Trinkets",
                                             items: [("lace-glove", "Lace Glove")])])
        let incoming = schema([bosses])
        let diff = TrackerMerge.diff(current: current, incoming: incoming)

        #expect(diff.isEmpty)
        #expect(!diff.removed.contains { $0.name == "Lace Glove" })
    }

    /// An incoming schema can't smuggle content into a locked category either —
    /// locking means "leave this alone", in both directions.
    @Test func lockedCategoriesAreNotAddedTo() {
        let current = schema([lockedCategory(id: "trinkets", name: "Trinkets",
                                             items: [("lace-glove", "Lace Glove")])])
        let incoming = schema([category(id: "trinkets", name: "Trinkets",
                                        items: [("bogus", "Invented Trinket")])])
        let diff = TrackerMerge.diff(current: current, incoming: incoming)

        #expect(diff.added.isEmpty)
    }

    @Test func lockCanBeSetAndCleared() throws {
        let data = schema([bosses])
        let locked = try #require(TrackerSchemaJSON.settingLock(true, categoryID: "bosses", in: data))
        #expect(TrackerSchemaJSON.lockedCategoryIDs(in: locked) == ["bosses"])

        let unlocked = try #require(TrackerSchemaJSON.settingLock(false, categoryID: "bosses", in: locked))
        #expect(TrackerSchemaJSON.lockedCategoryIDs(in: unlocked).isEmpty)
    }

    /// Imported checklists arrive locked by default — that's what makes the
    /// import safe without flattening it into Personal Goals.
    @Test func importedSchemaArrivesLocked() {
        let parsed = TrackerListParser.parse("""
        Heart Coins:
        1. Koala Village - Nia's Bedroom
        2. Kantar Lake - Chest
        """)
        let data = TrackerListParser.schemaData(from: parsed)

        #expect(TrackerSchemaJSON.lockedCategoryIDs(in: data) == ["heart-coins"])
        #expect(TrackerSchemaJSON.categories(from: data).first?.items.count == 2)
    }

    /// The parser's location/name guess is a heuristic, so the correction has
    /// to be lossless — flipping twice returns exactly what you started with.
    @Test func flippingTheLeadingSegmentRoundTrips() throws {
        let parsed = TrackerListParser.parse("""
        Heart Coins:
        1. Koala Village - Nia's Bedroom
        2. Koala Village - Trophus' 2nd Floor
        """)
        let original = try #require(parsed.categories.first)
        #expect(original.leadingSegmentIsLocation)

        let flipped = TrackerListParser.flippingLeadingSegment(original)
        #expect(!flipped.leadingSegmentIsLocation)
        #expect(flipped.items.first?.name == "Koala Village")
        #expect(flipped.items.first?.detail == "Nia's Bedroom")
        #expect(flipped.items.first?.location == nil)

        let back = TrackerListParser.flippingLeadingSegment(flipped)
        #expect(back.items.map(\.name) == original.items.map(\.name))
        #expect(back.items.map(\.location) == original.items.map(\.location))
    }

    @Test func matchKeyCollapsesSlugsPunctuationAndCase() {
        #expect(TrackerMerge.matchKey("Boss: False Knight!") == TrackerMerge.matchKey("boss-false-knight"))
        #expect(TrackerMerge.matchKey("Pokémon") == TrackerMerge.matchKey("pokemon"))
        #expect(TrackerMerge.matchKey("  Soul   Master ") == TrackerMerge.matchKey("Soul Master"))
        #expect(TrackerMerge.matchKey("Hornet") != TrackerMerge.matchKey("Hornet Sentinel"))
    }
}
