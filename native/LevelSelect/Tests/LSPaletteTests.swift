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

    @Test("Pink's step is the one Tim corrected, and every step is darker than its accent")
    func stepsAreAuthored() {
        #expect(LSPalette.pair(matching: "#FF74D9")?.step == "#6B1B6D")
        for p in LSPalette.pairs {
            #expect(LSContrast.luminance(of: p.stepColor) < LSContrast.luminance(of: p.accentColor),
                    Comment(rawValue: p.name))
        }
    }

    // The step is also the ink on the accent itself — "Start Session" on the
    // red button. Tim re-authored the set on 2026-09-09 after red's old step
    // (#7E3047) sat at 2.12:1 there and read as maroon-on-red; the floor is
    // the same 3:1 the light ground gets, and the weakest pairs sit at 3.6.
    // Torch is left out on purpose: its step (#A55410) is the brand's torch
    // shadow, kept as Tim authored it, and it sits at 2.59:1 on its own
    // accent. Whether the default pair ever writes its step on its own fill
    // is Tim's call (2026-09-09), not this test's.
    @Test("The step reads as ink on its own accent, for every pair but Torch")
    func stepReadsOnAccent() {
        for p in LSPalette.pairs where p.name != "Torch" {
            let ratio = LSContrast.ratio(p.stepColor, p.accentColor)
            #expect(ratio >= 3.0, Comment(rawValue: "\(p.name): \(ratio)"))
        }
    }

    @Test("The ground is the pair laid over the base: purple reproduces Tim's sheet, and no tint means purple")
    func groundIsAnOverlay() throws {
        let purple = LSPalette.pair(matching: "#976EF5")!
        let dark = try #require(LSPalette.ground(tint: purple.accentColor, dark: true).lsRGB)
        let light = try #require(LSPalette.ground(tint: purple.accentColor, dark: false).lsRGB)
        // #2E214F and #F0E5FE on the sheet; within a few units either way.
        #expect(abs(dark.r - 0x2E / 255.0) < 0.03 && abs(dark.g - 0x21 / 255.0) < 0.03 && abs(dark.b - 0x4F / 255.0) < 0.03)
        #expect(abs(light.r - 0xF0 / 255.0) < 0.03 && abs(light.g - 0xE5 / 255.0) < 0.03 && abs(light.b - 0xFE / 255.0) < 0.03)
        // Nothing stored is the same as purple.
        #expect(LSPalette.ground(tint: nil, dark: true).hexString() == LSPalette.ground(tint: purple.accentColor, dark: true).hexString())
        // Every pair's dark ground stays dark and light ground stays light —
        // the overlay cannot take the base past legibility.
        for p in LSPalette.pairs {
            #expect(LSContrast.luminance(of: LSPalette.ground(tint: p.accentColor, dark: true)) < 0.1, Comment(rawValue: p.name))
            #expect(LSContrast.luminance(of: LSPalette.ground(tint: p.accentColor, dark: false)) > 0.7, Comment(rawValue: p.name))
        }
    }

    @Test("Lookup is case- and hash-insensitive, and misses honestly")
    func lookup() {
        #expect(LSPalette.pair(matching: "#f5a34d")?.name == "Torch")
        #expect(LSPalette.pair(matching: "2573DD")?.name == "Blue")
        // The old drifted Torch hex from the build-37 picker; the brand
        // torch #F5A34D IS the Torch pair since 2026-09-09.
        #expect(LSPalette.pair(matching: "#F2A24B") == nil)   // the old torch is not a pair
        #expect(LSPalette.pair(matching: nil) == nil)
    }
}
