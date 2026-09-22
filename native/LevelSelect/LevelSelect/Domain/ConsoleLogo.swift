import Foundation

/// **A console's logo, as its name on its own page.**
///
/// Tim, 09-18: *"So many consoles have such distinct logos that it feels a
/// shame to not display them prominently on the console's page."* The spec is
/// `LevelSelect console logos 2026-09-18` in the vault.
///
/// **Chosen by hand, from Wikimedia Commons.** The spec proposed asking
/// Wikidata's P154 through `wikidata-proxy` with a table of overrides on top.
/// Doing the pass showed the overrides would be most of the table: Wikidata
/// lists three GameCube files (one CC BY-SA), the NES item's logo list leads
/// with the Famicom's, the TurboGrafx-16's is a JPEG with no transparency, and
/// the Super Famicom and Mega Drive only have one there by accident. So the
/// table is the whole answer: every file was looked at on both grounds and
/// every license read (09-21), and nothing changes server-side. A console not
/// in it shows its name, as it always has.
///
/// **Public domain only.** Every file here is a simple wordmark Commons marks
/// public domain ("PD-textlogo"). The marks are still their owners'
/// trademarks — naming the console with its own logo is the use game pages
/// already make of IGDB's wordmarks. Don't alter one beyond recoloring for
/// legibility, and don't use them decoratively elsewhere.
enum ConsoleLogo {

    struct Entry: Equatable, Sendable {
        /// The file's name on Commons, spaces and all.
        let file: String
        /// As Commons records it. Kept so the tests can hold the line.
        let license: String
        /// **Drawn as it comes, on both grounds.** For the few logos the
        /// measurement gets wrong: light by design, and made to be read on
        /// white. Tim, 09-21, with a photo of the white Xbox 360 box: *"Xbox
        /// 360 and Xbox logos should both be fine on white as they originally
        /// were."* The rule had turned the 360's silver sphere into a dark dot.
        let keepsColors: Bool

        init(_ file: String, license: String = "Public domain", keepsColors: Bool = false) {
            self.file = file
            self.license = license
            self.keepsColors = keepsColors
        }

        /// A PNG render at a width Commons picks near the one asked for — it
        /// rasterizes the SVG, so the app never parses one.
        var url: URL? {
            let title = file.replacingOccurrences(of: " ", with: "_")
            var parts = URLComponents(string: "https://commons.wikimedia.org/w/index.php")
            parts?.queryItems = [
                URLQueryItem(name: "title", value: "Special:Redirect/file/\(title)"),
                URLQueryItem(name: "width", value: "600"),
            ]
            return parts?.url
        }
    }

