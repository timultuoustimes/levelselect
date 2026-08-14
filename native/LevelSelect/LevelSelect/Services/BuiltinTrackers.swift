import Foundation
import SwiftData

/// Built-in tracker schemas converted from the web app's data files by the
/// web app's OWN conversion functions (scripts run at build time), so item
/// ids are byte-identical to the legacy `itemState` keys — imported progress
/// (e.g. Under the Island 12/33, Sayonara 23) lights up immediately.
enum BuiltinTrackers {
    /// Attach built-in schemas to matching games that have no tracker yet.
    /// Idempotent; never overwrites an existing (e.g. AI-generated) schema.
    /// Returns how many were installed.
    @MainActor
    @discardableResult
    static func installMissing(context: ModelContext) -> Int {
        guard let url = Bundle.main.url(forResource: "builtin-trackers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let games = try? context.fetch(
                FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil }))
        else { return 0 }

        let repo = Repository(context)
        var installed = 0

        for entry in entries {
            guard let structured = entry["structuredData"] as? [String: Any],
                  let schemaData = try? JSONSerialization.data(withJSONObject: structured)
            else { continue }
            let igdbIDs = Set((entry["igdbIds"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? [])
            let name = (entry["name"] as? String) ?? ""

            let matches = games.filter { game in
                if let id = game.igdbID, igdbIDs.contains(id) { return true }
                return !name.isEmpty && game.name.caseInsensitiveCompare(name) == .orderedSame
            }
            let engine = TrackerEngine(rawValue: (entry["engine"] as? String) ?? "") ?? .objective
            for game in matches where game.trackerSchema == nil {
                let record = TrackerSchemaRecord(
                    source: .builtIn, engine: engine, jsonData: schemaData)
                context.insert(record)
                record.game = game
                repo.recomputeProgress(game)
                installed += 1
            }
        }
        if installed > 0 { PersistenceMonitor.shared.commit(context) }
        return installed
    }
}
