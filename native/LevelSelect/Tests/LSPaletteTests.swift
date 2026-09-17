import Testing
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
@testable import LevelSelect

/// Tim's seven pairs plus Mono: real hexes, black ink readable on every
/// accent, and a lookup that survives the ways a hex gets written.
struct LSPaletteTests {

    @Test("Eight pairs, every hex parses, no two accents alike")
    func pairsAreWellFormed() {
        #expect(LSPalette.pairs.count == 8)
        for p in LSPalette.pairs {
            #expect(Color(hex: p.accent) != nil, Comment(rawValue: "\(p.name) accent"))
            #expect(Color(hex: p.step) != nil, Comment(rawValue: "\(p.name) step"))
        }
        #expect(Set(LSPalette.pairs.map(\.accent)).count == 8)
    }

    /// **"Use the default" must land on the first swatch.**
    ///
    /// It did not: clearing the stored hexes left no pair matched, so the app
    /// fell back to two build-37 constants and ran them through the legacy
    /// contrast correction. `LSTheme.torchInk` had drifted to #996630 where
    /// Torch's authored step is #A55410, so the light accent came back a brown
    /// that is not in the palette, and the dark one came back re-derived
    /// against whatever ground was stored. Tim hit it on King Kai, 09-09.
    @Test("The default accent is the first swatch, and its colors are the pair's")
    func theDefaultIsTheFirstSwatch() {
        #expect(LSPalette.defaultAccent.name == LSPalette.pairs[0].name)
        #expect(LSPalette.defaultAccent.name == "Torch")
        // The two values the editor and the app both read for "no choice".
        #expect(LSPalette.defaultAccent.accent == "#F5A34D")
        #expect(LSPalette.defaultAccent.step == "#A55410")
        // And it is a real pair, so it resolves back to itself — which is what
        // makes "no choice" and "tapped the first circle" the same state.
        #expect(LSPalette.pair(matching: LSPalette.defaultAccent.accent)?.name == "Torch")
    }