    /// Keyed by the app's short name (`PlatformKey.canonical`).
    static let byConsole: [String: Entry] = [
        "Switch":               Entry("Nintendo Switch logo.svg"),
        "Switch 2":             Entry("Nintendo Switch 2 logo.svg"),
        "PS5":                  Entry("PlayStation 5 logo and wordmark.svg"),
        "PS4":                  Entry("PlayStation 4 logo and wordmark.svg"),
        "PS3":                  Entry("PlayStation 3 logo (2009).svg"),
        "PS2":                  Entry("PlayStation 2 logo.svg"),
        "PS1":                  Entry("PlayStation wordmark (1994-2009).svg"),
        "PSP":                  Entry("PSP Logo.svg"),
        "Vita":                 Entry("PlayStation Vita logo.svg"),
        "PlayStation VR":       Entry("PlayStation VR logo.svg"),
        "PlayStation VR2":      Entry("PlayStation VR2 logo.svg"),
        // The green badge rather than the black wordmark: it reads on either
        // ground without being redrawn.
        "Xbox Series":          Entry("Xbox Series X S color.svg"),
        "Xbox One":             Entry("X Box One logo.svg"),
        "Xbox 360":             Entry("X Box 360 logo.svg", keepsColors: true),
        "Xbox":                 Entry("Xbox Logo 2001.svg", keepsColors: true),
        "3DS":                  Entry("Nintendo 3DS logo.svg"),
        "DS":                   Entry("Nintendo DS Logo.svg"),
        "Wii U":                Entry("WiiU.svg"),
        "Wii":                  Entry("Wii.svg"),
        "SNES":                 Entry("SNES logo.svg"),
        "Super Famicom":        Entry("Nintendo Super Famicom logo.svg"),
        "NES":                  Entry("NES logo.svg"),
        "Famicom":              Entry("Family Computer logo.svg"),
        "Famicom Disk System":  Entry("Family Computer Disk System logo.png"),
        "N64":                  Entry("Nintendo 64 wordmark.svg"),
        // The public-domain one. "GC Logo.svg", the cube alone, is CC BY-SA
        // and would need attribution on screen.
        "GameCube":             Entry("Nintendo GameCube Official Logo.svg"),
        "Game Boy":             Entry("Nintendo Game Boy Logo.svg"),
        "GBA":                  Entry("Game Boy Advance logo.svg"),
        "GBC":                  Entry("Game Boy Color logo.svg"),
        "Virtual Boy":          Entry("Virtualboy logo.svg"),
        "Satellaview":          Entry("Satellaview logo.svg"),
        "Game & Watch":         Entry("Game and watch logo.svg"),
        "Genesis":              Entry("Sega genesis logo.svg"),
        "Master System":        Entry("Master System Logo.svg"),
        "Sega CD":              Entry("Sega CD Logo.svg"),
        "Sega 32X":             Entry("Sega 32X logo.svg"),
        "Saturn":               Entry("Sega Saturn USA logo.svg"),
        "Dreamcast":            Entry("Dreamcast logo.svg"),
        "Game Gear":            Entry("Game Gear logo Sega.png"),
        // No TurboGrafx-16 entry: Commons' only one is a JPEG, which has no
        // transparency and would sit on the page as a white card. It shows
        // its name — and the PC Engine logo when it's called that.
        "Atari 2600":           Entry("Atari2600logo.svg"),
        "Atari 5200":           Entry("Atari 5200 logo.svg"),
        "Atari 7800":           Entry("Atari 7800 logo.svg"),
        "Atari Lynx":           Entry("Atari Lynx logo.svg"),
        "Atari Jaguar":         Entry("Atari Jaguar logo.svg"),
        "Amiga":                Entry("Commodore Amiga logo-03.svg"),
        "Amiga CD32":           Entry("Amigacd32-logo.svg"),
        "Commodore 64":         Entry("Commodore 64 logo-00.svg"),
        // The wordmark, not the mascot Wikidata lists — the mascot is a
        // character, not a name.
        "Neo Geo AES":          Entry("Neo Geo logo (old).svg"),
        "Neo Geo MVS":          Entry("Neo Geo logo (old).svg"),
        "Neo Geo Pocket Color": Entry("Neo Geo Pocket Color logo.svg"),
        "Intellivision":        Entry("Intellivision-logo.svg"),
        "ColecoVision":         Entry("COLECO VISION LOGO.svg"),
        "Vectrex":              Entry("Vectrex logo.png"),
        "ZX Spectrum":          Entry("Sinclair ZX Spectrum-02b.svg"),
        "MSX":                  Entry("MSX-Logo.svg"),
        "Amstrad CPC":          Entry("Amstrad CPC logo.svg"),
        "FM Towns":             Entry("FM TOWNS logo.svg"),
        "WonderSwan":           Entry("WonderSwan logo text.png"),
        "WonderSwan Color":     Entry("Wonderswan-Color-Logo.svg"),
        "Stadia":               Entry("Google Stadia logo.svg"),
        "Ouya":                 Entry("Ouya Logo (Color).svg"),
        "Valve Index":          Entry("Valve Index logo.svg"),
        "Steam Deck":           Entry("Steam Deck colored logo.svg"),
    ]

    /// **The logo follows the name you chose** in Settings → System names.
    /// Keyed by the shown name; a name not here (Nintendo, Super Nintendo,
    /// PlayStation) is the same machine sold under the same logo.
    static let byRegionalName: [String: Entry] = [
        "Mega Drive": Entry("MegaDriveJPLogo.svg"),
        "Mark III":   Entry("Sega Mark III logo.svg"),
        "PC Engine":  Entry("PC engine logo red.svg"),
        "Mega-CD":    Entry("Mega-CD logo.png"),
    ]

    /// The logo for a console, given its short name and the name it's shown
    /// under. Nil means draw the name.
    static func entry(console short: String, shown: String) -> Entry? {
        if shown != short, let regional = byRegionalName[shown] { return regional }
        return byConsole[short]
    }
}

