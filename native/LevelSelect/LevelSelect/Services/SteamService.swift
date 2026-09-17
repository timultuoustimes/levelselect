import Foundation

/// Steam, split the way RetroAchievements is.
///
/// **There is no keyless route to Steam.** Measured 09-14: the schema call
/// answers 400 without a key and the owned-games call 401, and the community
/// pages that used to serve XML to anyone now return HTML or a sign-in page.
///
/// So, as with RA (Tim, 09-14: *"the same setup as Retroachievements"*):
/// catalogue lookups that say nothing about who's asking — store search and a
/// game's achievement list — go through `steam-proxy` on LevelSelect's key, and
/// need nothing from the player. What IS about them — their library and their
/// unlocks — uses their own key (`SteamCredentials`), device → Steam.
///
/// The parsing is split from the networking so tests can feed it fixtures;
/// Steam's responses carry an error inside a 200 as often as they use a status.
enum SteamService {
    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Profile: Sendable, Equatable {
        let steamID: String
        let personaName: String
        let profileURL: String?
        /// `communityvisibilitystate == 3`. A private profile still connects —
        /// it just can't share a library or achievements until it's public.
        let isPublic: Bool
    }

    struct OwnedGame: Sendable, Equatable, Identifiable {
        let appID: Int
        let name: String
        let minutesPlayed: Int
        let lastPlayed: Date?
        var id: Int { appID }
        var hoursPlayed: Double { Double(minutesPlayed) / 60 }
    }

    struct Installed: Sendable {
        let title: String
        let count: Int
        let schema: Data
    }

    struct Progress: Sendable {
        let total: Int
        let unlocked: [RAUnlock]
    }

    /// The one category a Steam import writes, and its items' id prefix — so an
    /// achievement's api name can never collide with a generated item id.
    static let categoryID = "steam"
    static let categoryName = "Steam Achievements"
    static let itemPrefix = "steam-"

    static let apiKeyPage = URL(string: "https://steamcommunity.com/dev/apikey")!

    static func storePage(_ appID: Int) -> URL {
        URL(string: "https://store.steampowered.com/app/\(appID)")!
    }

    static func achievementsPage(appID: Int, steamID: String) -> URL? {
        URL(string: "https://steamcommunity.com/profiles/\(steamID)/stats/\(appID)/achievements/")
    }

    static func profilePage(_ steamID: String) -> URL? {
        URL(string: "https://steamcommunity.com/profiles/\(steamID)")
    }

    // MARK: Which profile

    enum ProfileInput: Equatable {
        case steamID(String)
        case vanity(String)
    }

