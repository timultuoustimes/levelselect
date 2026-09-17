import Foundation

/// PlayStation trophies and games, read with the player's own sign-in.
///
/// **There is no public PlayStation API.** Every third-party trophy app signs
/// in the way Sony's own PlayStation App does: the player's NPSSO (a sign-in
/// cookie from playstation.com) is traded for an access code, then for tokens,
/// using the PlayStation App's public client. Tim, 09-14, accepted this as an
/// explicit, disclosed opt-in. Every call goes device → Sony; nothing passes
/// through our server, and the NPSSO itself is never stored.
///
/// Endpoints and parameters follow psn-api (achievements-app) and the
/// community PlayStation Trophies documentation — verified against their
/// source on 2026-09-16, not against a live account.
@MainActor
enum PlayStationService {
    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Tokens: Sendable, Equatable {
        let access: String
        let accessExpiry: Date
        let refresh: String?
        let refreshExpiry: Date?
    }

    struct TrophyTitle: Sendable, Equatable, Identifiable {
        /// The NP communication id, `NPWR12345_00`.
        let id: String
        /// `trophy` for PS4, PS3 and Vita; `trophy2` for PS5.
        let service: String
        let name: String
        let platform: String
        let defined: Int
        let earned: Int
    }

    struct PlayedGame: Sendable, Equatable {
        let titleID: String
        let name: String
        let category: String
        let minutesPlayed: Int
        let lastPlayed: Date?

        /// IGDB's name for the machine, so a matched game's dates line up.
        var platform: String? {
            switch category {
            case "ps5_native_game": "PlayStation 5"
            case "ps4_game": "PlayStation 4"
            default: nil
            }
        }
    }

    static let categoryID = "playstation"
    static let categoryName = "PlayStation Trophies"
    static let itemPrefix = "psn-"

    static let signInPage = URL(string: "https://www.playstation.com/")!
    static let npssoPage = URL(string: "https://ca.account.sony.com/api/v1/ssocookie")!

    private static let authBase = "https://ca.account.sony.com/api/authz/v3/oauth"
    private static let apiBase = "https://m.np.playstation.com/api"
    // The PlayStation App's public client — the one psn-api and every other
    // PSN library use. It identifies the app kind, not LevelSelect or anyone.
    private static let clientID = "09515159-7237-4370-9b40-3806e67c0891"
    private static let clientAuthorization =
        "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="
    private static let redirect = "com.scee.psxandroid.scecompcall://redirect"
    private static let scope = "psn:mobile.v2.core psn:clientapp"

    /// Redirects are refused off-host, which is also how the authorize step
    /// works: its answer IS the redirect, read rather than followed.
    private static let http = CredentialRedirectGuard.session()
    private static var cache: Tokens?

    // MARK: Connecting

    /// The pasted NPSSO — the bare value, or the whole `{"npsso":"…"}` the page shows.
    static func npssoValue(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let value = object["npsso"] as? String {
            return value.isEmpty ? nil : value
        }
        let bare = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        guard bare.count >= 40, bare.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return bare
    }

    static func connect(npsso pasted: String) async throws -> PlayStationCredentials.Value {
        guard let npsso = npssoValue(from: pasted) else {
            throw ServiceError(message: "That doesn't look like an NPSSO. Copy the long value after \"npsso\" on Sony's page.")
        }
        let code = try await accessCode(npsso: npsso)
        let tokens = try await exchange([
            "code": code,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "token_format": "jwt",
        ])
        guard let refresh = tokens.refresh, !refresh.isEmpty else {
            throw ServiceError(message: "PlayStation signed in but didn't return a lasting sign-in. Try a fresh NPSSO.")
        }
        cache = tokens
        // A real read, so a sign-in that can't see trophies says so now.
        let summary = try await get("trophy/v1/users/me/trophySummary", token: tokens.access)
        return PlayStationCredentials.Value(refreshToken: refresh, refreshExpiry: tokens.refreshExpiry,
                                            accountID: summary["accountId"] as? String)
    }

    static func forget() { cache = nil }

