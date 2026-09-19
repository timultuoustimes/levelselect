import Testing
@testable import LevelSelect

/// `Format.abbreviation` — the mark a coverless card wears.
///
/// The rule is Tim's, given by example: *"hollow knight is HK, Vampire
/// Survivors is VS, Legend of Heroes: Trails of cold steel is LH:TCS."*
/// These are those examples, plus the cases in his own library that decide
/// whether the rule generalises.
struct AbbreviationTests {

    @Test func theExamplesTheRuleWasGivenAs() {
        #expect(Format.abbreviation("Hollow Knight") == "HK")
        #expect(Format.abbreviation("Vampire Survivors") == "VS")
        #expect(Format.abbreviation("The Legend of Heroes: Trails of Cold Steel") == "LH:TCS")
    }

    /// The reason this exists at all. A single initial cannot tell these two
    /// apart, and both are on Home right now.
    @Test func twoGamesThatCollideAsOneLetter() {
        #expect(Format.abbreviation("Hades") != Format.abbreviation("Hollow Knight"))
    }

    /// A numeral is the whole point of the title it is in — an initial would
    /// turn Cat Quest III into CQI and collide it with the first game.
    @Test func numeralsAndRomanNumeralsSurviveWhole() {
        #expect(Format.abbreviation("Cat Quest III") == "CQIII")
        #expect(Format.abbreviation("Sonic the Hedgehog 2") == "SH2")
        #expect(Format.abbreviation("Clair Obscur: Expedition 33") == "CO:E33")
    }

    /// Only a LEADING article goes. Dropping every article everywhere would
    /// make "Rift of the NecroDancer" into RN either way, but a title whose
    /// first word is meaningful must keep it.
    @Test func onlyTheLeadingArticleIsDropped() {
        #expect(Format.abbreviation("The Legend of Zelda") == "LZ")
        #expect(Format.abbreviation("Rift of the NecroDancer") == "RN")
        #expect(Format.abbreviation("A Short Hike") == "SH")
    }

    /// Nothing here may crash or return junk on the shapes real data takes.
    @Test func degenerateTitles() {
        #expect(Format.abbreviation("") == "")
        #expect(Format.abbreviation("   ") == "")
        #expect(Format.abbreviation("the") == "")
        #expect(Format.abbreviation("Hades") == "H")
        #expect(Format.abbreviation("Ori and the Blind Forest") == "OBF")
        #expect(Format.abbreviation("Half-Life 2") == "HL2")
    }

    /// **A title can be arbitrarily long; a mark cannot.**
    ///
    /// The first build of this shipped uncapped, and the sim's copy of the
    /// Trails of Cold Steel entry came out as LH:TCSIVESFEDDSC — sixteen
    /// characters, which at the width of a cover card sets at six points and
    /// is a smear rather than a mark. Three tokens a segment, two segments.
    @Test func aRunawayTitleIsStillAMark() {
        let long = "The Legend of Heroes: Trails of Cold Steel IV - Vespers of Fate and Endless Days of Struggle Continued"
        #expect(Format.abbreviation(long) == "LH:TCS")
    }

    /// The mark has to stay short enough to set on a card. Seven characters is
    /// about where a 108pt cover runs out of width at a readable size.
    @Test func marksStayShort() {
        for title in ["The Legend of Heroes: Trails of Cold Steel",
                      "Teenage Mutant Ninja Turtles: Splintered Fate",
                      "Clair Obscur: Expedition 33",
                      "Umihara Kawase Shun: Steam Edition Deluxe Complete"] {
            let mark = Format.abbreviation(title)
            #expect(mark.count <= 7, Comment(rawValue: "\(title) -> \(mark)"))
        }
    }
}
