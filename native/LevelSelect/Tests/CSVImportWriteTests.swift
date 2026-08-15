import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The parser has its own tests; these cover what happens to the data once a
/// user hits Import — the half that can quietly corrupt a library.
///
/// The view owns the IGDB lookup and the file picker, so this exercises the
/// same write sequence the view performs, without the network.
@MainActor
struct CSVImportWriteTests {

    private func importRows(_ csv: String, into context: ModelContext) -> Int {
        let repo = Repository(context)
        let parsed = CSVImport.parse(csv)
        for row in parsed.rows {
            let game = repo.addGame(name: row.name, status: row.status ?? .backlog)
            if let platform = row.platform { game.platforms = [platform] }
            game.rating = row.rating
            if let notes = row.notes { game.notes = notes }
            if let hours = row.hoursPlayed, hours > 0 {
                let pt = repo.ensureDefaultPlaythrough(for: game)
                repo.logManualSession(on: pt, duration: hours * 3600, notes: "Imported from CSV")
            }
        }
        return parsed.rows.count
    }

    /// A realistic third-party export: renamed columns, mixed statuses, a
    /// 1-10 rating scale, quoted commas, and a row with no title.
    private let gameryStyle = """
    Game Title,System,Shelf,Score,Total Hours,My Review,Some Column
    "Celeste",Nintendo Switch,Beaten,9,22.1,"Perfect platformer, brutal B-sides",x
    "Outer Wilds",PC,Completed,10,31.7,"Do not spoil this",x
    "Tunic",Nintendo Switch,Plan to Play,,,,x
    "Vampire Survivors",PC,In Progress,7,4.5,,x
    ,Switch,Playing,,,orphan row,x
    """

    @Test func importsEveryRowThatHasATitle() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let count = importRows(gameryStyle, into: context)
        #expect(count == 4)                      // the titleless row is dropped
        #expect(try context.fetch(FetchDescriptor<Game>()).count == 4)
    }

    @Test func mapsStatusesRatingsAndNotes() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        importRows(gameryStyle, into: context)
        let games = try context.fetch(FetchDescriptor<Game>())

        let celeste = try #require(games.first { $0.name == "Celeste" })
        #expect(celeste.status == .completed)     // "Beaten"
        #expect(celeste.rating == 5)              // 9/10 rounds to 5
        #expect(celeste.notes.contains("brutal B-sides"))   // quoted comma survived
        #expect(celeste.platforms == ["Nintendo Switch"])

        let tunic = try #require(games.first { $0.name == "Tunic" })
        #expect(tunic.status == .queued)          // "Plan to Play"
        #expect(tunic.rating == nil)              // blank stays blank

        let vs = try #require(games.first { $0.name == "Vampire Survivors" })
        #expect(vs.status == .playing)            // "In Progress"
    }

    /// Hours become one manual session so the time shows in stats — without
    /// inventing a play history that never happened.
    @Test func hoursBecomeASingleManualSession() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        importRows(gameryStyle, into: context)
        let games = try context.fetch(FetchDescriptor<Game>())

        let celeste = try #require(games.first { $0.name == "Celeste" })
        let pt = try #require(celeste.activePlaythrough)
        let sessions = (pt.sessions ?? []).filter { $0.deletedAt == nil }
        #expect(sessions.count == 1)
        #expect(sessions.first?.isManual == true)
        #expect(abs(pt.totalPlaytime() - 22.1 * 3600) < 1)

        // A row with no hours must not fabricate a session.
        let tunic = try #require(games.first { $0.name == "Tunic" })
        #expect((tunic.activePlaythrough?.sessions ?? []).isEmpty)
    }

    /// Importing the same file twice is the user's call, but it must not
    /// corrupt anything — each pass adds its own games rather than merging
    /// half-and-half into existing ones.
    @Test func reimportingIsAdditiveNotDestructive() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        importRows(gameryStyle, into: context)
        importRows(gameryStyle, into: context)
        let games = try context.fetch(FetchDescriptor<Game>())
        #expect(games.count == 8)
        // Every copy kept its own data rather than being partially overwritten.
        #expect(games.filter { $0.name == "Celeste" }.allSatisfy { $0.rating == 5 })
    }

    /// The export is the other half of the round trip: a CSV import should
    /// come back out of the JSON export intact.
    @Test func importedLibraryRoundTripsThroughExport() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        importRows(gameryStyle, into: context)

        let data = try LibraryExport.makeJSON(context: context)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let manifest = try #require(root["manifest"] as? [String: Any])
        #expect(manifest["games"] as? Int == 4)
        #expect(manifest["sessions"] as? Int == 3)   // three rows carried hours

        let exported = try #require(root["games"] as? [[String: Any]])
        let celeste = try #require(exported.first { $0["name"] as? String == "Celeste" })
        #expect(celeste["rating"] as? Int == 5)
        #expect(celeste["status"] as? String == GameStatus.completed.rawValue)
    }
}
