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
    /// `profile:me` is only so a connected account can say whose it is.
    ///
    /// **`profile:collections` was requested and has been withdrawn.** It
    /// grants listing collections and nothing more: a collection object
    /// carries `created_at, games_count, id, title, updated_at` — a COUNT,
    /// not the games — and every path to the contents answers 403 to a token
    /// holding that scope. Measured against Tim's account rather than
    /// guessed. Asking someone for a permission the app cannot act on is
    /// worse than not having it, so the prompt no longer mentions
    /// collections.
    private static let scopes = "profile:me profile:owned"

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
    static func ownedGames(probe: inout Probe) async throws -> [OwnedGame] {
        guard let token = ItchCredentials.current?.token else { throw ItchError.notConnected }
        // One probing call first, so an empty result can name its cause.
        if let url = URL(string: "https://api.itch.io/profile/owned-keys?page=1") {
            probe = await get(url, token: token).probe
        }
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

    /// What one call actually did. A silent `nil` was the wrong shape here:
    /// a wrong path, a missing scope and an empty account all produced the
    /// same nothing, so the screen could not say which — and neither could I.
    struct Probe: Sendable {
        var status: Int = 0
        /// Top-level keys the response actually had. The fastest way to see
        /// that a path answered but under a different name than expected.
        var keys: [String] = []
        var count: Int = 0
        var errors: [String] = []
        /// What each candidate path answered, when more than one was tried.
        var attempts: [String] = []

        var line: String {
            if status == 0 { return "unreachable" }
            if status != 200 { return "HTTP \(status)" }
            if !errors.isEmpty { return "error: \(errors.joined(separator: "; "))" }
            let base = "\(count) from [\(keys.joined(separator: ", "))]"
            return attempts.isEmpty ? base : base + " · " + attempts.joined(separator: " · ")
        }
    }

    private static func get(_ url: URL, token: String) async -> (json: [String: Any]?, probe: Probe) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return (nil, Probe())
        }
        var probe = Probe(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        probe.keys = json.map { Array($0.keys).sorted() } ?? []
        // itch answers 200 with an `errors` array rather than an HTTP code,
        // so the status alone says nothing — the text is the only signal.
        if let errors = json?["errors"] as? [String] { probe.errors = errors }
        return (json, probe)
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