    /// **The whole default look is two pairs, and the picker can say so.**
    ///
    /// The first fix pointed the ACCENT at `defaultAccent` and stopped there.
    /// The ground kept a loose `LSTheme.purpleDeep`, which is not the purple
    /// `LSPalette.ground(tint: nil,)` actually lays down — so the Background
    /// half of the editor offered a default it could not produce, ticked no
    /// circle for it, and "Use the default" looked like it had done nothing.
    /// Tim, on King Kai: *"I hit use default for accent and background, but it
    /// didn't work at all."*
    ///
    /// Both halves of the default must be PAIR hexes, because a pair hex is
    /// the only thing the circles can tick and the only thing `ThemePalette`
    /// resolves without going through the legacy correction.
    @Test("An untouched library's colors are both palette pairs")
    func theEmptyLibraryIsTwoPairs() throws {
        // The accent, on both grounds — the pair's accent hex is what a tap
        // stores, and the step is derived from it rather than stored.
        #expect(LSPalette.pair(matching: LSPalette.defaultAccent.accent)?.name == "Torch")
        // The ground the app draws when nothing is stored, and the tint the
        // editor now hands back for "unset", have to be the same color.
        #expect(LSPalette.defaultGround.name == "Purple")
        #expect(LSPalette.pair(matching: LSPalette.defaultGround.accent)?.name == "Purple")
        for dark in [true, false] {
            for bottom in [true, false] {
                let unset = try #require(
                    LSPalette.ground(tint: nil, dark: dark, bottom: bottom).lsRGB)
                let asPair = try #require(
                    LSPalette.ground(tint: LSPalette.defaultGround.accentColor,
                                     dark: dark, bottom: bottom).lsRGB)
                #expect(abs(unset.r - asPair.r) < 0.001
                        && abs(unset.g - asPair.g) < 0.001
                        && abs(unset.b - asPair.b) < 0.001,
                        Comment(rawValue: "dark \(dark) bottom \(bottom)"))
            }
        }
    }

    /// **No pair's step is any pair's accent.**
    ///
    /// `pair(matching:)` looks at the accents first and the steps second, so
    /// that a hex written by the build that stored the light INK still
    /// resolves to the pair it came from. The two passes can only stay
    /// consistent while the two sets are disjoint — one overlap and the same
    /// hex would mean two different pairs depending on which loop saw it.
    @Test("No step collides with an accent, so the lookup cannot be ambiguous")
    func noStepIsAnyPairsAccent() {
        let accents = Set(LSPalette.pairs.map { LSPalette.normalized($0.accent) })
        let steps = Set(LSPalette.pairs.map { LSPalette.normalized($0.step) })
        #expect(accents.isDisjoint(with: steps))
        #expect(steps.count == LSPalette.pairs.count)
        // And the fallback actually resolves, since that is the point.
        for p in LSPalette.pairs {
            #expect(LSPalette.pair(matching: p.step)?.name == p.name,
                    Comment(rawValue: "\(p.name) step"))
        }
    }

    /// **The high-contrast pair, and the reason it needed a branch.**
    ///
    /// Mono is the seven's shape with the hue taken out: a light-grey accent
    /// that is the ink on dark, a charcoal step that is the ink on light. The
    /// ground is the part that could not be derived — the shared bases lean
    /// blue on dark and lavender on light, which is right under a hue and
    /// wrong under a grey.
    @Test("Mono's ground is actually neutral, and it out-contrasts all seven")
    func monoIsTheHighContrastPair() throws {
        let mono = try #require(LSPalette.pairs.first { $0.name == LSPalette.neutralPairName })

        // Neutral means the three channels are equal — not merely close.
        for dark in [true, false] {
            for bottom in [true, false] {
                let g = try #require(LSPalette.ground(tint: mono.accentColor,
                                                      dark: dark, bottom: bottom).lsRGB)
                #expect(abs(g.r - g.g) < 0.002 && abs(g.g - g.b) < 0.002,
                        Comment(rawValue: "dark:\(dark) bottom:\(bottom) → \(g)"))
            }
        }

        // A colored pair through the same call is NOT neutral, which is what
        // makes the branch worth having rather than a no-op.
        let purple = try #require(LSPalette.pairs.first { $0.name == "Purple" })
        let pg = try #require(LSPalette.ground(tint: purple.accentColor, dark: true).lsRGB)
        #expect(abs(pg.b - pg.r) > 0.05, "the seven keep their cast")

        // Both directions clear AAA, which none of the seven do.
        let onDark = LSContrast.ratio(mono.accentColor,
                                      LSPalette.ground(tint: mono.accentColor, dark: true))
        let onLight = LSContrast.ratio(mono.stepColor,
                                       LSPalette.ground(tint: mono.accentColor, dark: false))
        #expect(onDark >= 7.0, Comment(rawValue: "light grey on charcoal: \(onDark)"))
        #expect(onLight >= 7.0, Comment(rawValue: "charcoal on light grey: \(onLight)"))
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

/// **A pair for light and a different one for dark.**
///
/// The two hexes have been separate deployed fields since build 37, and every
/// resolved value in `ThemePalette` was already `.lsDynamic`; all that was
/// missing was reading them as two choices rather than one written twice.
/// Tim, 2026-09-09: *"can we make it so that I can pick one set of colors for
/// light mode and another set for dark mode, and then they auto switch
/// between them when the system switches?"*
@MainActor
struct PerAppearancePairTests {

    private func settings(light: String? = nil, dark: String? = nil) -> ThemeSettings {
        let s = ThemeSettings()
        s.accentHexLight = light
        s.accentHexDark = dark
        return s
    }

    @Test("Light and dark resolve to their own pairs")
    func eachAppearanceKeepsItsOwnPair() throws {
        let blue = try #require(LSPalette.pairs.first { $0.name == "Blue" })
        let pink = try #require(LSPalette.pairs.first { $0.name == "Pink" })
        ThemePalette.refresh(from: settings(light: blue.accent, dark: pink.accent))

        #expect(ThemePalette.activePair?.name == "Blue")
        #expect(ThemePalette.activePairDark?.name == "Pink")
        #expect(ThemePalette.accentIsAPair)
    }

