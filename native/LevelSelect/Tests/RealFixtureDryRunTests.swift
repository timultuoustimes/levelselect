import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Dev-only dry run of the importer against the REAL (gitignored) canonical
/// library export. Inert unless `LS_LEGACY_FIXTURE` points at the JSON file, so
/// it is safe to keep in the suite and does nothing in CI / for other clones.
///
/// Run with:
///   LS_LEGACY_FIXTURE=/abs/path/legacy-canonical-….json xcodebuild … test
@MainActor
struct RealFixtureDryRunTests {

    @Test func dryRunAgainstRealLibrary() throws {
        guard
            let path = ProcessInfo.processInfo.environment["LS_LEGACY_FIXTURE"],
            FileManager.default.fileExists(atPath: path)
        else {
            print("DRYRUN| skipped — set LS_LEGACY_FIXTURE to the canonical export path")
            return
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawLibrary = (root["library"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []

        // Import into a throwaway in-memory store (nothing persisted).
        let ctx = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let report = try LegacyImporter(ctx).import(
            data: data,
            sourceDeviceID: "7f86df1b-a815-4798-a9d5-00974419eec3"
        )

        // ---- Diagnostics (grep the log for "DRYRUN|") ----
        func line(_ s: String) { print("DRYRUN| \(s)") }

        line("raw library entries:        \(rawLibrary.count)")
        line("imported games:             \(report.games)")
        line("playthroughs:               \(report.playthroughs)")
        line("sessions:                   \(report.sessions)")
        line("completionEvents:           \(report.completionEvents)")
        line("maps:                       \(report.maps)")
        line("markers:                    \(report.markers)")
        line("trackerSchemas:             \(report.trackerSchemas)")
        line("skipped:                    \(report.skipped.count)")
        for s in report.skipped { line("  - \(s)") }

        // Raw trackerType distribution (from source, before mapping).
        var trackerTypes: [String: Int] = [:]
        var rawStatuses: [String: Int] = [:]
        for g in rawLibrary {
            trackerTypes[(g["trackerType"] as? String) ?? "nil", default: 0] += 1
            rawStatuses[(g["status"] as? String) ?? "nil", default: 0] += 1
        }
        line("raw trackerType dist:       \(trackerTypes.sorted { $0.value > $1.value })")
        line("raw status dist:            \(rawStatuses.sorted { $0.value > $1.value })")

        // Imported-side checks.
        let games = try ctx.fetch(FetchDescriptor<Game>())
        let statusDist = Dictionary(grouping: games, by: { $0.status.rawValue }).mapValues(\.count)
        line("imported status dist:       \(statusDist.sorted { $0.value > $1.value })")

        let ratings = games.compactMap(\.rating)
        line("games with rating:          \(ratings.count) (values: \(Set(ratings).sorted()))")
        line("games missing igdbID:       \(games.filter { $0.igdbID == nil }.count)")

        let sessions = try ctx.fetch(FetchDescriptor<Session>())
        let sessionStates = Dictionary(grouping: sessions, by: { $0.state.rawValue }).mapValues(\.count)
        line("session state dist:         \(sessionStates)")

        let markers = try ctx.fetch(FetchDescriptor<Marker>())
        let outOfBounds = markers.filter { $0.normalizedX < 0 || $0.normalizedX > 1 || $0.normalizedY < 0 || $0.normalizedY > 1 }
        line("markers out of 0…1 bounds:  \(outOfBounds.count)")

        let receipts = try ctx.fetchCount(FetchDescriptor<MigrationReceipt>())
        line("migration receipts:         \(receipts)")

        // ---- Invariants ----
        #expect(report.alreadyImported == false)
        #expect(report.games == rawLibrary.count)   // no game silently dropped
        #expect(report.skipped.isEmpty)
        #expect(outOfBounds.isEmpty)                 // all marker coords normalized
        #expect(receipts == 1)
        #expect(games.allSatisfy { !$0.name.isEmpty })
    }
}
