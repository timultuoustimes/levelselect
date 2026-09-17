import Foundation
import CryptoKit
import Security

/// Xbox achievements and games, read after a Microsoft sign-in.
///
/// Sign-in happens on Microsoft's own page (authorization code with PKCE, no
/// client secret — a public client registered by LevelSelect; see the vault
/// note "LevelSelect Xbox app registration"). The Microsoft token becomes an
/// Xbox user token, then an XSTS token for Xbox Live, and every call goes
/// device → Microsoft/Xbox. Nothing passes through our server. Tim, 09-14,
/// accepted this as an explicit, disclosed opt-in.
///
/// Xbox playtime isn't offered: Microsoft documents no reliable way for an app
/// to read it. Xbox 360-era games may come back without achievements.
@MainActor
enum XboxService {
    struct ServiceError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Title: Sendable, Equatable, Identifiable {
        let id: Int
        let name: String
        let devices: [String]
        let earned: Int
        let total: Int
        let lastPlayed: Date?
        let isGame: Bool

        /// IGDB's names for the machines, oldest first.
        ///
        /// `devices` is every machine the game runs on, not the ones this
        /// account played it on: a backward-compatible 360 game lists the Series
        /// consoles too, for someone who has only ever owned a 360.
        var platforms: [String] {
            let names: [(String, String)] = [
                ("Xbox360", "Xbox 360"),
                ("XboxOne", "Xbox One"),
                ("XboxSeries", "Xbox Series X|S"),
                ("PC", "PC (Microsoft Windows)"),
            ]
            return names.filter { devices.contains($0.0) }.map(\.1)
        }

        /// The console the game was made for — the best guess at the one it
        /// was played on, since Xbox doesn't say.
        var originalPlatform: String? { platforms.first }

        /// The machines to offer in the review, newest console first and PC
        /// last, so the default lands on the newest console you have.
        var platformChoices: [String] {
            let pc = platforms.filter { $0.hasPrefix("PC") }
            return platforms.filter { !$0.hasPrefix("PC") }.reversed() + pc
        }
    }

    struct XboxSession: Sendable, Equatable {
        let userHash: String
        let token: String
        let xuid: String
        let gamertag: String?
        let expiry: Date
    }

    static let categoryID = "xbox"
    static let categoryName = "Xbox Achievements"
    static let itemPrefix = "xbox-"

    /// From `LSXboxClientID` in Info.plist, set from `Secrets.xcconfig`. Not a
    /// secret — it names the app — but kept out of the public repo anyway.
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LSXboxClientID") as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static var isAvailable: Bool { clientID != nil }

    private static let redirect = "levelselect://xbox/callback"
    private static let scope = "XboxLive.signin offline_access"
    /// The consumer sign-in: the Xbox scope works there without being added
    /// to the app registration first, and only there.
    private static let authority = "https://login.microsoftonline.com/consumers/oauth2/v2.0"

    private static let http = CredentialRedirectGuard.session()
    private static var cached: XboxSession?

    // MARK: Signing in

    #if canImport(AuthenticationServices) && !os(watchOS)
    static func connect() async throws -> XboxCredentials.Value {
        guard let clientID else {
            throw ServiceError(message: "Xbox isn't set up in this build yet.")
        }
        let verifier = randomVerifier()
        let state = UUID().uuidString
        var components = URLComponents(string: "\(authority)/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        let callback = try await ItchAuth.run(url: components.url!, scheme: "levelselect")
        guard let code = authorizationCode(from: callback, expecting: state) else {
            throw ServiceError(message: "That sign-in didn't come back as expected. Try again.")
        }
        let tokens = try await token([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect,
            "code_verifier": verifier,
            "scope": scope,
        ])
        let session = try await xboxSession(microsoftToken: tokens.access)
        cached = session
        return XboxCredentials.Value(refreshToken: tokens.refresh, gamertag: session.gamertag, xuid: session.xuid)
    }
    #endif

    static func forget() { cached = nil }

    static func authorizationCode(from url: URL, expecting state: String) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              items.first(where: { $0.name == "error" }) == nil,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code
    }

    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private struct MicrosoftTokens { let access: String; let refresh: String }

    private static func token(_ form: [String: String]) async throws -> MicrosoftTokens {
        var request = URLRequest(url: URL(string: "\(authority)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = PlayStationService.formBody(form)
        let (data, response) = try await send(request)
        let body = json(data)
        guard let access = body["access_token"] as? String, !access.isEmpty,
              let refresh = body["refresh_token"] as? String, !refresh.isEmpty else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (body["error"] as? String) == "invalid_grant" {
                throw ServiceError(message: "Xbox needs you to sign in again.")
            }
            throw ServiceError(message: "Microsoft didn't sign in (\(status)).")
        }
        return MicrosoftTokens(access: access, refresh: refresh)
    }

    private static func xboxSession(microsoftToken: String) async throws -> XboxSession {
        let user = try await postJSON("https://user.auth.xboxlive.com/user/authenticate", [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "d=\(microsoftToken)",
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT",
        ])
        guard let userToken = user["Token"] as? String else {
            throw ServiceError(message: "Xbox didn't accept that Microsoft account.")
        }
        let xsts = try await postJSON("https://xsts.auth.xboxlive.com/xsts/authorize", [
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [userToken]],
            "RelyingParty": "http://xboxlive.com",
            "TokenType": "JWT",
        ])
        if let code = (xsts["XErr"] as? NSNumber)?.int64Value {
            throw ServiceError(message: xstsMessage(code))
        }
        guard let session = session(fromXSTS: xsts) else {
            throw ServiceError(message: "Xbox didn't return a profile for that account.")
        }
        return session
    }

