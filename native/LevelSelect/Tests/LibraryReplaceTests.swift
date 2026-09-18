import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Replace Library with Backup and Erase Library. Tim, 2026-09-17: a backup
/// you can only add on top of "defeats the purpose of making a backup".
@MainActor
struct LibraryReplaceTests {

    private let folder = URL.temporaryDirectory.appending(path: "ls-safety-\(UUID().uuidString)")

    private func store() -> ModelContext {
        LibraryReplace.safetyFolderOverride = folder
        return ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    private func fetch<M: PersistentModel>(_ type: M.Type, _ context: ModelContext) -> [M] {
        (try? context.fetch(FetchDescriptor<M>())) ?? []
    }

    /// A small library: two games with playthroughs and sessions, ticks, a
    /// collection and a console.
    private func seed(_ context: ModelContext) -> (keep: Game, other: Game) {
        let keep = Game(name: "Hollow Knight", status: .playing)
        keep.ownership = ["digital"]
        keep.rating = 5
        let other = Game(name: "Skyrim", status: .completed)
        context.insert(keep); context.insert(other)
        for game in [keep, other] {
            let pt = Playthrough()
            context.insert(pt)
            pt.game = game
            game.currentPlaythroughID = pt.id
            let session = Session(startDate: .now.addingTimeInterval(-3600), state: .stopped)
            session.accumulatedDuration = 3600
            session.endDate = .now
            context.insert(session)
            session.playthrough = pt
            let tick = TrackerStateRecord(itemID: "boss")
            tick.completed = true
            context.insert(tick)
            tick.playthrough = pt
        }
        let shelf = GameCollection(name: "Favorites")
        shelf.gameIDs = [keep.id.uuidString]
        context.insert(shelf)
        context.insert(Console(platform: "Switch", ownership: ["physical"]))
        try? context.save()
        return (keep, other)
    }

    @Test("Replace puts changed values back, revives, re-creates and removes — only the tops of branches")
    func replaceMakesTheLibraryMatch() throws {
        let context = store()
        let (keep, other) = seed(context)
        let backup = try LibraryExport.makeJSON(context: context)

        // The damage, of every kind.
        keep.ownership = ["physical"]
        keep.rating = nil
        keep.status = .abandoned
        let tick = try #require(keep.playthroughs?.first?.trackerStates?.first)
        tick.completed = false
        other.deletedAt = .now                               // deleted since
        let lostSession = try #require(keep.playthroughs?.first?.sessions?.first)
        context.delete(lostSession)                          // gone outright
        let junk = Game(name: "Active Test")                 // added since
        context.insert(junk)
        let junkPT = Playthrough(); context.insert(junkPT); junkPT.game = junk
        let running = Session(state: .running)               // a new session on a kept game
        context.insert(running)
        running.playthrough = keep.playthroughs?.first
        try context.save()

        let preview = try LibraryReplace.preview(data: backup, context: context)
        #expect(preview.gamesInBackup == 2)
        #expect(preview.revived == 1)
        #expect(preview.added == 1)
        #expect(preview.removed == ["games": 1, "sessions": 1])

        let outcome = try LibraryReplace.apply(data: backup, context: context)
        #expect(outcome.revived == preview.revived && outcome.added == preview.added)
        #expect(outcome.removed == preview.removed)

        #expect(keep.ownership == ["digital"] && keep.rating == 5 && keep.status == .playing)
        #expect(tick.completed)
        #expect(other.deletedAt == nil)
        #expect(junk.deletedAt != nil)
        #expect(junkPT.deletedAt == nil, "a removed game's playthrough rides with it to Recently Deleted")
        #expect(running.deletedAt != nil && running.state == .stopped, "a timer is stopped before it goes")
        let sessions = fetch(Session.self, context).filter { $0.deletedAt == nil && $0.playthrough?.game?.id == keep.id }
        #expect(sessions.count == 1, "the lost session is back under its playthrough")

        // And a safety copy of the damaged library was written first.
        let copy = try #require(outcome.safetyCopy)
        let saved = try LibraryImport.preview(data: Data(contentsOf: copy), context: store())
        #expect(saved.creates["games"] == 2)
    }

    @Test("Replacing with the same backup twice is a no-op the second time")
    func replaceIsIdempotent() throws {
        let context = store()
        _ = seed(context)
        let backup = try LibraryExport.makeJSON(context: context)
        _ = try LibraryReplace.apply(data: backup, context: context)
        let again = try LibraryReplace.preview(data: backup, context: context)
        #expect(again.removed.isEmpty && again.revived == 0 && again.added == 0)
        #expect(fetch(Game.self, context).filter { $0.deletedAt == nil }.count == 2)
    }

    @Test("A replace round-trips: the library exports the same as the backup it came from")
    func replaceRoundTrips() throws {
        let context = store()
        let (keep, _) = seed(context)
        let theme = ThemePalette.fetchOrCreate(in: context)
        theme.homeSystemsRaw = "sort=custom,Switch"
        try context.save()
        let backup = try LibraryExport.makeJSON(context: context)
        keep.name = "Renamed"
        keep.userTags = ["oops"]
        keep.sectionStateRaw = "notes:collapsed"
        theme.homeLayoutRaw = "continue"
        theme.homeSystemsRaw = nil
        try context.save()

        _ = try LibraryReplace.apply(data: backup, context: context)
        let after = try LibraryExport.makeJSON(context: context)
        let differences = Self.differences(Self.comparable(after), Self.comparable(backup))
        #expect(differences.isEmpty, "\(differences)")
        #expect(keep.sectionStateRaw == nil && theme.homeLayoutRaw == nil)
        #expect(theme.homeSystemsRaw == "sort=custom,Switch")
    }

    @Test("Erase moves everything to Recently Deleted, keeps settings, and Replace brings it back")
    func eraseThenReplace() throws {
        let context = store()
        _ = seed(context)
        let profile = PlayerProfile()
        profile.displayName = "timultuoustimes"
        context.insert(profile)
        let theme = ThemePalette.fetchOrCreate(in: context)
        theme.appearanceRaw = "dark"
        try context.save()
        let backup = try LibraryExport.makeJSON(context: context)

        #expect(try LibraryReplace.erasePreview(context: context)
                == ["games": 2, "collections": 1, "consoles": 1])
        let erased = try LibraryReplace.erase(context: context)
        #expect(erased.totalRemoved == 4)
        #expect(erased.safetyCopy != nil)
        #expect(fetch(Game.self, context).allSatisfy { $0.deletedAt != nil })
        #expect(Repository(context).trashedGames().count == 2, "they're in Recently Deleted")
        #expect(profile.displayName == "timultuoustimes" && theme.appearanceRaw == "dark")

        // An ordinary import would skip every one of them.
        #expect(try LibraryImport.preview(data: backup, context: context).totalCreates == 0)
        let back = try LibraryReplace.apply(data: backup, context: context)
        #expect(back.revived >= 4)
        #expect(fetch(Game.self, context).allSatisfy { $0.deletedAt == nil })
        #expect(fetch(Console.self, context).allSatisfy { $0.deletedAt == nil })
        #expect(fetch(Console.self, context).count == 1, "the console came back, not a second one")
    }

