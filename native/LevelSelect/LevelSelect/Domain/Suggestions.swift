import Foundation

/// Games you might like, worked out from the games you already care about.
///
/// The rules, from the 09-08 roadmap line Tim pulled into build 39 on 09-17:
/// **your own library is the only input.** No trending, no popular, no "people
/// who played this" — IGDB's own `similar_games`, read from a capped set of
/// the games you rated, played or finished, minus everything you already have.
/// Every row says which of your games it came from, because a suggestion you
/// can't trace is just an advert.
enum Suggestions {

    /// What a suggestion shelf is for. Upcoming first: a game that isn't out
    /// is the one you'd want on a wishlist.
    enum Shelf: String, CaseIterable, Identifiable, Codable, Sendable {
        case upcoming, undated, recent, older
        var id: String { rawValue }

        var label: String {
            switch self {
            case .upcoming: "Coming soon"
            // The wishlist's own wording for the same thing, so the two
            // halves of this tab don't name one idea twice.
            case .undated: "No date yet"
            case .recent: "Out recently"
            case .older: "Older"
            }
        }

        /// Soonest-first only makes sense where "soon" exists. Everywhere
        /// else the newest belongs at the top — Tim, 09-17: *"I think our
        /// sort for older is backwards. Newer at the top, older at the
        /// bottom."*
        var countsUp: Bool { self == .upcoming }
    }

    /// One suggestion, kept small enough to cache as it is.
    struct Item: Codable, Hashable, Identifiable, Sendable {
        var id: Int
        var name: String
        var coverImageID: String?
        var releaseTimestamp: Double?
        var summary: String?
        /// How much of the date IGDB actually knows. A year-only date is
        /// padded to a real day by IGDB, and printing "Dec 2026" for
        /// "sometime in 2026" is the mistake the game page already avoids.
        var precision: String = IGDBGame.ReleasePrecision.unknown.rawValue
        /// The systems IGDB lists it on, so the shelf can be filtered to the
        /// ones you still play. Tim, 09-17: *"If I don't play Xbox 360 games
        /// anymore, then I might not want or need to know about Xbox 360
        /// games I might like."*
        var platforms: [String] = []
        /// Who made it and who put it out, so following or hiding a company
        /// can act on it (`SuggestionPrefs`).
        var developers: [String] = []
        var publishers: [String] = []
        /// The name of your game it came from — "because you played …".
        var because: String
        /// A term from your own vocabulary that both this game and the game
        /// it came from answer to — "Metroidvania". Shown beside the row, and
        /// never written anywhere: `SuggestedTags` applies nothing on your
        /// behalf, and reading a word out of a summary is not applying it.
        var tag: String?
        var shelf: Shelf

        var releaseDate: Date? { releaseTimestamp.map { Date(timeIntervalSince1970: $0) } }

        /// The date as much as IGDB knows it: a day, a month, or a year.
        var releaseText: String? {
            guard let date = releaseDate else { return nil }
            switch IGDBGame.ReleasePrecision(rawValue: precision) ?? .unknown {
            case .day: return date.formatted(date: .abbreviated, time: .omitted)
            case .month: return date.formatted(.dateTime.month(.abbreviated).year())
            case .quarter, .year, .tbd, .unknown:
                return date.formatted(.dateTime.year())
            }
        }
    }

    struct Cache: Codable, Sendable {
        var madeAt: Date
        var items: [Item]
        /// The library the suggestions were drawn from, so a changed library
        /// asks again rather than showing yesterday's answer forever.
        var sourceIDs: [Int]

        func isFresh(sourceIDs: [Int], now: Date = .now, maxAge: TimeInterval = 24 * 60 * 60) -> Bool {
            now.timeIntervalSince(madeAt) < maxAge && self.sourceIDs == sourceIDs
        }
    }

    /// How a shelf is ordered.
    enum Sort: String, CaseIterable, Identifiable, Sendable {
        /// `date` keeps the stored value "soonest" from the day it shipped.
        case date = "soonest"
        case newest, name
        var id: String { rawValue }

        var label: String {
            switch self {
            case .date: "By release date"
            case .newest: "Newest first"
            case .name: "Name (A–Z)"
            }
        }

        var systemImage: String {
            switch self {
            case .date: "calendar"
            case .newest: "sparkles"
            case .name: "textformat"
            }
        }
    }

