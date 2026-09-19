import Testing
import Foundation
@testable import LevelSelect

/// **Stage 2 — a picker vocabulary, not a classifier.**
///
/// The whole design rests on one line: a suggestion becomes a tag only when
/// somebody taps it, and from that moment it is an ordinary `userTags` string.
/// These tests pin the properties that keep it that way — nothing is applied,
/// nothing is rewritten, and the bundled list stays a READ-side concern.
@MainActor
struct SuggestedTagsTests {

    // MARK: The file itself

    @Test func theVocabularyShipsInTheBundle() {
        #expect(!SuggestedTags.all.isEmpty,
                "SuggestedTags.json did not load — check it reaches the resources phase")
    }

    /// Small and opinionated on purpose. If this ever needs raising, raise it
    /// deliberately; drifting to hundreds is the thing the spec argues against.
    @Test func itStaysASmallVocabulary() {
        #expect(SuggestedTags.all.count >= 30)
        #expect(SuggestedTags.all.count <= 60)
    }

    @Test func idsAndNamesAreUnique() {
        #expect(Set(SuggestedTags.all.map(\.id)).count == SuggestedTags.all.count)
        #expect(Set(SuggestedTags.all.map(\.name)).count == SuggestedTags.all.count)
    }

    @Test func everyTermHasACategory() {
        for tag in SuggestedTags.all {
            #expect(!tag.category.isEmpty, Comment(rawValue: "\(tag.id) has no category"))
            #expect(!tag.name.isEmpty, Comment(rawValue: "\(tag.id) has no name"))
        }
        #expect(SuggestedTags.byCategory.reduce(0) { $0 + $1.tags.count }
                == SuggestedTags.all.count)
    }

    /// **Curated around where IGDB stops.** Repeating a word IGDB already
    /// carries as a genre would offer a term you can browse from the genre
    /// shelf already — and the genre shelf is Stage 1, which shipped.
    @Test func itDoesNotRepeatAnIgdbGenre() {
        let igdbGenres = ["Point-and-click", "Fighting", "Shooter", "Music", "Platform",
                          "Puzzle", "Racing", "Real Time Strategy (RTS)", "RTS",
                          "Role-playing (RPG)", "Simulator", "Sport", "Strategy",
                          "Turn-based strategy (TBS)", "TBS", "Tactical",
                          "Hack and slash/Beat 'em up", "Quiz/Trivia", "Pinball",
                          "Adventure", "Indie", "Arcade", "Visual Novel",
                          "Card & Board Game", "MOBA", "Rhythm"]
        let names = Set(SuggestedTags.all.map { $0.name.lowercased() })
        for genre in igdbGenres {
            #expect(!names.contains(genre.lowercased()),
                    Comment(rawValue: "\(genre) is already an IGDB genre"))
        }
    }

    // MARK: Matching

    @Test func typingFindsATerm() {
        #expect(SuggestedTags.matching("metroid").map(\.name).contains("Metroidvania"))
        #expect(SuggestedTags.matching("METROID").map(\.name).contains("Metroidvania"))
    }

    /// **An alias offers the canonical spelling.** This is what stops one idea
    /// fragmenting into three spellings across a library.
    @Test func anAliasOffersTheCanonicalName() {
        #expect(SuggestedTags.matching("souls-like").map(\.name).contains("Soulslike"))
        #expect(SuggestedTags.canonical("Souls-like") == "Soulslike")
        #expect(SuggestedTags.canonical("ARPG") == "Action RPG")
        #expect(SuggestedTags.canonical("SRPG") == "Tactical RPG")
    }

    @Test func canonicalIsCaseInsensitiveAndExact() {
        #expect(SuggestedTags.canonical("soulslike") == "Soulslike")
        // A partial word is not a canonical form — that is what `matching` is.
        #expect(SuggestedTags.canonical("souls") == nil)
        #expect(SuggestedTags.canonical("something nobody wrote") == nil)
    }

    @Test func anEmptyQueryMatchesNothing() {
        #expect(SuggestedTags.matching("").isEmpty)
        #expect(SuggestedTags.matching("   ").isEmpty)
        #expect(SuggestedTags.matching("#").isEmpty)
    }

    @Test func aLeadingHashIsIgnoredTheWayTheFieldIgnoresIt() {
        #expect(SuggestedTags.matching("#roguelite").map(\.name).contains("Roguelite"))
    }

    // MARK: The rules that keep it a picker

    /// **The vocabulary is read-only about your library.** Nothing here writes
    /// a tag, and `canonical` exists for searching and offering — never for
    /// rewriting what a game already carries. A v2 rename must leave an
    /// existing string alone, which is why the id never reaches a game.
    @Test func anIdIsNeverSomethingAGameStores() {
        let game = Game(name: "Hollow Knight")
        game.userTags = ["Souls-like"]          // a spelling the vocabulary calls an alias
        // The stored text is the user's and stays exactly as written…
        #expect(game.userTags == ["Souls-like"])
        // …while the vocabulary can still tell it is the same idea.
        #expect(SuggestedTags.canonical(game.userTags[0]) == "Soulslike")
        // And no id is anywhere near it.
        #expect(!SuggestedTags.all.map(\.id).contains("Souls-like"))
    }

    /// Two spellings of one idea both resolve, which is what makes filtering
    /// across a mixed library worth anything.
    @Test func twoSpellingsResolveToOneIdea() {
        #expect(SuggestedTags.canonical("Rogue-like") == SuggestedTags.canonical("Roguelike"))
        #expect(SuggestedTags.canonical("Deck-builder") == "Deckbuilder")
    }

    /// An alias must never collide with another term's name, or tapping a
    /// suggestion would be ambiguous.
    @Test func noAliasShadowsADifferentTerm() {
        let names = Dictionary(uniqueKeysWithValues:
            SuggestedTags.all.map { ($0.name.lowercased(), $0.id) })
        for tag in SuggestedTags.all {
            for alias in tag.aliases {
                if let owner = names[alias.lowercased()] {
                    #expect(owner == tag.id,
                            Comment(rawValue: "\(tag.id) claims '\(alias)', which names \(owner)"))
                }
            }
        }
    }
}

