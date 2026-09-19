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
    /// The newest format this build understands. **Older files are read, not
    /// refused** — see the gate in `root(of:)`.
    nonisolated static let supportedVersion = 3

    enum ImportError: LocalizedError {
        case notAnExport
        case unsupportedVersion(Int)
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .notAnExport:
                "This file isn't a LevelSelect export — no manifest found."
            case .unsupportedVersion(let v):
                "This export is format version \(v); this build reads up to version \(LibraryImport.supportedVersion). It was made by a newer version of LevelSelect."
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
        // **Older is fine; newer is not.** Equality was right when there was
        // only one version, and became a bug the moment there were two: it
        // refused every backup made before memories existed, which is exactly
        // the file someone restoring from a backup is most likely to hold.
        //
        // Reading down is safe because the format only ever gains keys — a v1
        // file simply has no `memories`, and every lookup here already treats
        // a missing key as an empty list. Reading *up* is not: a newer file
        // carries records this build has no model for, and dropping them
        // silently is the failure v2 exists to fix.
        guard version >= 1, version <= Self.supportedVersion else {
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
        var trackerItemDetails = Set<UUID>()
        /// The profile is a singleton, so it is present-or-absent rather than
        /// matched by id — but the preview still has to say which.
        var hasProfile = false

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
            trackerItemDetails = Set(try context.fetch(FetchDescriptor<TrackerItemDetail>()).map(\.id))
            hasProfile = !(try context.fetch(FetchDescriptor<PlayerProfile>()).isEmpty)
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

        // **The profile counts, or it cannot be restored at all.**
        //
        // `applyProfile` has always known how to rebuild a missing identity
        // from a backup, but the walk never counted it — so a file whose only
        // missing record was the profile previewed as "everything is already
        // in your library" and `LibraryImportView` hid the Restore button
        // behind `totalCreates > 0`. The one record you cannot re-type from
        // memory (a name, five handles and an avatar) was the one the
        // importer silently refused to hand back.
        //
        // Not matched by id like the rest: there is only ever one, and
        // `applyProfile` fills a blank rather than overwriting a live
        // identity, so present means skip.
        if root["profile"] != nil {
            existing.hasProfile ? onSkip("profile") : onCreate("profile")
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
        // Maps and memories need the OBJECT, not just the id.
        //
        // A partial restore is precisely the case where the parent survived
        // and a child under it did not, so a present parent has to be usable
        // as the relationship target — the same thing the game and playthrough
        // paths above already do.
        var mapsByID: [UUID: GameMap] = [:]
        for map in try context.fetch(FetchDescriptor<GameMap>()) { mapsByID[map.id] = map }
        var memoriesByID: [UUID: Memory] = [:]
        for m in try context.fetch(FetchDescriptor<Memory>()) { memoriesByID[m.id] = m }

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

            // The user's own notes and renames on tracker items.
            //
            // Game-scoped, and restored whether or not the game already
            // existed — a present game with a lost note is exactly the partial
            // disaster the importer promises to repair.
            for dDict in (gameDict["trackerItemDetails"] as? [[String: Any]]) ?? [] {
                guard let dID = uuid(dDict["id"]) else { continue }
                if existing.trackerItemDetails.contains(dID) {
                    outcome.skipped["tracker notes", default: 0] += 1; continue
                }
                let detail = TrackerItemDetail(itemID: (dDict["itemID"] as? String) ?? "")
                detail.id = dID
                detail.note = dDict["note"] as? String
                detail.chosenName = dDict["chosenName"] as? String
                detail.sourceName = dDict["sourceName"] as? String
                detail.createdAt = date(dDict["createdAt"]) ?? .now
                detail.updatedAt = date(dDict["updatedAt"]) ?? .now
                context.insert(detail)
                detail.game = game
                outcome.created["tracker notes", default: 0] += 1
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
                    // The comment below was true of the intent and false of the
                    // code: `map = nil` meant the `if let` skipped every marker
                    // under a map that already existed, which is the one case a
                    // partial restore is for.
                    map = mapsByID[mID]   // markers under a present map still checked below
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
            // A present memory is still the parent for its photos.
            //
            // This used to `continue`, so a memory that survived with one
            // picture missing could never get that picture back — while
            // Preview, which walks nested images whether or not the parent
            // exists, promised the user it would.
            let memory: Memory
            if let present = memoriesByID[mID] {
                outcome.skipped["memories", default: 0] += 1
                memory = present
            } else {
                let made = Memory()
                made.id = mID
                made.title = (mDict["title"] as? String) ?? ""
                made.body = mDict["body"] as? String
                // Taken from the file, never rebuilt from `precision`: the words
                // are the memory's own answer to "when", and the interval is what
                // places it. Deriving either would restore a guess.
                made.whenText = mDict["whenText"] as? String
                made.precision = mDict["precision"] as? String
                made.earliest = date(mDict["earliest"]) ?? .now
                made.latest = date(mDict["latest"]) ?? made.earliest
                made.kind = (mDict["kind"] as? String) ?? "memory"
                made.place = mDict["place"] as? String
                made.platform = mDict["platform"] as? String
                made.createdAt = date(mDict["createdAt"]) ?? .now
                made.companions = companions(mDict["playedWith"])
                // A memory whose game is not in this file stays standalone rather
                // than being dropped — it is the user's writing either way.
                if let gID = uuid(mDict["gameID"]) { made.game = gamesByID[gID] }
                context.insert(made)
                memoriesByID[mID] = made
                outcome.created["memories", default: 0] += 1
                memory = made
            }

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

        applyProfile(root["profile"] as? [String: Any], context: context, outcome: &outcome)
        applyAppearance(root["appearance"] as? [String: Any], context: context, outcome: &outcome)

        // Reappearing data deserves true rings.
        let repo = Repository(context)
        for game in gamesByID.values { repo.recomputeProgress(game) }
        try context.save()
        return outcome
    }

    /// Restore the player's identity — but never over one that already exists.
    ///
    /// A present profile is the user's current identity; a restore fills a
    /// blank, it does not overwrite a name and avatar someone is using. Same
    /// rule the tracker schema follows above.
    private static func applyProfile(
        _ d: [String: Any]?, context: ModelContext, outcome: inout Outcome
    ) {
        guard let d else { return }
        let present = (try? context.fetch(FetchDescriptor<PlayerProfile>()))?.first
        if present != nil {
            outcome.skipped["profile", default: 0] += 1
            return
        }
        let profile = PlayerProfile()
        if let id = uuid(d["id"]) { profile.id = id }
        profile.createdAt = date(d["createdAt"]) ?? .now
        profile.updatedAt = date(d["updatedAt"]) ?? .now
        profile.displayName = d["displayName"] as? String
        profile.avatarData = (d["avatar"] as? String).flatMap { Data(base64Encoded: $0) }
        profile.nameColorRaw = d["nameColor"] as? String
        profile.useHandleAsName = (d["useHandleAsName"] as? Bool) ?? false
        if let handles = d["handles"] as? [String: String] { profile.handles = handles }
        context.insert(profile)
        outcome.created["profile", default: 0] += 1
    }

    /// Restore appearance choices.
    ///
    /// Through v2 the exporter wrote this block and NOTHING read it — the
    /// importer ended after memories, so every accent, status color and custom
    /// word in the file was decorative. Unlike the profile this fills the
    /// existing settings row, because there is always exactly one and a blank
    /// default is not an identity worth protecting.
    private static func applyAppearance(
        _ d: [String: Any]?, context: ModelContext, outcome: inout Outcome
    ) {
        guard let d else { return }
        let theme = ThemePalette.fetchOrCreate(in: context)
        if let v = d["accentHex"] as? String { theme.accentHex = v }
        if let v = d["backgroundHex"] as? String { theme.backgroundHex = v }
        if let v = d["accentHue"] as? Double { theme.accentHue = v }
        if let v = d["accentSaturation"] as? Double { theme.accentSaturation = v }
        if let v = d["paletteLinked"] as? Bool { theme.paletteLinked = v }
        if let v = d["accentHexLight"] as? String { theme.accentHexLight = v }
        if let v = d["accentHexDark"] as? String { theme.accentHexDark = v }
        if let v = d["backgroundHexLight"] as? String { theme.backgroundHexLight = v }
        if let v = d["backgroundHexDark"] as? String { theme.backgroundHexDark = v }
        if let v = d["appearance"] as? String { theme.appearanceRaw = v }
        if let v = d["statusColors"] as? [String: String] { theme.statusColors = v }
        if let v = d["statusNames"] as? [String: String] { theme.statusNames = v }
        // Sanitized on the way in: a backup can be older or newer than this
        // build, and a name it no longer offers must not reach a shelf.
        if let v = d["platformNames"] as? [String: String] {
            theme.platformNames = PlatformNaming.sanitized(v)
        }
        if let v = d["pageBackground"] as? String { theme.pageBackgroundRaw = v }
        if let v = d["gamePageLayout"] as? String { theme.gamePageLayoutRaw = v }
        if let v = d["defaultTrackerDisplay"] as? String { theme.defaultTrackerDisplayRaw = v }
        if let v = d["defaultMergeMode"] as? String { theme.defaultMergeModeRaw = v }
        if let v = d["overlappingTimerPolicy"] as? String { theme.overlappingTimerPolicyRaw = v }
        if let v = d["starNames"] as? [String] { theme.starNames = v }
        if let v = d["backdropIntensity"] as? String { theme.backdropIntensityRaw = v }
        if let v = d["showItemHints"] as? Bool { theme.showItemHints = v }
        if let v = d["showGameLogos"] as? Bool { theme.showGameLogos = v }
        if let v = d["dekuWishlistURL"] as? String { theme.dekuWishlistURLString = v }
        if let v = d["platformIconVariants"] as? String {
            theme.platformIconVariantsData = Data(base64Encoded: v)
        }
        if let v = d["savedSwatches"] as? String {
            theme.savedSwatchesData = Data(base64Encoded: v)
        }
        theme.updatedAt = .now
        // Push it into the live palette, so a restore repaints the app instead
        // of waiting for the next launch.
        ThemePalette.refresh(from: theme)
        outcome.created["appearance", default: 0] += 1
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
        // v3. Nil here is not "owned nowhere" — `ownedPlatformNames` reads nil
        // as pre-V3 data and falls back to `platforms.first`, so restoring a
        // v1/v2 file must leave it nil rather than write an empty array.
        game.ownedPlatforms = d["ownedPlatforms"] as? [String]
        game.platformReleasesData = (d["platformReleases"] as? String).flatMap { Data(base64Encoded: $0) }
        game.showItemHintsOverride = d["showItemHintsOverride"] as? Bool
        game.userTags = (d["userTags"] as? [String]) ?? []
        game.summary = d["summary"] as? String
        game.rating = d["rating"] as? Int
        game.review = d["review"] as? String
        game.igdbID = d["igdbID"] as? Int
        game.igdbSlug = d["igdbSlug"] as? String
        game.wikidataID = d["wikidataID"] as? String
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
        // Absent in every file written before build 37, which is exactly the
        // zero this defaults to.
        pt.carriedOverSeconds = (d["carriedOverSeconds"] as? Double) ?? 0
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
        // v3: the chosen form, and the timestamp "where you left off" reads.
        state.completedAt = date(d["completedAt"])
        state.selectedVariant = d["selectedVariant"] as? String
        state.selectedVariantUpdatedAt = date(d["selectedVariantUpdatedAt"])
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