    @Test("Safety copies keep the newest five")
    func safetyCopiesArePruned() throws {
        let context = store()
        _ = seed(context)
        for i in 0..<7 {
            _ = try LibraryReplace.safetyCopy(
                context: context, reason: "test", now: Date(timeIntervalSince1970: 1_800_000_000 + Double(i) * 60))
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(files.count == 5)
    }

    /// Tim's real backup against a copy of the damaged store, when
    /// `LS_REPLACE_DIR` holds `work/default.store` and `backup.json`.
    @Test("A real backup replaces a real damaged library")
    func realBackup() throws {
        guard let dir = ProcessInfo.processInfo.environment["LS_REPLACE_DIR"] else { return }
        let base = URL(filePath: dir)
        LibraryReplace.safetyFolderOverride = base.appending(path: "copies")
        let schema = Schema(versionedSchema: LevelSelectSchemaV3.self)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: base.appending(path: "work/default.store"),
                                                cloudKitDatabase: .none)])
        let context = ModelContext(container)
        let data = try Data(contentsOf: base.appending(path: "backup.json"))
        let preview = try LibraryReplace.preview(data: data, context: context)
        let outcome = try LibraryReplace.apply(data: data, context: context)
        let report = "preview \(preview)\noutcome \(outcome)\n"
        try report.write(to: base.appending(path: "work/outcome.txt"), atomically: true, encoding: .utf8)
        #expect(fetch(Game.self, context).filter { $0.deletedAt == nil }.count == preview.gamesInBackup)
    }

    private static func differences(_ a: Any, _ b: Any, path: String = "") -> [String] {
        if let x = a as? [String: Any], let y = b as? [String: Any] {
            return Set(x.keys).union(y.keys).sorted().flatMap { key -> [String] in
                guard let l = x[key], let r = y[key] else { return ["\(path).\(key) only on one side"] }
                return differences(l, r, path: "\(path).\(key)")
            }
        }
        if let x = a as? [Any], let y = b as? [Any] {
            guard x.count == y.count else { return ["\(path) count \(x.count) vs \(y.count)"] }
            return zip(x, y).enumerated().flatMap { differences($1.0, $1.1, path: "\(path)[\($0)]") }
        }
        return (a as? NSObject)?.isEqual(b) == true ? [] : ["\(path): \(a) vs \(b)"]
    }

    /// The export minus what legitimately differs after a replace: stamps.
    private static func comparable(_ data: Data) -> [String: Any] {
        func strip(_ any: Any) -> Any {
            if let dict = any as? [String: Any] {
                var out: [String: Any] = [:]
                for (k, v) in dict where !["updatedAt", "exportedAt"].contains(k) { out[k] = strip(v) }
                return out
            }
            if let list = any as? [Any] { return list.map(strip) }
            return any
        }
        let root = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        return strip(root) as? [String: Any] ?? [:]
    }
}
