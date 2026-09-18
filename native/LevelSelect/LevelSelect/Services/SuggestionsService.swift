import Foundation
import SwiftData

/// Asks IGDB what else you might like, and what a game connects to.
///
/// Two calls per refresh: one for `similar_games` on your own games, one to
/// look the answers up. Cached for a day on the device (`Suggestions.Cache`),
/// because this is a browsing surface, not a live feed, and the proxy's
/// allowance belongs to everyone.
@MainActor
enum SuggestionsService {

    // MARK: Games you might like

    static func suggestions(for games: [Game], force: Bool = false,
                            now: Date = .now) async throws -> [Suggestions.Item] {
        let sources = Suggestions.sources(from: games.compactMap { game in
            game.igdbID.map { (id: $0, name: game.name, status: game.status,
                               rating: game.rating,
                               lastPlayed: game.activePlaythrough?.lastPlayedAt,
                               addedAt: game.addedAt) }
        })
        guard !sources.isEmpty else { return [] }
        let sourceIDs = sources.map(\.id).sorted()

        if !force, let cached = SuggestionsCache.read(), cached.isFresh(sourceIDs: sourceIDs, now: now) {
            return cached.items.filter { !hidden.contains($0.id) }
        }

        let sourceGames = games.filter { game in
            game.igdbID.map { id in sourceIDs.contains(id) } ?? false
        }
        let similar = try await similarGames(forIDs: sourceIDs)
        let names = Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let have = Set(games.compactMap(\.igdbID))
        let picks = Suggestions.merge(similarBySource: similar, sourceNames: names,
                                      have: have, hidden: hidden)
        guard !picks.isEmpty else { return [] }

        // What each of your games IS, so a suggestion can be held against it.
        var traitsBySource: [Int: Set<String>] = [:]
        var nameBySource: [Int: String] = [:]
        var termsBySource: [Int: Set<String>] = [:]
        for game in sourceGames {
            guard let id = game.igdbID else { continue }
            traitsBySource[id] = Suggestions.traits(genres: game.genres, themes: game.themes,
                                                    perspectives: game.playerPerspectives)
            nameBySource[id] = game.name
            // Your own words for this game, plus anything its summary says
            // in the vocabulary's terms.
            termsBySource[id] = Set(game.userTags.compactMap { SuggestedTags.canonical($0) })
                .union(Suggestions.terms(in: game.summary))
        }
        // The terms you actually use, so a match with one of them can be said
        // out loud on the row.
        let taste = Set(Suggestions.taste(from: games.map(\.userTags)))
        let details = try await IGDBService.lookup(ids: Array(picks.prefix(80).map(\.id)))
        let items: [Suggestions.Item] = picks.compactMap { pick in
            guard let game = details.first(where: { $0.id == pick.id }) else { return nil }
            // Credited to a game of yours it actually resembles. If none of
            // the games that suggested it does, it isn't a suggestion.
            let candidate = Suggestions.traits(genres: game.genres, themes: game.themes,
                                               perspectives: game.playerPerspectives)
            let candidateTerms = Suggestions.terms(in: game.summary)
                .union(Suggestions.terms(in: game.name))
            var sharedTerm: String?
            let credit = pick.sources.first { source in
                let shared = candidateTerms.intersection(termsBySource[source] ?? [])
                // A term you actually use beats one you don't, for what the
                // row says: "Metroidvania" means more if it's your word.
                if let term = shared.first(where: taste.contains) ?? shared.first {
                    sharedTerm = term
                    return true
                }
                return Suggestions.resembles(candidate, traitsBySource[source] ?? [])
            }
            guard let credit, let becauseName = nameBySource[credit] else { return nil }
            return Suggestions.Item(
                id: game.id, name: game.name, coverImageID: game.coverImageID,
                releaseTimestamp: game.releaseTimestamp, summary: game.summary,
                precision: game.releasePrecision.rawValue,
                platforms: game.platforms,
                developers: game.developers, publishers: game.publishers,
                because: becauseName,
                tag: sharedTerm,
                shelf: Suggestions.shelf(releaseTimestamp: game.releaseTimestamp, now: now))
        }
        // Announced games from the series and studios you play, which
        // `similar_games` rarely knows about yet — IGDB fills that field from
        // what players have already compared, and nothing has been compared
        // to a game that isn't out. Tim, 09-17: *"let's add upcoming games
        // you might like too."*
        // Announced AND newly released, in your series and from your studios.
        // `similar_games` knows neither: IGDB fills that field from what
        // players have compared, and a game from this year has barely been
        // compared to anything. It is why a Switch 2 shelf looked so thin.
        let ahead = await fromYourSeries(sourceGames, have: have, now: now)
        // Companies you follow, whether or not you own anything of theirs:
        // "what is Capcom putting out" is a question about Capcom, not about
        // your library.
        let followed = await fromFollowedCompanies(have: have, now: now)
        var known = Set(items.map(\.id))
        var merged = items
        for extra in ahead + followed where known.insert(extra.id).inserted {
            merged.append(extra)
        }
        SuggestionsCache.write(.init(madeAt: now, items: merged, sourceIDs: sourceIDs))
        return merged
    }

