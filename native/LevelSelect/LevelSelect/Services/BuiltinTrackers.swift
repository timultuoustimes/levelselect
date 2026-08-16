import Foundation
import SwiftData

/// Built-in tracker schemas converted from the web app's data files by the
/// web app's OWN conversion functions (scripts run at build time), so item
/// ids are byte-identical to the legacy `itemState` keys — imported progress
/// (e.g. Under the Island 12/33, Sayonara 23) lights up immediately.
enum BuiltinTrackers {
    /// One entry from `builtin-trackers.json`, decoded once per lookup.
    private struct Entry {
        let igdbIDs: Set<Int>
        let name: String
        let engine: TrackerEngine
        let schemaData: Data
    }

    private static func loadEntries() -> [Entry] {
        guard let url = Bundle.main.url(forResource: "builtin-trackers", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }

        return raw.compactMap { entry in
            guard let structured = entry["structuredData"] as? [String: Any],
                  let schemaData = try? JSONSerialization.data(withJSONObject: structured)
            else { return nil }
            let igdbIDs = Set((entry["igdbIds"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? [])
            let name = (entry["name"] as? String) ?? ""
            let engine = TrackerEngine(rawValue: (entry["engine"] as? String) ?? "") ?? .objective
            return Entry(igdbIDs: igdbIDs, name: name, engine: engine, schemaData: schemaData)
        }
    }

    /// The built-in schema for a specific game, if one ships for it — matched
    /// by igdb id first, else an exact (case-insensitive) name match, same
    /// order `installMissing` uses.
    static func match(for game: Game) -> (schemaData: Data, engine: TrackerEngine)? {
        let entries = loadEntries()
        if let id = game.igdbID, let hit = entries.first(where: { $0.igdbIDs.contains(id) }) {
            return (hit.schemaData, hit.engine)
        }
        if let hit = entries.first(where: {
            !$0.name.isEmpty && $0.name.caseInsensitiveCompare(game.name) == .orderedSame
        }) {
            return (hit.schemaData, hit.engine)
        }
        return nil
    }

    /// Attach built-in schemas to matching games that have no tracker yet.
    /// Idempotent; never overwrites an existing (e.g. AI-generated) schema —
    /// that's what `Repository.useBuiltinSchema` is for, as a deliberate,
    /// user-initiated swap. Returns how many were installed.
    @MainActor
    @discardableResult
    static func installMissing(context: ModelContext) -> Int {
        guard let games = try? context.fetch(
            FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil }))
        else { return 0 }
        let entries = loadEntries()
        guard !entries.isEmpty else { return 0 }

        let repo = Repository(context)
        var installed = 0

        for entry in entries {
            let matches = games.filter { game in
                if let id = game.igdbID, entry.igdbIDs.contains(id) { return true }
                return !entry.name.isEmpty && game.name.caseInsensitiveCompare(entry.name) == .orderedSame
            }
            for game in matches where game.trackerSchema == nil {
                let record = TrackerSchemaRecord(
                    source: .builtIn, engine: entry.engine, jsonData: entry.schemaData)
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
