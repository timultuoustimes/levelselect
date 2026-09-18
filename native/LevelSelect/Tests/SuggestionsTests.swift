import Testing
import Foundation
@testable import LevelSelect

/// Games you might like, and the connections on a game page (2026-09-17).
/// Your own library is the only input: no trending, no popular.
struct SuggestionsTests {

    private func source(_ id: Int, _ name: String, _ status: GameStatus,
                        rating: Int? = nil, played: Date? = nil,
                        added: Date = Date(timeIntervalSince1970: 0))
        -> (id: Int, name: String, status: GameStatus, rating: Int?, lastPlayed: Date?, addedAt: Date) {
        (id, name, status, rating, played, added)
    }

    @Test("Sources are what you rated, played or finished — never the wishlist")
    func sources() {
        let picked = Suggestions.sources(from: [
            source(1, "Hollow Knight", .completed, played: Date(timeIntervalSince1970: 100)),
            source(2, "Wanted Game", .wishlist, rating: 5),
            source(3, "Backlog Filler", .backlog),
            source(4, "Rated Highly", .backlog, rating: 5),
            source(5, "Playing Now", .playing, played: Date(timeIntervalSince1970: 500)),
            source(6, "Rated Low", .backlog, rating: 2),
        ])
        #expect(picked.map(\.name) == ["Rated Highly", "Hollow Knight", "Playing Now"])
        #expect(!picked.contains { $0.name == "Wanted Game" })
        #expect(!picked.contains { $0.name == "Rated Low" })
        #expect(Suggestions.sources(from: [source(1, "A", .completed)], limit: 0).isEmpty)
    }

