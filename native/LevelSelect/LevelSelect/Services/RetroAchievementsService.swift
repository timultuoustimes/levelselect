import Foundation

/// RetroAchievements as a tracker source.
///
/// For an old game with an RA set, this is strictly better than generating a
/// tracker: the achievement list is the real, authored one — the same list the
/// emulator pops up against — rather than a model's best recollection of what
/// the game contains. It also arrives in a second instead of a minute, and it
/// cannot be subtly wrong about how many there are.
///
/// It is not a replacement for generation, only a better answer where it
/// applies. RA covers retro consoles, so a modern game has nothing here, and
/// an achievement set is one view of a game — it says nothing about the 900
/// collectibles someone might also want to track.
///
/// The APP's own key lives in an edge-function secret, never in the app: this
/// repo is public, and a key in the binary is a key in the repo. A USER's key
/// is different — it never touches our server at all, because Supabase logs
/// request bodies and headers. See `callRA`.
enum RetroAchievementsService {
    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One candidate RA game.
    struct Match: Identifiable, Hashable, Sendable {
        let id: Int
        let title: String
        let achievements: Int
    }

    struct Console: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
    }

    /// Consoles RA covers, in the app's platform vocabulary. Matched loosely —
    /// "SNES", "Super Nintendo" and "Super Nintendo Entertainment System" are
    /// all the same machine, and the library stores whatever IGDB or the user
    /// typed.
    private static let coveredPlatformKeys: [String] = [
        "nes", "famicom", "snes", "super nintendo", "nintendo 64", "n64",
        "game boy", "gameboy", "gba", "virtual boy", "gamecube",
        "nintendo ds", "nintendo dsi", "genesis", "mega drive", "master system",
        "game gear", "sega cd", "saturn", "dreamcast", "32x", "sg 1000",
        "playstation", "psx", "ps1", "ps2", "psp",
        "atari", "lynx", "jaguar", "neo geo", "neogeo",
        "pc engine", "turbografx", "wonderswan", "arcade", "msx",
        "apple ii", "amstrad", "zx spectrum", "intellivision", "colecovision",
        "vectrex", "3do", "odyssey", "channel f", "uzebox", "arduboy",
    ]

    /// Platforms whose names would otherwise match above but that RA does not
    /// cover. "PlayStation" is the trap: it is a prefix of every Sony console,
    /// and RA stops at PS2/PSP because modern PlayStation achievements are
    /// trophies, which are Sony's own system and not RA's to publish.
    private static let excludedPlatformKeys: [String] = [
        "playstation 3", "playstation 4", "playstation 5", "playstation vita",
        "ps3", "ps4", "ps5", "vita",
    ]

    /// Emulation front-ends. Someone who plays through one of these is playing
    /// a console RA covers — the library just records the box in the living
    /// room rather than the machine it emulates. This is also the case RA is
    /// most useful for, since these are exactly the setups that unlock
    /// achievements in the first place.
    private static let emulatorPlatformKeys: [String] = [
        "recalbox", "retropie", "batocera", "emulationstation", "retroarch",
        "emudeck", "mister", "lakka", "emulator", "emulation",
    ]

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Whether RetroAchievements plausibly has anything for this game.
    ///
    /// A local guess, not an answer. The real one costs a round trip through
    /// the proxy, and this only decides whether to *offer* the import, so it
    /// leans generous on purpose: an offer that finds nothing costs one tap and
    /// a clear "no matches", while a missing offer on a SNES game leaves the
    /// whole feature invisible to someone who never opens the menu.
    ///
    /// `platforms` is the user's OWN list — what they have it on — not the
    /// game's release platforms, which the library doesn't store. So a Genesis
    /// game played through Recalbox says "Recalbox" and nothing else, and a
    /// console-name check alone would hide RA from precisely the library that
    /// wants it most. Ownership answers it where the platform name can't:
    /// `.emulated` means an emulator, and an emulator means a console old
    /// enough for RA.
    static func mayCover(platforms: [String], ownership: [String]) -> Bool {
        if ownership.contains(Ownership.emulated.rawValue) { return true }
        return platforms.contains { platform in
            let key = normalized(platform)
            guard !key.isEmpty else { return false }
            if excludedPlatformKeys.contains(where: key.contains) { return false }
            if emulatorPlatformKeys.contains(where: key.contains) { return true }
            return coveredPlatformKeys.contains(where: key.contains)
        }
    }

    /// What a search came back with. RA's console vocabulary doesn't line up
    /// with the app's platform names, so "which system is this?" is a real
    /// answer rather than a failure — the caller asks and searches again.
    enum SearchResult: Sendable {
        case matches(console: Console, results: [Match])
        case needsConsole([Console])
    }

    struct Installed: Sendable {
        let title: String
        let count: Int
        let points: Int
        let schema: Data
    }

    /// Defined in Domain so `Repository` — which the watch compiles without
    /// any networking — can take these without importing the service.
    typealias Unlock = RAUnlock

    /// One game-shaped site award — a mastered or completed set. The wall
    /// people share.
    struct Award: Sendable, Equatable, Codable {
        let gameID: Int
        let title: String
        let consoleName: String?
        let iconPath: String?
        /// RA's own distinction: hardcore mastery vs softcore completion.
        /// The wall must say which, so it's carried rather than flattened.
        let hardcore: Bool
        let awardedAt: Date?
    }

    struct Progress: Sendable {
        let title: String?
        let total: Int
        let unlocked: [Unlock]
        let points: Int
        let totalPoints: Int
    }

    private static let functionURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/ra-proxy")!

    static func search(gameName: String, platform: String?,
                       consoleID: Int? = nil) async throws -> SearchResult {
        var body: [String: Any] = ["mode": "search", "gameName": gameName]
        if let platform, !platform.isEmpty { body["platform"] = platform }
        if let consoleID { body["consoleID"] = consoleID }
        let root = try await post(body)

        if root["needsConsole"] as? Bool == true {
            return .needsConsole(consoles(from: root["consoles"]))
        }
        guard let raw = root["console"] as? [String: Any],
              let id = raw["id"] as? Int, let name = raw["name"] as? String else {
            throw ServiceError(message: "RetroAchievements sent back something unreadable.")
        }
        let results = ((root["results"] as? [[String: Any]]) ?? []).compactMap { entry -> Match? in
            guard let id = entry["id"] as? Int,
                  let title = entry["title"] as? String else { return nil }
            return Match(id: id, title: title,
                         achievements: (entry["achievements"] as? Int) ?? 0)
        }
        return .matches(console: Console(id: id, name: name), results: results)
    }

    /// The achievement list for one RA game, as an installable tracker schema.
    static func achievements(gameID: Int) async throws -> Installed {
        let root = try await post(["mode": "achievements", "gameID": gameID])
        guard let structured = root["structuredData"] as? [String: Any],
              let categories = structured["categories"] as? [[String: Any]],
              !categories.isEmpty else {
            throw ServiceError(message: "That set came back empty. Try another entry.")
        }
        return Installed(
            title: (root["title"] as? String) ?? "RetroAchievements",
            count: (root["count"] as? Int) ?? 0,
            points: (root["points"] as? Int) ?? 0,
            schema: try JSONSerialization.data(withJSONObject: structured))
    }

    /// Check a username and key before saving them.
    ///
    /// Worth a round trip: a typo'd key would otherwise fail silently at the
    /// first sync, days later, looking like the sync is broken rather than
    /// the credentials.
    static func verify(username: String, apiKey: String) async throws -> RACredentials.Value {
        let root = try await callRA("API_GetUserProfile.php",
                                    ["u": username], apiKey: apiKey)
        // RA answers 200 with an empty body for a bad key rather than a 401,
        // so "the request worked" is not the same question as "the key is good".
        guard let user = root["User"] as? String, !user.isEmpty else {
            throw ServiceError(message: "RetroAchievements rejected that key. Check both fields.")
        }
        return RACredentials.Value(username: user, apiKey: apiKey,
                                   ulid: root["ULID"] as? String)
    }

    /// What this user has unlocked on one game, across their whole account.
    static func progress(gameID: Int, credentials: RACredentials.Value) async throws -> Progress {
        // `u` accepts a username OR a ULID, and the ULID is the stable one —
        // RA's docs say the username "is not considered a stable value".
        let raw = try await callRA(progressURL(gameID: gameID, credentials: credentials))
        let root = shapeProgress(raw)
        let formatter = ISO8601DateFormatter()
        // RA writes "2024-03-11 21:04:07" — a space, no zone. Parsed as UTC
        // rather than guessed at, since a wrong zone silently shifts an
        // unlock across a day boundary.
        let plain = DateFormatter()
        plain.dateFormat = "yyyy-MM-dd HH:mm:ss"
        plain.timeZone = TimeZone(identifier: "UTC")
        plain.locale = Locale(identifier: "en_US_POSIX")

        let unlocked = ((root["unlocked"] as? [[String: Any]]) ?? []).compactMap { entry -> Unlock? in
            guard let id = entry["id"] as? String else { return nil }
            let raw = entry["earnedAt"] as? String
            return Unlock(
                itemID: id,
                hardcore: (entry["hardcore"] as? Bool) ?? false,
                earnedAt: raw.flatMap { plain.date(from: $0) ?? formatter.date(from: $0) },
                points: (entry["points"] as? Int) ?? 0)
        }
        return Progress(
            title: root["title"] as? String,
            total: (root["total"] as? Int) ?? 0,
            unlocked: unlocked,
            points: (root["points"] as? Int) ?? 0,
            totalPoints: (root["totalPoints"] as? Int) ?? 0)
    }

    /// Every mastery/completion on this account, newest first.
    ///
    /// Direct to RA with the user's key, like all user-scoped calls — the
    /// proxy never sees credentials.
    static func masteries(credentials: RACredentials.Value) async throws -> [Award] {
        let root = try await callRA("API_GetUserAwards.php",
                                    ["u": credentials.ulid ?? credentials.username],
                                    apiKey: credentials.apiKey)
        return shapeAwards(root)
    }

    /// Pure, so tests can feed it fixtures. Keeps only "Mastery/Completion"
    /// awards; a game that has both a softcore completion and a later
    /// hardcore mastery appears once, wearing the mastery.
    static func shapeAwards(_ root: [String: Any]) -> [Award] {
        let iso = ISO8601DateFormatter()
        let rows = (root["VisibleUserAwards"] as? [[String: Any]]) ?? []
        var byGame: [Int: Award] = [:]
        var order: [Int] = []
        for row in rows {
            guard (row["AwardType"] as? String) == "Mastery/Completion",
                  let gameID = (row["AwardData"] as? NSNumber)?.intValue,
                  let title = row["Title"] as? String, !title.isEmpty else { continue }
            let award = Award(
                gameID: gameID,
                title: title,
                consoleName: row["ConsoleName"] as? String,
                iconPath: row["ImageIcon"] as? String,
                hardcore: (row["AwardDataExtra"] as? NSNumber)?.intValue == 1,
                awardedAt: (row["AwardedAt"] as? String).flatMap { iso.date(from: $0) })
            if let existing = byGame[gameID] {
                if !existing.hardcore && award.hardcore { byGame[gameID] = award }
            } else {
                byGame[gameID] = award
                order.append(gameID)
            }
        }
        return order.compactMap { byGame[$0] }
            .sorted { ($0.awardedAt ?? .distantPast) > ($1.awardedAt ?? .distantPast) }
    }

    // MARK: Talking to RetroAchievements directly

    /// User-scoped calls go device → RetroAchievements, never through our
    /// proxy.
    ///
    /// They used to be proxied, with the user's key in the request body. That
    /// was wrong: Supabase's Function Invocation logs capture "request/response
    /// data including headers, body, status codes", so every connect and every
    /// sync wrote a plaintext password-equivalent into platform telemetry that
    /// anyone with dashboard or log-drain access could read. Moving the key to
    /// a header would not have helped — headers are logged too.
    ///
    /// So the server is removed from the path entirely for anything carrying a
    /// user's credential. The key still rides in the query string, because
    /// that is RA's own API contract and unavoidable for any client, but our
    /// infrastructure never sees it. The proxy keeps the catalogue lookups,
    /// which use the app's own key and no user data.
    private static func callRA(_ endpoint: String, _ parameters: [String: String],
                               apiKey: String) async throws -> [String: Any] {
        let url = try credentialURL(endpoint: endpoint, parameters: parameters, apiKey: apiKey)
        return try await callRA(url)
    }

    private static func callRA(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await credentialSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceError(message: "Network error — check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            throw ServiceError(message: "RetroAchievements rejected that key. Check both fields.")
        }
        guard status == 200 else {
            throw ServiceError(message: "RetroAchievements is unavailable right now (\(status)).")
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ServiceError(message: "RetroAchievements sent back something unreadable.")
        }
        return root
    }

    static func progressURL(gameID: Int, credentials: RACredentials.Value) throws -> URL {
        let who = (credentials.ulid?.isEmpty == false ? credentials.ulid! : credentials.username)
        return try credentialURL(
            endpoint: "API_GetGameInfoAndUserProgress.php",
            parameters: ["g": String(gameID), "u": who],
            apiKey: credentials.apiKey
        )
    }

    /// Current RA endpoints authenticate with `y`; `u` is the target username
    /// or stable ULID. Sending the display username again as legacy `z` made a
    /// later username change capable of breaking a request that otherwise
    /// targeted the stable ULID.
    static func credentialURL(endpoint: String, parameters: [String: String],
                              apiKey: String) throws -> URL {
        var components = URLComponents(string: "https://retroachievements.org/API/\(endpoint)")!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "y", value: apiKey)]
        guard let url = components.url else {
            throw ServiceError(message: "Couldn't build the RetroAchievements request.")
        }
        return url
    }

    /// A session that cannot write these responses to disk.
    ///
    /// `.reloadIgnoringLocalAndRemoteCacheData` was not enough and the comment
    /// claiming "never cached" was wrong: that policy only stops the request
    /// READING the cache — Foundation may still store a cacheable response,
    /// keyed by the full URL, which for these calls contains the API key. An
    /// ephemeral configuration with no URL cache is what actually prevents a
    /// second copy of the secret landing on disk.
    private static let credentialSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    /// Fold RA's raw achievement map into the shape `progress` reads.
    ///
    /// `DateEarned` / `DateEarnedHardcore` are PRESENT only when earned, per
    /// RA's docs — so presence is the unlock signal, not the value.
    private static func shapeProgress(_ raw: [String: Any]) -> [String: Any] {
        let achievements = (raw["Achievements"] as? [String: Any])?.values
            .compactMap { $0 as? [String: Any] } ?? []
        func points(_ entry: [String: Any]) -> Int {
            (entry["Points"] as? Int) ?? Int((entry["Points"] as? String) ?? "") ?? 0
        }
        let unlocked = achievements
            .filter { $0["DateEarned"] != nil || $0["DateEarnedHardcore"] != nil }
            .map { entry -> [String: Any] in
                let id = (entry["ID"] as? Int).map(String.init)
                    ?? (entry["ID"] as? String) ?? ""
                let hardcore = entry["DateEarnedHardcore"] != nil
                return [
                    "id": "ra-\(id)",
                    "hardcore": hardcore,
                    "earnedAt": (entry["DateEarnedHardcore"] as? String)
                        ?? (entry["DateEarned"] as? String) ?? "",
                    "points": points(entry),
                ]
            }
        return [
            "title": raw["Title"] as Any,
            "total": achievements.count,
            "unlocked": unlocked,
            "points": unlocked.reduce(0) { $0 + (($1["points"] as? Int) ?? 0) },
            "totalPoints": achievements.reduce(0) { $0 + points($1) },
        ]
    }

    private static func consoles(from value: Any?) -> [Console] {
        ((value as? [[String: Any]]) ?? []).compactMap { entry in
            guard let id = entry["id"] as? Int,
                  let name = entry["name"] as? String else { return nil }
            return Console(id: id, name: name)
        }
    }

    private static func post(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
        // A lookup, not a generation — if it isn't back in half a minute
        // something is wrong rather than slow.
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceError(message: "Network error — check your connection and try again.")
        }

        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ServiceError(
                message: (root?["error"] as? String) ?? "RetroAchievements lookup failed (\(status)).")
        }
        guard let root else {
            throw ServiceError(message: "RetroAchievements sent back something unreadable.")
        }
        return root
    }
}
