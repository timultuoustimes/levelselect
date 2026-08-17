import Testing
import Foundation
@testable import LevelSelect

/// Built from the two real checklists in Tim's vault rather than invented
/// fixtures, because the awkwardness is all in real data: markdown links inside
/// cells, count qualifiers in section headers, hyphenated names that must not
/// be split, and sections where the leading segment is a place in one and an
/// item name in the next.
struct TrackerListParserTests {

    // MARK: Markdown table — Mina the Hollower

    private let minaTable = """
    ## All Trinket Locations Checklist

    | #   | Trinket | Effect | Location | Notes |
    | --- | ------- | ------ | -------- | ----- |
    | 1 | [Lace Glove](https://www.minahollower.com/database/trinkets/lace-glove.html) | Raises Attack level by one. | Southern Outskirts / Western Wilds | Progress the Ack and Dak encounter. |
    | 2 | [Twill Weave](https://www.minahollower.com/database/trinkets/twill-weave.html) | Raises Defense level by one. | Nox's Bayou | Found in Boat Bog, south of the tower. |
    | 3 | Smelling Salts | Raises Sidearm level by one. | Eastern Heath | Frozen Pass. |
    """

    @Test func parsesAMarkdownTableIntoNamedItems() throws {
        let result = TrackerListParser.parse(minaTable, defaultCategoryName: "Trinkets")

        #expect(result.format == .markdownTable)
        #expect(result.itemCount == 3)
        let category = try #require(result.categories.first)
        #expect(category.name == "Trinkets")
        #expect(category.items.map(\.name) == ["Lace Glove", "Twill Weave", "Smelling Salts"])
    }

    /// Names in the real file are wiki links. Keeping the markup would put a
    /// URL in every tracker row.
    @Test func stripsMarkdownLinksFromCells() throws {
        let result = TrackerListParser.parse(minaTable)
        let first = try #require(result.categories.first?.items.first)

        #expect(first.name == "Lace Glove")
        #expect(!first.name.contains("http"))
    }

    /// The columns map onto real schema fields — this is what makes a pasted
    /// checklist better than a generated one.
    @Test func mapsEffectLocationAndNotesOntoTheRightFields() throws {
        let result = TrackerListParser.parse(minaTable)
        let second = try #require(result.categories.first?.items.dropFirst().first)

        #expect(second.detail == "Raises Defense level by one.")
        #expect(second.location == "Nox's Bayou")
        #expect(second.source == "Found in Boat Bog, south of the tower.")
    }

    @Test func aBareIndexColumnIsNotReportedAsUnrecognised() {
        let result = TrackerListParser.parse(minaTable)
        #expect(result.warnings.isEmpty)
    }

    @Test func unrecognisedColumnsAreReportedNotFatal() {
        let table = """
        | Item | Rarity | Location |
        | --- | --- | --- |
        | Bone Charm | Rare | Ossex |
        """
        let result = TrackerListParser.parse(table)

        #expect(result.itemCount == 1)
        #expect(result.warnings.contains { $0.contains("Rarity") })
    }

    // MARK: Sectioned list — Under the Island

    private let islandList = """
    Heart Coins (44 Required):
    1. Koala Village - Nia's Bedroom
    2. Koala Village - Cave behind M. Uscle's house.
    3. Koala Village - Trophus' 2nd Floor
    10. Kantar Lake - Chest.
    11. Windy Hills - Cliff below Betty's house

    Honey Pots (25 Required):
    51. Koala Village - Nia's Parents' Nightstand
    52. Koala Village - Grass-covered cave.
    59. Alberto's Farm - Yak Cave.

    Upgrades:
    Wallet 1 - Koala Village shop, sold for 170g.
    Wallet 2 - Phantom Grove, lower caves.
    Bombs 1 - Treasure Beach, island.

    https://steamcommunity.com/app/1583520/discussions/0/760681630846353933/
    """

