import Foundation
import SwiftData

/// **Make the library match a backup, or clear it.**
///
/// `LibraryImport` only ever adds, which is right for merging and useless for
/// "put me back where I was": a record the library already has is never
/// touched, and one it shouldn't have is never removed. Tim, 2026-09-17,
/// after a Development merge damaged his library: *"That kind of defeats the
/// purpose of making a backup if you can't clear the entire app and restore
/// from a backup."*
///
/// Replace is one step, not erase-then-restore. Erasing tombstones every
/// record, and an additive restore would then skip them all, because they
/// still own their ids. Doing both in one pass also means a failure never
/// leaves an empty library.
///
/// The rules:
///
/// - **In the backup:** the record takes the backup's values and is brought
///   back if it had been deleted. Missing records are created, by the import.
/// - **Not in the backup:** it moves to Recently Deleted, never gone outright.
///   Only the top of a branch is tombstoned (a game, not its sessions), so
///   restoring the game from Recently Deleted brings everything under it back.
/// - Every write is stamped now, so this is the newest edit on every device.
/// - A copy of the library as it was is written first (`safetyCopy`).
///
/// Badges are left alone: backups don't carry them, and they are earned from
/// the library rather than entered.
@MainActor
enum LibraryReplace {

    struct Preview: Equatable {
        var exportedAt = ""
        var appVersion = ""
        var gamesInBackup = 0
        /// Present in the library and the backup; takes the backup's values.
        var matched = 0
        /// In the backup and in Recently Deleted; comes back.
        var revived = 0
        /// In the backup only; created.
        var added = 0
        /// Live now, not in the backup; moves to Recently Deleted.
        var removed: [String: Int] = [:]
        var totalRemoved: Int { removed.values.reduce(0, +) }
    }

    struct Outcome: Equatable {
        var matched = 0
        var revived = 0
        var added = 0
        var removed: [String: Int] = [:]
        var safetyCopy: URL?
        var totalRemoved: Int { removed.values.reduce(0, +) }
    }

    // MARK: Safety copy

    /// Where copies taken before a replace or erase go. In Documents, which
    /// the Files app shows under LevelSelect.
    static var safetyFolder: URL {
        safetyFolderOverride
            ?? URL.documentsDirectory.appending(path: "Safety Copies", directoryHint: .isDirectory)
    }

    /// Tests write their copies somewhere disposable.
    static var safetyFolderOverride: URL?

    /// Where a person finds the copies, in their platform's words.
    static var safetyFolderDescription: String {
        #if os(macOS)
        "LevelSelect's Documents folder, under Safety Copies"
        #else
        "Files → LevelSelect → Safety Copies"
        #endif
    }

