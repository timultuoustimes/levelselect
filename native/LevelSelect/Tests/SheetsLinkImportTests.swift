import Testing
import Foundation
@testable import LevelSelect

/// Paste a Google Sheets link: the URL arithmetic and the CSV → table step,
/// which are the two parts that can be wrong without a network.
struct SheetsLinkImportTests {

    @Test("An edit link with a tab fragment becomes that tab's CSV export")
    func editLinkWithGid() {
        let out = SheetsLinkImport.exportURL(from: "https://docs.google.com/spreadsheets/d/1AbC_dEf-123/edit#gid=987654321")
        #expect(out?.absoluteString == "https://docs.google.com/spreadsheets/d/1AbC_dEf-123/export?format=csv&gid=987654321")
    }

    @Test("A link without a tab exports the first tab")
    func editLinkNoGid() {
        let out = SheetsLinkImport.exportURL(from: " https://docs.google.com/spreadsheets/d/1AbC/edit?usp=sharing \n")
        #expect(out?.absoluteString == "https://docs.google.com/spreadsheets/d/1AbC/export?format=csv")
    }

    @Test("A gid in the query works too, and other hosts are refused")
    func gidInQueryAndOtherHosts() {
        #expect(SheetsLinkImport.exportURL(from: "https://docs.google.com/spreadsheets/d/X/view?gid=5")?.absoluteString.hasSuffix("&gid=5") == true)
        #expect(SheetsLinkImport.exportURL(from: "https://example.com/spreadsheets/d/X/edit") == nil)
        #expect(SheetsLinkImport.exportURL(from: "https://docs.google.com/spreadsheets/d/e/2PACX-published/pubhtml") == nil)
        #expect(SheetsLinkImport.exportURL(from: "not a url") == nil)
    }

    @Test("looksLikeLink only says yes to a single Sheets URL")
    func looksLikeLink() {
        #expect(SheetsLinkImport.looksLikeLink("https://docs.google.com/spreadsheets/d/X/edit"))
        #expect(!SheetsLinkImport.looksLikeLink("| # | Name |\n| 1 | Thing |"))
        #expect(!SheetsLinkImport.looksLikeLink("docs.google.com/spreadsheets/d/X"))
    }

    @Test("CSV becomes the markdown table the parser reads, pipes and blank rows handled")
    func csvToTable() {
        let csv = "Name,Location,Notes\nWayward Compass,Dirtmouth,\"Sold by Iselda | 220 geo\"\n,,\nGathering Swarm,Forgotten Crossroads,Sly"
        let table = SheetsLinkImport.markdownTable(fromCSV: csv)
        let lines = table.split(separator: "\n").map(String.init)
        #expect(lines[0] == "| Name | Location | Notes |")
        #expect(lines[1] == "| --- | --- | --- |")
        #expect(lines[2] == "| Wayward Compass | Dirtmouth | Sold by Iselda / 220 geo |")
        #expect(lines.count == 4)
        // And the parser reads it as two items with locations.
        let parsed = TrackerListParser.parse(table, defaultCategoryName: "Sheet")
        #expect(parsed.itemCount == 2)
    }

    @Test("The list is found under a banner, trimmed to its own columns, and ends where the calculators begin")
    func listFoundOnABusyTab() {
        let csv = """
        Created by someone,,,Today's Date:,9/8/2026
        ,,,,
        Charm,Equipped,Boost Value,,Owned,Normal Spell
        Unbreakable Strength,TRUE,50%,,TRUE,Vengeful Spirit
        Shaman Stone,FALSE,33%,,TRUE,Desolate Dive
        ,,,,
        Soul Catcher,FALSE,3,,,
        ,,,,
        All values are under an ideal scenario where all attacks hit,,,,
        ,Nail Damage,Spell Damage,,
        Input 1,Pure Nail,Shade Soul,,
        Output 1,21,20,,
        """
        let table = SheetsLinkImport.markdownTable(fromCSV: csv)
        #expect(table.hasPrefix("| Charm | Equipped | Boost Value |"))
        #expect(!table.contains("Owned"))          // the neighbor table to the right is not this list
        #expect(!table.contains("Input 1"))        // the calculator below is not a list
        #expect(!table.contains("Created by"))     // the banner above is not the header
        let parsed = TrackerListParser.parse(table)
        #expect(parsed.categories.count == 1)
        #expect(parsed.categories.first?.name == "Charm")
        #expect(parsed.itemCount == 3)             // the blank row inside the list is skipped
    }

    @Test("Two tables under headings become two categories")
    func headedTables() {
        let text = """
        ## Bosses
        | Name | Location |
        | --- | --- |
        | False Knight | Forgotten Crossroads |
        | Hornet | Greenpath |

        ## Charms
        | Name | Notes |
        | --- | --- |
        | Wayward Compass | Iselda |
        """
        let parsed = TrackerListParser.parse(text)
        #expect(parsed.categories.map(\.name) == ["Bosses", "Charms"])
        #expect(parsed.categories[0].items.map(\.name) == ["False Knight", "Hornet"])
        #expect(parsed.categories[0].items[0].location == "Forgotten Crossroads")
        #expect(parsed.categories[1].items.count == 1)
    }
}