    /// A profile link, a custom URL name, or a SteamID — whichever someone has
    /// to hand. Steam's own settings show all three in different places.
    static func profileInput(_ raw: String) -> ProfileInput? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if isSteamID(text) { return .steamID(text) }
        if text.contains("/") {
            let parts = text.split(separator: "/").map(String.init)
            if let i = parts.firstIndex(of: "profiles"), i + 1 < parts.count, isSteamID(parts[i + 1]) {
                return .steamID(parts[i + 1])
            }
            if let i = parts.firstIndex(of: "id"), i + 1 < parts.count, isVanity(parts[i + 1]) {
                return .vanity(parts[i + 1])
            }
            return nil
        }
        return isVanity(text) ? .vanity(text) : nil
    }

    static func isSteamID(_ text: String) -> Bool {
        text.count == 17 && text.hasPrefix("7656119")
            && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isVanity(_ text: String) -> Bool {
        (2...32).contains(text.count)
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// Check a profile and key together before anything is saved — a typo'd
    /// key would otherwise fail at the first import, looking like Steam broke.
    static func verify(profile raw: String, apiKey: String) async throws -> SteamCredentials.Value {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let input = profileInput(raw) else {
            throw ServiceError(message: "That doesn't look like a Steam profile. Paste your profile link, or the name at the end of it.")
        }
        let steamID: String
        switch input {
        case .steamID(let id):
            steamID = id
        case .vanity(let name):
            let (_, json) = try await call("ISteamUser/ResolveVanityURL/v1/",
                                           ["vanityurl": name], apiKey: key)
            guard let id = resolvedSteamID(json) else {
                throw ServiceError(message: "Steam has no profile called “\(name)”.")
            }
            steamID = id
        }
        let (_, json) = try await call("ISteamUser/GetPlayerSummaries/v2/",
                                       ["steamids": steamID], apiKey: key)
        guard let profile = profile(from: json) else {
            throw ServiceError(message: "Steam didn't return that profile. Check the link and the key.")
        }
        return SteamCredentials.Value(steamID: profile.steamID, apiKey: key,
                                      personaName: profile.personaName)
    }

    /// `success` is 1 for a match and 42 for none, inside a 200 either way.
    static func resolvedSteamID(_ json: [String: Any]) -> String? {
        guard let response = json["response"] as? [String: Any],
              (response["success"] as? NSNumber)?.intValue == 1,
              let id = response["steamid"] as? String, isSteamID(id) else { return nil }
        return id
    }

    static func profile(from json: [String: Any]) -> Profile? {
        guard let response = json["response"] as? [String: Any],
              let player = (response["players"] as? [[String: Any]])?.first,
              let id = player["steamid"] as? String, isSteamID(id) else { return nil }
        return Profile(steamID: id,
                       personaName: (player["personaname"] as? String) ?? id,
                       profileURL: player["profileurl"] as? String,
                       isPublic: (player["communityvisibilitystate"] as? NSNumber)?.intValue == 3)
    }

    // MARK: The library

    static func ownedGames(credentials: SteamCredentials.Value) async throws -> [OwnedGame] {
        let (_, json) = try await call("IPlayerService/GetOwnedGames/v1/", [
            "steamid": credentials.steamID,
            "include_appinfo": "1",
            // Free games only count once played — which is the library people
            // mean; every free-to-play demo ever clicked is not.
            "include_played_free_games": "1",
        ], apiKey: credentials.apiKey)
        guard let games = ownedGames(from: json) else {
            throw ServiceError(message: "Steam didn't share this library. In Steam, set Privacy → Game details to Public, then try again.")
        }
        return games
    }

    /// Nil for a hidden library: Steam answers a private one with an empty
    /// `response` rather than an error, and "0 games" would be the wrong thing
    /// to tell someone who owns four hundred.
    static func ownedGames(from json: [String: Any]) -> [OwnedGame]? {
        guard let response = json["response"] as? [String: Any],
              response["game_count"] != nil else { return nil }
        let rows = (response["games"] as? [[String: Any]]) ?? []
        return rows.compactMap { row -> OwnedGame? in
            guard let appID = (row["appid"] as? NSNumber)?.intValue,
                  let name = (row["name"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return nil }
            let last = (row["rtime_last_played"] as? NSNumber)?.doubleValue ?? 0
            return OwnedGame(appID: appID, name: name,
                             minutesPlayed: (row["playtime_forever"] as? NSNumber)?.intValue ?? 0,
                             lastPlayed: last > 0 ? Date(timeIntervalSince1970: last) : nil)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Achievements

    /// The game's achievement list as an installable tracker schema.
    ///
    /// Through our proxy on LevelSelect's own key, the way RetroAchievements'
    /// lists come: an app id says nothing about who is asking, so nobody needs
    /// a key of their own to track a Steam game's achievements by hand. Their
    /// key is for what IS about them — their library and their unlocks.
    static func achievements(appID: Int) async throws -> Installed {
        let json = try await post(["mode": "achievements", "appID": appID])
        guard let installed = installed(appID: appID, from: json) else {
            throw ServiceError(message: "Steam lists no achievements for that game.")
        }
        return installed
    }

    struct SearchResult: Sendable, Equatable, Identifiable {
        let id: Int
        let name: String
    }

    /// Steam's store search, through our proxy — a search term, no identity.
    static func search(_ term: String) async throws -> [SearchResult] {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return [] }
        return searchResults(from: try await post(["mode": "search", "term": String(clean.prefix(200))]))
    }

    static func searchResults(from json: [String: Any]) -> [SearchResult] {
        ((json["results"] as? [[String: Any]]) ?? []).compactMap { row in
            guard let id = (row["id"] as? NSNumber)?.intValue, id > 0,
                  let name = row["name"] as? String, !name.isEmpty else { return nil }
            return SearchResult(id: id, name: name)
        }
    }

    /// Shaped like the RetroAchievements import, so the tracker treats both
    /// the same way: one category, stamped with the id a later sync looks the
    /// game up by, carried whole through a merge.
    static func installed(appID: Int, from json: [String: Any], now: Date = .now) -> Installed? {
        guard let game = json["game"] as? [String: Any],
              let stats = game["availableGameStats"] as? [String: Any],
              let raw = stats["achievements"] as? [[String: Any]], !raw.isEmpty else { return nil }
        let title = (game["gameName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Steam"
        let items: [[String: Any]] = raw.compactMap { achievement in
            guard let api = achievement["name"] as? String, !api.isEmpty else { return nil }
            let display = (achievement["displayName"] as? String)?
                .trimmingCharacters(in: .whitespaces)
            var item: [String: Any] = [
                "id": itemPrefix + api,
                "name": (display?.isEmpty == false ? display! : api),
            ]
            if let description = achievement["description"] as? String, !description.isEmpty {
                item["description"] = description
            }
            // In metadata, where RA keeps its badge: invisible to merge logic,
            // kept by item edits, ignored by builds that don't read it.
            var metadata: [String: Any] = ["steamAPIName": api]
            if let icon = achievement["icon"] as? String { metadata["icon"] = icon }
            if let locked = achievement["icongray"] as? String { metadata["iconLocked"] = locked }
            if (achievement["hidden"] as? NSNumber)?.intValue == 1 { metadata["hidden"] = true }
            item["metadata"] = metadata
            return item
        }
        guard !items.isEmpty else { return nil }
        let root: [String: Any] = [
            "schemaVersion": 1,
            "generatedAt": ISO8601DateFormatter().string(from: now),
            "generatedBy": "steam",
            "sources": [["type": "steam", "url": storePage(appID).absoluteString]],
            "categories": [[
                "id": categoryID,
                "name": categoryName,
                TrackerSchemaJSON.steamAppIDKey: appID,
                "description": "Steam achievements for \(title)",
                "type": "checklist",
                "items": items,
            ]],
            "runs": [],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return Installed(title: title, count: items.count, schema: data)
    }

    /// What this account has unlocked in one game.
    static func progress(appID: Int, credentials: SteamCredentials.Value) async throws -> Progress {
        let (status, json) = try await call("ISteamUserStats/GetPlayerAchievements/v1/", [
            "steamid": credentials.steamID,
            "appid": String(appID),
        ], apiKey: credentials.apiKey)
        if let progress = progress(from: json) { return progress }
        let message = ((json["playerstats"] as? [String: Any])?["error"] as? String) ?? ""
        if status == 403 || message.localizedCaseInsensitiveContains("not public") {
            throw ServiceError(message: "Steam keeps this profile's achievements private. In Steam, set Privacy → Game details to Public, then sync again.")
        }
        throw ServiceError(message: message.isEmpty
                           ? "Steam didn't return achievements for this game (\(status))."
                           : "Steam says: \(message)")
    }

    /// Only achieved rows become unlocks; `unlocktime` 0 means Steam doesn't
    /// know when, which is recorded as not knowing rather than as 1970.
    static func progress(from json: [String: Any]) -> Progress? {
        guard let stats = json["playerstats"] as? [String: Any],
              (stats["success"] as? Bool) == true else { return nil }
        let rows = (stats["achievements"] as? [[String: Any]]) ?? []
        let unlocked = rows.compactMap { row -> RAUnlock? in
            guard let api = row["apiname"] as? String,
                  (row["achieved"] as? NSNumber)?.intValue == 1 else { return nil }
            let time = (row["unlocktime"] as? NSNumber)?.doubleValue ?? 0
            return RAUnlock(itemID: itemPrefix + api, hardcore: false,
                            earnedAt: time > 0 ? Date(timeIntervalSince1970: time) : nil,
                            points: 0)
        }
        return Progress(total: rows.count, unlocked: unlocked)
    }

    // MARK: Library import

    /// IGDB's own name for the platform, so a matched game's platform lines up
    /// with the release dates IGDB gives it.
    static let pcPlatform = "PC (Microsoft Windows)"

    /// Valve's own machines, which play the same library.
    static let steamHardware = ["Steam Deck", "Steam Machine"]

    /// Headsets that play Steam's VR games, as IGDB names them.
    static let pcHeadsets = ["Valve Index", "HTC Vive", "Oculus Rift", "Meta Quest"]

    /// Steam's library as import rows, minus the `existing…` games (the
    /// wishlist) — by IGDB id when the app maps to one, by name otherwise. A
    /// game in `libraryByIGDB`/`library` comes as a row that adds PC to it.
    /// Hours stay off the rows:
    /// Steam playtime goes to the Steam playthrough (`applySteamPlaytime`), and
    /// status is left to the review rather than guessed from playtime.
    static func libraryRows(from owned: [OwnedGame], igdbByApp: [Int: Int],
                            existingIGDBIDs: Set<Int>, existingNames: Set<String>,
                            libraryByIGDB: [Int: UUID] = [:],
                            library: [String: UUID] = [:]) -> [CSVImport.Row] {
        var seen = Set<Int>()
        var seenExisting = Set<UUID>()
        return owned.enumerated().compactMap { index, game in
            let igdbID = igdbByApp[game.appID]
            let existing = igdbID.flatMap { libraryByIGDB[$0] } ?? library[TrackerMerge.matchKey(game.name)]
            if let existing {
                guard seenExisting.insert(existing).inserted else { return nil }
            } else {
                if let igdbID {
                    // Two Steam apps can be one IGDB game (a game and its
                    // soundtrack edition); add it once.
                    guard !existingIGDBIDs.contains(igdbID), seen.insert(igdbID).inserted else { return nil }
                }
                guard !existingNames.contains(game.name.lowercased()) else { return nil }
            }
            return CSVImport.Row(name: game.name, platform: pcPlatform, platforms: [pcPlatform],
                                 status: nil, rating: nil, notes: nil,
                                 hoursPlayed: nil,
                                 igdbID: igdbID, line: index + 1,
                                 skipReason: looksLikeDemo(game.name) ? "Demo — left unticked" : nil,
                                 // Steam doesn't say which machine; the match
                                 // adds Mac or a headset when you have one.
                                 offersPlatformChoice: true,
                                 platformChoices: [pcPlatform],
                                 ownedOnlyChoices: steamHardware,
                                 vrChoices: pcHeadsets,
                                 fallbackPlatform: pcPlatform,
                                 existingGameID: existing)
        }
    }

    /// Which library game each played Steam game is — by IGDB id when the app
    /// maps to one, by name otherwise — with the minutes Steam has for it. Two
    /// apps that are one game (a game and its soundtrack) keep the larger
    /// number rather than a sum that would count the same hours twice.
    static func playtimeMatches(owned: [OwnedGame], igdbByApp: [Int: Int],
                                library: [(id: UUID, igdbID: Int?, name: String)]) -> [UUID: Int] {
        var byIGDB: [Int: UUID] = [:]
        var byName: [String: UUID] = [:]
        for game in library {
            if let igdbID = game.igdbID, byIGDB[igdbID] == nil { byIGDB[igdbID] = game.id }
            let key = game.name.lowercased()
            if byName[key] == nil { byName[key] = game.id }
        }
        var out: [UUID: Int] = [:]
        for game in owned where game.minutesPlayed > 0 {
            guard let match = igdbByApp[game.appID].flatMap({ byIGDB[$0] })
                    ?? byName[game.name.lowercased()] else { continue }
            out[match] = max(out[match] ?? 0, game.minutesPlayed)
        }
        return out
    }

    /// Steam counts a played demo as an owned game, and it's rarely one someone
    /// wants in their library. The whole word only, so "Demon's Souls" and
    /// "Pandemonium" stay ticked.
    static func looksLikeDemo(_ name: String) -> Bool {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains("demo")
    }

    /// Loose on purpose — "Portal 2" should find "Portal 2: Complete" — because
    /// this only narrows a list someone picks from; nothing installs on it.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let fold = { (text: String) in text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let x = fold(a), y = fold(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x.contains(y) || y.contains(x)
    }

    // MARK: Matching Steam to IGDB

    /// IGDB's id for Steam in `external_games`. The old `category` enum used
    /// the same value and the parser accepts either field, so a game still
    /// matches whichever one IGDB is serving. Unverified against a live
    /// response until a real key has run it; name search is the fallback.
    static let igdbSteamSource = 1

    private static let igdbExternalFields =
        "fields id,external_games.uid,external_games.category,external_games.external_game_source;"

    /// The Steam app ids IGDB records for one game.
    static func appIDs(forIGDB igdbID: Int) async -> [Int] {
        let rows = await IGDBService.raw(endpoint: "games",
                                         query: "\(igdbExternalFields) where id = \(igdbID); limit 1;")
        return steamAppIDs(fromIGDBRows: rows)[igdbID] ?? []
    }

    /// App id → IGDB id, fifty to a request. Queried on `games`, which the
    /// proxy already allows, so no deploy; the uid filter matches any store,
    /// so only Steam's are kept.
    static func igdbIDs(forAppIDs appIDs: [Int]) async -> [Int: Int] {
        var result: [Int: Int] = [:]
        let unique = Array(Set(appIDs)).sorted()
        for start in stride(from: 0, to: unique.count, by: 50) {
            let chunk = Array(unique[start..<min(start + 50, unique.count)])
            let wanted = Set(chunk)
            let list = chunk.map { "\"\($0)\"" }.joined(separator: ",")
            let rows = await IGDBService.raw(
                endpoint: "games",
                query: "\(igdbExternalFields) where external_games.uid = (\(list)); limit 500;")
            for (igdbID, apps) in steamAppIDs(fromIGDBRows: rows) {
                for app in apps where wanted.contains(app) && result[app] == nil {
                    result[app] = igdbID
                }
            }
        }
        return result
    }

    static func steamAppIDs(fromIGDBRows rows: [[String: Any]]) -> [Int: [Int]] {
        var out: [Int: [Int]] = [:]
        for row in rows {
            guard let id = (row["id"] as? NSNumber)?.intValue else { continue }
            let externals = (row["external_games"] as? [[String: Any]]) ?? []
            let apps = externals.compactMap { external -> Int? in
                let source = (external["external_game_source"] as? NSNumber)?.intValue
                    ?? (external["category"] as? NSNumber)?.intValue
                guard source == igdbSteamSource, let uid = external["uid"] as? String else { return nil }
                return Int(uid)
            }
            if !apps.isEmpty { out[id] = apps }
        }
        return out
    }

    // MARK: Transport

    private static let functionURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/steam-proxy")!

    /// Our proxy, for catalogue lookups only. It is never sent a key or a SteamID.
    private static func post(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
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
            throw ServiceError(message: (root?["error"] as? String) ?? "Steam lookup failed (\(status)).")
        }
        guard let root else {
            throw ServiceError(message: "Steam sent back something unreadable.")
        }
        return root
    }

    /// The key rides in the query string — Steam's own contract — so the
    /// session is ephemeral with no URL cache, as `RetroAchievementsService`
    /// learned: a cached response is keyed by the full URL, key included.
    /// Redirects are held to api.steampowered.com (`CredentialRedirectGuard`).
    private static let session: URLSession = CredentialRedirectGuard.session()

    private static func call(_ path: String, _ parameters: [String: String],
                             apiKey: String) async throws -> (status: Int, json: [String: Any]) {
        var components = URLComponents(string: "https://api.steampowered.com/\(path)")!
        components.queryItems = parameters.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "key", value: apiKey), URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else {
            throw ServiceError(message: "Couldn't build the Steam request.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceError(message: "Network error — check your connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        // A bad key is a 401, or a 403 with an HTML body; a private profile is
        // a 403 WITH a JSON error, which the caller reads.
        if status == 401 || (status == 403 && json.isEmpty) {
            throw ServiceError(message: "Steam rejected that key. Check it at steamcommunity.com/dev/apikey.")
        }
        if (300..<400).contains(status) {
            throw ServiceError(message: "Steam tried to send this request somewhere else, so it wasn't followed.")
        }
        if status >= 500 {
            throw ServiceError(message: "Steam is unavailable right now (\(status)).")
        }
        return (status, json)
    }
}
