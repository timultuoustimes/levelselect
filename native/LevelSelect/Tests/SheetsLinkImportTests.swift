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
}