    @Test func splitsHeadedSectionsIntoCategories() {
        let result = TrackerListParser.parse(islandList)

        #expect(result.format == .sectionedList)
        #expect(result.categories.map(\.name) == ["Heart Coins", "Honey Pots", "Upgrades"])
    }

    /// "(44 Required)" is metadata about the category, not part of its name.
    @Test func dropsCountQualifiersFromSectionHeaders() {
        let result = TrackerListParser.parse(islandList)
        #expect(result.categories.first?.name == "Heart Coins")
    }

    /// ⭐ The heuristic that makes this list usable. A leading segment that
    /// REPEATS is a place; one that's unique per line is the item's name.
    /// Both cases appear in the same file.
    @Test func repeatedLeadingSegmentIsReadAsALocation() throws {
        let result = TrackerListParser.parse(islandList)
        let hearts = try #require(result.categories.first { $0.name == "Heart Coins" })

        #expect(hearts.leadingSegmentIsLocation)
        #expect(hearts.items.first?.location == "Koala Village")
        #expect(hearts.items.first?.name == "Nia's Bedroom")
    }

    @Test func uniqueLeadingSegmentIsReadAsTheName() throws {
        let result = TrackerListParser.parse(islandList)
        let upgrades = try #require(result.categories.first { $0.name == "Upgrades" })

        #expect(!upgrades.leadingSegmentIsLocation)
        #expect(upgrades.items.map(\.name) == ["Wallet 1", "Wallet 2", "Bombs 1"])
        #expect(upgrades.items.first?.detail == "Koala Village shop, sold for 170g.")
    }

    @Test func skipsTrailingURLsAndBlankLines() {
        let result = TrackerListParser.parse(islandList)
        let allNames = result.categories.flatMap(\.items).map(\.name)

        #expect(!allNames.contains { $0.contains("steamcommunity") })
        #expect(result.itemCount == 11)
    }

    /// Numbering in the real file is continuous across sections (Heart Coins
    /// end at 50, Honey Pots start at 51) and has gaps. Neither should matter.
    @Test func nonContiguousNumberingIsIrrelevant() throws {
        let result = TrackerListParser.parse(islandList)
        let honey = try #require(result.categories.first { $0.name == "Honey Pots" })
        #expect(honey.items.count == 3)
    }

    // MARK: Ids

    /// Progress is keyed by item id, so a duplicate id would mean two items
    /// sharing one checkmark.
    @Test func duplicateNamesStillGetDistinctIDs() {
        let list = """
        Chests:
        1. Ossex - Chest
        2. Bone Beach - Chest
        3. Sandfalls - Chest
        """
        let result = TrackerListParser.parse(list)
        let ids = result.categories.flatMap(\.items).map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    /// Hyphenated names are everywhere in these games ("Hiku-Bird",
    /// "Key-Rex"), so only " - " with surrounding spaces may split a line.
    @Test func hyphenatedNamesAreNotSplit() throws {
        let list = """
        Items:
        1. Hiku-Bird
        2. Key-Rex
        """
        let result = TrackerListParser.parse(list)
        let names = try #require(result.categories.first?.items.map(\.name))

        #expect(names == ["Hiku-Bird", "Key-Rex"])
    }

    // MARK: Robustness

    @Test func emptyInputIsHarmless() {
        let result = TrackerListParser.parse("")
        #expect(result.isEmpty)
        #expect(result.format == .empty)
    }

    @Test func proseWithoutStructureYieldsNothingUsable() {
        let result = TrackerListParser.parse("This is just a paragraph about a game.")
        // One line, no markers — treated as a plain list of one rather than
        // silently inventing categories.
        #expect(result.itemCount <= 1)
    }

    @Test func aPlainUnheadedListStillParses() {
        let result = TrackerListParser.parse("""
        - False Knight
        - Hornet
        - Soul Master
        """, defaultCategoryName: "Bosses")

        #expect(result.format == .plainList)
        #expect(result.categories.first?.items.map(\.name) == ["False Knight", "Hornet", "Soul Master"])
    }
}
