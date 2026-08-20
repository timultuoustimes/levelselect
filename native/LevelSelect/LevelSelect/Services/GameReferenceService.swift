import Foundation

/// Critic scores and completion times, from IGDB.
///
/// Deliberately NOT stored on `Game`. These are reference facts about a game
/// rather than anything the user authored — they change as more reviews and
/// submissions land, and owning a copy would mean owning a number that goes
/// quietly stale. Fetched on demand, cached in memory for the session, and
/// forgotten when the app closes. It also means no new stored property, so no
/// Schema V3 for a feature that is entirely display.
///
/// Why IGDB and nothing else: Metacritic has never had a public API and
/// Fandom's terms forbid scraping; HowLongToBeat disallows `/api` in
/// robots.txt by name and bans commercial use, and its community wrappers
/// break roughly quarterly; OpenCritic is legitimate but requires a $50/month
/// commercial plan the moment an app is on a store. IGDB is free for
/// commercial use, already licensed here, and explicitly encourages caching.
@MainActor
final class GameReferenceService {
    static let shared = GameReferenceService()

    /// How many independent sources a figure needs before it's shown.
    ///
    /// Measured against a real 163-game library: without this, Sonic 2 and
    /// Sonic Mania both claim "2 hours" on the strength of one submission
    /// each (both are roughly three times that), and Super Metroid, Super
    /// Mario World and A Link to the Past each show a critic score of 100
    /// from a single outlet. A wrong number is worse than no number, because
    /// it teaches you to distrust the right ones too.
    ///
    /// The cost is real and worth stating: about half the library shows a
    /// critic score and 40% a completion time. Everything before 1996 shows
    /// almost nothing — which is honest, and those are the games where your
    /// own logged hours are the better answer anyway.
    static let minimumSources = 3

    struct Reference: Sendable, Equatable {
        var criticScore: Int?
        var criticSources: Int = 0
        /// Seconds to finish, "normally" — credits plus moderate extras.
        var normally: TimeInterval?
        var hastily: TimeInterval?
        var completely: TimeInterval?
        var timeReports: Int = 0

        var hasCritic: Bool { criticScore != nil }
        var hasTime: Bool { normally != nil }
        var isEmpty: Bool { !hasCritic && !hasTime }
    }

    private var cache: [Int: Reference] = [:]
    private var inFlight: Set<Int> = []

    private init() {}

    func cached(_ igdbID: Int) -> Reference? { cache[igdbID] }

    /// Look up one game, once. Repeated calls while a fetch is in flight are
    /// dropped rather than queued — this is called from `.task`, which runs
    /// again on every navigation back to the page.
    func load(_ igdbID: Int) async -> Reference? {
        if let hit = cache[igdbID] { return hit }
        guard !inFlight.contains(igdbID) else { return nil }
        inFlight.insert(igdbID)
        defer { inFlight.remove(igdbID) }

        async let critic = fetchCritic(igdbID)
        async let time = fetchTime(igdbID)
        var reference = await critic
        let times = await time
        reference.normally = times.normally
        reference.hastily = times.hastily
        reference.completely = times.completely
        reference.timeReports = times.reports

        cache[igdbID] = reference
        return reference
    }

    // MARK: IGDB

    private func fetchCritic(_ id: Int) async -> Reference {
        let rows = await IGDBService.raw(
            endpoint: "games",
            query: "fields aggregated_rating,aggregated_rating_count; where id = \(id); limit 1;")
        guard let row = rows.first,
              let score = row["aggregated_rating"] as? Double else { return Reference() }
        let count = (row["aggregated_rating_count"] as? Int) ?? 0
        // Below the threshold the figure is dropped entirely rather than shown
        // with a caveat: a caveat next to a number is still a number.
        guard count >= Self.minimumSources else { return Reference() }
        return Reference(criticScore: Int(score.rounded()), criticSources: count)
    }

    private func fetchTime(_ id: Int)
        async -> (normally: TimeInterval?, hastily: TimeInterval?,
                  completely: TimeInterval?, reports: Int) {
        let rows = await IGDBService.raw(
            endpoint: "game_time_to_beats",
            query: "fields hastily,normally,completely,count; where game_id = \(id); limit 1;")
        guard let row = rows.first else { return (nil, nil, nil, 0) }
        let count = (row["count"] as? Int) ?? 0
        guard count >= Self.minimumSources else { return (nil, nil, nil, count) }
        func seconds(_ key: String) -> TimeInterval? {
            (row[key] as? Int).map(TimeInterval.init)
        }
        return (seconds("normally"), seconds("hastily"), seconds("completely"), count)
    }
}
