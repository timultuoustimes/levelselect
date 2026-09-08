import Testing
import SwiftUI
@testable import LevelSelect

/// Tim's seven pairs: real hexes, black ink readable on every accent, and a
/// lookup that survives the ways a hex gets written.
struct LSPaletteTests {

    @Test("Seven pairs, every hex parses, no two accents alike")
    func pairsAreWellFormed() {
        #expect(LSPalette.pairs.count == 7)
        for p in LSPalette.pairs {
            #expect(Color(hex: p.accent) != nil, Comment(rawValue: "\(p.name) accent"))
            #expect(Color(hex: p.step) != nil, Comment(rawValue: "\(p.name) step"))
        }
        #expect(Set(LSPalette.pairs.map(\.accent)).count == 7)
    }

    @Test("Black knockout ink clears 4.5:1 on every accent — the fill rule")
    func knockoutReadsOnEveryAccent() {
        for p in LSPalette.pairs {
            let ratio = LSContrast.ratio(.black, p.accentColor)
            #expect(ratio >= 4.5, Comment(rawValue: "\(p.name): \(ratio)"))
        }
    }

    @Test("The step reads as ink on the light ground, for every pair")
    func stepReadsOnLight() {
        let light = Color(red: 0.97, green: 0.96, blue: 1.00)
        for p in LSPalette.pairs {
            #expect(LSContrast.ratio(p.stepColor, light) >= 3.0, Comment(rawValue: p.name))
        }
    }

    @Test("Lookup is case- and hash-insensitive, and misses honestly")
    func lookup() {
        #expect(LSPalette.pair(matching: "#f2a24b")?.name == "Torch")
        #expect(LSPalette.pair(matching: "2573DD")?.name == "Blue")
        #expect(LSPalette.pair(matching: "#F5A34D") == nil)   // the old torch is not a pair
        #expect(LSPalette.pair(matching: nil) == nil)
    }
}
