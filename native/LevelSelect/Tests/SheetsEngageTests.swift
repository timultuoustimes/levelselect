import Testing
import Foundation
@testable import LevelSelect

/// Tim's Fire Emblem Engage sheet (09-17): a Team Builder tab first, then
/// reference tabs. A link with no tab read the Team Builder and reported
/// "empty"; the unit tab took a unit whose skill is "Charmer" for its header.
struct SheetsEngageTests {

    @Test("The unit tab reads all its units, as a roster — a skill called Charmer is not a header")
    func unitsAreARoster() throws {
        let table = SheetsLinkImport.markdownTable(fromCSV: EngageSheetFixtures.units)
        #expect(table.hasPrefix("| Unit |"))
        let result = TrackerListParser.parse(table)
        let category = try #require(result.categories.first)
        #expect(category.items.count == 37)
        #expect(category.items.first?.name == "Alcryst")
        #expect(category.items.contains { $0.name == "Fogado" })
        #expect(category.kind == TrackerSchemaJSON.rosterKind)
        #expect(category.items.first?.detail?.contains("Str+3") == true,
                "the personal skill's description comes with it")
    }

    @Test("The team builder tab isn't read as a roster, and a tab with no list says so")
    func teamBuilderIsNotAList() {
        #expect(SheetsLinkImport.markdownTable(fromCSV: EngageSheetFixtures.teamBuilder).isEmpty,
                "stacked Name / Class / Emblem Ring headers are a planner")
        #expect(SheetsLinkImport.Failure.notAList.errorDescription?.contains("Pick another tab") == true)
        #expect(SheetsLinkImport.markdownTable(fromCSV: "Total,,\n,,\n12,,\n").isEmpty)
    }

    @Test("A leading blank column doesn't hide the table")
    func leadingBlankColumn() {
        let table = SheetsLinkImport.markdownTable(fromCSV: ",Name,Where\n,Sword,Cave\n,Shield,Town\n")
        #expect(table.hasPrefix("| Name | Where |"))
        #expect(TrackerListParser.parse(table).categories.first?.items.map(\.name) == ["Sword", "Shield"])
    }

    @Test("Skills group under their emblem, and Name beats Emblem as the name column")
    func skillsGroupByEmblem() throws {
        let table = SheetsLinkImport.markdownTable(fromCSV: EngageSheetFixtures.skills)
        let items = try #require(TrackerListParser.parse(table).categories.first?.items)
        #expect(items.first?.name == "Perceptive")
        #expect(items.first?.location == "Marth")
        #expect(Set(items.compactMap(\.location)).count >= 2)
    }

    @Test("Headers match whole words only")
    func wordMatching() {
        #expect(TrackerListParser.words("EmblemSkills") == ["emblem", "skills"])
        #expect(TrackerListParser.words("Emblem Name") == ["emblem", "name"])
        #expect(!TrackerListParser.isNameHeader("Charmer"))
        #expect(TrackerListParser.isNameHeader("Charm"))
        #expect(TrackerListParser.isNameHeader("Unit"))
    }

    @Test("The sheet's tabs come off its page, and reference tabs feed the right field")
    func tabsAndReferences() {
        let page = #"items.push({name: "Team Builder", pageUrl: "https:\/\/docs.google.com\/x?headers\x3dtrue&gid=1665995859", gid: "1665995859",initialSheet: true});items.push({name: "Unit \"Ref\"", pageUrl: "u", gid: "862735184",initialSheet: false});"#
        let tabs = SheetsLinkImport.tabs(inPage: page)
        #expect(tabs.map(\.gid) == ["1665995859", "862735184"])
        #expect(tabs.first?.name == "Team Builder")
        #expect(tabs.last?.name == #"Unit "Ref""#)
        #expect(SheetsLinkImport.referenceField(forTab: "ClassReference") == "class")
        #expect(SheetsLinkImport.referenceField(forTab: "EmblemRings") == "emblem")
        #expect(SheetsLinkImport.referenceField(forTab: "EmblemSkills") == nil)
        #expect(SheetsLinkImport.referenceField(forTab: "InheritableSkills") == nil)
        #expect(SheetsLinkImport.referenceField(forTab: "UnitReference") == nil)
        #expect(SheetsLinkImport.tabID(from: "https://docs.google.com/spreadsheets/d/abc/edit#gid=42") == "42")
        #expect(SheetsLinkImport.tabID(from: "https://docs.google.com/spreadsheets/d/abc/htmlview") == nil)
        #expect(SheetsLinkImport.exportURL(from: "https://docs.google.com/spreadsheets/d/abc/htmlview", gid: "7")?
            .absoluteString == "https://docs.google.com/spreadsheets/d/abc/export?format=csv&gid=7")
    }

    @Test("A roster imports with its fields and choices")
    func rosterSchema() throws {
        var result = TrackerListParser.parse(SheetsLinkImport.markdownTable(fromCSV: EngageSheetFixtures.units))
        result.categories[0].fields = TrackerFieldDTO.rpgDefaults(
            options: ["class": ["Sage", "Avenir"], "emblem": ["Marth"]])
        let schema = TrackerListParser.schemaData(from: result)
        let category = try #require(TrackerSchemaJSON.categories(from: schema).first)
        #expect(category.isRoster)
        #expect(category.fields.map(\.id) == ["class", "level", "weapon", "emblem", "party"])
        #expect(category.fields.first?.options == ["Sage", "Avenir"])
        #expect(category.items.count == 37)
    }
}