    @Test("Shelves split by release: ahead, this year, and everything else")
    func shelves() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = now.addingTimeInterval(60 * 24 * 3600).timeIntervalSince1970
        let lastMonth = now.addingTimeInterval(-30 * 24 * 3600).timeIntervalSince1970
        let longAgo = now.addingTimeInterval(-800 * 24 * 3600).timeIntervalSince1970
        #expect(Suggestions.shelf(releaseTimestamp: soon, now: now) == .upcoming)
        #expect(Suggestions.shelf(releaseTimestamp: lastMonth, now: now) == .recent)
        #expect(Suggestions.shelf(releaseTimestamp: longAgo, now: now) == .older)
        #expect(Suggestions.shelf(releaseTimestamp: nil, now: now) == .undated,
                "no date is its own shelf, not 'Older'")
    }

    @Test("Suggestions carry every game that suggested them, skip what you have, and rank by agreement")
    func merge() {
        let picks = Suggestions.merge(
            similarBySource: [10: [100, 200, 300], 20: [200, 400], 30: [500]],
            sourceNames: [10: "Hollow Knight", 20: "Celeste", 30: "Hades"],
            have: [300],
            hidden: [500])
        #expect(picks.map(\.id) == [200, 100, 400],
                "two of your games pointing at 200 puts it first")
        #expect(picks.first?.sources == [10, 20])
        #expect(!picks.contains { $0.id == 300 }, "already in your library")
        #expect(!picks.contains { $0.id == 500 }, "you said not interested")

        // A source the caller didn't name can't credit anything, so it's skipped.
        #expect(Suggestions.merge(similarBySource: [99: [1]], sourceNames: [:], have: []).isEmpty)
        #expect(Suggestions.merge(similarBySource: [10: [1, 2, 3]], sourceNames: [10: "A"],
                                  have: [], limitPerSource: 2).count == 2)
    }

    @Test("A day-old answer for the same library is reused; a changed library isn't")
    func cacheFreshness() {
        let made = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = Suggestions.Cache(madeAt: made, items: [], sourceIDs: [1, 2, 3])
        #expect(cache.isFresh(sourceIDs: [1, 2, 3], now: made.addingTimeInterval(3600)))
        #expect(!cache.isFresh(sourceIDs: [1, 2, 3], now: made.addingTimeInterval(25 * 3600)))
        #expect(!cache.isFresh(sourceIDs: [1, 2], now: made.addingTimeInterval(60)),
                "finishing a game asks again rather than showing yesterday's answer")
    }

    @Test("A cached suggestion round-trips, shelf and all")
    func cacheRoundTrip() throws {
        let item = Suggestions.Item(id: 7, name: "Animal Well", coverImageID: "abc",
                                    releaseTimestamp: 1_700_000_000, summary: "A well.",
                                    because: "Hollow Knight", shelf: .recent)
        let data = try JSONEncoder().encode(Suggestions.Cache(madeAt: .now, items: [item], sourceIDs: [1]))
        let back = try JSONDecoder().decode(Suggestions.Cache.self, from: data)
        #expect(back.items == [item])
        #expect(back.items.first?.releaseDate != nil)
    }

    @Test("A suggestion has to resemble the game that suggested it")
    func resemblance() {
        let sonic = Suggestions.traits(genres: ["Platform"], themes: ["Action"])
        let borderlands = Suggestions.traits(genres: ["Shooter", "Role-playing (RPG)"],
                                             themes: ["Action", "Science fiction"])
        #expect(!Suggestions.resembles(borderlands, sonic),
                "one shared theme is not a reason to suggest a game")

        let ori = Suggestions.traits(genres: ["Platform", "Adventure"],
                                     themes: ["Action", "Fantasy"],
                                     perspectives: ["Side view"])
        let silksong = Suggestions.traits(genres: ["Platform", "Adventure"],
                                          themes: ["Action", "Fantasy"],
                                          perspectives: ["Side view"])
        #expect(Suggestions.resembles(silksong, ori))

        // A game tagged with everything must not match everything.
        let vague = Suggestions.traits(genres: ["Platform", "Shooter", "Puzzle", "Racing", "Sport"],
                                       themes: ["Action", "Comedy", "Horror", "Fantasy"])
        #expect(!Suggestions.resembles(vague, sonic))
        #expect(Suggestions.resembles([], sonic), "a game IGDB knows nothing about isn't ruled out")
        #expect(Suggestions.resembles(sonic, []))
    }

    @Test("Your own vocabulary counts: a shared term settles it, and your tags are read through aliases")
    func vocabulary() {
        // Whole words, and an alias resolves to the canonical spelling.
        #expect(Suggestions.terms(in: "A hand-drawn Metroidvania about a knight.") == ["Metroidvania"])
        #expect(Suggestions.terms(in: "A souls-like with bugs") == ["Soulslike"])
        #expect(Suggestions.terms(in: "Set in Cozyville, a town").isEmpty,
                "a term inside a longer word is not that term")
        #expect(Suggestions.terms(in: nil).isEmpty)

        // Your tags, most used first, folded across spellings.
        let taste = Suggestions.taste(from: [
            ["Metroidvania"], ["Souls-like"], ["metroidvania", "Cozy"], ["Not A Term"],
        ])
        #expect(taste.first == "Metroidvania")
        #expect(Set(taste) == ["Metroidvania", "Soulslike", "Cozy"])
        #expect(!taste.contains("Not A Term"), "only the vocabulary's own terms count")

        // A shared term beats the genre thresholds: two Metroidvanias belong
        // together whatever IGDB tagged them.
        let sparse = Suggestions.traits(genres: ["Adventure"], themes: [])
        let other = Suggestions.traits(genres: ["Platform"], themes: ["Horror"])
        #expect(!Suggestions.resembles(sparse, other))
        #expect(Suggestions.resembles(sparse, other, sharedTerm: true))
    }

    @Test("A Wikidata role reads as a sentence")
    func roleWords() {
        #expect(SuggestionsService.roleWord("composer") == "scored by")
        #expect(SuggestionsService.roleWord("director") == "directed by")
        #expect(SuggestionsService.roleWord("") == "by")
    }

    @Test("Systems rank by how recently you played them, not by how many you own")
    func activeSystems() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func game(_ platforms: [String], months: Double)
            -> (platforms: [String], lastPlayed: Date?, addedAt: Date) {
            (platforms, now.addingTimeInterval(-months * 30 * 24 * 3600), now)
        }
        let systems = Suggestions.activeSystems(from: [
            game(["Xbox 360"], months: 70), game(["Xbox 360"], months: 70),
            game(["Xbox 360"], months: 70), game(["Xbox 360"], months: 70),
            game(["Switch 2"], months: 0.2), game(["Switch 2"], months: 1),
        ], now: now)
        #expect(systems.first == "Switch 2", "four dusty 360 games don't outrank two current ones")
        #expect(systems.contains("Xbox 360"))
        #expect(Suggestions.activeSystems(from: [game([""], months: 1)], now: now).isEmpty)
    }

    @Test("A system filter keeps games with no platforms listed, and sorts run three ways")
    func filterAndSort() {
        func item(_ id: Int, _ name: String, _ when: Double?, _ platforms: [String]) -> Suggestions.Item {
            Suggestions.Item(id: id, name: name, coverImageID: nil, releaseTimestamp: when,
                             summary: nil, platforms: platforms, because: "You", shelf: .upcoming)
        }
        let items = [
            item(1, "Switch Game", 300, ["Nintendo Switch"]),
            item(2, "Xbox Game", 100, ["Xbox 360"]),
            item(3, "Unknown Platforms", 200, []),
        ]
        #expect(Suggestions.onSystem("Switch", items).map(\.id) == [1, 3],
                "a game IGDB lists no systems for isn't hidden by a filter")
        #expect(Suggestions.onSystem(nil, items).count == 3)
        #expect(Suggestions.sorted(items, by: .date).map(\.id) == [2, 3, 1])
        #expect(Suggestions.sorted(items, by: .newest).map(\.id) == [1, 3, 2])
        #expect(Suggestions.sorted(items, by: .name).map(\.name).first == "Switch Game")
        let undated = [item(4, "No date", nil, [])]
        #expect(Suggestions.sorted(undated + items, by: .date).last?.id == 4,
                "a game with no date is last in a soonest-first list, not first")

        // By release date means soonest on Coming soon and newest everywhere
        // else: 1989 above 1987 in Older.
        #expect(Suggestions.sorted(items, by: .date, shelf: .upcoming).map(\.id) == [2, 3, 1])
        #expect(Suggestions.sorted(items, by: .date, shelf: .older).map(\.id) == [1, 3, 2])
        #expect(Suggestions.sorted(items, by: .name, shelf: .older).map(\.id)
                == Suggestions.sorted(items, by: .name).map(\.id), "an explicit sort is never flipped")
    }

    @Test("A year-only date says the year, never a month it doesn't know")
    func releaseText() {
        // IGDB pads a year-only date to 30 December, which is why this can't
        // just format the timestamp.
        let december = Date(timeIntervalSince1970: 1_798_588_800)
        func item(_ precision: IGDBGame.ReleasePrecision) -> Suggestions.Item {
            Suggestions.Item(id: 1, name: "Game", coverImageID: nil,
                             releaseTimestamp: december.timeIntervalSince1970,
                             summary: nil, precision: precision.rawValue,
                             platforms: [], because: "You", shelf: .upcoming)
        }
        #expect(item(.year).releaseText == "2026")
        #expect(item(.quarter).releaseText == "2026")
        #expect(item(.month).releaseText?.contains("2026") == true)
        #expect(item(.month).releaseText?.contains("Dec") == true)
        #expect(item(.day).releaseText != item(.month).releaseText,
                "an exact day says the day, which a month-precision date must not")
        var none = item(.day)
        none.releaseTimestamp = nil
        #expect(none.releaseText == nil)
    }

    @Test("A quoted IGDB list can't be broken by a name")
    func quotedList() {
        #expect(SuggestionsService.list(["Capcom", "Team Cherry"]) == "(\"Capcom\",\"Team Cherry\")")
        #expect(SuggestionsService.list(["Bob\"s"]) == "(\"Bobs\")")
    }

    @Test("A studio name with a quote in it can't break the IGDB query")
    func escaping() {
        #expect(SuggestionsService.escaped("Bob\"s \\Games") == "Bobs Games")
        #expect(SuggestionsService.escaped("Naughty Dog") == "Naughty Dog")
    }
}

