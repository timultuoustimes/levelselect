import Testing
import Foundation
@testable import LevelSelect

/// Console logos: which file names which console, and the rule that keeps a
/// logo's colors unless they vanish on the ground.
struct ConsoleLogoTests {

    // MARK: - The table

    @Test func everyLoggedConsoleIsOneTheAppNames() {
        // A key the fold never produces is a logo nobody will ever see.
        let names = Set(PlatformKey.everySpelling.map(PlatformKey.canonical))
            .union(["Game Boy", "Virtual Boy", "Xbox", "Steam Deck"])
        for key in ConsoleLogo.byConsole.keys {
            #expect(names.contains(key), "\(key) isn't a name PlatformKey produces")
        }
    }

    @Test func theConsolesPeopleOwnHaveOne() {
        for key in ["Switch", "Switch 2", "PS5", "PS4", "PS3", "PS2", "PS1",
                    "Xbox Series", "Xbox One", "Xbox 360", "3DS", "DS", "Wii U",
                    "Wii", "SNES", "NES", "N64", "GameCube", "GBA", "GBC",
                    "Genesis", "Dreamcast", "Saturn", "PSP", "Vita", "Steam Deck"] {
            #expect(ConsoleLogo.entry(console: key, shown: key) != nil, "\(key)")
        }
    }

    @Test func noLogoMeansTheName() {
        for key in ["PC", "Arcade", "Raspberry Pi", "TurboGrafx-16", "3DO", "Other"] {
            #expect(ConsoleLogo.entry(console: key, shown: key) == nil, "\(key)")
        }
    }

    @Test func publicDomainOnly() {
        let all = Array(ConsoleLogo.byConsole.values) + Array(ConsoleLogo.byRegionalName.values)
        for entry in all {
            #expect(entry.license == "Public domain", "\(entry.file)")
            // The CC BY-SA cube must never come back in.
            #expect(entry.file != "GC Logo.svg")
        }
    }