    /// **The fallthrough this replaces.** `pair(matching: light) ?? pair(matching:
    /// dark)` meant a library that had only ever set a dark accent wore that
    /// choice on BOTH grounds — so the light default was unreachable without
    /// setting light explicitly to the thing it already should have been.
    @Test("An unset appearance keeps the default rather than inheriting the other")
    func oneSideSetLeavesTheOtherOnTheDefault() throws {
        let green = try #require(LSPalette.pairs.first { $0.name == "Green" })
        ThemePalette.refresh(from: settings(dark: green.accent))

        #expect(ThemePalette.activePairDark?.name == "Green")
        #expect(ThemePalette.activePair?.name == LSPalette.defaultAccent.name)
    }

    /// Nothing stored anywhere is the first swatch on both, which is what the
    /// empty library wears and what "Use the default colors" restores.
    @Test("Nothing stored is the default pair on both grounds")
    func nothingStoredIsTheDefaultOnBoth() {
        ThemePalette.refresh(from: settings())
        #expect(ThemePalette.activePair?.name == "Torch")
        #expect(ThemePalette.activePairDark?.name == "Torch")
    }

    /// A hex that belongs to no pair is still a custom color, per appearance,
    /// and still goes through the legibility correction rather than being
    /// quietly rounded to a swatch.
    @Test("A custom hex on one side does not make the other side custom")
    func aCustomColorStaysOnItsOwnSide() throws {
        let red = try #require(LSPalette.pairs.first { $0.name == "Red" })
        ThemePalette.refresh(from: settings(light: "#123456", dark: red.accent))

        #expect(ThemePalette.activePair == nil)
        #expect(ThemePalette.activePairDark?.name == "Red")
        #expect(ThemePalette.accentIsAPair)
    }

    /// The step a build-38 Cancel could have committed to the light hex still
    /// names its pair — see `LSPalette.pair(matching:)`.
    @Test("A stored step resolves to the pair it is half of")
    func aStoredStepIsNotACustomColor() throws {
        let yellow = try #require(LSPalette.pairs.first { $0.name == "Yellow" })
        ThemePalette.refresh(from: settings(light: yellow.step, dark: yellow.accent))
        #expect(ThemePalette.activePair?.name == "Yellow")
        #expect(ThemePalette.activePairDark?.name == "Yellow")
    }
}

/// **Every surface takes the tint of the appearance it is drawn in.**
///
/// The ground learned this in build 37 and the hero did not: `hero(tintedBy:)`
/// shaded BOTH branches of every dynamic color from one tint, and its caller
/// handed it `ThemePalette.backgroundOverride` — which is the DARK value, by
/// design. So a green dark ground turned the Continue Playing card green on a
/// light page. Tim, 2026-09-09: *"the home hero on light mode's background
/// changes to whatever I pick as the dark background color but shows as
/// light."*
///
/// `hero` now demands both tints, so that call cannot be written any more.
/// What is left to guard is the ingredient: `backgroundOverride` is a
/// compatibility accessor for ONE thing — the legacy `backgroundHex` key in
/// the widget snapshot — and any drawing code that reaches for it is
/// reintroducing the bug. Read off the source, because the mistake is a value
/// arriving somewhere it should not; a `LinearGradient` will not tell you what
/// it was built from, and a test that tried to reflect on one asserted
/// nothing at all.
@MainActor
struct HeroTintTests {

    @Test("Nothing that draws reaches for the dark-only background override")
    func onlyTheLegacyWidgetKeyUsesTheDarkOnlyOverride() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        // Where a per-appearance mistake would actually be visible. The
        // legitimate use lives in Services/WidgetBridge.swift, which is not
        // scanned.
        let dirs = ["LevelSelect/UI", "Shared"]

