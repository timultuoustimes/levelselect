import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Writes the shared widget snapshot from the live store and pokes WidgetKit
/// to reload. Called on launch, on scene changes, and after mutations.
@MainActor
enum WidgetBridge {
    static func refresh() {
        let ctx = LevelSelectStore.shared.mainContext
        guard let result = build(context: ctx) else {
            WidgetSnapshot.clear()
            reload()
            return
        }
        result.snapshot.save()
        reload()

        // Cache any covers not on disk yet; reload once they land so tiles swap
        // their placeholder for real box art.
        let pending = result.covers.filter { !coverExists($0.name) }
        if !pending.isEmpty {
            Task.detached(priority: .utility) {
                for job in pending { await cacheCover(from: job.url, fileName: job.name) }
                await MainActor.run { reload() }
            }
        }
    }

    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: Build

    private struct CoverJob { let url: URL; let name: String }
    private struct BuildResult { let snapshot: WidgetSnapshot; let covers: [CoverJob] }

    private static func build(context: ModelContext) -> BuildResult? {
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil })
        guard let games = try? context.fetch(descriptor), !games.isEmpty else { return nil }

        var covers: [CoverJob] = []
        func coverName(_ g: Game) -> String? {
            guard let s = g.coverURLString, let url = URL(string: s) else { return nil }
            let name = coverFileName(for: s)
            covers.append(CoverJob(url: url, name: name))
            return name
        }

        // Continue Playing: playing/paused (most recent activity) else most recent.
        let active = games
            .filter { $0.status == .playing || $0.status == .paused }
            .max { activityKey($0) < activityKey($1) }
        guard let game = active ?? mostRecentlyPlayed(games) else { return nil }

        let pt = game.activePlaythrough
        let session = pt?.activeSession
        let (objectives, done, total) = trackerItems(game: game, pt: pt)
        let nextIncomplete = objectives.first { !$0.done }

        // Shelf: playing games most active first, then paused, then queued —
        // twelve, because the iPad extra-large shelf shows a wall of twelve
        // covers. The phone widgets still take their four or eight off the
        // top, so they see the same games they always did.
        let shelfStatuses: [GameStatus] = [.playing, .paused, .queued]
        let nowPlaying: [WidgetShelfGame] = shelfStatuses
            .flatMap { status in
                games.filter { $0.status == status }
                    .sorted { activityKey($0) > activityKey($1) }
            }
            .prefix(12)
            .map { g in
                let pt = g.activePlaythrough
                // Per-game progress for the extra-large widgets: the tracker
                // fraction when one exists, the run record when runs do.
                let (_, gDone, gTotal) = trackerItems(game: g, pt: pt)
                let runs = pt?.liveRuns.filter { $0.outcome != .inProgress } ?? []
                let wins = runs.filter { $0.outcome == .success }.count
                let losses = runs.filter { $0.outcome == .failure }.count
                return WidgetShelfGame(
                    id: g.id.uuidString, name: g.name,
                    coverFileName: coverName(g),
                    isPlaying: pt?.activeSession?.state == .running,
                    statusRaw: g.status.rawValue,
                    done: gTotal > 0 ? gDone : nil,
                    total: gTotal > 0 ? gTotal : nil,
                    wins: runs.isEmpty ? nil : wins,
                    losses: runs.isEmpty ? nil : losses)
            }

        let (weekly, gamesThisWeek) = weeklyStats(context: context)
        let runGame = mostRecentRunGame(games, coverName: coverName)

        // Shuffle pool: everything the "choose a game for me" widget may
        // pick from. Wishlist and abandoned never qualify — a shuffler that
        // suggests a game you gave up on is a nag, not a choice. Cover names
        // are computed WITHOUT enqueueing downloads (150 covers per refresh
        // would drown the cache); only the picks the widgets currently show
        // get their covers fetched, read back from the picks store below.
        let poolStatuses: Set<GameStatus> = [.playing, .paused, .queued,
                                             .backlog, .ongoing, .shelved, .completed]
        let shufflePool: [WidgetPoolGame] = games
            .filter { poolStatuses.contains($0.status) }
            .map { g in
                WidgetPoolGame(
                    id: g.id.uuidString, name: g.name,
                    coverFileName: g.coverURLString.map { coverFileName(for: $0) },
                    statusRaw: g.status.rawValue,
                    platform: PlatformShort.name(PlatformPreference.owned(g.platforms) ?? "Other"))
            }
        let libraryPlatforms = Array(Set(shufflePool.map(\.platform))).sorted()

        // Daily rollup (16 weeks), the 4-week pace, finished share, and the
        // collections the launcher widget can point at.
        let daily = dailyStats(context: context, days: 112)
        let priorFourWeeks = daily.dropLast(7).suffix(28)
        let weeklyAverage = priorFourWeeks.isEmpty ? 0
            : priorFourWeeks.reduce(0, +) * 60 / 4
        let completedCount = games.filter { $0.status == .completed }.count
        let collectionDescriptor = FetchDescriptor<GameCollection>(
            predicate: #Predicate { $0.deletedAt == nil })
        let collectionRefs: [WidgetCollectionRef] = ((try? context.fetch(collectionDescriptor)) ?? [])
            .map { WidgetCollectionRef(id: $0.id.uuidString, name: $0.name,
                                       count: gamesCount(in: $0)) }
            .sorted { $0.name < $1.name }

        // Current shuffle picks (any widget instance) get real covers.
        if let defaults = UserDefaults(suiteName: WidgetShared.appGroup),
           let picks = defaults.dictionary(forKey: "shufflePicks") as? [String: String] {
            let picked = Set(picks.values)
            for g in games where picked.contains(g.id.uuidString) {
                _ = coverName(g)
            }
        }

        let snapshot = WidgetSnapshot(
            gameID: game.id.uuidString,
            gameName: game.name,
            statusRaw: game.status.rawValue,
            isPlaying: session?.state == .running,
            isPaused: session?.state == .paused,
            playtimeSeconds: pt?.totalPlaytime() ?? 0,
            lastPlayedAt: pt?.lastPlayedAt,
            nextObjective: nextIncomplete?.name,
            nextObjectiveID: nextIncomplete?.id,
            completionDone: done,
            completionTotal: total,
            coverFileName: coverName(game),
            activeSessionID: session?.id.uuidString,
            generatedAt: .now,
            objectives: objectives,
            nowPlaying: nowPlaying,
            weeklySeconds: weekly,
            gamesPlayedThisWeek: gamesThisWeek,
            runGame: runGame,
            shufflePool: shufflePool,
            libraryPlatforms: libraryPlatforms,
            dailyMinutes: daily,
            weeklyAverageSeconds: weeklyAverage,
            completedCount: completedCount,
            libraryCount: games.count,
            collections: collectionRefs
        )
        return BuildResult(snapshot: snapshot, covers: covers)
    }

    private static func activityKey(_ g: Game) -> (Bool, Date) {
        (g.pinned, g.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? g.addedAt)
    }

    private static func mostRecentlyPlayed(_ games: [Game]) -> Game? {
        games
            .filter { $0.livePlaythroughs.contains { $0.lastPlayedAt != nil } }
            .max { activityKey($0) < activityKey($1) }
    }

    /// Visible tracker items (spoiler items hidden until revealed) + done/total.
    private static func trackerItems(game: Game, pt: Playthrough?) -> ([WidgetObjective], Int, Int) {
        guard let schema = game.trackerSchema else { return ([], 0, 0) }
        let cats = TrackerSchemaJSON.categories(from: schema.jsonData)
        let states = (pt?.trackerStates ?? []).filter { $0.deletedAt == nil }
        // Same winner rule as the repository read: the widget refreshes on
        // foreground BEFORE any per-game reconcile has folded sync twins, so
        // an arbitrary-first pick here could show an objective the app
        // considers unticked as done (or hide it).
        let byItem = Dictionary(states.map { ($0.itemID, $0) },
                                uniquingKeysWith: { a, b in b.outranks(a) ? b : a })

        let allItems = cats.flatMap(\.items)
        let done = allItems.filter { byItem[$0.id]?.completed == true }.count

        // Objectives for the checklist: incomplete non-spoiler items first, in
        // schema order (capped) — the actionable "what's next" list.
        let objectives: [WidgetObjective] = allItems
            .filter { item in !(item.hideUntilDiscovered && byItem[item.id]?.revealed != true) }
            .filter { byItem[$0.id]?.completed != true }
            .prefix(8)
            .map { WidgetObjective(id: $0.id, name: $0.name, done: false) }

        return (objectives, done, allItems.count)
    }

    /// Playtime per day for the last 7 days (index 0 = 6 days ago, 6 = today)
    /// plus the count of distinct games played in that window.
    /// Minutes per day for the trailing `days` window, oldest → newest.
    private static func dailyStats(context: ModelContext, days: Int) -> [Double] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .day, value: -(days - 1), to: today)
        else { return [] }
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startDate >= windowStart })
        guard let sessions = try? context.fetch(descriptor) else {
            return Array(repeating: 0, count: days)
        }
        var buckets = Array(repeating: 0.0, count: days)
        for s in sessions {
            let day = cal.startOfDay(for: s.startDate)
            guard let offset = cal.dateComponents([.day], from: day, to: today).day,
                  offset >= 0, offset < days else { continue }
            buckets[days - 1 - offset] += s.elapsed() / 60
        }
        return buckets
    }

    private static func gamesCount(in collection: GameCollection) -> Int {
        collection.gameIDs.count
    }

    private static func weeklyStats(context: ModelContext) -> ([Double], Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .day, value: -6, to: today) else { return ([], 0) }
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startDate >= windowStart }
        )
        guard let sessions = try? context.fetch(descriptor) else { return (Array(repeating: 0, count: 7), 0) }

        var buckets = Array(repeating: 0.0, count: 7)
        var gameIDs = Set<UUID>()
        for s in sessions {
            let day = cal.startOfDay(for: s.startDate)
            let idx = (cal.dateComponents([.day], from: day, to: today).day).map { 6 - $0 } ?? -1
            guard idx >= 0, idx < 7 else { continue }
            buckets[idx] += s.elapsed()
            if let gid = s.playthrough?.game?.id { gameIDs.insert(gid) }
        }
        return (buckets, gameIDs.count)
    }

    /// The most recently played game that has runs, with win/loss tallies.
    private static func mostRecentRunGame(_ games: [Game], coverName: (Game) -> String?) -> WidgetRunGame? {
        var best: (game: Game, runs: [Run], latest: Date)?
        for game in games {
            let runs = game.livePlaythroughs.flatMap { $0.liveRuns }
            guard let latest = runs.map(\.startedAt).max() else { continue }
            if best == nil || latest > best!.latest {
                best = (game, runs, latest)
            }
        }
        guard let best else { return nil }
        let runs = best.runs
        let wins = runs.filter { $0.outcome == .success }.count
        let losses = runs.filter { $0.outcome == .failure }.count
        let inProgress = runs.contains { $0.outcome == .inProgress }
        let last = runs.max { $0.startedAt < $1.startedAt }
        return WidgetRunGame(
            id: best.game.id.uuidString, name: best.game.name,
            coverFileName: coverName(best.game),
            inProgress: inProgress, wins: wins, losses: losses, total: runs.count,
            lastOutcomeRaw: last?.outcome.rawValue
        )
    }

    // MARK: Cover cache

    private static func coverFileName(for urlString: String) -> String {
        let hash = UInt64(bitPattern: Int64(urlString.hashValue))
        return "cover-\(hash).jpg"
    }

    private static func coverExists(_ name: String) -> Bool {
        guard let url = WidgetShared.coversDir?.appendingPathComponent(name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func cacheCover(from url: URL, fileName: String) async {
        #if canImport(UIKit)
        guard let dir = WidgetShared.coversDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        let target = downscale(image, maxWidth: 320)
        guard let jpeg = target.jpegData(compressionQuality: 0.85) else { return }
        try? jpeg.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        #endif
    }

    #if canImport(UIKit)
    private static func downscale(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        guard image.size.width > maxWidth else { return image }
        let scale = maxWidth / image.size.width
        let size = CGSize(width: maxWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    #endif
}
