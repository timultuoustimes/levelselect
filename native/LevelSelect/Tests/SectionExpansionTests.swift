import Testing
@testable import LevelSelect

/// **Which game-page sections open, and whose answer wins.**
///
/// Two levels, both synced: a library-wide default the user sets, and a
/// per-game override for the games they have adjusted. The property that makes
/// the pair safe is that a game only stores what it DISAGREES with — otherwise
/// changing the default would leave old games pinned to the old one with
/// nothing on screen to explain it.
struct SectionExpansionTests {

    private let none: Set<GamePageSection> = []

    @Test func theBuiltInSetIsTimsMinimumPlusTheInvitations() {
        let d = GamePageSection.defaultExpanded(stored: nil)
        #expect(d.contains(.info))
        #expect(d.contains(.connections))
        // About is the long one and is deliberately left out — one toggle away.
        #expect(!d.contains(.about))
    }

    /// An empty string is a real answer, not "unset". Someone who turns every
    /// section off must not get the built-in set back.
    @Test func openNothingIsAnAnswer() {
        #expect(GamePageSection.defaultExpanded(stored: "") == none)
        #expect(GamePageSection.defaultExpanded(stored: nil) == GamePageSection.builtInExpanded)
    }

    @Test func aGameOverridesTheDefaultBothWays() {
        let defaults: Set<GamePageSection> = [.info, .connections]
        #expect(GamePageSection.isExpanded(.info, defaults: defaults, overrides: nil))
        #expect(!GamePageSection.isExpanded(.about, defaults: defaults, overrides: nil))
        #expect(!GamePageSection.isExpanded(.info, defaults: defaults, overrides: "info:0"))
        #expect(GamePageSection.isExpanded(.about, defaults: defaults, overrides: "about:1"))
    }

    /// The load-bearing one. A game that agrees with the default stores
    /// nothing, so moving the default moves that game with it.
    @Test func agreeingWithTheDefaultClearsTheOverride() {
        let defaults: Set<GamePageSection> = [.info]
        // Close info on this game — a disagreement, so it is stored.
        let closed = GamePageSection.writingOverride(.info, open: false, into: nil, defaults: defaults)
        #expect(closed == "info:0")
        // Open it again — back in agreement, so the override goes away entirely.
        let reopened = GamePageSection.writingOverride(.info, open: true, into: closed, defaults: defaults)
        #expect(reopened == nil)
    }

    @Test func overridesAccumulateAndStayOrdered() {
        let defaults: Set<GamePageSection> = [.info]
        var raw = GamePageSection.writingOverride(.about, open: true, into: nil, defaults: defaults)
        raw = GamePageSection.writingOverride(.info, open: false, into: raw, defaults: defaults)
        // `allCases` order, not insertion order, so two devices setting the
        // same pair write the same string.
        #expect(raw == "about:1,info:0")
    }

    @Test func junkInTheStringIsIgnoredRatherThanFatal() {
        let map = GamePageSection.overrideMap("about:1,,nonsense,tags:9,info:0")
        #expect(map[.about] == true)
        #expect(map[.info] == false)
        #expect(map[.tags] == false)   // "9" is not "1"
        #expect(map.count == 3)
    }
}
