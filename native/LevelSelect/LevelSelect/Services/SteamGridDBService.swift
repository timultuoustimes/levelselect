import Foundation

/// Artwork from SteamGridDB, for the roles IGDB can't reliably fill.
///
/// IGDB does publish logos — an earlier build wrongly said otherwise — but its
/// coverage is partial, and the gap is exactly the smaller and newer games a
/// tracker gets used for. Teenage Mutant Ninja Turtles: Splintered Fate is a
/// 2024 release with four logos, six heroes and forty-odd grids on
/// SteamGridDB, and nothing at all on IGDB.
///
/// So this is about COVERAGE, not capability. IGDB stays first for every role
/// — it's the app's source of record for what a game IS — and SteamGridDB
/// fills in behind it.
///
/// No account, no key, nothing to set up: the proxy uses the app's own key.
/// See `steamgriddb-proxy/index.ts` for why that's the right call here and
/// wrong for RetroAchievements.
///
/// `@MainActor` for the same reason `BackdropArt` is: the only mutable state
/// here is a lookup cache read and written from SwiftUI views, and pinning it
/// to one actor is cheaper than an actor hop on every read.
@MainActor
enum SteamGridDBService {

    /// Which SteamGridDB asset kind fills which of the app's artwork roles.
    enum Kind: String {
        case grids, heroes, logos, icons

        init?(role: ArtworkRole) {
            switch role {
            case .cover:    self = .grids
            case .backdrop: self = .heroes
            case .logo:     self = .logos
            // The gallery role is a scrapbook of the user's own images; it
            // isn't a slot a stranger's artwork should fill.
            case .gallery:  return nil
            }
        }
    }

    private static let proxyURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/steamgriddb-proxy")!

    /// Resolved SteamGridDB game IDs, keyed by the name we searched.
    ///
    /// One key serves every install, so the cheapest request is the one never
    /// made. The picker resolves a game once per launch; the URL the user
    /// actually chooses is then stored on the `Game` and never looked up again.
    private static var idCache: [String: Int?] = [:]

    // MARK: Lookup

    /// SteamGridDB's ID for a game, by name.
    ///
    /// Name matching is all that's available: SteamGridDB keys off Steam
    /// appids and its own IDs, and this app has neither. `autocomplete`
    /// returns best-match-first, so the first hit is taken — a wrong guess
    /// here costs a gallery of somebody else's artwork, which the user simply
    /// doesn't pick, rather than anything written to their library.
    static func gameID(named name: String) async -> Int? {
        let term = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        if let cached = idCache[term] { return cached }

        let rows = await post(["action": "search", "term": term])
        let id = (rows?["data"] as? [[String: Any]])?.first?["id"] as? Int
        idCache[term] = id
        return id
    }

    /// Image URLs for one role, best-scored first (SteamGridDB's own order).
    static func artwork(for game: Game, role: ArtworkRole) async -> [String] {
        guard let kind = Kind(role: role),
              let id = await gameID(named: game.name)
        else { return [] }

        let rows = await post(["action": "assets", "kind": kind.rawValue, "gameID": id])
        guard let data = rows?["data"] as? [[String: Any]] else { return [] }
        return data.compactMap { $0["url"] as? String }
    }

    // MARK: Transport

    private static func post(_ body: [String: Any]) async -> [String: Any]? {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
        request.timeoutInterval = 20
        guard let encoded = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = encoded

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }
}