    @Test func theLogoFollowsTheNameYouChose() {
        #expect(ConsoleLogo.entry(console: "Genesis", shown: "Mega Drive")?.file == "MegaDriveJPLogo.svg")
        #expect(ConsoleLogo.entry(console: "Genesis", shown: "Genesis")?.file == "Sega genesis logo.svg")
        #expect(ConsoleLogo.entry(console: "TurboGrafx-16", shown: "PC Engine")?.file == "PC engine logo red.svg")
        #expect(ConsoleLogo.entry(console: "Master System", shown: "Mark III")?.file == "Sega Mark III logo.svg")
        #expect(ConsoleLogo.entry(console: "Sega CD", shown: "Mega-CD")?.file == "Mega-CD logo.png")
        // Another word for the same logo.
        #expect(ConsoleLogo.entry(console: "NES", shown: "Nintendo")?.file == "NES logo.svg")
        #expect(ConsoleLogo.entry(console: "PS1", shown: "PlayStation")?.file
                == ConsoleLogo.byConsole["PS1"]?.file)
    }

    @Test func theURLAsksCommonsForAPNGAtWidth() throws {
        let url = try #require(ConsoleLogo.byConsole["PS5"]?.url)
        let text = url.absoluteString
        #expect(text.hasPrefix("https://commons.wikimedia.org/w/index.php?"))
        #expect(text.contains("Special:Redirect/file/PlayStation_5_logo_and_wordmark.svg"))
        #expect(text.contains("width=600"))
    }

    // MARK: - Legibility

    private struct Canvas {
        let width: Int, height: Int
        var pixels: [UInt8]
        init(_ width: Int, _ height: Int) {
            self.width = width; self.height = height
            pixels = [UInt8](repeating: 0, count: width * height * 4)
        }
        mutating func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int,
                           _ rgb: (UInt8, UInt8, UInt8)) {
            for y in y0..<y1 { for x in x0..<x1 {
                let i = (y * width + x) * 4
                pixels[i] = rgb.0; pixels[i + 1] = rgb.1; pixels[i + 2] = rgb.2; pixels[i + 3] = 255
            } }
        }
        func rgb(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * width + x) * 4
            return (pixels[i], pixels[i + 1], pixels[i + 2])
        }
        mutating func adapt(_ ground: Double) -> Double {
            LogoLegibility.adapt(&pixels, width: width, height: height,
                                 ground: ground, ink: (240, 240, 240))
        }
    }

    private let black: (UInt8, UInt8, UInt8) = (0, 0, 0)
    private let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
    private let snesRed: (UInt8, UInt8, UInt8) = (230, 0, 18)

    @Test func blackLetteringIsRedrawnOnTheDarkGround() {
        // The PS5 case: black strokes floating on transparency.
        var c = Canvas(40, 20)
        c.fill(4, 4, 10, 16, black)
        c.fill(20, 4, 26, 16, black)
        let share = c.adapt(LogoLegibility.darkGround)
        #expect(share == 1)
        #expect(c.rgb(6, 8) == (240, 240, 240))
    }

    @Test func blackLetteringIsKeptOnTheLightGround() {
        var c = Canvas(40, 20)
        c.fill(4, 4, 10, 16, black)
        #expect(c.adapt(LogoLegibility.lightGround) == 0)
        #expect(c.rgb(6, 8) == black)
    }

    @Test func snesRedIsKeptOnBothGrounds() {
        for ground in [LogoLegibility.darkGround, LogoLegibility.lightGround] {
            var c = Canvas(40, 20)
            c.fill(4, 4, 36, 16, snesRed)
            #expect(c.adapt(ground) == 0)
            #expect(c.rgb(10, 10) == snesRed)
        }
    }

    @Test func onlyThePartThatVanishesIsRedrawn() {
        // Super Famicom: a colored mark that reads, lettering that doesn't.
        var c = Canvas(60, 20)
        c.fill(2, 4, 14, 16, snesRed)
        c.fill(24, 6, 30, 14, black)
        c.fill(36, 6, 42, 14, black)
        _ = c.adapt(LogoLegibility.darkGround)
        #expect(c.rgb(8, 10) == snesRed)
        #expect(c.rgb(26, 10) == (240, 240, 240))
    }

    @Test func lettersInsideAnOutlineStay() {
        // Genesis: black letters enclosed by a white outline.
        var c = Canvas(40, 24)
        c.fill(2, 2, 38, 22, white)
        c.fill(8, 8, 32, 16, black)
        _ = c.adapt(LogoLegibility.darkGround)
        #expect(c.rgb(20, 12) == black)
        #expect(c.rgb(3, 3) == white)
    }

    @Test func aPlateCarryingLetteringIsLeftAlone() {
        // MSX: a dark box with light lettering on it.
        var c = Canvas(40, 24)
        c.fill(0, 0, 40, 24, black)
        c.fill(6, 6, 34, 18, white)
        _ = c.adapt(LogoLegibility.darkGround)
        #expect(c.rgb(1, 1) == black)
        #expect(c.rgb(20, 12) == white)
    }

    @Test func aPlateWithTheLettersCutOutIsRedrawn() {
        // Valve Index: a black box with its letters knocked out to nothing.
        var c = Canvas(40, 24)
        c.fill(0, 0, 40, 24, black)
        for i in stride(from: (6 * 40 + 6) * 4, to: (6 * 40 + 34) * 4, by: 4) { c.pixels[i + 3] = 0 }
        _ = c.adapt(LogoLegibility.darkGround)
        #expect(c.rgb(1, 1) == (240, 240, 240))
    }

    @Test func premultipliedEdgesKeepTheirAlpha() {
        // A half-covered edge pixel of a black stroke: alpha stays, ink scales.
        var c = Canvas(4, 4)
        c.fill(1, 1, 3, 3, black)
        let edge = (1 * 4 + 1) * 4
        c.pixels[edge + 3] = 128
        _ = c.adapt(LogoLegibility.darkGround)
        #expect(c.pixels[edge + 3] == 128)
        #expect(c.pixels[edge] == UInt8((240.0 * 128 / 255).rounded()))
    }
}
