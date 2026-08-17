import Foundation
import SwiftData

/// Versioned JSON export of everything the user has created.
///
/// Beta P0: soft-delete plus iCloud is not a backup. Asking testers to invest
/// hours of tracking with no way to get their data out is how a beta loses
/// people's trust permanently — so this exists before the first external
/// tester, not after.
///
/// The format is deliberately plain and self-describing: a `manifest` with
/// counts and a checksum so an import can prove it read everything, then the
/// records themselves with stable UUIDs so a future importer can round-trip
/// without duplicating. Tombstoned (deleted) records are excluded — this is a
/// copy of the library as the user sees it.
@MainActor
enum LibraryExport {
    /// Bump when the shape changes; importers should refuse unknown majors.
    static let formatVersion = 1

    struct Manifest: Codable {
        var formatVersion: Int
        var exportedAt: Date
        var appVersion: String
        var games: Int
        var playthroughs: Int
        var sessions: Int
        var runs: Int
        var trackerStates: Int
        var trackerSchemas: Int
        var completions: Int
        var videos: Int
        var collections: Int
        /// Sum of every record count above — a cheap integrity check that an
        /// importer (or a person) can verify without parsing the whole file.
        var totalRecords: Int
    }

    // MARK: Building

    /// Produce the export as pretty-printed JSON data.
    static func makeJSON(context: ModelContext) throws -> Data {
        let games = try context.fetch(
            FetchDescriptor<Game>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.name)]
            )
        )
        let collections = try context.fetch(
            FetchDescriptor<GameCollection>(predicate: #Predicate { $0.deletedAt == nil })
        )

        var counts = (playthroughs: 0, sessions: 0, runs: 0,
                      states: 0, schemas: 0, completions: 0, videos: 0)

        var gameObjects: [[String: Any]] = []
        for game in games {
            var dict: [String: Any] = [
                "id": game.id.uuidString,
                "name": game.name,
                "status": game.status.rawValue,
                "addedAt": iso(game.addedAt),
                "createdAt": iso(game.createdAt),
                "updatedAt": iso(game.updatedAt),
                "pinned": game.pinned,
                "notes": game.notes,
                "platforms": game.platforms,
                "ownership": game.ownership,
                "userTags": game.userTags,
            ]
            dict["summary"] = game.summary
            dict["rating"] = game.rating
            dict["review"] = game.review
            dict["igdbID"] = game.igdbID
            dict["igdbSlug"] = game.igdbSlug
            dict["coverImageID"] = game.coverImageID
            dict["coverURL"] = game.coverURLString
            dict["franchise"] = game.franchise
            dict["firstReleaseDate"] = game.firstReleaseDate.map(iso)
            dict["developers"] = game.developers
            dict["publishers"] = game.publishers
            dict["genres"] = game.genres

            // Tracker schema (the structure), separate from progress.
            if let schema = game.trackerSchema, schema.deletedAt == nil {
                counts.schemas += 1
                dict["trackerSchema"] = [
                    "id": schema.id.uuidString,
                    "schemaVersion": schema.schemaVersion,
                    "source": schema.source.rawValue,
                    "engine": schema.engine.rawValue,
                    "generatedAt": schema.generatedAt.map(iso) as Any,
                    "generatedBy": schema.generatedBy as Any,
                    // Embedded as parsed JSON, not an opaque blob, so the file
                    // stays readable and diffable.
                    "data": (try? JSONSerialization.jsonObject(with: schema.jsonData)) ?? [:],
                ]
            }

            var playthroughObjects: [[String: Any]] = []
            for pt in game.livePlaythroughs {
                counts.playthroughs += 1

                let sessions = (pt.sessions ?? []).filter { $0.deletedAt == nil }
                counts.sessions += sessions.count
                let sessionObjects = sessions
                    .sorted { $0.startDate < $1.startDate }
                    .map { session -> [String: Any] in
                        var s: [String: Any] = [
                            "id": session.id.uuidString,
                            "startDate": iso(session.startDate),
                            "durationSeconds": session.accumulatedDuration,
                            "state": session.state.rawValue,
                            "isManual": session.isManual,
                        ]
                        s["endDate"] = session.endDate.map(iso)
                        s["notes"] = session.notes
                        return s
                    }

                let runs = pt.liveRuns
                counts.runs += runs.count
                let runObjects = runs.map { run -> [String: Any] in
                    var r: [String: Any] = [
                        "id": run.id.uuidString,
                        "templateID": run.templateID,
                        "startedAt": iso(run.startedAt),
                        "outcome": run.outcome.rawValue,
                        "fields": run.fieldsDict,
                    ]
                    r["endedAt"] = run.endedAt.map(iso)
                    r["notes"] = run.notes
                    return r
                }

                let states = (pt.trackerStates ?? []).filter { $0.deletedAt == nil }
                counts.states += states.count
                let stateObjects = states
                    .sorted { $0.itemID < $1.itemID }
                    .map { state -> [String: Any] in
                        var t: [String: Any] = [
                            "itemID": state.itemID,
                            "completed": state.completed,
                            "revealed": state.revealed,
                        ]
                        t["count"] = state.count
                        t["rank"] = state.rank
                        t["notes"] = state.notes
                        return t
                    }

                var p: [String: Any] = [
                    "id": pt.id.uuidString,
                    "name": pt.name,
                    "progressPercent": pt.progressPercent,
                    "isActive": pt.id == game.activePlaythrough?.id,
                    "createdAt": iso(pt.createdAt),
                    "sessions": sessionObjects,
                    "runs": runObjects,
                    "trackerProgress": stateObjects,
                ]
                p["notes"] = pt.notes
                p["startedAt"] = pt.startedAt.map(iso)
                p["lastPlayedAt"] = pt.lastPlayedAt.map(iso)
                playthroughObjects.append(p)
            }
            dict["playthroughs"] = playthroughObjects

            let completions = (game.completionEvents ?? []).filter { $0.deletedAt == nil }
            counts.completions += completions.count
            dict["completions"] = completions.map { event -> [String: Any] in
                var c: [String: Any] = ["date": iso(event.date), "label": event.label.rawValue]
                c["customLabel"] = event.customLabel
                c["platform"] = event.platform
                c["notes"] = event.notes
                return c
            }

            let videos = (game.videos ?? []).filter { $0.deletedAt == nil }
            counts.videos += videos.count
            dict["videos"] = videos.sorted { $0.orderIndex < $1.orderIndex }.map { video -> [String: Any] in
                var v: [String: Any] = [
                    "url": video.urlString,
                    "kind": video.kindRaw,
                    "title": video.title,
                    "group": video.groupName,
                    "watchedSeconds": video.watchedSeconds,
                    "watchedPartIndex": video.watchedPartIndex,
                ]
                v["channel"] = video.channel
                return v
            }

            gameObjects.append(dict.compactMapValues { $0 })
        }

        let collectionObjects = collections
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { collection -> [String: Any] in
                [
                    "id": collection.id.uuidString,
                    "name": collection.name,
                    "isBundle": collection.isBundle,
                    "notes": collection.notes,
                    "gameIDs": collection.gameIDs,
                ]
            }

        let total = games.count + counts.playthroughs + counts.sessions + counts.runs
            + counts.states + counts.schemas + counts.completions + counts.videos
            + collectionObjects.count

        let manifest = Manifest(
            formatVersion: formatVersion,
            exportedAt: .now,
            appVersion: appVersionString,
            games: games.count,
            playthroughs: counts.playthroughs,
            sessions: counts.sessions,
            runs: counts.runs,
            trackerStates: counts.states,
            trackerSchemas: counts.schemas,
            completions: counts.completions,
            videos: counts.videos,
            collections: collectionObjects.count,
            totalRecords: total
        )

        let root: [String: Any] = [
            "manifest": try manifestDictionary(manifest),
            "games": gameObjects,
            "collections": collectionObjects,
        ]
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// Write the export to a temporary file and return its URL, ready to hand
    /// to a share sheet. Named with the date so a user's Files folder stays
    /// legible when they export more than once.
    static func writeToTemporaryFile(context: ModelContext) throws -> URL {
        try writeToTemporaryFile(data: makeJSON(context: context))
    }

    /// Write already-built export bytes. The settings screen builds the JSON
    /// once for its summary; serialising the whole graph a second time on the
    /// main actor just to write the same bytes doubled the freeze on a big
    /// library.
    static func writeToTemporaryFile(data: Data) throws -> URL {
        let stamp = ExportFormatters.dateOnly.string(from: .now)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LevelSelect-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Short human summary for the UI after an export.
    static func summary(for data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let manifest = root["manifest"] as? [String: Any],
            let games = manifest["games"] as? Int,
            let sessions = manifest["sessions"] as? Int,
            let total = manifest["totalRecords"] as? Int
        else { return nil }
        return "\(games) games · \(sessions) sessions · \(total) records total"
    }

    // MARK: Helpers

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func iso(_ date: Date) -> String {
        ExportFormatters.timestamp.string(from: date)
    }

    private static func manifestDictionary(_ manifest: Manifest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Formatters are not Sendable, so they live on the main actor alongside the
/// export itself rather than as free-floating statics.
@MainActor
private enum ExportFormatters {
    static let timestamp = ISO8601DateFormatter()
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
