import Foundation

/// "Find one" — the `map-finder` edge function, which the web app used and
/// which has stayed deployed. It searches the web for map images by game
/// name (or reads them off a page you give it) and answers with candidates;
/// nothing is kept until the person picks one, and the site it came from is
/// kept with the map as provenance.
///
/// Same guard as every Genie call: the app key, the install quota, and a
/// plain sentence when it cannot help. The bytes are fetched here, by the
/// device, straight from the source — the function never proxies an image.
enum MapFinderService {
    private static let proxyURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/map-finder")!

    struct Suggestion: Identifiable, Hashable, Decodable {
        let url: String
        let name: String
        let type: String?
        var id: String { url }

        var kind: MapKind {
            switch (type ?? "").lowercased() {
            case "world": .world
            case "area", "level", "region", "dungeon": .area
            default: .other
            }
        }

        /// The host, for the "from …" line. `www.` is noise.
        var source: String {
            guard let host = URL(string: url)?.host() else { return "the web" }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    private struct Payload: Decodable { let suggestions: [Suggestion] }
    private struct Failure: Decodable { let error: String }

    enum FinderError: LocalizedError {
        case offline, unavailable(String)
        var errorDescription: String? {
            switch self {
            case .offline:               "Couldn't reach the map finder."
            case .unavailable(let why):  why
            }
        }
    }

    static func find(gameName: String, pageURL: String? = nil) async throws -> [Suggestion] {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        EdgeFunctions.authorize(&request)
        var body: [String: String] = ["gameName": gameName]
        if let pageURL, !pageURL.isEmpty { body["pageUrl"] = pageURL }
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FinderError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw FinderError.offline }
        guard http.statusCode == 200 else {
            let why = (try? JSONDecoder().decode(Failure.self, from: data))?.error
                ?? "Map search isn't available right now."
            throw FinderError.unavailable(why)
        }
        return try JSONDecoder().decode(Payload.self, from: data).suggestions
    }

    /// A wiki CDN answers a browser and refuses a bare `URLSession` agent —
    /// Fandom's does. This is what a browser would send for the same file,
    /// no more: the site's own page as the referer, a Safari agent.
    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let host = url.host() { request.setValue("https://\(host)/", forHTTPHeaderField: "Referer") }
        return request
    }

    /// The image itself, fetched by this device from where it lives.
    static func download(_ suggestion: Suggestion) async throws -> Data {
        guard let url = URL(string: suggestion.url) else { throw FinderError.offline }
        let (data, response) = try await URLSession.shared.data(for: request(for: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw FinderError.unavailable(code == 404
                ? "That image isn't where the finder thought it was."
                : "That site wouldn't hand the image over (\(code)).")
        }
        return data
    }
}
