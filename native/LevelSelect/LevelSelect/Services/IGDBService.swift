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
    /// IGDB's `first_release_date`, kept whole. See `releaseDate`.
    var releaseTimestamp: Double? = nil
    /// How much of that timestamp IGDB actually knows. See `ReleasePrecision`.
    var releasePrecision: ReleasePrecision = .unknown
    /// Every dated release IGDB lists, per platform. See `release(on:)`.
    var platformReleases: [PlatformRelease] = []
    /// YouTube ids, trailers first.
    var videoIDs: [String] = []

    /// One platform's release, with IGDB's own precision for it.
    struct PlatformRelease: Hashable, Sendable {
        let platform: String
        let timestamp: Double
        let precision: ReleasePrecision
        /// IGDB's release TYPE, not its precision. A game can carry two rows
        /// for one platform — a beta and the launch. nil is the common case.
        var status: Int? = nil
    }

    /// What IGDB's date actually claims.
    ///
    /// IGDB pads imprecise dates to real timestamps: a year-only entry can
    /// arrive as **30 December**, a quarter as the last day of that quarter.
    /// Without this the app cannot tell "launches 30 December" from "sometime
    /// in 2026", and it printed the former for the Ocarina of Time remake,
    /// which has no announced date at all.
    enum ReleasePrecision: String, Codable, Sendable {
        case day, month, quarter, year, tbd, unknown

        /// Whether a day may be shown. Only IGDB's own exact-day category
        /// earns that; everything else is a placeholder wearing a date.
        var hasDay: Bool { self == .day }
    }

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

    /// The real release date when IGDB gave one, falling back to 1 January of
    /// the year.
    ///
    /// IGDB sends `first_release_date` as a Unix timestamp and this type used
    /// to keep only `Calendar.component(.year:)` of it, rebuilding a
    /// 1-January date from the year alone — so **every release date in the
    /// library was 1 January**, and the month and day were thrown away at
    /// parse time on data the proxy had already fetched.
    ///
    /// Found 2026-08-31 through the wishlist's "coming soon" split, which
    /// could not tell a February release from a November one because both were
    /// stored as January. `releaseYear` stays as the fallback for rows written
    /// before this and for games IGDB dates only by year.
    /// The date as the app should STORE it.
    ///
    /// A precise day is kept whole. Anything vaguer collapses to 1 January of
    /// its year — the shorthand the rest of the app already reads as "the year
    /// is all we know" (`MetadataRefresh.isYearOnly`). That keeps one
    /// convention rather than introducing a second kind of fuzzy date, and it
    /// means an imprecise answer can never be mistaken for a launch day.
    /// The date to store for someone who owns — or intends to buy — this game
    /// on `platform`.
    ///
    /// `first_release_date` is the EARLIEST across every platform, so a game
    /// that reached PC in 2025 and arrives on Switch 2 in 2026 reads as
    /// released. For a wishlist that is the wrong answer in exactly the case
    /// the wishlist exists for. Tim's framing, 2026-08-31: *"letting them pick
    /// the game and then the platform they want it for, which in turn is
    /// choosing the date."*
    ///
    /// Falls back to the aggregate when IGDB lists no date for that platform,
    /// or when no platform has been chosen.
    /// A beta is not a release.
    ///
    /// IGDB gives a game one `release_dates` row PER EVENT, not per platform,
    /// and each carries a `status`. Call of Duty: Modern Warfare 4 has eight
    /// rows: a beta on 28 August for four platforms, and the launches — 16
    /// October on Switch 2, 23 October everywhere else. Taking the first row
    /// for a platform took the beta, so the app called an unreleased game
    /// released, on every platform, and counted down to the wrong day.
    ///
    /// Measured, not guessed: `status=2` is that beta and `status=6` those
    /// launches. Most games set no status at all — the Vault Edition of the
    /// same game has `nil` — so `nil` counts as a launch, and a platform with
    /// nothing but pre-release rows falls back to them rather than vanishing.
    static let launchStatuses: Set<Int> = [6]

    var launchReleases: [PlatformRelease] {
        let launches = platformReleases.filter { $0.status == nil || Self.launchStatuses.contains($0.status!) }
        return launches.isEmpty ? platformReleases : launches
    }

    func storableReleaseDate(on platform: String?) -> Date? {
        guard let platform,
              let match = launchReleases.first(where: {
                  PlatformIcon.consoleKey($0.platform) == PlatformIcon.consoleKey(platform)
              })
        else { return earliestAnnouncedDay ?? storableReleaseDate }

        let date = Date(timeIntervalSince1970: match.timestamp)
        guard match.precision.hasDay, !MetadataRefresh.isYearOnly(date) else {
            // Built in UTC, like every other release date in the app.
            //
            // This wrote LOCAL midnight, so Onimusha's placeholder was stored
            // as 1 January 05:00Z from Eastern time. Read back with the UTC
            // rules everything else uses, a local-midnight 1 January is 31
            // December of the previous year anywhere EAST of Greenwich — which
            // still reads as year-only, by luck, but reads as the WRONG year,
            // so `awaitsAnnouncedDate` would answer no and the game would
            // never be asked about again.
            let utc = ReleaseCountdown.utc
            let year = utc.component(.year, from: date)
            return DateComponents(calendar: utc, year: year, month: 1, day: 1).date
        }
        return date
    }

    var storableReleaseDate: Date? {
        guard let date = releaseDate else { return nil }
        // IGDB's own category is trusted, EXCEPT when the day it gives is one
        // of the two padding days — a category-0 answer landing on
        // 31 December is a period boundary far more often than a launch.
        guard releasePrecision.hasDay, !MetadataRefresh.isYearOnly(date) else {
            let utc = ReleaseCountdown.utc
            let year = utc.component(.year, from: date)
            return DateComponents(calendar: utc, year: year, month: 1, day: 1).date
        }
        return date
    }

    /// Every platform date, in the shape the app stores. Schema V4.
    ///
    /// `platformReleases` is the API's own answer and is thrown away after one
    /// date is picked from it; this is the same data on its way to disk, so a
    /// game can carry all of them.
    var storedPlatformReleases: [StoredPlatformRelease] {
        // Only launches are stored. A beta date on a game page would read as
        // a release, which is exactly the bug this fixes.
        launchReleases.map {
            StoredPlatformRelease(platform: $0.platform,
                                  date: Date(timeIntervalSince1970: $0.timestamp),
                                  hasDay: $0.precision.hasDay)
        }
    }

    /// The soonest platform release IGDB gives an exact day for.
    ///
    /// When you have not said which platform you will get a game on, a
    /// day-precise platform entry beats IGDB's own summary. Onimusha: Way of
    /// the Sword carries 3 September 2026 on every platform it ships on, while
    /// `first_release_date` is coarse enough to pad to 1 January — so the app
    /// stored "2026", filed a game two days out under "No date yet", and
    /// disagreed with IGDB's own countdown on the same game's page.
    ///
    /// A CHOSEN platform still wins, even when its own entry is vague: if you
    /// said Switch 2 and Switch 2 has no day, the honest answer is that nobody
    /// has told you when YOUR copy arrives.
    var earliestAnnouncedDay: Date? {
        launchReleases
            .filter(\.precision.hasDay)
            .map { Date(timeIntervalSince1970: $0.timestamp) }
            .filter { !MetadataRefresh.isYearOnly($0) }
            .min()
    }

    var releaseDate: Date? {
        if let stamp = releaseTimestamp { return Date(timeIntervalSince1970: stamp) }
        return releaseYear.flatMap { DateComponents(calendar: .current, year: $0, month: 1, day: 1).date }
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
        first_release_date, release_dates.*, release_dates.platform.name, \
        platforms.name, genres.name, themes.name, game_modes.name, \
        player_perspectives.name, videos.video_id, videos.name, \
        involved_companies.developer, involved_companies.publisher, \
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
        /// IGDB's own precision for each regional release. `category` is the
        /// date-format enum: 0 = exact day, 1 = month, 2 = year, 3–6 = a
        /// quarter, 7 = TBD.
        struct ReleaseDate: Decodable {
            let category: Int?
            let date: Double?
            /// What `category` used to be. IGDB stopped answering with
            /// `category` — every row now comes back with it nil — and moved
            /// the precision to `date_format`. Both are read, so this keeps
            /// working whichever one an endpoint decides to send.
            let date_format: Int?
            /// IGDB's release TYPE — Beta, Early Access, Full Release. Not
            /// precision. A game can have two rows for one platform.
            let status: Int?
            struct Platform: Decodable { let name: String? }
            let platform: Platform?
        }
        let release_dates: [ReleaseDate]?
        struct Video: Decodable { let video_id: String?; let name: String? }
        let videos: [Video]?

        /// How precise IGDB's own answer is for the earliest release.
        ///
        /// `first_release_date` is an aggregate with no precision attached, and
        /// **IGDB pads an imprecise date to a real timestamp** — a year-only
        /// entry can arrive as 30 December. So the day alone cannot be trusted:
        /// the Ocarina of Time remake, announced for "late 2026" with no date,
        /// came through as 30 December 2026 and the wishlist printed it as a
        /// launch day. The matching `release_dates` row carries the truth.
        static func precision(of first: Double?,
                              in dates: [ReleaseDate]?) -> IGDBGame.ReleasePrecision {
            guard let first, let dates, !dates.isEmpty else { return .unknown }
            // The row the aggregate came from — the earliest matching date.
            let match = dates
                .filter { $0.date != nil }
                .min { abs(($0.date ?? 0) - first) < abs(($1.date ?? 0) - first) }
            return match.map { precision(of: $0) } ?? .unknown
        }

        static func precision(for category: Int?) -> IGDBGame.ReleasePrecision {
            switch category {
            case 0: return .day
            case 1: return .month
            case 2: return .year
            case 3, 4, 5, 6: return .quarter
            case 7: return .tbd
            default: return .unknown
            }
        }

        /// The precision of one release row, from whichever field IGDB sent.
        ///
        /// When it sends neither, the timestamp is judged on its own. That is
        /// the case that mattered: IGDB now returns `category` as nil on every
        /// row, so every date read as `.unknown`, and an exact day was thrown
        /// away and padded to 1 January. Onimusha: Way of the Sword came back
        /// with a real timestamp on all four of its platforms and the app
        /// filed it as undated.
        ///
        /// Judging the timestamp is safe because the thing being guarded
        /// against has a shape: IGDB pads an imprecise date to the boundary of
        /// its period, which is 1 January or 31 December. A timestamp landing
        /// anywhere else was not padded, so it is a day someone published.
        static func precision(of row: ReleaseDate) -> IGDBGame.ReleasePrecision {
            if let category = row.category { return precision(for: category) }
            if let format = row.date_format { return precision(for: format) }
            guard let stamp = row.date else { return .unknown }
            return MetadataRefresh.isYearOnly(Date(timeIntervalSince1970: stamp)) ? .year : .day
        }

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
                publishers: publishers,
                releaseTimestamp: first_release_date,
                releasePrecision: Self.precision(of: first_release_date, in: release_dates),
                platformReleases: (release_dates ?? []).compactMap { row in
                    guard let name = row.platform?.name, let stamp = row.date else { return nil }
                    return IGDBGame.PlatformRelease(
                        platform: name, timestamp: stamp,
                        precision: Self.precision(of: row), status: row.status)
                },
                videoIDs: {
                    let rows = videos ?? []
                    let trailers = rows.filter {
                        ($0.name ?? "").localizedCaseInsensitiveContains("trailer")
                    }
                    let rest = rows.filter { row in
                        !trailers.contains { $0.video_id == row.video_id }
                    }
                    return (trailers + rest).compactMap(\.video_id)
                }()
            )
        }
    }
}

