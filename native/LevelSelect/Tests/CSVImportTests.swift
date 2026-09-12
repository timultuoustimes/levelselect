import Testing
import Foundation
@testable import LevelSelect

/// CSV is the on-ramp, so it has to survive whatever another app exported —
/// odd column names, quoted commas, mixed rating scales, unknown statuses.
struct CSVImportTests {

    // MARK: Parser mechanics

    @Test func handlesQuotedFieldsCommasAndEscapedQuotes() {
        let csv = """
        Title,Notes
        "Hollow Knight","Bought it, loved it"
        "The ""Best"" Game",plain
        """
        let result = CSVImport.parse(csv)
        #expect(result.rows.count == 2)
        #expect(result.rows[0].notes == "Bought it, loved it")
        #expect(result.rows[1].name == "The \"Best\" Game")
    }

    @Test func handlesCRLFAndTrailingNewline() {
        let csv = "Title,Platform\r\nCeleste,Switch\r\nTunic,PC\r\n"
        let result = CSVImport.parse(csv)
        #expect(result.rows.count == 2)
        #expect(result.rows[1].platform == "PC")
    }

    // MARK: Column aliasing

    @Test func recognizesDifferentAppsColumnNames() {
        // Roughly a Gamery/Backloggd-shaped export.
        let csv = """
        Game Title,System,Shelf,Score,My Review,Total Hours,Some Other Column
        Hades,Nintendo Switch,Playing,9,"Great",28.6,ignore me
        """
        let result = CSVImport.parse(csv)
        let row = try! #require(result.rows.first)
        #expect(row.name == "Hades")
        #expect(row.platform == "Nintendo Switch")
        #expect(row.status == .playing)
        #expect(row.rating == 5)              // 9/10 -> 4.5 -> 5
        #expect(row.notes == "Great")
        #expect(row.hoursPlayed == 28.6)
        #expect(result.ignoredColumns.contains("Some Other Column"))
    }

    @Test func rowsWithoutATitleAreSkippedNotFatal() {
        let csv = """
        Title,Platform
        ,Switch
        Celeste,Switch
        """
        let result = CSVImport.parse(csv)
        #expect(result.rows.count == 1)
        #expect(result.skippedLines == [2])
    }

    // MARK: Value coercion

    @Test func mapsForeignStatusVocabulary() {
        #expect(CSVImport.status(from: "In Progress") == .playing)
        #expect(CSVImport.status(from: "on hold") == .paused)
        #expect(CSVImport.status(from: "Beaten") == .completed)
        #expect(CSVImport.status(from: "Plan to Play") == .queued)
        #expect(CSVImport.status(from: "Dropped") == .abandoned)
        // Unknown vocabulary must not drop the row.
        #expect(CSVImport.status(from: "Weird Custom Shelf") == .backlog)
    }

    @Test func normalizesRatingScales() {
        #expect(CSVImport.rating(from: "5") == 5)        // out of 5
        #expect(CSVImport.rating(from: "4.5") == 5)
        #expect(CSVImport.rating(from: "8") == 4)        // out of 10
        #expect(CSVImport.rating(from: "80%") == 4)      // percentage
        #expect(CSVImport.rating(from: "★★★") == 3)
        #expect(CSVImport.rating(from: "0") == nil)
        #expect(CSVImport.rating(from: "n/a") == nil)
    }

    @Test func parsesHourFormats() {
        #expect(CSVImport.hours(from: "12") == 12)
        #expect(CSVImport.hours(from: "12.5h") == 12.5)
        #expect(CSVImport.hours(from: "1,234 hours") == 1234)
        #expect(CSVImport.hours(from: "none") == nil)
    }

    /// LevelSelect's own export is CSV-adjacent; at minimum a simple
    /// name/platform/status round-trip has to survive.
    @Test func handlesAMinimalSingleColumnFile() {
        let result = CSVImport.parse("Title\nCeleste\nTunic\nHades")
        #expect(result.rows.count == 3)
        #expect(result.rows.map(\.name) == ["Celeste", "Tunic", "Hades"])
        #expect(result.rows.allSatisfy { $0.status == nil })
    }
}
