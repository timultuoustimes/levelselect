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
                                    ["u": username], username: username, apiKey: apiKey)
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
        let who = (credentials.ulid?.isEmpty == false ? credentials.ulid! : credentials.username)
        let raw = try await callRA("API_GetGameInfoAndUserProgress.php",
                                   ["g": String(gameID), "u": who],
                                   username: credentials.username, apiKey: credentials.apiKey)
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
    /// that is RA's own API contract and unavoidable for any client, but now
    /// only RA sees it. The proxy keeps the catalogue lookups, which use the
    /// app's own key and no user data.
    private static func callRA(_ endpoint: String, _ parameters: [String: String],
                               username: String, apiKey: String) async throws -> [String: Any] {
        var components = URLComponents(string: "https://retroachievements.org/API/\(endpoint)")!
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "z", value: username),
               URLQueryItem(name: "y", value: apiKey)]
        guard let url = components.url else {
            throw ServiceError(message: "Couldn't build the RetroAchievements request.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Never cached: the response is account data and the URL contains the
        // key, so a cache entry would be a second copy of the secret on disk.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
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