/// **The date control is five grains and a switch, not six peers.**
///
/// "Not sure" is the absence of a precision — no grain is stored and only the
/// words say when — so it was never a peer of "Day". As a sixth segment it
/// truncated to "Not s…" at the DEFAULT text size before anyone touched it.
@MainActor
struct Build37PrecisionControlTests {

    @Test func fiveGrainsAreOfferedAndUnsureIsNotOneOfThem() {
        #expect(MemorySheet.HowKnown.grains.count == 5)
        #expect(!MemorySheet.HowKnown.grains.contains(.unsure))
        #expect(MemorySheet.HowKnown.grains == [.day, .month, .season, .year, .decade])
    }

    /// The data model is unchanged — that was the whole argument for the
    /// restructure being cheap.
    @Test func everyGrainStillStoresItsOwnPrecision() {
        #expect(MemorySheet.HowKnown.day.precision == "day")
        #expect(MemorySheet.HowKnown.month.precision == "month")
        #expect(MemorySheet.HowKnown.season.precision == "season")
        #expect(MemorySheet.HowKnown.year.precision == "year")
        #expect(MemorySheet.HowKnown.decade.precision == "decade")
        // Still nil, still the point: "1995 or 1996" is two years and no
        // single grain describes it.
        #expect(MemorySheet.HowKnown.unsure.precision == nil)
    }

    /// Every grain that can be picked has a label short enough to be a
    /// segment. "Not sure" was the long one, and it is no longer a segment.
    @Test func noGrainLabelIsAsLongAsTheOneThatTruncated() {
        for grain in MemorySheet.HowKnown.grains {
            #expect(grain.label.count <= "Not sure".count - 1,
                    Comment(rawValue: "\(grain.label) is as wide as the label that truncated"))
        }
    }
}
