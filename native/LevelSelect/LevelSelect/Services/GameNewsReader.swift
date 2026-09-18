import Foundation
import Observation
import OSLog

/// A feed as the reader needs it — plain values, safe to hand to a task.
struct FeedSnapshot: Sendable, Hashable, Identifiable {
    let id: UUID
    let url: String
    let title: String
}

/// Fetches the feeds you follow and holds their stories.
///
/// **Reads, not reports.** A feed fetch is a plain GET of a public file with
/// nothing of ours attached — no install id, no LevelSelect key — the same
/// rule `NewsFeeds` keeps for the changelog. The only thing a site learns is
/// that someone fetched its feed, which is what a feed is for.
///
/// **Stories live in memory and in Caches**, never the store: see
/// `FeedStory`. The cache is what makes the tab open full on a plane.
@MainActor
@Observable
final class GameNewsReader {
    static let shared = GameNewsReader()

    private(set) var stories: [FeedStory] = []
    private(set) var refreshing = false
    private(set) var lastRefresh: Date?
    /// Per feed: the last failure, in words, or nil when it worked.
    private(set) var problems: [UUID: String] = [:]
    /// Found by reading a story's page, for feeds that send no image.
    private(set) var pageImages: [String: URL] = [:]
    private var askedPageImages: Set<String> = []

    private(set) var upcoming: [UpcomingRelease] = []
    private(set) var upcomingLoadedAt: Date?
    private(set) var upcomingFailed = false
    /// The most-followed releases of the next month, for Up Next.
    private(set) var upNextIDs: [Int] = []
    /// The most-followed releases of the last two weeks, for Just Out.
    private(set) var justOutIDs: [Int] = []

    private let log = Logger(subsystem: Diagnostics.subsystem, category: "game-news")

    /// How long a story is kept after it was published.
    static let keepFor: TimeInterval = 21 * 86_400
    /// Stories kept per feed — IGN alone posts forty a day.
    static let perFeed = 80

    private init() {
        if let cached = Self.readCache() {
            stories = cached.stories
            lastRefresh = cached.fetchedAt
            pageImages = cached.pageImages
        }
        if let cached = Self.readUpcomingCache() {
            upcoming = cached.releases
            upNextIDs = cached.upNextIDs ?? []
            justOutIDs = cached.justOutIDs ?? []
            upcomingLoadedAt = cached.fetchedAt
        }
    }

    // MARK: Refresh

    private var running: Task<Void, Never>?
    private var queued: (feeds: [FeedSnapshot], force: Bool)?

    /// Refresh if it has been a while. `force` is pull-to-refresh.
    ///
    /// **The fetch is not the caller's task.** The tab starts this from
    /// `.task(id:)`, and seeding the starter feeds changes that id a moment
    /// later — which cancelled the first fetch mid-flight, recorded all seven
    /// feeds as failed, and blocked the retry that should have followed. So
    /// the work runs in its own task, a caller only waits on it, and a request
    /// made while one is running is queued and run straight after.
    func refresh(_ feeds: [FeedSnapshot], force: Bool = false) async {
        if running != nil {
            queued = (feeds, force || (queued?.force ?? false))
            await running?.value
            return
        }
        var next: (feeds: [FeedSnapshot], force: Bool)? = (feeds, force)
        while let job = next {
            let task = Task { await self.perform(job.feeds, force: job.force) }
            running = task
            await task.value
            running = nil
            next = queued
            queued = nil
        }
    }

    private func perform(_ feeds: [FeedSnapshot], force: Bool) async {
        if !force, let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 15 * 60,
           Set(stories.map(\.feedID)).isSuperset(of: feeds.map(\.id)) {
            return
        }
        refreshing = true
        defer { refreshing = false }

        var fresh: [UUID: [FeedStory]] = [:]
        var failures: [UUID: String] = [:]
        await withTaskGroup(of: (UUID, Result<[FeedStory], Error>).self) { group in
            var queue = feeds[...]
            // Six at a time: enough to be quick, few enough not to look like
            // a flood to anyone's server or to a phone on one bar.
            func startNext() {
                guard let feed = queue.popFirst() else { return }
                group.addTask {
                    do { return (feed.id, .success(try await Self.fetchStories(feed))) }
                    catch { return (feed.id, .failure(error)) }
                }
            }
            for _ in 0..<6 { startNext() }
            while let (id, result) = await group.next() {
                switch result {
                case .success(let list): fresh[id] = list
                case .failure(let error): failures[id] = Self.readable(error)
                }
                startNext()
            }
        }

        let followed = Set(feeds.map(\.id))
        let cutoff = Date.now.addingTimeInterval(-Self.keepFor)
        var merged: [String: FeedStory] = [:]
        // Keep what a failed feed had, so one bad fetch doesn't empty it.
        for story in stories where followed.contains(story.feedID) && fresh[story.feedID] == nil {
            merged[story.id] = story
        }
        for (_, list) in fresh {
            for story in list.prefix(Self.perFeed) { merged[story.id] = story }
        }
        stories = merged.values
            .filter { ($0.published ?? .now) > cutoff }
            .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
        problems = failures
        lastRefresh = .now
        for (id, why) in failures { log.error("feed \(id) failed: \(why)") }
        writeCache()
    }