/// The IGDB clauses the connections shelves use. Checked here because a
/// wrong clause returns an empty shelf rather than an error — the Hollow
/// Knight case, where the series is a collection and not a franchise.
struct ConnectionQueryTests {
    @Test("A series asks both of IGDB's names for one, and a studio asks for developers")
    func clauses() {
        let series = SuggestionsService.seriesClause("Castlevania")
        #expect(series.contains("franchises.name = \"Castlevania\""))
        #expect(series.contains("collection.name = \"Castlevania\""))
        #expect(series.hasPrefix("(") && series.contains("|"))

        let studio = SuggestionsService.studioClause("Team Cherry")
        #expect(studio.contains("involved_companies.company.name = \"Team Cherry\""))
        #expect(studio.contains("involved_companies.developer = true"))
        #expect(!SuggestionsService.seriesClause("Bob\"s").contains("Bob\"s"))
    }
}

/// Following and hiding studios, publishers, tags and systems (2026-09-17).
/// Tim: *"they really like Capcom, Konami, and Nintendo so they want to see
/// what games they are publishing"* — and not be bombarded by the rest.
@MainActor
struct SuggestionPrefsTests {

    private func clean() {
        for kind in SuggestionPrefs.Kind.allCases {
            for name in SuggestionPrefs.names(kind, .followed).union(SuggestionPrefs.names(kind, .hidden)) {
                SuggestionPrefs.set(.neutral, kind, name)
            }
        }
    }