    /// Writes the library as it is now, keeping the newest five.
    static func safetyCopy(context: ModelContext, reason: String, now: Date = .now) throws -> URL {
        let data = try LibraryExport.makeJSON(context: context)
        let folder = safetyFolder
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash)
            .time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let url = folder.appending(path: "LevelSelect before \(reason) \(stamp).json")
        try data.write(to: url, options: .atomic)
        let copies = ((try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in copies.dropFirst(5) { try? fm.removeItem(at: old) }
        return url
    }

    // MARK: Replace

    static func preview(data: Data, context: ModelContext) throws -> Preview {
        let root = try LibraryImport.root(of: data)
        var preview = Preview()
        if let manifest = root["manifest"] as? [String: Any] {
            preview.exportedAt = (manifest["exportedAt"] as? String) ?? ""
            preview.appVersion = (manifest["appVersion"] as? String) ?? ""
        }
        preview.gamesInBackup = ((root["games"] as? [[String: Any]]) ?? []).count
        let library = try Library(context: context)
        let file = FileIDs(root: root, library: library)
        for (id, _) in file.all {
            if let deleted = library.deletedAt[id] {
                if deleted == nil { preview.matched += 1 } else { preview.revived += 1 }
            } else {
                preview.added += 1
            }
        }
        preview.removed = library.removals(keeping: file).counts
        return preview
    }

    static func apply(data: Data, context: ModelContext, now: Date = .now) throws -> Outcome {
        let root = try LibraryImport.root(of: data)
        var out = Outcome()
        out.safetyCopy = try safetyCopy(context: context, reason: "replace", now: now)

        // Consoles first, matched by id and then by name. The import only
        // matches LIVE consoles by name, so a deleted Genesis would otherwise
        // get a second record beside it, and the platform fold would then
        // hard-delete one of the two.
        let before = try Library(context: context)
        for d in (root["consoles"] as? [[String: Any]]) ?? [] {
            guard let console = before.console(for: d) else { continue }
            if console.deletedAt != nil { console.deletedAt = nil }
            console.platform = PlatformKey.canonical((d["platform"] as? String) ?? console.platform)
        }

        // Everything the library lacks, created with its original id.
        _ = try LibraryImport.apply(data: data, context: context)

        // Everything else in the file, overwritten and relinked.
        let library = try Library(context: context)
        let file = FileIDs(root: root, library: library)
        for (id, _) in file.all {
            switch before.deletedAt[id] {
            case .none: out.added += 1
            case .some(.none): out.matched += 1
            case .some(.some): out.revived += 1
            }
        }
        overwrite(root: root, library: library, now: now)

        // What the backup doesn't have.
        let removals = library.removals(keeping: file)
        out.removed = removals.counts
        let repo = Repository(context)
        for game in removals.games {
            for session in repo.runningSessions(in: game) { repo.stopSession(session, at: now) }
        }
        for session in removals.sessions where session.state != .stopped {
            repo.stopSession(session, at: now)
        }
        removals.tombstone(at: now)

        var appearance = LibraryImport.Outcome()
        LibraryImport.applyAppearance(root["appearance"] as? [String: Any], context: context,
                                      outcome: &appearance, replacing: true)
        if let d = root["profile"] as? [String: Any],
           let profile = try context.fetch(FetchDescriptor<PlayerProfile>(
               sortBy: [SortDescriptor(\.createdAt)])).first {
            LibraryImport.fillProfile(profile, d)
            profile.updatedAt = now
        }

        for game in library.games.values where game.deletedAt == nil {
            repo.recomputeProgress(game)
        }
        try context.save()
        return out
    }

    private static func overwrite(root: [String: Any], library: Library, now: Date) {
        let uuid = LibraryImport.uuid
        func stamp(_ m: some Syncable) {
            m.deletedAt = nil
            m.updatedAt = now
            m.revision += 1
        }
        func stamp(_ image: GameImage) {
            image.deletedAt = nil
            image.updatedAt = now
            image.revision += 1
        }
        func images(_ list: Any?, into attach: (GameImage) -> Void) {
            for d in (list as? [[String: Any]]) ?? [] {
                guard let id = uuid(d["id"]), let image = library.images[id],
                      LibraryImport.fillImage(image, d) else { continue }
                attach(image)
                stamp(image)
            }
        }

        for gd in (root["games"] as? [[String: Any]]) ?? [] {
            guard let gid = uuid(gd["id"]), let game = library.games[gid] else { continue }
            LibraryImport.fillGame(game, gd)
            stamp(game)

            if let sd = gd["trackerSchema"] as? [String: Any], let sid = uuid(sd["id"]),
               let schema = library.schemas[sid] {
                LibraryImport.fillSchema(schema, sd)
                schema.game = game
                stamp(schema)
            }
            for dd in (gd["trackerItemDetails"] as? [[String: Any]]) ?? [] {
                guard let id = uuid(dd["id"]), let detail = library.details[id] else { continue }
                LibraryImport.fillDetail(detail, dd)
                detail.game = game
                stamp(detail)
            }
            for pd in (gd["playthroughs"] as? [[String: Any]]) ?? [] {
                guard let pid = uuid(pd["id"]), let pt = library.playthroughs[pid] else { continue }
                LibraryImport.fillPlaythrough(pt, pd)
                pt.game = game
                stamp(pt)
                if (pd["isActive"] as? Bool) == true { game.currentPlaythroughID = pid }
                for sd in (pd["sessions"] as? [[String: Any]]) ?? [] {
                    guard let id = uuid(sd["id"]), let s = library.sessions[id] else { continue }
                    LibraryImport.fillSession(s, sd)
                    s.playthrough = pt
                    stamp(s)
                }
                for rd in (pd["runs"] as? [[String: Any]]) ?? [] {
                    guard let id = uuid(rd["id"]), let r = library.runs[id] else { continue }
                    LibraryImport.fillRun(r, rd)
                    r.playthrough = pt
                    stamp(r)
                }
                for td in (pd["trackerProgress"] as? [[String: Any]]) ?? [] {
                    guard let id = uuid(td["id"]), let t = library.states[id] else { continue }
                    LibraryImport.fillState(t, td)
                    t.playthrough = pt
                    stamp(t)
                }
            }
            for cd in (gd["completions"] as? [[String: Any]]) ?? [] {
                guard let id = uuid(cd["id"]), let c = library.completions[id] else { continue }
                LibraryImport.fillCompletion(c, cd)
                c.game = game
                c.playthrough = uuid(cd["playthroughID"]).flatMap { library.playthroughs[$0] }
                stamp(c)
            }
            images(gd["images"]) { $0.game = game }
            for vd in (gd["videos"] as? [[String: Any]]) ?? [] {
                guard let id = uuid(vd["id"]), let v = library.videos[id] else { continue }
                LibraryImport.fillVideo(v, vd)
                v.game = game
                stamp(v)
            }
            for md in (gd["maps"] as? [[String: Any]]) ?? [] {
                guard let id = uuid(md["id"]), let map = library.maps[id] else { continue }
                LibraryImport.fillMap(map, md)
                map.game = game
                stamp(map)
                for kd in (md["markers"] as? [[String: Any]]) ?? [] {
                    guard let kid = uuid(kd["id"]), let marker = library.markers[kid] else { continue }
                    LibraryImport.fillMarker(marker, kd)
                    marker.map = map
                    stamp(marker)
                }
            }
        }
        for cd in (root["collections"] as? [[String: Any]]) ?? [] {
            guard let id = uuid(cd["id"]), let c = library.collections[id] else { continue }
            LibraryImport.fillCollection(c, cd)
            stamp(c)
        }
        for md in (root["memories"] as? [[String: Any]]) ?? [] {
            guard let id = uuid(md["id"]), let m = library.memories[id] else { continue }
            LibraryImport.fillMemory(m, md)
            m.game = uuid(md["gameID"]).flatMap { library.games[$0] }
            stamp(m)
            images(md["images"]) { $0.memory = m }
        }
        for cd in (root["consoles"] as? [[String: Any]]) ?? [] {
            guard let console = library.console(for: cd) else { continue }
            LibraryImport.fillConsole(console, cd)
            stamp(console)
            images(cd["images"]) { $0.console = console }
        }
        for fd in (root["newsFeeds"] as? [[String: Any]]) ?? [] {
            guard let id = uuid(fd["id"]), let feed = library.feeds[id] else { continue }
            LibraryImport.fillFeed(feed, fd)
            stamp(feed)
        }
        for ad in (root["newsArticles"] as? [[String: Any]]) ?? [] {
            guard let id = uuid(ad["id"]), let item = library.articles[id] else { continue }
            LibraryImport.fillArticle(item, ad)
            stamp(item)
        }
    }

    // MARK: Erase

    /// Everything to Recently Deleted: games (with all that hangs off them),
    /// collections, memories and consoles. Appearance and your profile stay —
    /// they are settings and identity, not library. Timers are stopped first.
    static func erase(context: ModelContext, now: Date = .now) throws -> Outcome {
        var out = Outcome()
        out.safetyCopy = try safetyCopy(context: context, reason: "erase", now: now)
        let library = try Library(context: context)
        let removals = library.removals(keeping: FileIDs(empty: ()))
        let repo = Repository(context)
        for game in removals.games {
            for session in repo.runningSessions(in: game) { repo.stopSession(session, at: now) }
        }
        out.removed = removals.counts
        removals.tombstone(at: now)
        try context.save()
        return out
    }

    /// What erase would move, for its confirmation screen.
    static func erasePreview(context: ModelContext) throws -> [String: Int] {
        try Library(context: context).removals(keeping: FileIDs(empty: ())).counts
    }

    // MARK: The library, indexed

    /// Every record by id, deleted ones included.
    private struct Library {
        var games: [UUID: Game] = [:]
        var playthroughs: [UUID: Playthrough] = [:]
        var sessions: [UUID: Session] = [:]
        var runs: [UUID: Run] = [:]
        var states: [UUID: TrackerStateRecord] = [:]
        var schemas: [UUID: TrackerSchemaRecord] = [:]
        var details: [UUID: TrackerItemDetail] = [:]
        var completions: [UUID: CompletionEvent] = [:]
        var videos: [UUID: GameVideo] = [:]
        var maps: [UUID: GameMap] = [:]
        var markers: [UUID: Marker] = [:]
        var images: [UUID: GameImage] = [:]
        var collections: [UUID: GameCollection] = [:]
        var memories: [UUID: Memory] = [:]
        var consoles: [UUID: Console] = [:]
        var feeds: [UUID: NewsFeed] = [:]
        var articles: [UUID: NewsItemState] = [:]
        /// Every id → its `deletedAt`, for the preview's arithmetic.
        var deletedAt: [UUID: Date?] = [:]

        init(context: ModelContext) throws {
            func load<M: PersistentModel & Syncable>(_ type: M.Type) throws -> [UUID: M] {
                var out: [UUID: M] = [:]
                for m in try context.fetch(FetchDescriptor<M>()) { out[m.id] = m }
                return out
            }
            games = try load(Game.self)
            playthroughs = try load(Playthrough.self)
            sessions = try load(Session.self)
            runs = try load(Run.self)
            states = try load(TrackerStateRecord.self)
            schemas = try load(TrackerSchemaRecord.self)
            details = try load(TrackerItemDetail.self)
            completions = try load(CompletionEvent.self)
            videos = try load(GameVideo.self)
            maps = try load(GameMap.self)
            markers = try load(Marker.self)
            collections = try load(GameCollection.self)
            memories = try load(Memory.self)
            consoles = try load(Console.self)
            feeds = try load(NewsFeed.self)
            articles = try load(NewsItemState.self)
            for image in try context.fetch(FetchDescriptor<GameImage>()) { images[image.id] = image }

            func note(_ dict: [UUID: some Syncable]) {
                for (id, m) in dict { deletedAt[id] = .some(m.deletedAt) }
            }
            note(games); note(playthroughs); note(sessions); note(runs); note(states)
            note(schemas); note(details); note(completions); note(videos); note(maps)
            note(markers); note(collections); note(memories); note(consoles)
            note(feeds); note(articles)
            for (id, image) in images { deletedAt[id] = .some(image.deletedAt) }
        }

        /// The console a backup entry means: the same id, or else the same
        /// system, preferring one that is not deleted.
        func console(for d: [String: Any]) -> Console? {
            if let id = LibraryImport.uuid(d["id"]), let c = consoles[id] { return c }
            guard let platform = d["platform"] as? String else { return nil }
            let key = PlatformKey.canonical(platform)
            let matches = consoles.values.filter { PlatformKey.canonical($0.platform) == key }
            return matches.first { $0.deletedAt == nil } ?? matches.min { $0.createdAt < $1.createdAt }
        }

        /// Live records `file` doesn't list, taking only the top of each
        /// branch: a child is removed only when its parent stays.
        func removals(keeping file: FileIDs) -> Removals {
            var r = Removals()
            func gone(_ id: UUID) -> Bool { !file.contains(id) }
            func kept(_ id: UUID?) -> Bool { id.map(file.contains) ?? false }

            r.games = games.values.filter { $0.deletedAt == nil && gone($0.id) }
            r.collections = collections.values.filter { $0.deletedAt == nil && gone($0.id) }
            r.memories = memories.values.filter { $0.deletedAt == nil && gone($0.id) }
            r.consoles = consoles.values.filter { $0.deletedAt == nil && !file.keepsConsole($0) }
            r.feeds = feeds.values.filter { $0.deletedAt == nil && gone($0.id) }
            r.articles = articles.values.filter { $0.deletedAt == nil && gone($0.id) }

            // A child whose parent stays goes on its own; so does one with no
            // parent at all, which nothing would ever bring back with it.
            func child<M: Syncable>(_ dict: [UUID: M], parent: (M) -> UUID?) -> [M] {
                dict.values.filter {
                    guard $0.deletedAt == nil, gone($0.id) else { return false }
                    let owner = parent($0)
                    return owner == nil || kept(owner)
                }
            }
            r.playthroughs = child(playthroughs) { $0.game?.id }
            r.sessions = child(sessions) { $0.playthrough?.id }
            r.runs = child(runs) { $0.playthrough?.id }
            r.states = child(states) { $0.playthrough?.id }
            r.schemas = child(schemas) { $0.game?.id }
            r.details = child(details) { $0.game?.id }
            r.completions = child(completions) { $0.game?.id }
            r.videos = child(videos) { $0.game?.id }
            r.maps = child(maps) { $0.game?.id }
            r.markers = child(markers) { $0.map?.id }
            r.images = images.values.filter {
                $0.deletedAt == nil && gone($0.id)
                    && (kept($0.game?.id) || kept($0.memory?.id) || kept($0.console?.id))
            }
            // A removed memory takes its pictures, stamped with its own time,
            // so restoring the memory brings them back (`Repository.restore`).
            r.memoryImages = r.memories.flatMap { ($0.images ?? []).filter { $0.deletedAt == nil } }
            return r
        }
    }

    private struct Removals {
        var games: [Game] = []
        var collections: [GameCollection] = []
        var memories: [Memory] = []
        var consoles: [Console] = []
        var playthroughs: [Playthrough] = []
        var sessions: [Session] = []
        var runs: [Run] = []
        var states: [TrackerStateRecord] = []
        var schemas: [TrackerSchemaRecord] = []
        var details: [TrackerItemDetail] = []
        var completions: [CompletionEvent] = []
        var videos: [GameVideo] = []
        var maps: [GameMap] = []
        var markers: [Marker] = []
        var images: [GameImage] = []
        var memoryImages: [GameImage] = []
        var feeds: [NewsFeed] = []
        var articles: [NewsItemState] = []

        var counts: [String: Int] {
            let all: [(String, Int)] = [
                ("games", games.count), ("collections", collections.count),
                ("memories", memories.count), ("consoles", consoles.count),
                ("feeds", feeds.count), ("saved articles", articles.count),
                ("playthroughs", playthroughs.count), ("sessions", sessions.count),
                ("runs", runs.count), ("tracker progress", states.count),
                ("trackers", schemas.count), ("tracker notes", details.count),
                ("completions", completions.count), ("videos", videos.count),
                ("maps", maps.count), ("map pins", markers.count), ("pictures", images.count),
            ]
            return Dictionary(uniqueKeysWithValues: all.filter { $0.1 > 0 })
        }

        func tombstone(at date: Date) {
            func bury(_ list: [some Syncable]) {
                for m in list {
                    m.deletedAt = date
                    m.updatedAt = date
                    m.revision += 1
                }
            }
            bury(games); bury(collections); bury(memories); bury(consoles)
            bury(feeds); bury(articles)
            bury(playthroughs); bury(sessions); bury(runs); bury(states); bury(schemas)
            bury(details); bury(completions); bury(videos); bury(maps); bury(markers)
            for image in images + memoryImages {
                image.deletedAt = date
                image.updatedAt = date
                image.revision += 1
            }
        }
    }

    /// Every id a backup names, and the systems its consoles are for.
    private struct FileIDs {
        var all: [UUID: String] = [:]
        var consoleIDs = Set<UUID>()
        var consolePlatforms = Set<String>()

        init(empty: Void) {}

        init(root: [String: Any], library: Library) {
            let uuid = LibraryImport.uuid
            func add(_ d: Any?, _ kind: String) {
                if let id = uuid((d as? [String: Any])?["id"]) { all[id] = kind }
            }
            func addAll(_ list: Any?, _ kind: String) {
                for d in (list as? [[String: Any]]) ?? [] { add(d, kind) }
            }
            for g in (root["games"] as? [[String: Any]]) ?? [] {
                add(g, "games")
                add(g["trackerSchema"], "trackers")
                addAll(g["trackerItemDetails"], "tracker notes")
                for p in (g["playthroughs"] as? [[String: Any]]) ?? [] {
                    add(p, "playthroughs")
                    addAll(p["sessions"], "sessions")
                    addAll(p["runs"], "runs")
                    addAll(p["trackerProgress"], "tracker progress")
                }
                addAll(g["completions"], "completions")
                addAll(g["images"], "pictures")
                addAll(g["videos"], "videos")
                for m in (g["maps"] as? [[String: Any]]) ?? [] {
                    add(m, "maps")
                    addAll(m["markers"], "map pins")
                }
            }
            addAll(root["collections"], "collections")
            addAll(root["newsFeeds"], "feeds")
            addAll(root["newsArticles"], "saved articles")
            for m in (root["memories"] as? [[String: Any]]) ?? [] {
                add(m, "memories")
                addAll(m["images"], "pictures")
            }
            for c in (root["consoles"] as? [[String: Any]]) ?? [] {
                if let console = library.console(for: c) {
                    consoleIDs.insert(console.id)
                    all[console.id] = "consoles"
                } else if let id = uuid(c["id"]) {
                    all[id] = "consoles"
                }
                if let p = c["platform"] as? String { consolePlatforms.insert(PlatformKey.canonical(p)) }
                addAll(c["images"], "pictures")
            }
        }

        func contains(_ id: UUID) -> Bool { all[id] != nil }

        func keepsConsole(_ console: Console) -> Bool {
            consoleIDs.contains(console.id)
        }
    }
}