    /// Drops the stories of feeds no longer followed or switched off, without
    /// waiting for a refresh.
    func keepOnly(_ feedIDs: Set<UUID>) {
        let before = stories.count
        stories.removeAll { !feedIDs.contains($0.feedID) }
        if stories.count != before { writeCache() }
    }

    nonisolated private static func fetchStories(_ feed: FeedSnapshot) async throws -> [FeedStory] {
        guard let url = URL(string: feed.url) else { throw URLError(.badURL) }
        let data = try await get(url)
        guard let parsed = FeedParser.parse(data, feedID: feed.id, base: url) else {
            throw ReaderError.notAFeed
        }
        return parsed.stories
    }

    nonisolated static func get(_ url: URL, limit: Int? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LevelSelect feed reader", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml, text/html;q=0.8, */*;q=0.5",
                         forHTTPHeaderField: "Accept")
        if let limit { request.setValue("bytes=0-\(limit)", forHTTPHeaderField: "Range") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    enum ReaderError: Error { case notAFeed, nothingFound }

    nonisolated static func readable(_ error: Error) -> String {
        if case ReaderError.notAFeed = error { return "That address isn't a feed." }
        if case ReaderError.nothingFound = error { return "Couldn't find a feed on that site." }
        return NewsFeeds.readable(error)
    }

    // MARK: Adding a feed

    struct Found: Sendable {
        let feedURL: String
        let title: String
        let siteURL: String?
        let storyCount: Int
    }

    /// What someone typed — a feed, or a site with a feed somewhere in it.
    nonisolated static func discover(_ typed: String) async throws -> Found {
        guard let url = FeedDiscovery.normalized(typed) else { throw URLError(.badURL) }
        let data = try await get(url)
        if let parsed = FeedParser.parse(data, feedID: UUID(), base: url) {
            return Found(feedURL: url.absoluteString, title: parsed.title.isEmpty ? (url.host ?? "Feed") : parsed.title,
                         siteURL: parsed.siteURL?.absoluteString, storyCount: parsed.stories.count)
        }
        let html = String(decoding: data, as: UTF8.self)
        var candidates = FeedDiscovery.feedLinks(inHTML: html, base: url)
        // Sites that don't advertise a feed usually still have one here.
        for guess in ["feed", "rss", "feed.xml", "rss.xml", "index.xml", "feeds/latest", "atom.xml"] {
            if let u = URL(string: guess, relativeTo: url.appendingPathComponent("/"))?.absoluteURL,
               !candidates.contains(u) { candidates.append(u) }
        }
        for candidate in candidates.prefix(8) {
            guard let data = try? await get(candidate),
                  let parsed = FeedParser.parse(data, feedID: UUID(), base: candidate),
                  !parsed.stories.isEmpty else { continue }
            return Found(feedURL: candidate.absoluteString,
                         title: parsed.title.isEmpty ? (url.host ?? "Feed") : parsed.title,
                         siteURL: parsed.siteURL?.absoluteString ?? url.absoluteString,
                         storyCount: parsed.stories.count)
        }
        throw ReaderError.nothingFound
    }

    // MARK: Page images

    /// The picture a story's own page offers (`og:image`), for feeds that
    /// send none. Asked once per story, only when its card is on screen.
    func pageImage(for story: FeedStory) async {
        guard story.imageURL == nil, let link = story.link,
              !askedPageImages.contains(story.id) else { return }
        askedPageImages.insert(story.id)
        guard let data = try? await Self.get(link, limit: 150_000) else { return }
        let html = String(decoding: data.prefix(150_000), as: UTF8.self)
        if let found = Self.ogImage(inHTML: html, base: link) {
            pageImages[story.id] = found
            writeCache()
        }
    }

    nonisolated static func ogImage(inHTML html: String, base: URL) -> URL? {
        for key in ["og:image", "twitter:image", "og:image:url"] {
            let patterns = [
                "<meta[^>]+(?:property|name)\\s*=\\s*[\"']\(key)[\"'][^>]+content\\s*=\\s*[\"']([^\"']+)[\"']",
                "<meta[^>]+content\\s*=\\s*[\"']([^\"']+)[\"'][^>]+(?:property|name)\\s*=\\s*[\"']\(key)[\"']",
            ]
            for p in patterns {
                guard let regex = try? NSRegularExpression(pattern: p, options: .caseInsensitive) else { continue }
                let ns = html as NSString
                if let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
                    let raw = FeedParser.decodeEntities(ns.substring(with: m.range(at: 1)))
                    if let url = URL(string: raw, relativeTo: base)?.absoluteURL { return url }
                }
            }
        }
        return nil
    }

