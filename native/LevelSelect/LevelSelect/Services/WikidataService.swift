import Foundation

/// The people who made a game, and a second opinion about its facts.
///
/// **This exists because IGDB structurally cannot answer it.** Asked for every
/// field it populates on Death Stranding, IGDB has no person or credit field
/// at all — every credit is company-level through `involved_companies`.
/// Director, composer, designer and writer are all ordinary Wikidata
/// properties, so a Miyamoto or a Kojima facet has exactly one free source.
///
/// **IGDB stays the identity source.** `igdbSlug` is what the library points
/// at and what Fix Match re-points; this is enrichment hung off that, so if
/// Wikidata ever goes away a field breaks and the library does not.
///
/// **The bridge is the slug, and that was checked rather than assumed.**
/// Wikidata's P5794 — "Internet Game Database game ID" — stores the SLUG
/// ("hollow-knight", "hades--1"), not the numeric id the spec had guessed.
/// Querying by name is how the wrong game's logo got attached to a manually
/// added title once already, so it is never done here.
///
/// **Nothing is overwritten, ever.** Where Wikidata and IGDB disagree about a
/// release date, that is a discrepancy for the reader to resolve — the same
/// principle as the local cover override: the app does not quietly substitute
/// one source for another.
enum WikidataService {
    private static let proxyURL = URL(
        string: "https://sextftevxqrtodlmnyve.supabase.co/functions/v1/wikidata-proxy")!

    /// A person, and what they did.
    struct Credit: Codable, Hashable, Identifiable {
        let role: String
        let name: String
        var id: String { "\(role)|\(name)" }

        /// Sentence case for a heading — the raw values are query bindings.
        var label: String {
            switch role {
            case "director": "Director"
            case "composer": "Composer"
            case "designer": "Designer"
            case "writer":   "Writer"
            default:         role.capitalized
            }
        }
    }

    struct Entry: Codable, Hashable {
        let qid: String
        let title: String?
        let series: String?
        let released: String?
        let credits: [Credit]

        /// Credits in a stable, readable order rather than query order.
        var orderedCredits: [Credit] {
            let rank = ["director": 0, "designer": 1, "writer": 2, "composer": 3]
            return credits.sorted {
                let a = rank[$0.role] ?? 9, b = rank[$1.role] ?? 9
                return a == b ? $0.name < $1.name : a < b
            }
        }
    }

    private struct Payload: Codable { let games: [String: Entry] }

    enum WikidataError: Error { case offline, unavailable, rejected(status: Int) }

    /// Look up several games at once, keyed by IGDB slug.
    ///
    /// Batched because the credits section on one page and a future "everything
    /// this composer scored" both want the same call, and Wikidata's query
    /// service is a shared resource that asks callers to be modest.
    static func lookup(slugs: [String]) async throws -> [String: Entry] {
        let clean = slugs.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return [:] }

        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        EdgeFunctions.authorize(&request)
        request.httpBody = try JSONEncoder().encode(["slugs": Array(clean.prefix(12))])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WikidataError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw WikidataError.offline }
        switch http.statusCode {
        case 200:  break
        case 502:  throw WikidataError.unavailable
        default:   throw WikidataError.rejected(status: http.statusCode)
        }
        return try JSONDecoder().decode(Payload.self, from: data).games
    }

    static func lookup(slug: String) async throws -> Entry? {
        try await lookup(slugs: [slug])[slug]
    }

    /// Answers already given this launch.
    ///
    /// Credits are not stored — whether they should be their own record type,
    /// queryable for "every game this person directed", is a real design
    /// question and the wrong one to answer in passing. So the same page
    /// revisited would ask Wikidata again every time without this.
    @MainActor private static var cache: [String: Entry?] = [:]

    /// **A missing entry is cached; a failed request is not.**
    ///
    /// "This game is not in Wikidata" is an answer and worth remembering.
    /// "The network was down" is not an answer, and caching it would mean one
    /// bad moment on a train silenced the section until the app restarted.
    @MainActor
    static func cachedLookup(slug: String) async -> Entry? {
        if let hit = cache[slug] { return hit }
        guard let found = try? await lookup(slug: slug) else { return nil }
        cache[slug] = found
        return found
    }

    /// Whether Wikidata's release year disagrees with the one already stored.
    ///
    /// **A question, not a correction.** Coverage is uneven and the modelling
    /// is inconsistent between entries, so a disagreement means "these two
    /// sources differ", never "IGDB is wrong" — and it is compared at YEAR
    /// granularity because a regional release date differing by a month is not
    /// a discrepancy worth putting in front of anybody.
    static func releaseYearDisagreement(_ entry: Entry, storedFirstRelease: Date?)
        -> (wikidata: Int, stored: Int)? {
        guard let stored = storedFirstRelease,
              let released = entry.released,
              let year = Int(released.prefix(4))
        else { return nil }
        let storedYear = Calendar.current.component(.year, from: stored)
        return year == storedYear ? nil : (year, storedYear)
    }
}
