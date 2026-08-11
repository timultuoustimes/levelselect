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
    let gameType: Int?
    let platforms: [String]
    let genres: [String]
    let themes: [String]
    let gameModes: [String]
    let playerPerspectives: [String]
    let developers: [String]
    let publishers: [String]

    /// Human label for non-main game types (nil for main games).
    var typeLabel: String? {
        switch gameType {
        case 1: "DLC"
        case 2: "Expansion"
        case 3: "Bundle"
        case 4: "Standalone"
        case 5: "Mod"
        case 6: "Episode"
        case 7: "Season"
        case 8: "Remake"
        case 9: "Remaster"
        case 10: "Expanded"
        case 11: "Port"
        case 12: "Fork"
        case 13: "Pack"
        case 14: "Update"
        default: nil
        }
    }

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
        fields name, slug, summary, game_type, cover.image_id, franchises.name, collection.name, \
        first_release_date, platforms.name, genres.name, themes.name, game_modes.name, \
        player_perspectives.name, involved_companies.developer, involved_companies.publisher, \
        involved_companies.company.name;
        """

    /// Name search — UNFILTERED (the web app's main-games-only filter hid
    /// bundles/editions like "Ultimate Bundle"). Main games sort first;
    /// bundles/DLC/remasters follow, badged via `typeLabel`.
    static func search(name: String) async throws -> [IGDBGame] {
        let clean = name.replacingOccurrences(of: "\"", with: "")
        guard clean.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        let query = "search \"\(clean)\"; \(fields) limit 15;"
        let results = try await perform(query)
        // Stable partition: main games first, IGDB relevance preserved within groups.
        return results.filter { ($0.gameType ?? 0) == 0 } + results.filter { ($0.gameType ?? 0) != 0 }
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
        let game_type: Int?
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
                gameType: game_type,
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
