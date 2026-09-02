import Foundation
#if canImport(AuthenticationServices) && !os(watchOS)
import AuthenticationServices
#endif

/// itch.io, connected rather than listed.
///
/// itch is a storefront, not a machine, and the roadmap item was never about
/// putting its name in the platform picker — it is about the games. itch is
/// also the case an IGDB-first app handles worst: a great many of its games
/// have no IGDB entry at all, so they can only arrive by being asked for.
///
/// **Implicit flow, per itch's own docs.** `response_type=token`, the token
/// comes back in the URL *fragment*, and there is no client secret and no
/// refresh token — which is why nothing here needs a server. A token that
/// stops working comes back as a 401 and the answer is to connect again.
///
/// **The fragment is the whole problem.** A fragment never leaves the browser,
/// so itch's allowed redirect targets (https, loopback, or copy-paste) cannot
/// hand it to a native app directly. levelselect.app/itch/callback is a page
/// that reads its own hash and bounces to `levelselect://itch/callback`, which
/// `ASWebAuthenticationSession` catches. The token is therefore never sent to
/// our server — the page is static and the redirect happens in the browser.
@MainActor
enum ItchService {
    /// From `LSItchClientID` in Info.plist, like the edge-function app key.
    /// A client id is public by design in the implicit flow — it identifies
    /// the app, it does not authorise anything on its own.
    static var clientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LSItchClientID") as? String,
              !value.isEmpty else { return nil }
        return value
    }

    static var isAvailable: Bool { clientID != nil }

    private static let callback = "https://levelselect.app/itch/callback"
    private static let scheme = "levelselect"

    /// Only what is needed to read a library, and nothing else.
    ///
    /// `profile:owned` grants `profile/owned-keys` — games bought or claimed.
    /// `profile:collections` is the other half, and it turned out to be the
    /// half that matters: a game added to a collection has no download key,
    /// so a library that is mostly collections comes back from owned-keys
    /// completely empty. Tim's did.
    ///
    /// `profile:me` is only so a connected account can say whose it is. Still
    /// not plain `profile`, which would also take the games someone develops
    /// — scopes are the one part of an OAuth prompt a user actually reads.
    private static let scopes = "profile:me profile:owned profile:collections"

    static func authorizationURL(state: String) -> URL? {
        guard let clientID else { return nil }
        var components = URLComponents(string: "https://itch.io/user/oauth")
        components?.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "scope", value: scopes),
            .init(name: "redirect_uri", value: callback),
            .init(name: "response_type", value: "token"),
            .init(name: "state", value: state),
        ]
        return components?.url
    }

    /// The token out of a callback URL, verifying `state`.
    ///
    /// itch returns credentials in the fragment, and the bounce page forwards
    /// the hash verbatim — so this reads the fragment, not the query. `state`
    /// is checked because an implicit-flow callback is a URL anything on the
    /// device could open; a mismatch means this response was not asked for.
    static func token(from url: URL, expecting state: String) -> String? {
        guard let fragment = url.fragment else { return nil }
        var found: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            found[String(parts[0])] = String(parts[1]).removingPercentEncoding
        }
        guard found["state"] == state else { return nil }
        return found["access_token"]
    }

    // MARK: The library

    struct OwnedGame: Sendable, Identifiable {
        var id: Int
        var name: String
        var coverURL: String?
        var url: String?
    }

    enum ItchError: Error, LocalizedError {
        case notConnected
        case unauthorized
        case transport

        var errorDescription: String? {
            switch self {
            case .notConnected: "Connect your itch.io account first."
            case .unauthorized: "itch.io rejected the connection. Connect again."
            case .transport:    "Couldn't reach itch.io."
            }
        }
    }

    /// Every game the account has purchased or claimed.
    ///
    /// Paged: `owned-keys` returns a page at a time, and a library of free
    /// jam games is routinely hundreds long — stopping at the first page
    /// would import a slice and call it the library.
    static func ownedGames() async throws -> [OwnedGame] {
        guard let token = ItchCredentials.current?.token else { throw ItchError.notConnected }
        var games: [OwnedGame] = []
        var page = 1
        // A ceiling rather than a while(true): a paging bug on either side
        // should stop, not spin against someone's network for as long as the
        // app is open.
        while page <= 40 {
            let rows = try await ownedKeys(token: token, page: page)
            guard !rows.isEmpty else { break }
            games += rows
            page += 1
        }
        return games
    }

    /// The games in the user's collections.
    ///
    /// Not in the public API reference — `profile:collections` appears in the
    /// OAuth scope list with no documented response — so these paths are the
    /// ones itch's own client uses. Failures are treated as "no collections"
    /// rather than as errors, so an endpoint that moves degrades to owned-keys
    /// alone instead of breaking the import.
    static func collectionGames() async throws -> [OwnedGame] {
        guard let token = ItchCredentials.current?.token else { throw ItchError.notConnected }
        guard let url = URL(string: "https://api.itch.io/profile/collections") else { return [] }
        guard let json = await get(url, token: token),
              let collections = json["collections"] as? [[String: Any]] else { return [] }

        var games: [OwnedGame] = []
        var seen = Set<Int>()
        for collection in collections {
            guard let id = collection["id"] as? Int else { continue }
            var page = 1
            while page <= 20 {
                guard let url = URL(string:
                    "https://api.itch.io/collections/\(id)/collection-games?page=\(page)"),
                      let json = await get(url, token: token),
                      let rows = json["collection_games"] as? [[String: Any]],
                      !rows.isEmpty
                else { break }
                for row in rows {
                    guard let game = row["game"] as? [String: Any],
                          let gameID = game["id"] as? Int,
                          let title = game["title"] as? String,
                          seen.insert(gameID).inserted else { continue }
                    games.append(OwnedGame(id: gameID, name: title,
                                           coverURL: game["cover_url"] as? String,
                                           url: game["url"] as? String))
                }
                page += 1
            }
        }
        return games
    }

    /// A GET that returns nil rather than throwing, for the endpoints that
    /// are not in the public reference and may not answer.
    private static func get(_ url: URL, token: String) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func ownedKeys(token: String, page: Int) async throws -> [OwnedGame] {
        guard let url = URL(string: "https://api.itch.io/profile/owned-keys?page=\(page)") else {
            throw ItchError.transport
        }
        var request = URLRequest(url: url)
        // Device → itch.io directly. The bearer token never touches our own
        // server, whose invocation logs capture headers.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ItchError.transport
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw ItchError.unauthorized
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keys = json["owned_keys"] as? [[String: Any]] else { return [] }

        return keys.compactMap { key in
            // The download key wraps the game; the game is what we want.
            guard let game = key["game"] as? [String: Any],
                  let id = game["id"] as? Int,
                  let title = game["title"] as? String else { return nil }
            return OwnedGame(id: id, name: title,
                             coverURL: game["cover_url"] as? String,
                             url: game["url"] as? String)
        }
    }
}