/// **Keep a logo's own colors unless they vanish on the ground.**
///
/// The spec's rule: SNES red, the Saturn's globe and the Dreamcast swirl stay
/// as they are; the black ones — PS5, the Steam Deck's lettering — are drawn
/// in the text color instead. Decided per appearance by measuring, never by a
/// hand list.
///
/// **Only the parts that vanish, and only where they touch the ground.** A
/// whole-logo rule broke half the table, measured 09-21:
///
/// - *PS2, the 3DS, Super Famicom, the Steam Deck* are mixed — colored parts
///   that read and black lettering that doesn't. Redrawing the whole thing
///   lost the Super Famicom's four dots to make its lettering legible.
///   Redrawing just the black lettering keeps both.
/// - *Genesis and the Commodore 64* have black letters inside a white
///   outline. Those letters don't touch the ground — the outline does, and
///   it reads — so they stay black.
/// - *MSX, the GameCube badge, Neo Geo MVS* are a dark box carrying light
///   lettering. The box vanishes into a dark ground but the lettering reads,
///   and whitening the box would bury it. A dark region with lettering of its
///   own inside it is a plate and is left alone. *Valve Index* is a box with
///   the letters cut out — nothing legible inside — so it is redrawn whole.
///
/// Pure, over RGBA bytes, so it runs off the main actor and tests without an
/// image framework.
enum LogoLegibility {

    /// The ground's relative luminance per appearance. The app's charcoal
    /// purple and its lavender, before any tint — close enough that a tinted
    /// ground doesn't change a single decision in the table.
    static let darkGround = 0.012
    static let lightGround = 0.80

    /// Below this contrast against the ground, a pixel is lost.
    static let legibleContrast = 2.0

    /// A dark region counts as a plate when this share of its bounding box
    /// is lettering that reads.
    static let plateLettering = 0.08

    /// Rewrites, in place, the pixels that vanish on a ground of luminance
    /// `ground` to `ink` (RGB, 0–255), keeping their alpha. Premultiplied or
    /// straight doesn't matter for the decision; the rewrite keeps each
    /// pixel's alpha and scales `ink` by it when `premultiplied`.
    ///
    /// Returns the share of visible pixels that were redrawn.
    @discardableResult
    static func adapt(_ pixels: inout [UInt8], width: Int, height: Int,
                      ground: Double, ink: (UInt8, UInt8, UInt8),
                      premultiplied: Bool = true) -> Double {
        let count = width * height
        guard count > 0, pixels.count >= count * 4 else { return 0 }

        var visible = [Bool](repeating: false, count: count)
        var lost = [Bool](repeating: false, count: count)
        var legible = [Bool](repeating: false, count: count)
        var visibleCount = 0

        for i in 0..<count {
            let a = Double(pixels[i * 4 + 3]) / 255
            guard a > 0.1 else { continue }
            visible[i] = true
            visibleCount += 1
            // Un-premultiply to judge the color itself.
            let scale = premultiplied ? 1 / a : 1
            let l = luminance(Double(pixels[i * 4]) * scale,
                              Double(pixels[i * 4 + 1]) * scale,
                              Double(pixels[i * 4 + 2]) * scale)
            if contrast(l, ground) < legibleContrast {
                lost[i] = true
            } else if a > 0.5 {
                legible[i] = true
            }
        }

        var seen = [Bool](repeating: false, count: count)
        var redrawn = 0
        var stack: [Int] = []
        var region: [Int] = []

        for start in 0..<count where lost[start] && !seen[start] {
            // One connected region of lost pixels.
            stack.removeAll(keepingCapacity: true)
            region.removeAll(keepingCapacity: true)
            stack.append(start)
            seen[start] = true
            var touchesGround = false
            var minX = width, maxX = 0, minY = height, maxY = 0
            while let i = stack.popLast() {
                region.append(i)
                let x = i % width, y = i / width
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else {
                            touchesGround = true
                            continue
                        }
                        let n = ny * width + nx
                        if !visible[n] {
                            touchesGround = true
                        } else if lost[n] && !seen[n] {
                            seen[n] = true
                            stack.append(n)
                        }
                    }
                }
            }
            // Enclosed by something that reads: it has its own outline.
            guard touchesGround else { continue }
            // A plate carrying its own lettering.
            let area = (maxX - minX + 1) * (maxY - minY + 1)
            var lettering = 0
            for y in minY...maxY {
                for x in minX...maxX where legible[y * width + x] { lettering += 1 }
            }
            if Double(lettering) > plateLettering * Double(area) { continue }

            for i in region {
                let a = premultiplied ? Double(pixels[i * 4 + 3]) / 255 : 1
                pixels[i * 4]     = UInt8((Double(ink.0) * a).rounded())
                pixels[i * 4 + 1] = UInt8((Double(ink.1) * a).rounded())
                pixels[i * 4 + 2] = UInt8((Double(ink.2) * a).rounded())
            }
            redrawn += region.count
        }
        return visibleCount == 0 ? 0 : Double(redrawn) / Double(visibleCount)
    }

    /// WCAG relative luminance of an sRGB color, 0–255 per channel.
    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double {
            let v = min(max(c / 255, 0), 1)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
