import Foundation

/// A game result from IGDB (via the Supabase `igdb-proxy` edge function —
/// same backend the web app uses; credentials never touch the client).
struct IGDBGame: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let slug: String?
    let coverImageID: String?
    let franchise: String?
    let releaseYear: Int?
    let summary: String?
    let gameType: Int?
    let platforms: [String]
    let genres: [String]
    let themes: [String]
    let gameModes: [String]
    let playerPerspectives: [String]
    let developers: [String]
    let publishers: [String]

    /// Human label for non-main game types (nil for main games).
    var typeLabel: String? {
        switch gameType {
        case 1: "DLC"
        case 2: "Expansion"
        case 3: "Bundle"
        case 4: "Standalone"
        case 5: "Mod"
        case 6: "Episode"
        case 7: "Season"
        case 8: "Remake"
        case 9: "Remaster"
        case 10: "Expanded"
        case 11: "Port"
        case 12: "Fork"
        case 13: "Pack"
        case 14: "Update"
        default: nil
        }
    }

    var coverURLString: String? {
        coverImageID.map { "https://images.igdb.com/igdb/image/upload/t_cover_big/\($0).jpg" }
    }

    var releaseDate: Date? {
        releaseYear.flatMap { DateComponents(calendar: .current, year: $0, month: 1, day: 1).date }
    }
}

/// Why a lookup didn't come back.
///
/// Every one of these used to be `try?` at the call site, which is fine for a
/// single search box that can just show nothing — and useless for a
/// library-wide pass, where "some batches failed" is the difference between
/// "you're offline", "you've hit the lookup limit, wait a minute", and "the
/// proxy is refusing us". A refresh that can't say which of those happened
/// leaves the user tapping a button that will never work.
enum IGDBError: Error, Equatable {
    /// 429 — the proxy's per-install quota (60/minute, 2,000/day). Retrying
    /// immediately makes it worse; the window has to roll over first.
    case rateLimited
    /// 503 — kill switch flipped, or the quota store is unreachable.
    case unavailable
    /// Any other non-200 from the proxy, status carried for the report.
    case rejected(status: Int)
    /// The request never completed — no network, DNS, timeout.
    case offline
    /// A 200 whose body wasn't the shape we decode. One malformed row fails a
    /// whole batch, so this is worth telling apart from an empty result.
    case malformed
}

enum IGDBService {
    private static let proxyURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/igdb-proxy")!

    private static let fields = """
        fields name, slug, summary, game_type, cover.image_id, franchises.name, collection.name, \
        first_release_date, platforms.name, genres.name, themes.name, game_modes.name, \
        player_perspectives.name, involved_companies.developer, involved_companies.publisher, \
        involved_companies.company.name;
        """

    /// Name search — UNFILTERED (the web app's main-games-only filter hid
    /// bundles/editions like "Ultimate Bundle"). Main games sort first;
    /// bundles/DLC/remasters follow, badged via `typeLabel`.
    static func search(name: String) async throws -> [IGDBGame] {
        let clean = name.replacingOccurrences(of: "\"", with: "")
        guard clean.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let query = "search \"\(clean)\"; \(fields) limit 15;"
        let results = try await perform(query)
        // Stable partition: main games first, IGDB relevance preserved within groups.
        return results.filter { ($0.gameType ?? 0) == 0 } + results.filter { ($0.gameType ?? 0) != 0 }
    }

    /// Direct ID lookup — deliberately UNFILTERED so specific editions,
    /// remasters, and DLC ids resolve (the reason to search by id at all).
    static func lookup(id: Int) async throws -> IGDBGame? {
        try await perform("where id = \(id); \(fields) limit 1;").first
    }

    /// Look many ids up in ONE request.
    ///
    /// IGDB matches a list, so a whole-library refresh is a handful of calls
    /// rather than one per game — which is what keeps a 164-game pass from
    /// eating three minutes of the proxy's per-minute allowance. See
    /// `MetadataRefresh.Budget` for the arithmetic.
    ///
    /// Order is IGDB's, not the caller's, and ids IGDB does not know are
    /// simply absent from the result. Callers key by `id`.
    static func lookup(ids: [Int]) async throws -> [IGDBGame] {
        let unique = Array(Set(ids)).sorted()
        guard !unique.isEmpty else { return [] }
        return try await perform(idQuery(unique))
    }

    /// The multi-id query, exposed so a test can hold it against the proxy's
    /// 2,000-character cap rather than trusting an estimate of it.
    ///
    /// `limit` is explicit because IGDB's default is 10 — without it a chunk of
    /// 50 silently returns the first ten and the other forty look like games
    /// IGDB has never heard of.
    static func idQuery(_ ids: [Int]) -> String {
        let list = ids.map(String.init).joined(separator: ",")
        return "where id = (\(list)); \(fields) limit \(ids.count);"
    }

    /// Untyped passthrough, for endpoints whose shape isn't a game.
    ///
    /// `game_time_to_beats` returns rows of integers, and the critic fields
    /// aren't part of `IGDBGame` — decoding either into the typed model would
    /// mean widening it for two display-only numbers. Returns an empty array
    /// on any failure: this backs an optional readout, and a game page must
    /// not fail to draw because a critic score didn't arrive.
    static func raw(endpoint: String, query: String) async -> [[String: Any]] {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
        request.timeoutInterval = 20
        guard let body = try? JSONEncoder().encode(["endpoint": endpoint, "query": query])
        else { return [] }
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        return rows
    }

    private static func perform(_ query: String) async throws -> [IGDBGame] {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
        request.httpBody = try JSONEncoder().encode(["endpoint": "games", "query": query])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw IGDBError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw IGDBError.offline }
        switch http.statusCode {
        case 200:  break
        case 429:  throw IGDBError.rateLimited
        case 503:  throw IGDBError.unavailable
        default:   throw IGDBError.rejected(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode([RawGame].self, from: data).map { $0.toGame() }
        } catch {
            throw IGDBError.malformed
        }
    }

    // MARK: Raw IGDB shape

    private struct RawGame: Decodable {
        struct Named: Decodable { let name: String }
        struct Cover: Decodable { let image_id: String? }
        struct Involved: Decodable {
            let developer: Bool?
            let publisher: Bool?
            let company: Named?
        }

        let id: Int
        let name: String
        let slug: String?
        let summary: String?
        let game_type: Int?
        let cover: Cover?
        let franchises: [Named]?
        let collection: Named?
        let first_release_date: Double?
        let platforms: [Named]?
        let genres: [Named]?
        let themes: [Named]?
        let game_modes: [Named]?
        let player_perspectives: [Named]?
        let involved_companies: [Involved]?

        func toGame() -> IGDBGame {
            var developers: [String] = []
            var publishers: [String] = []
            for ic in involved_companies ?? [] {
                guard let n = ic.company?.name else { continue }
                if ic.developer == true { developers.append(n) }
                if ic.publisher == true { publishers.append(n) }
            }
            return IGDBGame(
                id: id,
                name: name,
                slug: slug,
                coverImageID: cover?.image_id,
                franchise: franchises?.first?.name ?? collection?.name,
                releaseYear: first_release_date.map {
                    Calendar.current.component(.year, from: Date(timeIntervalSince1970: $0))
                },
                summary: summary,
                gameType: game_type,
                platforms: (platforms ?? []).map(\.name),
                genres: (genres ?? []).map(\.name),
                themes: (themes ?? []).map(\.name),
                gameModes: (game_modes ?? []).map(\.name),
                playerPerspectives: (player_perspectives ?? []).map(\.name),
                developers: developers,
                publishers: publishers
            )
        }
    }
}