    /// One shelf's order. `date` counts up where "soon" means something and
    /// down everywhere else.
    static func sorted(_ items: [Item], by sort: Sort, shelf: Shelf) -> [Item] {
        guard sort == .date else { return sorted(items, by: sort) }
        return sorted(items, by: shelf.countsUp ? .date : .newest)
    }

    static func sorted(_ items: [Item], by sort: Sort) -> [Item] {
        switch sort {
        // Coming soon reads best nearest-first; the other shelves have no
        // "soon", so they fall back to newest, which is the same comparison
        // the other way round.
        case .date:
            return items.sorted {
                ($0.releaseTimestamp ?? .greatestFiniteMagnitude,
                 $0.name) < ($1.releaseTimestamp ?? .greatestFiniteMagnitude, $1.name)
            }
        case .newest:
            return items.sorted { ($0.releaseTimestamp ?? 0, $1.name) > ($1.releaseTimestamp ?? 0, $0.name) }
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// Items on one system, by the app's own platform names. An item IGDB
    /// lists no platforms for is kept: a missing fact isn't a "no".
    /// What you've said you don't want: dropped outright.
    static func allowed(_ items: [Item]) -> [Item] {
        items.filter {
            !SuggestionPrefs.isHidden(developers: $0.developers, publishers: $0.publishers,
                                      tags: [$0.tag].compactMap { $0 }, platforms: $0.platforms)
        }
    }

    /// What you follow, first — with the rest still there.
    static func weighted(_ items: [Item]) -> [Item] {
        guard SuggestionPrefs.hasFollows else { return items }
        let followed = items.filter {
            SuggestionPrefs.isFollowed(developers: $0.developers, publishers: $0.publishers,
                                       tags: [$0.tag].compactMap { $0 }, platforms: $0.platforms)
        }
        let ids = Set(followed.map(\.id))
        return SuggestionPrefs.weave(followed: followed, others: items.filter { !ids.contains($0.id) })
    }

    static func onSystem(_ system: String?, _ items: [Item]) -> [Item] {
        guard let system, !system.isEmpty else { return items }
        let key = PlatformKey.canonical(system)
        return items.filter { item in
            item.platforms.isEmpty || item.platforms.contains { PlatformKey.canonical($0) == key }
        }
    }

    /// The systems you actually play, most active first.
    ///
    /// Recency beats size: twelve Xbox 360 games you last touched in 2019 rank
    /// below three Switch 2 games from last week. A system with nothing played
    /// keeps its place by count, so a fresh library still offers its consoles.
    static func activeSystems(from games: [(platforms: [String], lastPlayed: Date?, addedAt: Date)],
                              now: Date = .now, limit: Int = 8) -> [String] {
        var score: [String: Double] = [:]
        for game in games {
            let when = game.lastPlayed ?? game.addedAt
            let months = max(0, now.timeIntervalSince(when)) / (30 * 24 * 3600)
            // A year ago counts about a third of last month.
            let weight = 1 + 6 / (1 + months)
            // Blank first: `PlatformKey` folds "" to "Other", which would put
            // an "Other" chip on the shelf for every game with no console.
            let named = game.platforms
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for platform in Set(named.map(PlatformKey.canonical)) where !platform.isEmpty {
                score[platform, default: 0] += weight
            }
        }
        return score.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map(\.key)
    }

    /// The games worth asking about: what you rated well, are playing, or
    /// finished — newest first, and capped.
    ///
    /// Capped because each source costs a query and a shelf of forty
    /// half-relevant games is worse than a shelf of twelve good ones. Wishlist
    /// games are not sources: wanting a game says nothing about having liked it.
    static func sources(from games: [(id: Int, name: String, status: GameStatus,
                                     rating: Int?, lastPlayed: Date?, addedAt: Date)],
                        limit: Int = 20) -> [(id: Int, name: String)] {
        let liked: [(id: Int, name: String, weight: Int, when: Date)] = games.compactMap { game in
            guard game.status != .wishlist else { return nil }
            var weight = 0
            if let rating = game.rating, rating >= 4 { weight += rating }
            switch game.status {
            case .completed, .oldFavorite: weight += 3
            case .playing, .ongoing: weight += 2
            case .paused, .queued: weight += 1
            default: break
            }
            guard weight > 0 else { return nil }
            return (game.id, game.name, weight, game.lastPlayed ?? game.addedAt)
        }
        return liked
            .sorted { ($0.weight, $0.when) > ($1.weight, $1.when) }
            .prefix(limit)
            .map { ($0.id, $0.name) }
    }

    /// Which shelf a game belongs on. "Recent" is the last year, which is
    /// what "out recently" means to someone deciding what to buy next.
    static func shelf(releaseTimestamp: Double?, now: Date = .now) -> Shelf {
        // No date at all is its own shelf, not "Older": a game IGDB has no
        // date for is usually announced, occasionally cancelled, and never
        // something you played in 1989.
        guard let releaseTimestamp else { return .undated }
        let date = Date(timeIntervalSince1970: releaseTimestamp)
        if date > now { return .upcoming }
        return now.timeIntervalSince(date) < 365 * 24 * 60 * 60 ? .recent : .older
    }

    /// What a game is, for judging whether a suggestion is a real one.
    /// Genres, themes and perspectives together, lowercased.
    static func traits(genres: [String], themes: [String], perspectives: [String] = []) -> Set<String> {
        Set((genres + themes + perspectives)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    /// The vocabulary terms a piece of text answers to — a game's summary,
    /// usually. Whole words only, so "Cozy" doesn't match "Cozyville", and
    /// aliases resolve to the canonical spelling the way the picker does.
    static func terms(in text: String?) -> Set<String> {
        guard let text, !text.isEmpty else { return [] }
        var found = Set<String>()
        for tag in SuggestedTags.all {
            for term in tag.searchTerms {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
                if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    found.insert(tag.name)
                    break
                }
            }
        }
        return found
    }

    /// The terms YOU use, most-used first: your tags, read through the
    /// vocabulary so "Souls-like" and "Soulslike" count once.
    static func taste(from userTags: [[String]]) -> [String] {
        var counts: [String: Int] = [:]
        for tags in userTags {
            for tag in Set(tags.compactMap { SuggestedTags.canonical($0) }) {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    /// Whether a suggestion resembles the game that suggested it.
    ///
    /// IGDB's `similar_games` is loose — it offered WWE 2K24 for Tony Hawk and
    /// Borderlands for Sonic the Hedgehog 2 (Tim, 09-17: *"Some of these just
    /// don't feel right"*). The same two thresholds `RelatedGames` uses for the
    /// in-library shelf: at least two traits in common, and enough overlap that
    /// a game tagged with everything doesn't match everything. A game IGDB has
    /// no traits for is kept — an absent fact isn't a mismatch.
    /// A term both games answer to is decisive on its own: two games your own
    /// vocabulary calls Metroidvanias belong together whatever IGDB's genres
    /// say, which is the gap the vocabulary exists to fill.
    static func resembles(_ candidate: Set<String>, _ source: Set<String>,
                          sharedTerm: Bool = false,
                          minimumShared: Int = 2, minimumScore: Double = 0.25) -> Bool {
        if sharedTerm { return true }
        guard !candidate.isEmpty, !source.isEmpty else { return true }
        let shared = candidate.intersection(source).count
        guard shared >= minimumShared else { return false }
        return RelatedGames.similarity(candidate, source) >= minimumScore
    }

    /// Fold IGDB's answers into suggestions: each similar game once, credited
    /// to the source that suggested it most, and never something you have.
    ///
    /// `similarBySource` is source id → the ids IGDB called similar.
    /// `sourceNames` names them for the "because" line. `have` is every IGDB
    /// id in your library, wishlist included — a suggestion you already own
    /// or already want is noise.
    static func merge(similarBySource: [Int: [Int]],
                      sourceNames: [Int: String],
                      have: Set<Int>,
                      hidden: Set<Int> = [],
                      limitPerSource: Int = 8) -> [(id: Int, sources: [Int])] {
        var votes: [Int: (sources: [Int], order: Int)] = [:]
        var next = 0
        for (source, similar) in similarBySource.sorted(by: { $0.key < $1.key }) {
            guard sourceNames[source] != nil else { continue }
            for id in similar.prefix(limitPerSource) where !have.contains(id) && !hidden.contains(id) {
                if var existing = votes[id] {
                    existing.sources.append(source)
                    votes[id] = existing
                } else {
                    votes[id] = ([source], next)
                    next += 1
                }
            }
        }
        // More of your games pointing at it means more, and ties keep the
        // order IGDB gave, which is its own relevance.
        return votes
            .sorted { ($0.value.sources.count, -$0.value.order) > ($1.value.sources.count, -$1.value.order) }
            .map { ($0.key, $0.value.sources) }
    }
}