        var offenders: [String] = []
        for dir in dirs {
            let base = root.appendingPathComponent(dir)
            let names = try FileManager.default
                .contentsOfDirectory(atPath: base.path).filter { $0.hasSuffix(".swift") }
            #expect(!names.isEmpty, Comment(rawValue: "no sources found in \(dir)"))
            for name in names {
                let text = try String(contentsOf: base.appendingPathComponent(name),
                                      encoding: .utf8)
                for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                    guard line.contains("ThemePalette.backgroundOverride"),
                          !line.contains("ThemePalette.backgroundOverrideLight"),
                          !line.contains("ThemePalette.backgroundOverrideDark"),
                          // The accessor's own declaration.
                          !line.contains("static var backgroundOverride")
                    else { continue }
                    offenders.append("\(dir)/\(name):\(i + 1)")
                }
            }
        }
        #expect(offenders.isEmpty,
                Comment(rawValue: "read backgroundOverrideLight / -Dark instead: "
                        + offenders.joined(separator: ", ")))
    }

    /// The hero takes two tints and no longer offers a one-tint shortcut, so
    /// the original call is not expressible. Pinned as source too, because
    /// "someone re-adds the convenience overload" is exactly how it comes back.
    @Test("The hero exposes no single-tint entry point")
    func theHeroCannotBeGivenOneTint() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Shared/LSSurfaces.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("static func hero(lightTint: Color?, darkTint: Color?)"))
        #expect(!text.contains("static func hero(tintedBy:"))
        #expect(!text.contains("func hero(tintedBy tint:"))
    }
}

/// **A chosen ground reaches every page, or it reaches none of them.**
///
/// `LSTheme.background` is `ground(tintedBy: nil)` — the built-in purple. It
/// exists for the WIDGET target, which cannot read `ThemeSettings`. A page in
/// the app that stands on it silently ignores the ground you picked, and the
/// app then disagrees with itself one screen at a time: Home in your color,
/// the game page in the default. Tim, 2026-09-09, with the two side by side:
/// *"that game page is after choosing the red background color, so that means
/// it's not carrying to every page."*
///
/// `LSTheme.liveGround`'s own doc comment had said this since build 38 — *"a
/// page in the app should stand on THIS, or a chosen ground stops at Home"* —
/// which is exactly why it is a test now instead of a sentence.
@MainActor
struct GroundReachTests {

    @Test("No app surface stands on the untinted default ground")
    func everyPageStandsOnTheChosenGround() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        // Shared and Widgets are exempt on purpose: `background` is what the
        // widget target uses, and it is declared in Shared.
        let dirs = ["LevelSelect/UI", "LevelSelect/App"]

        var offenders: [String] = []
        for dir in dirs {
            let base = root.appendingPathComponent(dir)
            let names = try FileManager.default
                .contentsOfDirectory(atPath: base.path).filter { $0.hasSuffix(".swift") }
            #expect(!names.isEmpty, Comment(rawValue: "no sources found in \(dir)"))
            for name in names {
                let text = try String(contentsOf: base.appendingPathComponent(name),
                                      encoding: .utf8)
                for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.hasPrefix("//") else { continue }
                    // `LSTheme.background` exactly — `backgroundOverrideLight`
                    // and friends live on ThemePalette and are the right way
                    // to read a chosen tint.
                    guard let r = line.range(of: "LSTheme.background") else { continue }
                    let after = line[r.upperBound...].first
                    guard after == nil || !(after!.isLetter || after! == "_") else { continue }
                    offenders.append("\(dir)/\(name):\(i + 1)")
                }
            }
        }
        #expect(offenders.isEmpty,
                Comment(rawValue: "use LSTheme.liveGround (a page) or liveSheetGround "
                        + "(a sheet or popover): " + offenders.joined(separator: ", ")))
    }
}

/// Pins linked to a tracker item wear their category: Tim, 09-08, *"custom
/// names for pin types (based on tracker category names)… and multiple pin
/// icons for different things, not just colors."*
struct PinStyleTests {