    /// IGDB's own "similar games", for a batch of your games at once.
    static func similarGames(forIDs ids: [Int]) async throws -> [Int: [Int]] {
        guard !ids.isEmpty else { return [:] }
        var out: [Int: [Int]] = [:]
        // The proxy caps a query at 2,000 characters; 40 ids plus the field
        // list is well inside it.
        for chunk in stride(from: 0, to: ids.count, by: 40).map({ Array(ids[$0..<min($0 + 40, ids.count)]) }) {
            let list = chunk.map(String.init).joined(separator: ",")
            let rows = await IGDBService.raw(
                endpoint: "games",
                query: "where id = (\(list)); fields similar_games; limit \(chunk.count);")
            for row in rows {
                guard let id = (row["id"] as? NSNumber)?.intValue else { continue }
                let similar = (row["similar_games"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
                if let similar, !similar.isEmpty { out[id] = similar }
            }
        }
        return out
    }

    /// What's announced in the series and from the studios behind your own
    /// games, minus what you have. Two queries, whatever the library's size.
    static func fromYourSeries(_ sources: [Game], have: Set<Int>, now: Date = .now,
                               limit: Int = 24) async -> [Suggestions.Item] {
        // Series and studios are credited back to a game of yours, so the
        // "because you played …" line stays true for these rows too.
        var seriesBy: [String: String] = [:]
        var studioBy: [String: String] = [:]
        for game in sources {
            if let series = game.franchise, !series.isEmpty, seriesBy[series] == nil {
                seriesBy[series] = game.name
            }
            if let studio = game.developers.first, !studio.isEmpty, studioBy[studio] == nil {
                studioBy[studio] = game.name
            }
        }
        let series = Array(seriesBy.keys.sorted().prefix(12))
        let studios = Array(studioBy.keys.sorted().prefix(12))
        guard !series.isEmpty || !studios.isEmpty else { return [] }

        // Everything from the last year and a half, and everything announced.
        // Donkey Kong Bananza is the case: out in July, in a series Tim plays,
        // and `similar_games` had never heard of it.
        let since = Int(now.addingTimeInterval(-18 * 30 * 24 * 3600).timeIntervalSince1970)
        let window = "first_release_date > \(since)"
        var found: [(game: IGDBGame, because: String)] = []
        if !series.isEmpty {
            let names = list(series)
            let rows = await IGDBService.games(
                where: "\(window) & (franchises.name = \(names) | collection.name = \(names))",
                limit: limit, sort: "first_release_date desc")
            for row in rows {
                let credit = row.franchise.flatMap { seriesBy[$0] } ?? seriesBy.values.first ?? ""
                found.append((row, credit))
            }
        }
        if !studios.isEmpty {
            let rows = await IGDBService.games(
                where: "\(window) & involved_companies.company.name = \(list(studios)) & involved_companies.developer = true",
                limit: limit, sort: "first_release_date desc")
            for row in rows {
                let credit = row.developers.compactMap { studioBy[$0] }.first ?? studioBy.values.first ?? ""
                found.append((row, credit))
            }
        }

        var seen = Set<Int>()
        return found
            .filter { !have.contains($0.game.id) && !hidden.contains($0.game.id)
                && seen.insert($0.game.id).inserted }
            .map { row in
                Suggestions.Item(
                    id: row.game.id, name: row.game.name, coverImageID: row.game.coverImageID,
                    releaseTimestamp: row.game.releaseTimestamp, summary: row.game.summary,
                    precision: row.game.releasePrecision.rawValue,
                    platforms: row.game.platforms,
                    developers: row.game.developers, publishers: row.game.publishers,
                    because: row.because.isEmpty ? "your library" : row.because,
                    shelf: Suggestions.shelf(releaseTimestamp: row.game.releaseTimestamp, now: now))
            }
    }

    /// What the studios and publishers you follow have out lately or coming.
    static func fromFollowedCompanies(have: Set<Int>, now: Date = .now,
                                      limit: Int = 24) async -> [Suggestions.Item] {
        let studios = Array(SuggestionPrefs.names(.studio, .followed)).sorted().prefix(8)
        let publishers = Array(SuggestionPrefs.names(.publisher, .followed)).sorted().prefix(8)
        guard !studios.isEmpty || !publishers.isEmpty else { return [] }

        let since = Int(now.addingTimeInterval(-18 * 30 * 24 * 3600).timeIntervalSince1970)
        var found: [(game: IGDBGame, because: String)] = []
        if !studios.isEmpty {
            let rows = await IGDBService.games(
                where: "first_release_date > \(since) & involved_companies.company.name = \(list(Array(studios))) & involved_companies.developer = true",
                limit: limit, sort: "first_release_date desc")
            for row in rows { found.append((row, row.developers.first ?? "a studio you follow")) }
        }
        if !publishers.isEmpty {
            let rows = await IGDBService.games(
                where: "first_release_date > \(since) & involved_companies.company.name = \(list(Array(publishers))) & involved_companies.publisher = true",
                limit: limit, sort: "first_release_date desc")
            for row in rows { found.append((row, row.publishers.first ?? "a publisher you follow")) }
        }

        var seen = Set<Int>()
        return found
            .filter { !have.contains($0.game.id) && !hidden.contains($0.game.id)
                && seen.insert($0.game.id).inserted }
            .map { row in
                Suggestions.Item(
                    id: row.game.id, name: row.game.name, coverImageID: row.game.coverImageID,
                    releaseTimestamp: row.game.releaseTimestamp, summary: row.game.summary,
                    precision: row.game.releasePrecision.rawValue,
                    platforms: row.game.platforms,
                    developers: row.game.developers, publishers: row.game.publishers,
                    because: "you follow \(row.because)",
                    tag: nil,
                    shelf: Suggestions.shelf(releaseTimestamp: row.game.releaseTimestamp, now: now))
            }
    }

    /// A quoted IGDB list: `("Capcom","Nintendo")`.
    nonisolated static func list(_ names: [String]) -> String {
        "(" + names.map { "\"\(escaped($0))\"" }.joined(separator: ",") + ")"
    }

    // MARK: Connections on a game page

    /// A shelf of games this one connects to that you don't have.
    struct Connection: Identifiable, Sendable {
        var id: String { title }
        var title: String
        var games: [IGDBGame]
    }

    /// The series it belongs to and the studio that made it, minus everything
    /// in your library.
    ///
    /// Series first, studio second — the same order the in-library section
    /// uses, and for the same reason: a sequel you haven't played is a better
    /// answer than another game by the same people.
    static func connections(for game: Game, have: Set<Int>, limit: Int = 12) async -> [Connection] {
        var out: [Connection] = []
        func clean(_ games: [IGDBGame], excluding existing: Set<Int>) -> [IGDBGame] {
            var seen = existing
            return games
                .filter { $0.id != game.igdbID && !have.contains($0.id) && seen.insert($0.id).inserted }
                .sorted { ($0.releaseTimestamp ?? 0) > ($1.releaseTimestamp ?? 0) }
                .prefix(limit)
                .map { $0 }
        }

        var used = Set<Int>()
        // The people who made it, which IGDB cannot answer — a composer or a
        // director carries across studios and series both.
        if let slug = game.igdbSlug, !slug.isEmpty,
           let people = try? await WikidataService.people(slugs: [slug])[slug],
           let person = people.first(where: { $0.games.count >= 2 }) ?? people.first {
            let found = await IGDBService.games(slugs: person.games.map(\.slug))
            let picks = clean(found, excluding: used)
            used.formUnion(picks.map(\.id))
            if !picks.isEmpty {
                out.append(Connection(title: "Also \(roleWord(person.role)) \(person.name)", games: picks))
            }
        }
        if let franchise = game.franchise, !franchise.isEmpty {
            let series = await IGDBService.games(where: Self.seriesClause(franchise), limit: 40)
            let picks = clean(series, excluding: used)
            used.formUnion(picks.map(\.id))
            if !picks.isEmpty { out.append(Connection(title: "More from \(franchise)", games: picks)) }
        }
        if let studio = game.developers.first, !studio.isEmpty {
            let theirs = await IGDBService.games(where: Self.studioClause(studio), limit: 40)
            let picks = clean(theirs, excluding: used)
            used.formUnion(picks.map(\.id))
            if !picks.isEmpty { out.append(Connection(title: "More from \(studio)", games: picks)) }
        }
        return out
    }

    /// "Also scored by Michiru Yamane" reads better than "composer".
    nonisolated static func roleWord(_ role: String) -> String {
        switch role {
        case "composer": "scored by"
        case "director": "directed by"
        case "designer": "designed by"
        case "writer": "written by"
        default: "by"
        }
    }

    /// A series is a `franchise` for some games and a `collection` for others
    /// — IGDB has both, and the app reads whichever it finds. Asking for only
    /// one means a real series returns nothing: Castlevania answers, Hollow
    /// Knight (which has neither) answers either way.
    nonisolated static func seriesClause(_ name: String) -> String {
        let clean = escaped(name)
        return "(franchises.name = \"\(clean)\" | collection.name = \"\(clean)\")"
    }

    nonisolated static func studioClause(_ name: String) -> String {
        "involved_companies.company.name = \"\(escaped(name))\" & involved_companies.developer = true"
    }

    /// IGDB query strings are double-quoted, so a quote in a studio name ends
    /// the string early and the rest reads as syntax.
    nonisolated static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\"", with: "")
    }

    // MARK: Not interested

    private static let hiddenKey = "levelselect.suggestions.hidden"

    static var hidden: Set<Int> {
        Set(UserDefaults.standard.array(forKey: hiddenKey) as? [Int] ?? [])
    }

    static func hide(_ id: Int) {
        var ids = hidden
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: hiddenKey)
    }

    static func unhideAll() {
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }
}

/// Yesterday's answer, on disk. Application Support rather than UserDefaults:
/// sixty games with summaries is not a preference.
enum SuggestionsCache {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "suggestions.json")
    }

    static func read() -> Suggestions.Cache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Suggestions.Cache.self, from: data)
    }

    static func write(_ cache: Suggestions.Cache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