    func image(for story: FeedStory) -> URL? {
        story.imageURL ?? pageImages[story.id]
    }

    // MARK: Upcoming

    /// Every release in the next six months, from IGDB — not just your
    /// wishlist. Tim, 09-17: *"upcoming releases (all, not just the ones you
    /// might be interested in that we have in the wishlist section)"*.
    ///
    /// **Asked per platform launch** (`release_dates.date` in the window), so a
    /// port or a late platform counts — see `UpcomingRelease`.
    ///
    /// **Which games:** main games, remakes, remasters, expanded editions and
    /// ports with at least one person following or rating them, plus
    /// compilations with five ratings (the Kingdom Hearts collections). Measured
    /// 09-18 over the next 30 days on the main systems: every main game and
    /// port, 783; with that signal, 261; at two or more, 169. One keeps every
    /// title Game Informer listed that week — Garfield has one hype and NASCAR
    /// 26 two — and drops the five hundred listings nobody follows. Six months
    /// is about 1,200 games in three pages.
    ///
    /// **Up Next is the most-followed of the next month**, not the soonest:
    /// sorted by date it was ten small PC games while Control Resonant and
    /// Gears of War: E-Day sat forty rows down.
    func loadUpcoming(force: Bool = false) async {
        if !force, let upcomingLoadedAt, Date.now.timeIntervalSince(upcomingLoadedAt) < 6 * 3600,
           !upcoming.isEmpty { return }
        let start = Int(UpcomingReleases.utc.startOfDay(for: .now).timeIntervalSince1970)
        let until = start + 183 * 86_400
        let soon = start + 30 * 86_400
        let kinds = "((game_type = (0,8,9,10,11) & (hypes >= 1 | total_rating_count >= 1)) | (game_type = 3 & total_rating_count >= 5))"
        // From two weeks back, for Just Out (`UpcomingReleases.justOutDays`).
        let since = start - UpcomingReleases.justOutDays * 86_400
        let clause = "release_dates.date >= \(since) & release_dates.date < \(until) & \(kinds)"

        var all: [IGDBGame] = []
        for page in 0..<8 {
            guard let batch = await IGDBService.page(where: clause, offset: page * 500) else { break }
            all += batch
            if batch.count < 500 { break }
        }
        let top = await IGDBService.raw(
            endpoint: "games",
            query: "where release_dates.date >= \(start) & release_dates.date < \(soon) & game_type = (0,8,9,10,11) & hypes >= 5; fields id; sort hypes desc; limit 20;")
        // The most-followed of the last two weeks, for Just Out's short list:
        // 154 games came out in the fortnight to 09-18, and newest-first put
        // yesterday's small PC releases ahead of anything anyone waited for.
        let topRecent = await IGDBService.raw(
            endpoint: "games",
            query: "where release_dates.date >= \(since) & release_dates.date < \(start) & game_type = (0,8,9,10,11) & hypes >= 3; fields id; sort hypes desc; limit 20;")
        guard !all.isEmpty else {
            upcomingFailed = upcoming.isEmpty
            return
        }
        upcoming = all.compactMap(UpcomingRelease.init)
        upNextIDs = top.compactMap { ($0["id"] as? NSNumber)?.intValue }
        justOutIDs = topRecent.compactMap { ($0["id"] as? NSNumber)?.intValue }
        upcomingLoadedAt = .now
        upcomingFailed = false
        Self.writeUpcomingCache(.init(fetchedAt: .now, releases: upcoming, upNextIDs: upNextIDs,
                                      justOutIDs: justOutIDs))
    }

    // MARK: Cache

    private struct Cache: Codable {
        var fetchedAt: Date
        var stories: [FeedStory]
        var pageImages: [String: URL]
    }

    private struct UpcomingCache: Codable {
        var fetchedAt: Date
        var releases: [UpcomingRelease]
        var upNextIDs: [Int]?
        var justOutIDs: [Int]?
    }

    /// Caches, not Application Support: a copy of public feeds the system
    /// may evict, never backed up, never synced.
    private static func cacheURL(_ name: String) -> URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(name)
    }

    private func writeCache() {
        let cache = Cache(fetchedAt: lastRefresh ?? .now, stories: stories, pageImages: pageImages)
        guard let url = Self.cacheURL("game-news.json"), let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func readCache() -> Cache? {
        guard let url = cacheURL("game-news.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func writeUpcomingCache(_ cache: UpcomingCache) {
        guard let url = cacheURL("upcoming-releases-v3.json"), let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func readUpcomingCache() -> UpcomingCache? {
        guard let url = cacheURL("upcoming-releases-v3.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UpcomingCache.self, from: data)
    }
}
