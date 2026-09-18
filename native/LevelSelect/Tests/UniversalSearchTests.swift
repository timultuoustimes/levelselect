import Testing
import Foundation
@testable import LevelSelect

/// Universal search's matching (09-18).
struct UniversalSearchTests {
    @Test func everyWordMustAppear() {
        #expect(UniversalSearch.matches("Hollow Knight: Silksong", "silk knight"))
        #expect(!UniversalSearch.matches("Hollow Knight: Silksong", "silk mario"))
    }

    @Test func accentsAndCaseAside() {
        #expect(UniversalSearch.matches("Pokémon Legends: Z-A", "pokemon"))
        #expect(UniversalSearch.matches("God of War Ragnarök", "RAGNAROK"))
    }

    /// Two letters match the start of a word, not the middle of one.
    @Test func shortQueriesMatchWordStarts() {
        #expect(UniversalSearch.matches("Hades II", "ha"))
        #expect(!UniversalSearch.matches("Death Stranding", "ha"))
        #expect(UniversalSearch.matches("Castlevania: Symphony of the Night", "castle"))
    }

    @Test func namesThatStartWithItComeFirst() {
        #expect(UniversalSearch.rank("Castlevania", "castle") < UniversalSearch.rank("Super Castlevania IV", "castle"))
        #expect(UniversalSearch.rank("Super Castlevania IV", "castle") < UniversalSearch.rank("Newcastle", "castle"))
    }

    @Test func aSnippetShowsWhyANoteMatched() {
        let note = "Long day. Explored the library for an hour, then finally got into the inverted castle. Galamoth next, once I find the Crissaegrim."
        let s = UniversalSearch.snippet(note, "castle", radius: 20)
        #expect(s.contains("inverted castle"))
        #expect(s.hasPrefix("…") && s.hasSuffix("…"))
    }

    @Test func recentSearchesAreNewestFirstWithoutRepeats() {
        var recent = UniversalSearch.remember("silksong", in: [])
        recent = UniversalSearch.remember("moon pearl", in: recent)
        recent = UniversalSearch.remember("Silksong", in: recent)
        #expect(recent == ["Silksong", "moon pearl"])
        #expect(UniversalSearch.remember("a", in: recent) == recent)
    }

    @Test func wordsSiriSplitStillFindTheGame() {
        #expect(UniversalSearch.matches("Hollow Knight: Silksong", "silk song"))
        #expect(UniversalSearch.matches("Starfield", "Star field"))
        #expect(!UniversalSearch.matches("Silksong", "silk sock"))
        #expect(UniversalSearch.runTogether("silk song") == "silksong")
        #expect(UniversalSearch.runTogether("Silksong") == nil)
    }
}
