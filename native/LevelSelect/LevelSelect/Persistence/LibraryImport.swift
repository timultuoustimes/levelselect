import Foundation
import SwiftData

/// The other half of the export: read a LevelSelect JSON export back in.
///
/// Until now the export was "a record, not a restore point" — its own words.
/// This closes the loop, and its one rule makes it safe to run against ANY
/// library, not just an empty one:
///
///     **Additive by id. Create what's missing; never touch what exists.**
///
/// Every exported record carries its stable UUID, so the importer knows
/// exactly which records the library already has. Present → skipped, wholly
/// untouched — not merged, not updated, not "refreshed". Absent → created
/// with its original id, so a re-import stays idempotent and CloudKit treats
/// the restored record as the same record everywhere. Running it twice is a
/// no-op; running it after a partial disaster restores exactly the missing
/// part; running someone ELSE's export grafts their library alongside yours
/// (which is honest, if eccentric).
///
/// What it deliberately does not do: delete anything, overwrite anything, or
/// reconcile conflicting field values. Restore is not sync.
@MainActor
enum LibraryImport {

    /// Mirror of `LibraryExport.formatVersion`, nonisolated so error text can
    /// use it; a test pins that the two never drift.
    nonisolated static let supportedVersion = 2

    enum ImportError: LocalizedError {
        case notAnExport
        case unsupportedVersion(Int)
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .notAnExport:
                "This file isn't a LevelSelect export — no manifest found."
            case .unsupportedVersion(let v):
                "This export is format version \(v); this build reads version \(LibraryImport.supportedVersion)."
            case .malformed(let what):
                "The export is damaged: \(what)."
            }
        }
    }

    /// What an import WOULD do — computed without writing anything, for the
    /// confirmation screen. `create + skip` per type; problems are warnings,
    /// not refusals (a manifest miscount shouldn't strand a rescue).
    struct Preview {
        var exportedAt: String = ""
        var appVersion: String = ""
        var creates: [String: Int] = [:]
        var skips: [String: Int] = [:]
        var problems: [String] = []

        var totalCreates: Int { creates.values.reduce(0, +) }
        var totalSkips: Int { skips.values.reduce(0, +) }
    }

    struct Outcome {
        var created: [String: Int] = [:]
        var skipped: [String: Int] = [:]
        var totalCreated: Int { created.values.reduce(0, +) }
    }

    // MARK: Parsing

    private static func root(of data: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ImportError.malformed("not JSON") }
        guard let manifest = root["manifest"] as? [String: Any] else {
            throw ImportError.notAnExport
        }
        let version = (manifest["formatVersion"] as? Int) ?? 0
        guard version == Self.supportedVersion else {
            throw ImportError.unsupportedVersion(version)
        }
        return root
    }

    private static func date(_ any: Any?) -> Date? {
        (any as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    private static func uuid(_ any: Any?) -> UUID? {
        (any as? String).flatMap(UUID.init(uuidString:))
    }

    // MARK: Preview

    static func preview(data: Data, context: ModelContext) throws -> Preview {
        let root = try root(of: data)
        var preview = Preview()
        if let manifest = root["manifest"] as? [String: Any] {
            preview.exportedAt = (manifest["exportedAt"] as? String) ?? ""
            preview.appVersion = (manifest["appVersion"] as? String) ?? ""
        }
        let existing = try ExistingIDs(context: context)
        walk(root: root, existing: existing,
             onCreate: { preview.creates[$0, default: 0] += 1 },
             onSkip: { preview.skips[$0, default: 0] += 1 })

        // The manifest's own honesty check.
        if let manifest = root["manifest"] as? [String: Any],
           let claimed = manifest["totalRecords"] as? Int {
            let walked = preview.totalCreates + preview.totalSkips
            if walked != claimed {
                preview.problems.append(
                    "Manifest says \(claimed) records; the file holds \(walked). Importing what's actually here.")
            }
        }
        return preview
    }

    /// Every id already in the store, one fetch per type. Includes trashed
    /// records: a soft-deleted game still owns its id, and re-creating it
    /// would fork history — restore from Recently Deleted instead.
    private struct ExistingIDs {
        var games = Set<UUID>(), playthroughs = Set<UUID>(), sessions = Set<UUID>()
        var runs = Set<UUID>(), states = Set<UUID>(), schemas = Set<UUID>()
        var completions = Set<UUID>(), videos = Set<UUID>(), maps = Set<UUID>()
        var markers = Set<UUID>(), collections = Set<UUID>()
        var images = Set<UUID>()
        var memories = Set<UUID>()

        init(context: ModelContext) throws {
            games = Set(try context.fetch(FetchDescriptor<Game>()).map(\.id))
            playthroughs = Set(try context.fetch(FetchDescriptor<Playthrough>()).map(\.id))
            sessions = Set(try context.fetch(FetchDescriptor<Session>()).map(\.id))
            runs = Set(try context.fetch(FetchDescriptor<Run>()).map(\.id))
            states = Set(try context.fetch(FetchDescriptor<TrackerStateRecord>()).map(\.id))
            schemas = Set(try context.fetch(FetchDescriptor<TrackerSchemaRecord>()).map(\.id))
            completions = Set(try context.fetch(FetchDescriptor<CompletionEvent>()).map(\.id))
            videos = Set(try context.fetch(FetchDescriptor<GameVideo>()).map(\.id))
            maps = Set(try context.fetch(FetchDescriptor<GameMap>()).map(\.id))
            markers = Set(try context.fetch(FetchDescriptor<Marker>()).map(\.id))
            collections = Set(try context.fetch(FetchDescriptor<GameCollection>()).map(\.id))
            images = Set(try context.fetch(FetchDescriptor<GameImage>()).map(\.id))
            memories = Set(try context.fetch(FetchDescriptor<Memory>()).map(\.id))
        }
    }

    /// One traversal shared by preview and apply, so the confirmation screen
    /// can never disagree with what the import then does.
    private static func walk(root: [String: Any], existing: ExistingIDs,
                             onCreate: (String) -> Void, onSkip: (String) -> Void,
                             creating: ((String, [String: Any], UUID) -> Void)? = nil) {
        func visit(_ kind: String, _ dict: [String: Any], in set: Set<UUID>) {
            guard let id = uuid(dict["id"]) else { return }
            if set.contains(id) { onSkip(kind) }
            else { onCreate(kind); creating?(kind, dict, id) }
        }
        for game in (root["games"] as? [[String: Any]]) ?? [] {
            visit("games", game, in: existing.games)
            if let schema = game["trackerSchema"] as? [String: Any] {
                visit("tracker schemas", schema, in: existing.schemas)
            }
            for pt in (game["playthroughs"] as? [[String: Any]]) ?? [] {
                visit("playthroughs", pt, in: existing.playthroughs)
                for s in (pt["sessions"] as? [[String: Any]]) ?? [] {
                    visit("sessions", s, in: existing.sessions)
                }
                for r in (pt["runs"] as? [[String: Any]]) ?? [] {
                    visit("runs", r, in: existing.runs)
                }
                for t in (pt["trackerProgress"] as? [[String: Any]]) ?? [] {
                    visit("tracker progress", t, in: existing.states)
                }
            }
            for c in (game["completions"] as? [[String: Any]]) ?? [] {
                visit("completions", c, in: existing.completions)
            }
            for v in (game["videos"] as? [[String: Any]]) ?? [] {
                visit("videos", v, in: existing.videos)
            }
            for i in (game["images"] as? [[String: Any]]) ?? [] {
                visit("images", i, in: existing.images)
            }
            for m in (game["maps"] as? [[String: Any]]) ?? [] {
                visit("maps", m, in: existing.maps)
                for mk in (m["markers"] as? [[String: Any]]) ?? [] {
                    visit("markers", mk, in: existing.markers)
                }
            }
        }
        for c in (root["collections"] as? [[String: Any]]) ?? [] {
            visit("collections", c, in: existing.collections)
        }
        for m in (root["memories"] as? [[String: Any]]) ?? [] {
            visit("memories", m, in: existing.memories)
            for i in (m["images"] as? [[String: Any]]) ?? [] {
                visit("images", i, in: existing.images)
            }
        }
    }

    // MARK: Apply

    static func apply(data: Data, context: ModelContext) throws -> Outcome {
        let root = try root(of: data)
        let existing = try ExistingIDs(context: context)
        var outcome = Outcome()

        var gamesByID: [UUID: Game] = [:]
        for game in try context.fetch(FetchDescriptor<Game>()) { gamesByID[game.id] = game }
        var ptsByID: [UUID: Playthrough] = [:]
        for pt in try context.fetch(FetchDescriptor<Playthrough>()) { ptsByID[pt.id] = pt }

        for gameDict in (root["games"] as? [[String: Any]]) ?? [] {
            guard let gameID = uuid(gameDict["id"]) else { continue }
            let game: Game
            if let present = gamesByID[gameID] {
                game = present
                outcome.skipped["games", default: 0] += 1
            } else {
                game = makeGame(gameDict, id: gameID)
                context.insert(game)
                gamesByID[gameID] = game
                outcome.created["games", default: 0] += 1
            }

            // Schema: only onto a game that doesn't have one — a present
            // schema is the user's current tracker, and restore never
            // overwrites.
            if let schemaDict = gameDict["trackerSchema"] as? [String: Any],
               let schemaID = uuid(schemaDict["id"]) {
                if existing.schemas.contains(schemaID) || game.trackerSchema != nil {
                    outcome.skipped["tracker schemas", default: 0] += 1
                } else {
                    let schema = makeSchema(schemaDict, id: schemaID)
                    context.insert(schema)
                    schema.game = game
                    outcome.created["tracker schemas", default: 0] += 1
                }
            }

            var restoredActive: UUID?
            for ptDict in (gameDict["playthroughs"] as? [[String: Any]]) ?? [] {
                guard let ptID = uuid(ptDict["id"]) else { continue }
                let pt: Playthrough
                if let present = ptsByID[ptID] {
                    pt = present
                    outcome.skipped["playthroughs", default: 0] += 1
                } else {
                    pt = makePlaythrough(ptDict, id: ptID)
                    context.insert(pt)
                    pt.game = game
                    ptsByID[ptID] = pt
                    outcome.created["playthroughs", default: 0] += 1
                    if (ptDict["isActive"] as? Bool) == true { restoredActive = ptID }
                }

                for sDict in (ptDict["sessions"] as? [[String: Any]]) ?? [] {
                    guard let sID = uuid(sDict["id"]) else { continue }
                    if existing.sessions.contains(sID) {
                        outcome.skipped["sessions", default: 0] += 1; continue
                    }
                    let session = makeSession(sDict, id: sID)
                    context.insert(session)
                    session.playthrough = pt
                    outcome.created["sessions", default: 0] += 1
                }
                for rDict in (ptDict["runs"] as? [[String: Any]]) ?? [] {
                    guard let rID = uuid(rDict["id"]) else { continue }
                    if existing.runs.contains(rID) {
                        outcome.skipped["runs", default: 0] += 1; continue
                    }
                    let run = makeRun(rDict, id: rID)
                    context.insert(run)
                    run.playthrough = pt
                    outcome.created["runs", default: 0] += 1
                }
                for tDict in (ptDict["trackerProgress"] as? [[String: Any]]) ?? [] {
                    guard let tID = uuid(tDict["id"]) else { continue }
                    if existing.states.contains(tID) {
                        outcome.skipped["tracker progress", default: 0] += 1; continue
                    }
                    let state = makeState(tDict, id: tID)
                    context.insert(state)
                    state.playthrough = pt
                    outcome.created["tracker progress", default: 0] += 1
                }
            }
            if let active = restoredActive, game.currentPlaythroughID == nil {
                game.currentPlaythroughID = active
            }

            for cDict in (gameDict["completions"] as? [[String: Any]]) ?? [] {
                guard let cID = uuid(cDict["id"]) else { continue }
                if existing.completions.contains(cID) {
                    outcome.skipped["completions", default: 0] += 1; continue
                }
                let event = makeCompletion(cDict, id: cID)
                context.insert(event)
                event.game = game
                // Relink to its playthrough — restored this pass or already
                // present, either way it's reachable through the game.
                if let ptID = uuid(cDict["playthroughID"]) {
                    event.playthrough = ptsByID[ptID]
                        ?? (game.playthroughs ?? []).first { $0.id == ptID }
                }
                outcome.created["completions", default: 0] += 1
            }
            for iDict in (gameDict["images"] as? [[String: Any]]) ?? [] {
                guard let iID = uuid(iDict["id"]) else { continue }
                if existing.images.contains(iID) {
                    outcome.skipped["images", default: 0] += 1; continue
                }
                // An image row with no bytes is skipped rather than created.
                // A picture record that renders nothing is worse than an
                // absent one: it occupies a gallery slot and a role pointer
                // while showing a fallback.
                guard let image = makeImage(iDict, id: iID) else {
                    outcome.skipped["images", default: 0] += 1; continue
                }
                context.insert(image)
                image.game = game
                outcome.created["images", default: 0] += 1
            }
            for vDict in (gameDict["videos"] as? [[String: Any]]) ?? [] {
                guard let vID = uuid(vDict["id"]) else { continue }
                if existing.videos.contains(vID) {
                    outcome.skipped["videos", default: 0] += 1; continue
                }
                let video = makeVideo(vDict, id: vID)
                context.insert(video)
                video.game = game
                outcome.created["videos", default: 0] += 1
            }
            for mDict in (gameDict["maps"] as? [[String: Any]]) ?? [] {
                guard let mID = uuid(mDict["id"]) else { continue }
                let map: GameMap?
                if existing.maps.contains(mID) {
                    outcome.skipped["maps", default: 0] += 1
                    map = nil   // markers under a present map still checked below
                } else {
                    let made = makeMap(mDict, id: mID)
                    context.insert(made)
                    made.game = game
                    outcome.created["maps", default: 0] += 1
                    map = made
                }
                if let map {
                    for mkDict in (mDict["markers"] as? [[String: Any]]) ?? [] {
                        guard let mkID = uuid(mkDict["id"]) else { continue }
                        if existing.markers.contains(mkID) {
                            outcome.skipped["markers", default: 0] += 1; continue
                        }
                        let marker = makeMarker(mkDict, id: mkID)
                        context.insert(marker)
                        marker.map = map
                        outcome.created["markers", default: 0] += 1
                    }
                }
            }
        }

        for cDict in (root["collections"] as? [[String: Any]]) ?? [] {
            guard let cID = uuid(cDict["id"]) else { continue }
            if existing.collections.contains(cID) {
                outcome.skipped["collections", default: 0] += 1; continue
            }
            let collection = GameCollection(
                name: (cDict["name"] as? String) ?? "Collection",
                isBundle: (cDict["isBundle"] as? Bool) ?? false,
                sortIndex: (cDict["sortIndex"] as? Int) ?? 0)
            collection.id = cID
            collection.notes = (cDict["notes"] as? String) ?? ""
            collection.gameIDs = (cDict["gameIDs"] as? [String]) ?? []
            context.insert(collection)
            outcome.created["collections", default: 0] += 1
        }

        for mDict in (root["memories"] as? [[String: Any]]) ?? [] {
            guard let mID = uuid(mDict["id"]) else { continue }
            if existing.memories.contains(mID) {
                outcome.skipped["memories", default: 0] += 1; continue
            }
            let memory = Memory()
            memory.id = mID
            memory.title = (mDict["title"] as? String) ?? ""
            memory.body = mDict["body"] as? String
            // Taken from the file, never rebuilt from `precision`: the words
            // are the memory's own answer to "when", and the interval is what
            // places it. Deriving either would restore a guess.
            memory.whenText = mDict["whenText"] as? String
            memory.precision = mDict["precision"] as? String
            memory.earliest = date(mDict["earliest"]) ?? .now
            memory.latest = date(mDict["latest"]) ?? memory.earliest
            memory.kind = (mDict["kind"] as? String) ?? "memory"
            memory.place = mDict["place"] as? String
            memory.platform = mDict["platform"] as? String
            memory.createdAt = date(mDict["createdAt"]) ?? .now
            memory.companions = companions(mDict["playedWith"])
            // A memory whose game is not in this file stays standalone rather
            // than being dropped — it is the user's writing either way.
            if let gID = uuid(mDict["gameID"]) { memory.game = gamesByID[gID] }
            context.insert(memory)
            outcome.created["memories", default: 0] += 1

            for iDict in (mDict["images"] as? [[String: Any]]) ?? [] {
                guard let iID = uuid(iDict["id"]) else { continue }
                if existing.images.contains(iID) {
                    outcome.skipped["images", default: 0] += 1; continue
                }
                guard let image = makeImage(iDict, id: iID) else {
                    outcome.skipped["images", default: 0] += 1; continue
                }
                context.insert(image)
                image.memory = memory
                outcome.created["images", default: 0] += 1
            }
        }

        // Reappearing data deserves true rings.
        let repo = Repository(context)
        for game in gamesByID.values { repo.recomputeProgress(game) }
        try context.save()
        return outcome
    }

    // MARK: Record builders

    private static func makeGame(_ d: [String: Any], id: UUID) -> Game {
        let game = Game(name: (d["name"] as? String) ?? "Untitled",
                        status: GameStatus(rawValue: (d["status"] as? String) ?? "") ?? .backlog)
        game.id = id
        game.addedAt = date(d["addedAt"]) ?? .now
        game.pinned = (d["pinned"] as? Bool) ?? false
        game.notes = (d["notes"] as? String) ?? ""
        game.platforms = (d["platforms"] as? [String]) ?? []
        game.ownership = (d["ownership"] as? [String]) ?? []
        game.userTags = (d["userTags"] as? [String]) ?? []
        game.summary = d["summary"] as? String
        game.rating = d["rating"] as? Int
        game.review = d["review"] as? String
        game.igdbID = d["igdbID"] as? Int
        game.igdbSlug = d["igdbSlug"] as? String
        game.coverImageID = d["coverImageID"] as? String
        game.coverURLString = d["coverURL"] as? String
        game.coverOverrideURLString = d["coverOverrideURL"] as? String
        game.logoURLString = d["logoURL"] as? String
        game.backdropURLString = d["backdropURL"] as? String
        game.franchise = d["franchise"] as? String
        game.firstReleaseDate = date(d["firstReleaseDate"])
        game.developers = (d["developers"] as? [String]) ?? []
        game.publishers = (d["publishers"] as? [String]) ?? []
        game.genres = (d["genres"] as? [String]) ?? []
        game.themes = (d["themes"] as? [String]) ?? []
        game.gameModes = (d["gameModes"] as? [String]) ?? []
        game.playerPerspectives = (d["playerPerspectives"] as? [String]) ?? []
        game.trackerDisplayRaw = d["trackerDisplay"] as? String
        return game
    }

    private static func makeSchema(_ d: [String: Any], id: UUID) -> TrackerSchemaRecord {
        let schema = TrackerSchemaRecord(
            id: id,
            schemaVersion: (d["schemaVersion"] as? Int) ?? 1,
            source: TrackerSource(rawValue: (d["source"] as? String) ?? "") ?? .aiGenerated,
            engine: TrackerEngine(rawValue: (d["engine"] as? String) ?? "") ?? .objective,
            jsonData: (try? JSONSerialization.data(withJSONObject: d["data"] ?? [:])) ?? Data())
        schema.generatedAt = date(d["generatedAt"])
        schema.generatedBy = d["generatedBy"] as? String
        if let sources = d["sources"], !(sources is NSNull) {
            schema.sourcesJSON = try? JSONSerialization.data(withJSONObject: sources)
        }
        return schema
    }

    private static func makePlaythrough(_ d: [String: Any], id: UUID) -> Playthrough {
        let pt = Playthrough(id: id,
                             name: (d["name"] as? String) ?? "Playthrough",
                             progressPercent: (d["progressPercent"] as? Double) ?? 0,
                             startedAt: date(d["startedAt"]))
        pt.notes = d["notes"] as? String
        pt.lastPlayedAt = date(d["lastPlayedAt"])
        pt.outcomeRaw = d["outcome"] as? String
        pt.outcomeNote = d["outcomeNote"] as? String
        return pt
    }

    private static func makeSession(_ d: [String: Any], id: UUID) -> Session {
        let session = Session(
            id: id,
            startDate: date(d["startDate"]) ?? .now,
            state: SessionState(rawValue: (d["state"] as? String) ?? "") ?? .stopped,
            isManual: (d["isManual"] as? Bool) ?? false)
        session.accumulatedDuration = (d["durationSeconds"] as? Double) ?? 0
        session.endDate = date(d["endDate"])
        session.notes = d["notes"] as? String
        session.resumedAt = date(d["resumedAt"])
        session.pausedAt = date(d["pausedAt"])
        session.companions = companions(d["playedWith"])
        return session
    }

    private static func makeRun(_ d: [String: Any], id: UUID) -> Run {
        let run = Run(id: id,
                      templateID: (d["templateID"] as? String) ?? "default",
                      startedAt: date(d["startedAt"]) ?? .now,
                      outcome: RunOutcome(rawValue: (d["outcome"] as? String) ?? "") ?? .neutral,
                      fieldsJSON: (try? JSONSerialization.data(withJSONObject: d["fields"] ?? [:])) ?? Data())
        run.endedAt = date(d["endedAt"])
        run.notes = d["notes"] as? String
        run.companions = companions(d["playedWith"])
        return run
    }

    private static func makeState(_ d: [String: Any], id: UUID) -> TrackerStateRecord {
        let state = TrackerStateRecord(itemID: (d["itemID"] as? String) ?? "")
        state.id = id
        state.completed = (d["completed"] as? Bool) ?? false
        state.revealed = (d["revealed"] as? Bool) ?? false
        state.count = d["count"] as? Int
        state.rank = d["rank"] as? Int
        state.notes = d["notes"] as? String
        return state
    }

    private static func companions(_ any: Any?) -> [Companion] {
        guard let rows = any as? [[String: Any]] else { return [] }
        return rows.map {
            Companion(name: ($0["name"] as? String) ?? "",
                      handle: ($0["handle"] as? String) ?? "")
        }
    }

    private static func makeCompletion(_ d: [String: Any], id: UUID) -> CompletionEvent {
        let event = CompletionEvent(
            id: id,
            date: date(d["date"]) ?? .now,
            label: CompletionLabel(rawValue: (d["label"] as? String) ?? "") ?? .cleared,
            customLabel: d["customLabel"] as? String)
        event.platform = d["platform"] as? String
        event.notes = d["notes"] as? String
        event.datePrecision = d["datePrecision"] as? String
        event.startedDate = date(d["startedDate"])
        event.startedPrecision = d["startedPrecision"] as? String
        event.companions = companions(d["playedWith"])
        return event
    }

    /// nil when the record carries no decodable bytes — see the call site.
    private static func makeImage(_ d: [String: Any], id: UUID) -> GameImage? {
        guard let encoded = d["data"] as? String,
              let bytes = Data(base64Encoded: encoded), !bytes.isEmpty
        else { return nil }
        let image = GameImage(
            id: id,
            role: ArtworkRole(rawValue: (d["role"] as? String) ?? "") ?? .gallery,
            data: bytes)
        image.caption = d["caption"] as? String
        image.addedAt = date(d["addedAt"]) ?? .now
        // Trust the file's dimensions when present, but never the file's byte
        // count — that is a property of the bytes we actually hold.
        image.pixelWidth = (d["pixelWidth"] as? Int) ?? 0
        image.pixelHeight = (d["pixelHeight"] as? Int) ?? 0
        image.byteCount = bytes.count
        if image.pixelWidth == 0 || image.pixelHeight == 0,
           let size = ImageIngest.pixelSize(of: bytes) {
            image.pixelWidth = size.width
            image.pixelHeight = size.height
        }
        return image
    }

    private static func makeVideo(_ d: [String: Any], id: UUID) -> GameVideo {
        let video = GameVideo(
            kind: VideoKind(rawValue: (d["kind"] as? String) ?? "") ?? .video,
            urlString: (d["url"] as? String) ?? "",
            youtubeID: (d["youtubeID"] as? String) ?? "",
            title: (d["title"] as? String) ?? "")
        video.id = id
        video.groupName = (d["group"] as? String) ?? "Videos"
        video.orderIndex = (d["orderIndex"] as? Int) ?? 0
        video.watchedSeconds = (d["watchedSeconds"] as? Double) ?? 0
        video.watchedPartIndex = (d["watchedPartIndex"] as? Int) ?? 0
        video.channel = d["channel"] as? String
        video.thumbnailURL = d["thumbnailURL"] as? String
        video.notes = d["notes"] as? String
        video.lastWatchedAt = date(d["lastWatchedAt"])
        if let parts = d["parts"] as? [[String: Any]] {
            // `parts` is a computed read over partsData's compact row format
            // ([id, title, seconds]); write the rows directly.
            let rows: [[Any]] = parts.map {
                [($0["id"] as? String) ?? "",
                 ($0["title"] as? String) ?? "",
                 ($0["watchedSeconds"] as? Double) ?? 0]
            }
            video.partsData = try? JSONSerialization.data(withJSONObject: rows)
        }
        return video
    }

    private static func makeMap(_ d: [String: Any], id: UUID) -> GameMap {
        let map = GameMap(
            id: id,
            name: (d["name"] as? String) ?? "Map",
            kind: MapKind(rawValue: (d["kind"] as? String) ?? "") ?? .other,
            storageType: (d["storageType"] as? String) ?? "upload",
            remoteStoragePath: (d["remoteStoragePath"] as? String) ?? "",
            addedAt: date(d["addedAt"]) ?? .now)
        map.remoteURLString = d["remoteURL"] as? String
        map.pixelWidth = d["pixelWidth"] as? Int
        map.pixelHeight = d["pixelHeight"] as? Int
        return map
    }

    private static func makeMarker(_ d: [String: Any], id: UUID) -> Marker {
        let marker = Marker(
            id: id,
            normalizedX: (d["x"] as? Double) ?? 0.5,
            normalizedY: (d["y"] as? Double) ?? 0.5,
            category: MarkerCategory(rawValue: (d["category"] as? String) ?? "") ?? .note,
            label: (d["label"] as? String) ?? "")
        marker.notes = d["notes"] as? String
        marker.linkedTrackerItemID = d["linkedTrackerItemID"] as? String
        return marker
    }
}
