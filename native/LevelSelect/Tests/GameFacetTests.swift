import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Slicing the library by one field.
///
/// Every value in a game's info panel is really a set of games — "Sega" is a
/// shelf, not a fact — and these are the rules that decide who is on it.
/// Matching is exact on purpose: the values come from IGDB and from each
/// other, so they already agree, and a loose match would quietly merge
/// "Action" and "Action-Adventure" into a screen claiming to be neither.
@MainActor
struct GameFacetTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @discardableResult
    private func game(_ repo: Repository, _ name: String,
                      developers: [String] = [], publishers: [String] = [],
                      genres: [String] = [], themes: [String] = [],
                      perspectives: [String] = [], modes: [String] = [],
                      franchise: String? = nil, year: Int? = nil) -> Game {
        let game = repo.addGame(name: name, status: .backlog)
        repo.edit(game) {
            $0.developers = developers
            $0.publishers = publishers
            $0.genres = genres
            $0.themes = themes
            $0.playerPerspectives = perspectives
            $0.gameModes = modes
            $0.franchise = franchise
            if let year {
                $0.firstReleaseDate = Calendar.current.date(
                    from: DateComponents(year: year, month: 6, day: 1))
            }
        }
        return game
    }

    /// A studio credited second still counts — IGDB lists co-developers, and
    /// only reading the first would hide Sonic Team's own games.
    @Test func developerMatchesAnyCreditNotJustTheFirst() {
        let repo = self.repo()
        let sonic = game(repo, "Sonic 2",
                         developers: ["Sega Technical Institute", "Sonic Team"])
        let other = game(repo, "Nights", developers: ["Sonic Team"])
        let unrelated = game(repo, "Doom", developers: ["id Software"])

        let facet = GameFacet(kind: .developer, value: "Sonic Team")
        let names = GameFacet.games(facet, in: [sonic, other, unrelated]).map(\.name)
        #expect(Set(names) == ["Sonic 2", "Nights"])
    }

    @Test func publisherIsSeparateFromDeveloper() {
        let repo = self.repo()
        let a = game(repo, "Published By Sega", developers: ["Someone"], publishers: ["Sega"])
        let b = game(repo, "Made By Sega", developers: ["Sega"], publishers: ["Someone"])

        #expect(GameFacet.games(.init(kind: .publisher, value: "Sega"), in: [a, b])
                .map(\.name) == ["Published By Sega"])
        #expect(GameFacet.games(.init(kind: .developer, value: "Sega"), in: [a, b])
                .map(\.name) == ["Made By Sega"])
    }

    /// Genre and theme live in different fields and must not be conflated —
    /// "Action" the genre and "Action" the theme are different claims, and the
    /// info panel shows them in one row only for layout reasons.
    @Test func genreAndThemeAreDistinctFacets() {
        let repo = self.repo()
        let a = game(repo, "Genre Action", genres: ["Action"])
        let b = game(repo, "Theme Action", themes: ["Action"])

        #expect(GameFacet.games(.init(kind: .genre, value: "Action"), in: [a, b])
                .map(\.name) == ["Genre Action"])
        #expect(GameFacet.games(.init(kind: .theme, value: "Action"), in: [a, b])
                .map(\.name) == ["Theme Action"])
    }

    /// The year is derived from a date, so it has to survive that conversion —
    /// and a game with no release date belongs to no year rather than to 1970.
    @Test func yearComesFromTheReleaseDateAndUndatedGamesAreExcluded() {
        let repo = self.repo()
        let dated = game(repo, "Sonic 2", year: 1992)
        let alsoDated = game(repo, "Mortal Kombat", year: 1992)
        let undated = game(repo, "No Date")

        let names = GameFacet.games(.init(kind: .year, value: "1992"),
                                    in: [dated, alsoDated, undated]).map(\.name)
        #expect(Set(names) == ["Sonic 2", "Mortal Kombat"])
        #expect(GameFacet.games(.init(kind: .year, value: "1970"), in: [undated]).isEmpty)
    }

    /// Loose matching would merge shelves that claim to be one thing and
    /// contain another.
    @Test func matchingIsExactRatherThanContains() {
        let repo = self.repo()
        let broad = game(repo, "Broad", genres: ["Action"])
        let hyphenated = game(repo, "Hyphenated", genres: ["Action-Adventure"])

        #expect(GameFacet.games(.init(kind: .genre, value: "Action"), in: [broad, hyphenated])
                .map(\.name) == ["Broad"])
    }

    @Test func deletedGamesNeverAppearInASlice() {
        let repo = self.repo()
        let live = game(repo, "Live", genres: ["Puzzle"])
        let gone = game(repo, "Deleted", genres: ["Puzzle"])
        repo.softDelete(gone)

        #expect(GameFacet.games(.init(kind: .genre, value: "Puzzle"), in: [live, gone])
                .map(\.name) == ["Live"])
    }

    /// Oldest first: a studio's or a series' shelf reads as a history.
    @Test func aSliceIsOrderedByRelease() {
        let repo = self.repo()
        let late = game(repo, "Late", developers: ["Sega"], year: 1998)
        let early = game(repo, "Early", developers: ["Sega"], year: 1991)

        #expect(GameFacet.games(.init(kind: .developer, value: "Sega"), in: [late, early])
                .map(\.name) == ["Early", "Late"])
    }

    /// The facet is a navigation value, so it has to survive being one.
    @Test func aFacetRoundTripsAsARouteValue() throws {
        let facet = GameFacet(kind: .perspective, value: "Side view")
        let data = try JSONEncoder().encode(facet)
        #expect(try JSONDecoder().decode(GameFacet.self, from: data) == facet)
    }

    // MARK: Search reaches what navigation cannot

    /// The case that motivated widening search: "Capcom games", meaning
    /// published *or* developed by Capcom.
    ///
    /// Navigation cannot express it. `GameFacet.Kind` holds developer and
    /// publisher as separate kinds, so tapping either gives one set and no
    /// gesture unions them — and finding a game to tap requires already owning
    /// one. One string against both arrays is that union.
    @Test func searchFindsACompanyAsEitherDeveloperOrPublisher() {
        let repo = self.repo()
        let developed = game(repo, "Resident Evil 4", developers: ["Capcom"], publishers: ["Nintendo"])
        let published = game(repo, "Dragon's Dogma", developers: ["Some Studio"], publishers: ["Capcom"])
        let neither = game(repo, "Hollow Knight", developers: ["Team Cherry"], publishers: ["Team Cherry"])

        #expect(LibrarySearch.matches(developed, query: "Capcom"))
        #expect(LibrarySearch.matches(published, query: "Capcom"))
        #expect(!LibrarySearch.matches(neither, query: "Capcom"))
        // Case-insensitive, like every other search in the app.
        #expect(LibrarySearch.matches(published, query: "capcom"))
    }

    /// The other axes worth reaching by typing, and the ones that must NOT be
    /// folded in: status, ownership and platform-filter all have their own
    /// controls beside the field, and matching them here would return games on
    /// a meaning the user did not intend.
    @Test func searchCoversTheDescriptiveFieldsOnly() {
        let repo = self.repo()
        let g = game(repo, "Mina the Hollower", developers: ["Yacht Club Games"],
                     genres: ["Adventure"], themes: ["Horror"],
                     perspectives: ["Bird view / Isometric"], modes: ["Single player"],
                     franchise: "Mina")

        for term in ["Mina", "Yacht Club", "Adventure", "Horror", "Isometric", "Single player"] {
            #expect(LibrarySearch.matches(g, query: term), "should match \(term)")
        }
        #expect(!LibrarySearch.matches(g, query: "Capcom"))
        // An empty query is not a filter.
        #expect(LibrarySearch.matches(g, query: ""))
    }
}
