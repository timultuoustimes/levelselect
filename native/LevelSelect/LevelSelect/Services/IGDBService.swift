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
    let platforms: [String]
    let genres: [String]
    let themes: [String]
    let gameModes: [String]
    let playerPerspectives: [String]
    let developers: [String]
    let publishers: [String]

    var coverURLString: String? {
        coverImageID.map { "https://images.igdb.com/igdb/image/upload/t_cover_big/\($0).jpg" }
    }

    var releaseDate: Date? {
        releaseYear.flatMap { DateComponents(calendar: .current, year: $0, month: 1, day: 1).date }
    }
}

enum IGDBService {
    private static let proxyURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/igdb-proxy")!

    private static let fields = """
        fields name, slug, summary, cover.image_id, franchises.name, collection.name, \
        first_release_date, platforms.name, genres.name, themes.name, game_modes.name, \
        player_perspectives.name, involved_companies.developer, involved_companies.publisher, \
        involved_companies.company.name;
        """

    /// Name search — main games only (matches the web app's behavior).
    static func search(name: String) async throws -> [IGDBGame] {
        let clean = name.replacingOccurrences(of: "\"", with: "")
        guard clean.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let query = "search \"\(clean)\"; \(fields) where game_type = (0) & version_parent = null; limit 10;"
        return try await perform(query)
    }

    /// Direct ID lookup — deliberately UNFILTERED so specific editions,
    /// remasters, and DLC ids resolve (the reason to search by id at all).
    static func lookup(id: Int) async throws -> IGDBGame? {
        try await perform("where id = \(id); \(fields) limit 1;").first
    }

    private static func perform(_ query: String) async throws -> [IGDBGame] {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["endpoint": "games", "query": query])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([RawGame].self, from: data).map { $0.toGame() }
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
                platforms: (platforms ?? []).map(\.name),
                genres: (genres ?? []).map(\.name),
                themes: (themes ?? []).map(\.name),
                gameModes: (game_modes ?? []).map(\.name),
                playerPerspectives: (player_perspectives ?? []).map(\.name),
                developers: developers,
                publishers: publishers
            )
        }
    }
}