/// IGDB's image categories, as they arrive on `covers` and `artworks`.
///
/// In August 2026 IGDB split covers and logos out of artworks into their own
/// contributable data and introduced `image_type` to classify them; the older
/// `artwork_type` field is deprecated at the end of the year.
///
/// The full table, read from the `image_types` endpoint rather than guessed:
///
///  1 Artwork                 9 Historical cover
///  2 Key art without logo   10 Alternative cover
///  3 Key art with logo      11 Square cover
///  4 Concept art            12 Infographic
///  5 Game logo (white)      13 Icon
///  6 Game logo (black)      14 Historical logo
///  7 Game logo (color)      15 Historical icon
///  8 Main cover             16 Historical artwork
enum IGDBImageType {
    /// Behind a header that draws the logo itself, key art WITHOUT the logo
    /// is the one to want — otherwise the game's name appears twice, once
    /// baked into the backdrop at whatever size the publisher chose.
    static let keyArtWithoutLogo = 2
    static let keyArtWithLogo = 3

    /// Color first — it's the cut a game is recognized by. White and black
    /// are the same wordmark drawn for a light or dark ground, and they earn
    /// their place: the header lays the logo over artwork, where a white cut
    /// often reads better than the color one.
    ///
    /// An earlier pass shipped only `7`, inferred from one game's aspect
    /// ratio and alpha channel before this lookup was reachable. The
    /// inference was right about 7 and silently hid 5, 6 and 14 from every
    /// game that has them.
    static let logos = [7, 5, 6, 14]

    /// Never offered as a cover or a backdrop: a wordmark, an icon or an
    /// infographic is not a picture of the game.
    static let notScenery: Set<Int> = [5, 6, 7, 14, 12, 13, 15]
}