    private static func accessCode(npsso: String) async throws -> String {
        var components = URLComponents(string: "\(authBase)/authorize")!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
        ]
        var request = URLRequest(url: components.url!)
        request.httpShouldHandleCookies = false
        request.setValue("npsso=\(npsso)", forHTTPHeaderField: "Cookie")
        let (_, response) = try await send(request)
        let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location")
        guard let code = code(fromLocation: location) else {
            throw ServiceError(message: "Sony didn't accept that NPSSO. Sign in on playstation.com again and copy a fresh one.")
        }
        return code
    }

    /// `com.scee.psxandroid.scecompcall://redirect/?code=v3.XXXX&cid=…`
    static func code(fromLocation location: String?) -> String? {
        guard let location, let mark = location.firstIndex(of: "?") else { return nil }
        var components = URLComponents()
        components.percentEncodedQuery = String(location[location.index(after: mark)...])
        return components.queryItems?.first { $0.name == "code" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func exchange(_ form: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "\(authBase)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(clientAuthorization, forHTTPHeaderField: "Authorization")
        request.httpBody = formBody(form)
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let tokens = tokens(from: json(data), now: .now) else {
            if status == 400 || status == 401 {
                throw ServiceError(message: "PlayStation needs you to connect again — the sign-in has expired.")
            }
            throw ServiceError(message: "PlayStation didn't sign in (\(status)).")
        }
        return tokens
    }

    static func tokens(from json: [String: Any], now: Date) -> Tokens? {
        guard let access = json["access_token"] as? String, !access.isEmpty else { return nil }
        let expires = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let refreshExpires = (json["refresh_token_expires_in"] as? NSNumber)?.doubleValue
        return Tokens(access: access,
                      accessExpiry: now.addingTimeInterval(max(0, expires - 60)),
                      refresh: json["refresh_token"] as? String,
                      refreshExpiry: refreshExpires.map { now.addingTimeInterval($0) })
    }

    static func formBody(_ form: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = form.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func accessToken() async throws -> String {
        if let cache, cache.accessExpiry > .now { return cache.access }
        guard let credentials = PlayStationCredentials.current else {
            throw ServiceError(message: "Connect PlayStation first, in Settings → Services.")
        }
        let tokens = try await exchange([
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token",
            "token_format": "jwt",
            "scope": scope,
        ])
        cache = tokens
        if let refresh = tokens.refresh, !refresh.isEmpty, refresh != credentials.refreshToken {
            PlayStationCredentials.save(.init(refreshToken: refresh,
                                              refreshExpiry: tokens.refreshExpiry ?? credentials.refreshExpiry,
                                              accountID: credentials.accountID))
        }
        return tokens.access
    }

    // MARK: Trophies

    /// Every game this account has a trophy list for, by name.
    static func trophyTitles() async throws -> [TrophyTitle] {
        var titles: [TrophyTitle] = []
        var offset = 0
        for _ in 0..<20 {
            let page = try await get("trophy/v1/users/me/trophyTitles",
                                     ["limit": "800", "offset": String(offset)])
            titles += trophyTitles(from: page)
            guard let next = (page["nextOffset"] as? NSNumber)?.intValue, next > offset else { break }
            offset = next
        }
        return titles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func trophyTitles(from json: [String: Any]) -> [TrophyTitle] {
        ((json["trophyTitles"] as? [[String: Any]]) ?? []).compactMap { title in
            guard let id = title["npCommunicationId"] as? String, !id.isEmpty,
                  let name = (title["trophyTitleName"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return nil }
            func total(_ key: String) -> Int {
                let counts = (title[key] as? [String: Any]) ?? [:]
                return ["bronze", "silver", "gold", "platinum"]
                    .reduce(0) { $0 + ((counts[$1] as? NSNumber)?.intValue ?? 0) }
            }
            return TrophyTitle(id: id,
                               service: (title["npServiceName"] as? String) ?? "trophy2",
                               name: name,
                               platform: (title["trophyTitlePlatform"] as? String) ?? "",
                               defined: total("definedTrophies"),
                               earned: total("earnedTrophies"))
        }
    }

    /// A game's full trophy list, as a tracker category.
    static func trophyList(for title: TrophyTitle) async throws -> ImportedSet {
        let json = try await get("trophy/v1/npCommunicationIds/\(title.id)/trophyGroups/all/trophies",
                                 ["npServiceName": title.service, "limit": "1000"])
        guard let set = importedSet(title: title, from: json) else {
            throw ServiceError(message: "PlayStation lists no trophies for that game.")
        }
        return set
    }

    /// Shaped like the Steam and RetroAchievements imports: one category,
    /// stamped with what a later sync looks the game up by.
    static func importedSet(title: TrophyTitle, from json: [String: Any], now: Date = .now) -> ImportedSet? {
        let items: [[String: Any]] = ((json["trophies"] as? [[String: Any]]) ?? []).compactMap { trophy in
            guard let number = (trophy["trophyId"] as? NSNumber)?.intValue else { return nil }
            let name = ((trophy["trophyName"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            var item: [String: Any] = [
                "id": itemPrefix + String(number),
                "name": name.isEmpty ? "Trophy \(number)" : name,
            ]
            if let detail = trophy["trophyDetail"] as? String, !detail.isEmpty { item["description"] = detail }
            var metadata: [String: Any] = ["psnTrophyID": number]
            if let type = trophy["trophyType"] as? String { metadata["trophyType"] = type }
            if let icon = trophy["trophyIconUrl"] as? String { metadata["icon"] = icon }
            if let group = trophy["trophyGroupId"] as? String { metadata["trophyGroup"] = group }
            if (trophy["trophyHidden"] as? Bool) == true { metadata["hidden"] = true }
            item["metadata"] = metadata
            return item
        }
        guard !items.isEmpty else { return nil }
        let root: [String: Any] = [
            "schemaVersion": 1,
            "generatedAt": ISO8601DateFormatter().string(from: now),
            "generatedBy": "playstation",
            "sources": [["type": "playstation", "id": title.id]],
            "categories": [[
                "id": categoryID,
                "name": categoryName,
                TrackerSchemaJSON.psnTitleIDKey: title.id,
                TrackerSchemaJSON.psnServiceKey: title.service,
                "description": "PlayStation trophies for \(title.name)",
                "type": "checklist",
                "items": items,
            ]],
            "runs": [],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return ImportedSet(title: title.name, count: items.count, schema: data)
    }

    /// What this account has earned in one game, with the dates Sony records.
    static func progress(titleID: String, service: String) async throws -> ServiceProgress {
        let json = try await get("trophy/v1/users/me/npCommunicationIds/\(titleID)/trophyGroups/all/trophies",
                                 ["npServiceName": service, "limit": "1000"])
        return progress(from: json)
    }

    static func progress(from json: [String: Any]) -> ServiceProgress {
        let rows = (json["trophies"] as? [[String: Any]]) ?? []
        let unlocked = rows.compactMap { trophy -> RAUnlock? in
            guard (trophy["earned"] as? Bool) == true,
                  let number = (trophy["trophyId"] as? NSNumber)?.intValue else { return nil }
            return RAUnlock(itemID: itemPrefix + String(number), hardcore: false,
                            earnedAt: ServiceDates.parse(trophy["earnedDateTime"] as? String),
                            points: 0)
        }
        return ServiceProgress(total: rows.count, unlocked: unlocked)
    }

    // MARK: Games and playtime

    /// PS4 and PS5 games this account has played, with Sony's playtime.
    static func playedGames() async throws -> [PlayedGame] {
        var games: [PlayedGame] = []
        var offset = 0
        for _ in 0..<20 {
            let page = try await get("gamelist/v2/users/me/titles", [
                "categories": "ps4_game,ps5_native_game",
                "limit": "200",
                "offset": String(offset),
            ])
            games += playedGames(from: page)
            guard let next = (page["nextOffset"] as? NSNumber)?.intValue, next > offset else { break }
            offset = next
        }
        return games
    }

    static func playedGames(from json: [String: Any]) -> [PlayedGame] {
        ((json["titles"] as? [[String: Any]]) ?? []).compactMap { title in
            guard let id = title["titleId"] as? String,
                  let name = (title["name"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return nil }
            return PlayedGame(titleID: id, name: name,
                              category: (title["category"] as? String) ?? "",
                              minutesPlayed: minutes(fromISODuration: title["playDuration"] as? String),
                              lastPlayed: ServiceDates.parse(title["lastPlayedDateTime"] as? String))
        }
    }

    /// `PT41H4M39S` → 2,465 minutes. Days count; months don't appear.
    static func minutes(fromISODuration text: String?) -> Int {
        guard let text, text.hasPrefix("P") else { return 0 }
        var total = 0.0
        var number = ""
        var inTime = false
        for character in text.dropFirst() {
            if character == "T" { inTime = true; continue }
            if character.isNumber || character == "." { number.append(character); continue }
            let value = Double(number) ?? 0
            number = ""
            switch character {
            case "D": total += value * 1440
            case "H": total += value * 60
            case "M": total += inTime ? value : 0
            case "S": total += value / 60
            default: break
            }
        }
        return Int(total.rounded())
    }

    /// The library as import rows: one row per game, however many machines it
    /// was played on, minus `existingNames` (the wishlist). A game in
    /// `library` comes as a row that adds its machines to that game. Hours stay
    /// off the rows — they go to the PlayStation playthrough
    /// (`applyPlayStationPlaytime`).
    static func libraryRows(from games: [PlayedGame], existingNames: Set<String>,
                            library: [String: UUID] = [:]) -> [CSVImport.Row] {
        var order: [String] = []
        var byKey: [String: (name: String, platforms: [String])] = [:]
        for game in games {
            let key = ServiceNames.fold(game.name)
            guard !key.isEmpty else { continue }
            guard library[TrackerMerge.matchKey(game.name)] != nil
                    || !existingNames.contains(game.name.lowercased()) else { continue }
            var entry = byKey[key] ?? (game.name, [])
            if let platform = game.platform, !entry.platforms.contains(platform) {
                entry.platforms.append(platform)
            }
            if byKey[key] == nil { order.append(key) }
            byKey[key] = entry
        }
        return order.enumerated().compactMap { index, key in
            guard let entry = byKey[key] else { return nil }
            let platforms = entry.platforms.sorted { $0 > $1 }   // PlayStation 5 first
            return CSVImport.Row(name: entry.name, platform: platforms.first, platforms: platforms,
                                 status: nil, rating: nil, notes: nil, hoursPlayed: nil,
                                 igdbID: nil, line: index + 1,
                                 skipReason: SteamService.looksLikeDemo(entry.name) ? "Demo — left unticked" : nil,
                                 // PlayStation says PS4 or PS5 but not VR; the
                                 // match offers the headset when you have one.
                                 offersPlatformChoice: true,
                                 platformChoices: platforms,
                                 platformsKnown: true,
                                 existingGameID: library[TrackerMerge.matchKey(entry.name)])
        }
    }

    /// Minutes per library game: every PS4 and PS5 entry of the same game adds
    /// up, since each is its own time played.
    static func playtimeMatches(games: [PlayedGame],
                                library: [(id: UUID, name: String)]) -> [UUID: Int] {
        var minutesByKey: [String: Int] = [:]
        for game in games where game.minutesPlayed > 0 {
            minutesByKey[ServiceNames.fold(game.name), default: 0] += game.minutesPlayed
        }
        var out: [UUID: Int] = [:]
        for game in library {
            if let minutes = minutesByKey[ServiceNames.fold(game.name)] { out[game.id] = minutes }
        }
        return out
    }

    // MARK: Transport

    private static func get(_ path: String, _ query: [String: String] = [:]) async throws -> [String: Any] {
        try await get(path, query, token: try await accessToken())
    }

    private static func get(_ path: String, _ query: [String: String] = [:],
                            token: String) async throws -> [String: Any] {
        var components = URLComponents(string: "\(apiBase)/\(path)")!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return json(data)
        case 401:
            cache = nil
            throw ServiceError(message: "PlayStation needs you to connect again.")
        case 404: throw ServiceError(message: "PlayStation has nothing for that game.")
        case 300..<400: throw ServiceError(message: "PlayStation tried to send this request somewhere else, so it wasn't followed.")
        default: throw ServiceError(message: "PlayStation is unavailable right now (\(status)).")
        }
    }

    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = 30
        do {
            return try await http.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ServiceError(message: "Network error — check your connection and try again.")
        }
    }

    private static func json(_ data: Data) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }
}