    /// A misspelled SF Symbol draws nothing and throws nothing. The only way
    /// to know every name in the table is real is to ask for each one.
    @Test("Every icon a category can get is a real symbol")
    func everySymbolExists() {
        for name in PinStyle.allSymbols {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                    "\(name) is not an SF Symbol")
        }
    }

    @Test("Hollow Knight's own categories read as what they are")
    func hollowKnightCategories() {
        #expect(PinStyle.symbol(forCategory: "Main Bosses") == "crown.fill")
        #expect(PinStyle.symbol(forCategory: "Dream Bosses") == "crown.fill")
        #expect(PinStyle.symbol(forCategory: "Grubs") == "ladybug.fill")
        #expect(PinStyle.symbol(forCategory: "Mask Shards") == "heart.fill")
        #expect(PinStyle.symbol(forCategory: "Vessel Fragments") == "drop.fill")
        #expect(PinStyle.symbol(forCategory: "Charms") == "sparkles")
        #expect(PinStyle.symbol(forCategory: "King's Idols") == "seal.fill")
        #expect(PinStyle.symbol(forCategory: "Colosseum of Fools") == "building.columns.fill")
    }

    /// Substring matching found "ring" inside "whispering" and made the roots
    /// a charm. Keys match the start of a word.
    @Test("A key matches the start of a word, not the middle of one")
    func matchesWordStarts() {
        #expect(PinStyle.symbol(forCategory: "Whispering Roots") == "leaf.fill")
        #expect(PinStyle.symbol(forCategory: "Monkeys") == PinStyle.fallback)
    }

    @Test("A category nothing recognizes still gets a pin")
    func fallsBack() {
        #expect(PinStyle.symbol(forCategory: "Miscellaneous") == PinStyle.fallback)
        #expect(PinStyle.symbol(forCategory: "") == PinStyle.fallback)
    }

    /// `hashValue` is reseeded every launch, so a category colored by it would
    /// change color each time the app opened. These are djb2's own answers.
    @Test("A category's color is the same every launch")
    func colorIsStable() {
        #expect(PinStyle.paletteIndex(for: "a", count: 10) == 0)   // 5381·33 + 97 = 177670
        #expect(PinStyle.paletteIndex(for: "b", count: 10) == 1)   // 177671
        for id in ["grubs", "bosses", "c1", ""] {
            let slot = PinStyle.paletteIndex(for: id, count: 7)
            #expect((0..<7).contains(slot))
        }
    }
}

struct PinStyleChoiceTests {
    @Test("Everything the picker offers is a real symbol, offered once")
    func choicesExist() {
        for name in PinStyle.choices {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                    "\(name) is not an SF Symbol")
        }
        #expect(Set(PinStyle.choices).count == PinStyle.choices.count)
    }

    @Test("A chosen pin wins over the one read from the name")
    func choiceWins() {
        let chosen = Self.category(symbol: "moon.stars.fill", color: "purple")
        #expect(PinStyle.symbol(for: chosen) == "moon.stars.fill")
        #expect(PinStyle.colorName(for: chosen) == "purple")
        // "Warrior Graves" — the list nothing in the table recognizes.
        #expect(PinStyle.symbol(for: Self.category(symbol: nil, color: nil)) == PinStyle.fallback)
    }

    /// Making colors choosable must not repaint anyone's existing pins.
    @Test("Automatic colors are the palette they always were")
    func automaticColorsUnchanged() {
        #expect(Array(PinStyle.colorNames.prefix(PinStyle.automaticColorCount))
                == ["orange", "teal", "pink", "yellow", "mint", "cyan", "indigo", "brown", "green", "coral"])
        #expect(PinStyle.colorName(for: Self.category(symbol: nil, color: nil))
                == PinStyle.colorNames[PinStyle.paletteIndex(for: "graves", count: 10)])
    }

    @Test("A stored color the app doesn't know falls back to automatic")
    func unknownColorFallsBack() {
        #expect(PinStyle.colorName(for: Self.category(symbol: nil, color: "chartreuse"))
                == PinStyle.colorNames[PinStyle.paletteIndex(for: "graves", count: 10)])
    }

    @Test("Endings read as an ending; Warrior Graves is left for the user")
    func endings() {
        #expect(PinStyle.symbol(forCategory: "Endings") == "flag.checkered")
        #expect(PinStyle.symbol(forCategory: "Warrior Graves") == PinStyle.fallback)
    }

    private static func category(symbol: String?, color: String?) -> TrackerCategoryDTO {
        var cat: [String: Any] = ["id": "graves", "name": "Warrior Graves",
                                  "items": [["id": "xero", "name": "Xero"]]]
        if let symbol { cat["pinSymbol"] = symbol }
        if let color { cat["pinColor"] = color }
        let data = try! JSONSerialization.data(withJSONObject: ["categories": [cat]])
        return TrackerSchemaJSON.categories(from: data)[0]
    }
}