    static func xstsMessage(_ code: Int64) -> String {
        switch code {
        case 2148916233: "That Microsoft account has no Xbox profile yet. Sign in on xbox.com once to make one."
        case 2148916238: "Xbox limits this for child accounts; a parent has to allow it."
        case 2148916235: "Xbox isn't available in this account's country."
        default: "Xbox refused the sign-in (\(code))."
        }
    }

    static func session(fromXSTS json: [String: Any]) -> XboxSession? {
        guard let token = json["Token"] as? String,
              let claims = ((json["DisplayClaims"] as? [String: Any])?["xui"] as? [[String: Any]])?.first,
              let hash = claims["uhs"] as? String,
              let xuid = claims["xid"] as? String, !xuid.isEmpty else { return nil }
        let expiry = ServiceDates.parse(json["NotAfter"] as? String) ?? Date.now.addingTimeInterval(3600)
        return XboxSession(userHash: hash, token: token, xuid: xuid,
                           gamertag: claims["gtg"] as? String, expiry: expiry)
    }

    private static func activeSession() async throws -> XboxSession {
        if let cached, cached.expiry > Date.now.addingTimeInterval(60) { return cached }
        guard let clientID, let credentials = XboxCredentials.current else {
            throw ServiceError(message: "Connect Xbox first, in Settings → Services.")
        }
        let tokens = try await token([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": scope,
        ])
        if tokens.refresh != credentials.refreshToken {
            XboxCredentials.save(.init(refreshToken: tokens.refresh,
                                       gamertag: credentials.gamertag, xuid: credentials.xuid))
        }
        let session = try await xboxSession(microsoftToken: tokens.access)
        cached = session
        return session
    }

    // MARK: Games