    private func item(_ id: Int, developers: [String] = [], publishers: [String] = [],
                      tag: String? = nil, platforms: [String] = []) -> Suggestions.Item {
        Suggestions.Item(id: id, name: "Game \(id)", coverImageID: nil, releaseTimestamp: Double(id),
                         summary: nil, platforms: platforms, developers: developers,
                         publishers: publishers, because: "You", tag: tag, shelf: .recent)
    }

    @Test("Follow and hide are one choice per thing, and case doesn't matter")
    func stances() {
        clean()
        defer { clean() }
        SuggestionPrefs.set(.followed, .publisher, "Capcom")
        #expect(SuggestionPrefs.stance(.publisher, "capcom") == .followed)
        #expect(SuggestionPrefs.hasFollows)
        // Hiding something you follow replaces the follow rather than both.
        SuggestionPrefs.set(.hidden, .publisher, "CAPCOM")
        #expect(SuggestionPrefs.stance(.publisher, "Capcom") == .hidden)
        #expect(SuggestionPrefs.names(.publisher, .followed).isEmpty)
        SuggestionPrefs.set(.neutral, .publisher, "Capcom")
        #expect(SuggestionPrefs.stance(.publisher, "Capcom") == .neutral)
        #expect(!SuggestionPrefs.hasFollows)
    }

    @Test("Hidden is absolute; a system is only hidden when every system is")
    func hiding() {
        clean()
        defer { clean() }
        SuggestionPrefs.set(.hidden, .studio, "Ubisoft")
        SuggestionPrefs.set(.hidden, .system, "Xbox 360")
        let items = [
            item(1, developers: ["Ubisoft Montreal"]),
            item(2, developers: ["Ubisoft"]),
            item(3, platforms: ["Xbox 360"]),
            item(4, platforms: ["Xbox 360", "Nintendo Switch"]),
            item(5, tag: "Soulslike"),
        ]
        #expect(Suggestions.allowed(items).map(\.id) == [1, 4, 5],
                "a studio with a longer name is a different studio, and a game on two systems survives")
    }

    @Test("Followed games come first, and the rest stay, lightly scattered")
    func weighting() {
        clean()
        defer { clean() }
        #expect(Suggestions.weighted([item(1), item(2)]).map(\.id) == [1, 2],
                "nothing followed changes nothing")

        SuggestionPrefs.set(.followed, .publisher, "Nintendo")
        let items = (1...4).map { item($0, publishers: ["Nintendo"]) } + (5...9).map { item($0) }
        let woven = Suggestions.weighted(items)
        #expect(woven.prefix(3).map(\.id) == [1, 2, 3])
        #expect(woven.count == items.count, "nothing is dropped, only ordered")
        #expect(woven.map(\.id) == [1, 2, 3, 5, 4, 6, 7, 8, 9])
    }

    @Test("Weaving handles the empty cases")
    func weave() {
        #expect(SuggestionPrefs.weave(followed: [1, 2], others: []) == [1, 2])
        #expect(SuggestionPrefs.weave(followed: [], others: [3, 4]) == [3, 4])
        #expect(SuggestionPrefs.weave(followed: [1], others: [2], everyNth: 1) == [1, 2])
    }
}
