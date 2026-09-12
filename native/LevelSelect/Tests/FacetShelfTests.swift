import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Browsing the library by what IGDB already told us.
///
/// Stage 1 of the taxonomy work, and the cheapest thing in it: `GameFacet` and
/// `FacetGamesView` already existed, so this is only an index. The rules worth
/// pinning are the ones the systems menu got wrong once already — counts come
/// from the games actually shown, wishlist games are not in the library, and
/// the order does not reshuffle between visits.
@MainActor
struct FacetShelfTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    @discardableResult
    private func game(_ context: ModelContext, _ name: String,
                      status: GameStatus = .playing,
                      genres: [String] = [], themes: [String] = []) -> Game {
        let game = Game(name: name)
        game.status = status
        game.genres = genres
        game.themes = themes
        context.insert(game)
        return game
    }

    private func all(_ context: ModelContext) -> [Game] {
        (try? context.fetch(FetchDescriptor<Game>())) ?? []
    }

    // MARK: Counting

    @Test func aValueIsCountedOncePerGameThatCarriesIt() {
        let context = makeContext()
        game(context, "Hollow Knight", genres: ["Platform", "Adventure"])
        game(context, "Celeste", genres: ["Platform"])
        game(context, "Hades", genres: ["Adventure"])

        let groups = GameFacet.groups(of: .genre, in: all(context))
        #expect(groups.count == 2)
        #expect(groups.first(where: { $0.value == "Platform" })?.count == 2)
        #expect(groups.first(where: { $0.value == "Adventure" })?.count == 2)
    }

    /// A game with three genres stands in three rows. The counts overlap on
    /// purpose and are not meant to sum to the library — the same way the
    /// systems row and the ownership chips behave.
    @Test func countsOverlapRatherThanPartition() {
        let context = makeContext()
        game(context, "Hollow Knight", genres: ["Platform", "Adventure", "Indie"])

        let total = GameFacet.groups(of: .genre, in: all(context)).reduce(0) { $0 + $1.count }
        #expect(total == 3)
        #expect(all(context).count == 1)
    }

    @Test func largestFirstAndTiesBreakAlphabetically() {
        let context = makeContext()
        game(context, "A", genres: ["Shooter", "Puzzle"])
        game(context, "B", genres: ["Shooter", "Arcade"])
        game(context, "C", genres: ["Shooter"])

        let groups = GameFacet.groups(of: .genre, in: all(context))
        #expect(groups.map(\.value) == ["Shooter", "Arcade", "Puzzle"])
    }

    /// The order must be stable, or the row reshuffles between visits and
    /// nothing can be found twice.
    @Test func theOrderIsDeterministic() {
        let context = makeContext()
        for name in ["A", "B", "C", "D"] {
            game(context, name, genres: ["Puzzle", "Arcade", "Racing", "Sport"])
        }
        let first = GameFacet.groups(of: .genre, in: all(context)).map(\.value)
        for _ in 0..<5 {
            #expect(GameFacet.groups(of: .genre, in: all(context)).map(\.value) == first)
        }
    }

    @Test func themesCountSeparatelyFromGenres() {
        let context = makeContext()
        game(context, "Hades", genres: ["Adventure"], themes: ["Action", "Fantasy"])

        #expect(GameFacet.groups(of: .genre, in: all(context)).map(\.value) == ["Adventure"])
        #expect(Set(GameFacet.groups(of: .theme, in: all(context)).map(\.value))
                == ["Action", "Fantasy"])
    }

    /// Only the kinds an index is offered for. A publisher row would be a
    /// hundred entries answering a question nobody opens Library to ask.
    @Test func kindsWithoutAnIndexReturnNothing() {
        let context = makeContext()
        let hades = game(context, "Hades", genres: ["Adventure"])
        hades.publishers = ["Supergiant Games"]
        hades.franchise = "Hades"

        #expect(GameFacet.groups(of: .publisher, in: all(context)).isEmpty)
        #expect(GameFacet.groups(of: .franchise, in: all(context)).isEmpty)
    }

    // MARK: The rule the systems menu got wrong

    /// Library excludes wishlist games from everything it counts. The shelf is
    /// built from the games on screen, so a wanted game cannot put a genre in
    /// an index that would then show an empty page.
    @Test func aWishlistGamesGenreIsNotIndexed() {
        let context = makeContext()
        game(context, "Hollow Knight", status: .playing, genres: ["Platform"])
        game(context, "The Duskbloods", status: .wishlist, genres: ["Role-playing (RPG)"])

        // What Library actually passes in: the games it is showing.
        let shown = all(context).filter { $0.status != .wishlist }
        let groups = GameFacet.groups(of: .genre, in: shown)
        #expect(groups.map(\.value) == ["Platform"])
    }

    // MARK: Display names

    /// IGDB writes three of a real library's twenty-one genres as
    /// "Name (ABBR)", and in each the abbreviation is the common name.
    @Test func anAbbreviationInParenthesesBecomesTheName() {
        #expect(GameFacet(kind: .genre, value: "Role-playing (RPG)").displayName == "RPG")
        #expect(GameFacet(kind: .genre, value: "Real Time Strategy (RTS)").displayName == "RTS")
        #expect(GameFacet(kind: .genre, value: "Turn-based strategy (TBS)").displayName == "TBS")
    }

    /// Everything else passes through untouched — no invented shortening.
    @Test func plainNamesAreLeftAlone() {
        for value in ["Adventure", "Platform", "Indie", "Shooter", "Puzzle",
                      "Hack and slash/Beat 'em up", "Card & Board Game",
                      "Quiz/Trivia", "Point-and-click", "MOBA",
                      "Science fiction", "Open world"] {
            #expect(GameFacet(kind: .genre, value: value).displayName == value)
        }
    }

    /// A parenthetical that is prose rather than an abbreviation stays.
    @Test func aParentheticalThatIsNotAnAbbreviationStays() {
        let value = "Strategy (and similar)"
        #expect(GameFacet(kind: .genre, value: value).displayName == value)
    }

    /// The stored value never changes — it is what `matches(_:)` compares
    /// against and what the game record holds.
    @Test func theStoredValueIsUntouchedByDisplay() {
        let context = makeContext()
        game(context, "Chrono Trigger", genres: ["Role-playing (RPG)"])

        let facet = GameFacet(kind: .genre, value: "Role-playing (RPG)")
        #expect(facet.displayName == "RPG")
        #expect(facet.value == "Role-playing (RPG)")
        #expect(GameFacet.games(facet, in: all(context)).count == 1)
        // The shortened form is a label, not a key: it must not match.
        #expect(GameFacet.games(GameFacet(kind: .genre, value: "RPG"), in: all(context)).isEmpty)
    }
}