    /// Games this account has played, with achievement progress.
    static func titles() async throws -> [Title] {
        let session = try await activeSession()
        let json = try await get(
            "https://titlehub.xboxlive.com/users/xuid(\(session.xuid))/titles/titlehistory/decoration/achievement,image",
            session: session)
        return titles(from: json).filter(\.isGame)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func titles(from json: [String: Any]) -> [Title] {
        ((json["titles"] as? [[String: Any]]) ?? []).compactMap { title in
            guard let id = (title["titleId"] as? String).flatMap({ Int($0) })
                    ?? (title["titleId"] as? NSNumber)?.intValue,
                  let name = (title["name"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return nil }
            let achievement = (title["achievement"] as? [String: Any]) ?? [:]
            let history = (title["titleHistory"] as? [String: Any]) ?? [:]
            let type = (title["type"] as? String) ?? "Game"
            return Title(id: id, name: name,
                         devices: (title["devices"] as? [String]) ?? [],
                         earned: (achievement["currentAchievements"] as? NSNumber)?.intValue ?? 0,
                         total: (achievement["totalAchievements"] as? NSNumber)?.intValue ?? 0,
                         lastPlayed: ServiceDates.parse(history["lastTimePlayed"] as? String),
                         isGame: type.caseInsensitiveCompare("Game") == .orderedSame)
        }
    }

    /// `library` is the games a row can add a console to, by
    /// `TrackerMerge.matchKey` of their names; `existingNames` are skipped
    /// outright (the wishlist: nobody owns a game they're waiting for).
    static func libraryRows(from titles: [Title], existingNames: Set<String>,
                            library: [String: UUID] = [:]) -> [CSVImport.Row] {
        titles.enumerated().compactMap { index, title in
            let existing = library[TrackerMerge.matchKey(title.name)]
            guard existing != nil || !existingNames.contains(title.name.lowercased()) else { return nil }
            // One platform only: more than one would also mark every machine
            // in `devices` as owned. The original console until the review
            // finds one you have; you can pick more there.
            let platforms = title.originalPlatform.map { [$0] } ?? []
            return CSVImport.Row(name: title.name, platform: platforms.first, platforms: platforms,
                                 status: nil, rating: nil, notes: nil, hoursPlayed: nil,
                                 igdbID: nil, line: index + 1,
                                 skipReason: SteamService.looksLikeDemo(title.name) ? "Demo — left unticked" : nil,
                                 offersPlatformChoice: true,
                                 platformChoices: title.platformChoices,
                                 fallbackPlatform: title.originalPlatform,
                                 mayBeAnApp: existing == nil && title.total == 0,
                                 existingGameID: existing)
        }
    }

    // MARK: Achievements

    /// One call answers both halves: the game's list, and what this account
    /// has unlocked in it.
    static func achievements(titleID: Int, titleName: String) async throws -> (set: ImportedSet, progress: ServiceProgress) {
        let session = try await activeSession()
        var rows: [[String: Any]] = []
        var continuation: String?
        for _ in 0..<10 {
            var components = URLComponents(string: "https://achievements.xboxlive.com/users/xuid(\(session.xuid))/achievements")!
            var items = [URLQueryItem(name: "titleId", value: String(titleID)),
                         URLQueryItem(name: "maxItems", value: "1000")]
            if let continuation { items.append(URLQueryItem(name: "continuationToken", value: continuation)) }
            components.queryItems = items
            let json = try await get(components.url!.absoluteString, session: session)
            rows += (json["achievements"] as? [[String: Any]]) ?? []
            continuation = ((json["pagingInfo"] as? [String: Any])?["continuationToken"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 }
            if continuation == nil { break }
        }
        guard let set = importedSet(titleID: titleID, titleName: titleName, rows: rows) else {
            throw ServiceError(message: "Xbox lists no achievements for that game. Games from the Xbox 360 era may not show here.")
        }
        return (set, progress(rows: rows))
    }

    static func importedSet(titleID: Int, titleName: String, rows: [[String: Any]],
                            now: Date = .now) -> ImportedSet? {
        let items: [[String: Any]] = rows.compactMap { row in
            guard let id = (row["id"] as? String) ?? (row["id"] as? NSNumber)?.stringValue, !id.isEmpty else { return nil }
            let name = ((row["name"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            var item: [String: Any] = ["id": itemPrefix + id, "name": name.isEmpty ? "Achievement \(id)" : name]
            let description = (row["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (row["lockedDescription"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let description { item["description"] = description }
            var metadata: [String: Any] = ["xboxAchievementID": id]
            let gamerscore = ((row["rewards"] as? [[String: Any]]) ?? [])
                .first { ($0["type"] as? String) == "Gamerscore" }
                .flatMap { reward -> Int? in
                    (reward["value"] as? String).flatMap { Int($0) } ?? (reward["value"] as? NSNumber)?.intValue
                }
            if let gamerscore { metadata["points"] = gamerscore }
            if let icon = ((row["mediaAssets"] as? [[String: Any]]) ?? []).first?["url"] as? String {
                metadata["icon"] = icon
            }
            if (row["isSecret"] as? Bool) == true { metadata["hidden"] = true }
            item["metadata"] = metadata
            return item
        }
        guard !items.isEmpty else { return nil }
        let root: [String: Any] = [
            "schemaVersion": 1,
            "generatedAt": ISO8601DateFormatter().string(from: now),
            "generatedBy": "xbox",
            "sources": [["type": "xbox", "id": String(titleID)]],
            "categories": [[
                "id": categoryID,
                "name": categoryName,
                TrackerSchemaJSON.xboxTitleIDKey: titleID,
                "description": "Xbox achievements for \(titleName)",
                "type": "checklist",
                "items": items,
            ]],
            "runs": [],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return nil }
        return ImportedSet(title: titleName, count: items.count, schema: data)
    }

    static func progress(rows: [[String: Any]]) -> ServiceProgress {
        let unlocked = rows.compactMap { row -> RAUnlock? in
            guard (row["progressState"] as? String) == "Achieved",
                  let id = (row["id"] as? String) ?? (row["id"] as? NSNumber)?.stringValue else { return nil }
            let when = ServiceDates.parse((row["progression"] as? [String: Any])?["timeUnlocked"] as? String)
            return RAUnlock(itemID: itemPrefix + id, hardcore: false, earnedAt: when, points: 0)
        }
        return ServiceProgress(total: rows.count, unlocked: unlocked)
    }

    // MARK: Transport

    private static func postJSON(_ url: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = json(data)
        guard status == 200 || json["XErr"] != nil else {
            throw ServiceError(message: "Xbox didn't sign in (\(status)).")
        }
        return json
    }

    private static func get(_ url: String, session: XboxSession) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("XBL3.0 x=\(session.userHash);\(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("2", forHTTPHeaderField: "x-xbl-contract-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return json(data)
        case 401:
            cached = nil
            throw ServiceError(message: "Xbox needs you to sign in again.")
        case 403: throw ServiceError(message: "Xbox keeps this private. Check your Xbox privacy settings for game history and achievements.")
        case 404: throw ServiceError(message: "Xbox has nothing for that game.")
        case 300..<400: throw ServiceError(message: "Xbox tried to send this request somewhere else, so it wasn't followed.")
        default: throw ServiceError(message: "Xbox is unavailable right now (\(status)).")
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
