import Testing
import Foundation
@testable import LevelSelect

/// **The console release table, and the invariant that keeps it honest.**
///
/// It exists so "sort my systems by when they came out" is one tap. The risk
/// with an authored table is drift: a platform gains art and nobody adds a
/// year, or a year is added for a platform the app cannot draw.
struct PlatformEraTests {

    /// Every platform the app has an icon for has a year, and vice versa.
    /// This is the whole reason the table is keyed by the icon slug.
    @Test func artAndYearsCoverTheSameSetOfPlatforms() throws {
        let assetsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // LevelSelect (project)
            .appendingPathComponent("LevelSelect/Assets.xcassets")
        let names = try FileManager.default.contentsOfDirectory(atPath: assetsDir.path)
        let slugs = Set(names
            .filter { $0.hasPrefix("platform-") && $0.hasSuffix(".imageset") }
            .map { $0.replacingOccurrences(of: "platform-", with: "")
                     .replacingOccurrences(of: ".imageset", with: "") })

        #expect(!slugs.isEmpty, "found no platform art to check against")
        // The storefront mark is a logo, not a machine — it has no release
        // year because nothing was released. See `PlatformIcon.storefronts`.
        let slugsExceptMarks = slugs.subtracting(["itch"])
        let missingYear = slugsExceptMarks.subtracting(PlatformEra.years.keys)
        let missingArt = Set(PlatformEra.years.keys).subtracting(slugsExceptMarks)
        #expect(missingYear.isEmpty, Comment(rawValue: "art with no release year: \(missingYear.sorted())"))
        #expect(missingArt.isEmpty, Comment(rawValue: "release year with no art: \(missingArt.sorted())"))
    }

    /// The lookup goes through the same name matching the icons use, so the
    /// spellings people actually type resolve.
    @Test func theNamesPeopleTypeResolve() {
        #expect(PlatformEra.releaseYear("Super Nintendo") == 1991)
        #expect(PlatformEra.releaseYear("SNES") == 1991)
        #expect(PlatformEra.releaseYear("Nintendo Switch 2") == 2025)
        #expect(PlatformEra.releaseYear("Switch") == 2017)
        #expect(PlatformEra.releaseYear("PlayStation 2") == 2000)
        #expect(PlatformEra.releaseYear("Mega Drive") == 1989, "Genesis, by its NA date")
    }

    /// A platform the app has never heard of sorts somewhere rather than
    /// crashing — the caller decides where.
    @Test func anUnknownPlatformHasNoYear() {
        #expect(PlatformEra.releaseYear("Amstrad CPC") == nil)
        #expect(PlatformEra.releaseYear("") == nil)
    }

    /// Sanity on the shape of the data itself. The floor was 1975 until the
    /// arcade cabinet arrived on 09-08 — a bound set when everything in the
    /// table was a home console, and arcade video games start in 1972.
    @Test func everyYearIsPlausible() {
        for (slug, year) in PlatformEra.years {
            #expect(year >= 1971 && year <= 2030, Comment(rawValue: "\(slug) = \(year)"))
        }
    }

    /// The generations land in the order anyone would expect, which is the
    /// only thing the sort actually promises.
    @Test func generationsSortInOrder() {
        let order = ["nes", "snes", "n64", "gamecube", "wii", "wiiu", "switch", "switch2"]
        let years = order.compactMap { PlatformEra.years[$0] }
        #expect(years == years.sorted(), Comment(rawValue: "Nintendo out of order: \(years)"))
        let sony = ["ps1", "ps2", "ps3", "ps4", "ps5"].compactMap { PlatformEra.years[$0] }
        #expect(sony == sony.sorted())
    }

    /// **The waterfall's order is the whole correctness of it.** Every one of
    /// these names contains another name tested nearby, and each was wrong
    /// before build 39 added the art: "Super Famicom" resolved to the SNES,
    /// "Nintendo 64DD" to the N64, "Famicom Disk System" to nothing, and the
    /// bare "DS" would have been swallowed by "3DS".
    @Test func namesThatContainOtherNamesResolveToTheirOwnArt() {
        #expect(PlatformIcon.assetName("Super Famicom") == "platform-superfamicom")
        #expect(PlatformIcon.assetName("Famicom") == "platform-famicom")
        #expect(PlatformIcon.assetName("Family Computer") == "platform-famicom")
        #expect(PlatformIcon.assetName("Family Computer Disk System") == "platform-famicom-disk")
        #expect(PlatformIcon.assetName("Nintendo 64DD") == "platform-64dd")
        #expect(PlatformIcon.assetName("Nintendo 64") == "platform-n64")
        #expect(PlatformIcon.assetName("Nintendo DS") == "platform-ds")
        #expect(PlatformIcon.assetName("Nintendo DSi") == "platform-ds")
        #expect(PlatformIcon.assetName("Nintendo 3DS") == "platform-3ds")
        #expect(PlatformIcon.assetName("PlayStation Portable") == "platform-psp")
        #expect(PlatformIcon.assetName("PlayStation") == "platform-ps1")
        #expect(PlatformIcon.assetName("Sega 32X") == "platform-32x")
        #expect(PlatformIcon.assetName("Sega Mega Drive/Genesis") == "platform-genesis")
        #expect(PlatformIcon.assetName("TurboGrafx-16/PC Engine") == "platform-turbografx16")
        #expect(PlatformIcon.assetName("Sega Master System/Mark III") == "platform-mastersystem")
        // And the SNES kept its own.
        #expect(PlatformIcon.assetName("SNES") == "platform-snes")
        #expect(PlatformIcon.assetName("Super Nintendo Entertainment System") == "platform-snes")
    }

    /// The consoles that had no art at all until build 39 — a game on any of
    /// them drew a generic controller, and the catalogue offered four of them
    /// with nothing to show.
    @Test func theConsolesThatHadNoArtNowHaveIt() {
        for name in ["Sega Dreamcast", "Sega Saturn", "Sega Game Gear",
                     "Nintendo DS", "PlayStation Portable", "Virtual Boy"] {
            #expect(PlatformIcon.assetName(name) != nil, Comment(rawValue: name))
            #expect(PlatformEra.releaseYear(name) != nil, Comment(rawValue: "\(name) has no year"))
        }
    }

    /// Every console the catalogue offers can be drawn. Offering one with no
    /// art puts a generic controller in the display case, which is the one
    /// place the app is claiming to show your actual hardware.
    @Test func everythingTheCatalogueOffersHasArt() {
        let noArt = PlatformCatalog.all.filter { PlatformIcon.assetName($0) == nil }
        #expect(noArt.isEmpty, Comment(rawValue: "catalogue entries with no icon: \(noArt)"))
    }

    /// The Xbox One drew the 2001 Xbox for want of a render of its own, and
    /// because a console's year is read off its art, it sorted as a 2001
    /// console — ahead of the Xbox 360. A `sharedArtYears` override held the
    /// line until Codex drew it one the same day. The bug this guards against
    /// is the ordering, not the override, so the test outlives it.
    @Test func theXboxesSortByTheirOwnYears() {
        #expect(PlatformIcon.assetName("Xbox One") == "platform-xbox-one")
        #expect(PlatformIcon.assetName("Xbox") == "platform-xbox")
        #expect(PlatformEra.releaseYear("Xbox One") == 2013)
        #expect(PlatformEra.releaseYear("Xbox") == 2001)
        #expect(PlatformEra.releaseYear("Xbox 360") == 2005)
        #expect(PlatformEra.releaseYear("Xbox Series X") == 2020)

        // Which is the order the picker shows them in.
        let microsoft = PlatformCatalog.all
            .filter { PlatformMaker.of($0) == "Microsoft" }
            .sorted { (PlatformEra.releaseYear($0) ?? .max) < (PlatformEra.releaseYear($1) ?? .max) }
        #expect(microsoft == ["Xbox", "Xbox 360", "Xbox One", "Xbox Series X"])
    }

    /// Every console the picker offers has a maker, or it would be filed
    /// under its own name in a list grouped by company.
    @Test func everythingTheCatalogueOffersHasAMaker() {
        let noMaker = PlatformCatalog.all.filter { PlatformMaker.of($0) == nil }
        #expect(noMaker == ["itch.io"], Comment(rawValue: "catalogue entries with no maker: \(noMaker)"))
        // And having no maker is exactly why it must not reach the grid on a
        // "does it have a picture" test — it has one now.
        #expect(PlatformIcon.isStorefront("itch.io"))
        #expect(PlatformIcon.assetName("itch.io") == "platform-itch")
    }

    /// Art and makers cover the same set, the way art and years do.
    @Test func artAndMakersCoverTheSameSetOfPlatforms() throws {
        let assetsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LevelSelect/Assets.xcassets")
        let names = try FileManager.default.contentsOfDirectory(atPath: assetsDir.path)
        let slugs = Set(names
            .filter { $0.hasPrefix("platform-") && $0.hasSuffix(".imageset") }
            .map { $0.replacingOccurrences(of: "platform-", with: "")
                     .replacingOccurrences(of: ".imageset", with: "") })
        let missing = slugs.subtracting(PlatformMaker.makers.keys).subtracting(["itch"])
        #expect(missing.isEmpty, Comment(rawValue: "art with no maker: \(missing.sorted())"))
    }

    /// **A PC is a PC whatever it boots.** There has never been a "Windows"
    /// console in this app, so a Linux one made the operating system the
    /// machine for one of the two and not the other. The penguin's art went
    /// with the name: a folded console must not draw a picture no other PC
    /// draws.
    @Test func linuxIsAPC() {
        #expect(PlatformKey.canonical("Linux") == "PC")
        #expect(PlatformKey.canonical("PC (Microsoft Windows)") == "PC")
        #expect(PlatformIcon.assetName("Linux") == "platform-pc")
        #expect(PlatformEra.releaseYear("Linux") == 1981, "the PC's year, since it is one")
        #expect(!PlatformCatalog.all.contains("Linux"))
        // Valve's boxes are hardware, not a choice of OS on a box you own.
        #expect(PlatformKey.canonical("Steam Deck") == "Steam Deck")
        #expect(PlatformIcon.assetName("Steam Machine") == "platform-steammachine")
    }

    /// Recalbox was the name of one operating system for a board the art has
    /// always drawn as a Raspberry Pi. Old libraries fold into the new name
    /// rather than standing a second console beside it.
    @Test func recalboxFoldsIntoRaspberryPi() {
        #expect(PlatformKey.canonical("Recalbox") == "Raspberry Pi")
        #expect(PlatformKey.canonical("Raspberry Pi") == "Raspberry Pi")
        #expect(PlatformKey.canonical("RetroPie") == "Raspberry Pi")
        #expect(PlatformIcon.assetName("Raspberry Pi") == "platform-recalbox")
        #expect(PlatformIcon.assetName("Recalbox") == "platform-recalbox")
        #expect(PlatformEra.releaseYear("Raspberry Pi") == 2015)
    }

    /// Grouped by maker, a picker of consoles opened with Apple and Google —
    /// two names that make phones — above every console anyone came for. The
    /// headings that are not console makers say what the thing IS.
    @Test func phonesAndComputersGroupByKindRatherThanCompany() {
        for phone in ["iOS", "Android", "iPad"] {
            #expect(PlatformMaker.of(phone) == "Mobile", Comment(rawValue: phone))
        }
        for computer in ["PC", "Mac", "Raspberry Pi"] {
            #expect(PlatformMaker.of(computer) == "Computers", Comment(rawValue: computer))
        }
        // The console makers stay themselves.
        #expect(PlatformMaker.of("Switch") == "Nintendo")
        #expect(PlatformMaker.of("Steam Deck") == "Valve")
        #expect(!PlatformMaker.makers.values.contains("Apple"))
        #expect(!PlatformMaker.makers.values.contains("Google"))
    }

    /// A storefront is not hardware. itch.io stays in the catalogue, because
    /// its games routinely have no IGDB entry and must be nameable — and it
    /// now has a mark of its own, which is precisely why the picker no longer
    /// decides this by asking whether a platform can be drawn.
    @Test func aStorefrontIsNotAConsole() {
        #expect(PlatformCatalog.all.contains("itch.io"))
        #expect(PlatformIcon.isStorefront("itch.io"))
        #expect(PlatformIcon.assetName("itch.io") == "platform-itch")
        // No maker and no release year: nobody manufactured it and nothing
        // came out. Those are the same reason it is not a console.
        #expect(PlatformMaker.of("itch.io") == nil)
        #expect(PlatformEra.releaseYear("itch.io") == nil)
        // Real hardware is never mistaken for a shop.
        for console in ["Switch", "PC", "Atari 2600", "Amiga CD32"] {
            #expect(!PlatformIcon.isStorefront(console), Comment(rawValue: console))
        }
    }

    /// **The two families Codex drew on 09-08.** Each is checked the way the
    /// waterfall can actually fail: a name that contains another name.
    @Test func atariAndCommodoreResolveToTheirOwnArt() {
        #expect(PlatformIcon.assetName("Atari 2600") == "platform-atari2600")
        #expect(PlatformIcon.assetName("Atari 5200") == "platform-atari5200")
        #expect(PlatformIcon.assetName("Atari 7800") == "platform-atari7800")
        #expect(PlatformIcon.assetName("Atari Lynx") == "platform-lynx")
        #expect(PlatformIcon.assetName("Atari Jaguar") == "platform-jaguar")
        // "Amiga CD32" contains "Amiga", so it must be tested first — the
        // Famicom Disk System's rule, applied to Commodore.
        #expect(PlatformIcon.assetName("Amiga CD32") == "platform-cd32")
        #expect(PlatformIcon.assetName("Amiga") == "platform-amiga")
        // IGDB's own spelling of the 8-bit machine.
        #expect(PlatformIcon.assetName("Commodore C64/128/MAX") == "platform-c64")

        // And the folds land on the names the picker shows.
        #expect(PlatformKey.canonical("Atari VCS") == "Atari 2600")
        #expect(PlatformKey.canonical("Lynx") == "Atari Lynx")
        #expect(PlatformKey.canonical("Atari Jaguar CD") == "Atari Jaguar")
        #expect(PlatformKey.canonical("Commodore C64/128/MAX") == "Commodore 64")
        #expect(PlatformKey.canonical("Commodore Amiga") == "Amiga")

        // Inside each heading the picker sorts oldest first.
        for maker in ["Atari", "Commodore"] {
            let shown = PlatformCatalog.all
                .filter { PlatformMaker.of($0) == maker }
                .sorted { (PlatformEra.releaseYear($0) ?? .max) < (PlatformEra.releaseYear($1) ?? .max) }
            #expect(shown == shown.sorted {
                (PlatformEra.releaseYear($0) ?? .max) < (PlatformEra.releaseYear($1) ?? .max) })
            #expect(shown.count > 2, Comment(rawValue: maker))
        }
        #expect(PlatformEra.releaseYear("Atari 2600") == 1977)
        #expect(PlatformEra.releaseYear("Amiga CD32") == 1993)
    }

    /// SNK, where every name contains the one below it.
    @Test func theNeoGeosResolveToTheirOwnArt() {
        #expect(PlatformIcon.assetName("Neo Geo Pocket Color") == "platform-ngpc")
        #expect(PlatformIcon.assetName("Neo Geo MVS") == "platform-neogeo-mvs")
        #expect(PlatformIcon.assetName("Neo Geo AES") == "platform-neogeo-aes")
        // The mono Pocket shares the Color's body, so it shares the picture
        // rather than falling through to the home console.
        #expect(PlatformIcon.assetName("Neo Geo Pocket") == "platform-ngpc")
        // A bare "Neo Geo" is the console someone owns.
        #expect(PlatformKey.canonical("Neo Geo") == "Neo Geo AES")
        #expect(PlatformEra.releaseYear("Neo Geo AES") == 1990)
        #expect(PlatformEra.releaseYear("Neo Geo Pocket Color") == 1999)
        for snk in ["Neo Geo AES", "Neo Geo MVS", "Neo Geo Pocket Color"] {
            #expect(PlatformMaker.of(snk) == "SNK", Comment(rawValue: snk))
        }
    }

    /// **"switch" contains "itch".** The storefront mark is matched exactly
    /// for that reason: a substring test would hand every Switch game a shop
    /// awning the moment anything above it in the waterfall moved.
    @Test func theStorefrontMarkNeverCatchesTheSwitch() {
        #expect(PlatformIcon.assetName("Switch") == "platform-switch")
        #expect(PlatformIcon.assetName("Switch 2") == "platform-switch2")
        #expect(PlatformIcon.assetName("Nintendo Switch") == "platform-switch")
        #expect(!PlatformIcon.isStorefront("Switch"))
        #expect(PlatformIcon.assetName("itch.io") == "platform-itch")
    }

    /// The machines that came before the ones anyone still sells, plus a
    /// cabinet with nobody's name on it.
    @Test func theEightiesMachinesResolveToTheirOwnArt() {
        let expected = ["Intellivision": "platform-intellivision",
                        "ColecoVision": "platform-colecovision",
                        "Vectrex": "platform-vectrex",
                        "ZX Spectrum": "platform-zxspectrum",
                        "MSX": "platform-msx",
                        "3DO": "platform-3do",
                        "WonderSwan Color": "platform-wonderswan",
                        "Arcade": "platform-arcade"]
        for (name, asset) in expected {
            #expect(PlatformIcon.assetName(name) == asset, Comment(rawValue: name))
        }
        // The mono WonderSwan shares the Color's body, so it shares the
        // picture — the Neo Geo Pocket's rule again.
        #expect(PlatformIcon.assetName("WonderSwan") == "platform-wonderswan")
        // A NAMED cabinet is matched before the general one can catch it.
        #expect(PlatformIcon.assetName("Neo Geo MVS") == "platform-neogeo-mvs")
        // Folds, including the revisions of one standard.
        #expect(PlatformKey.canonical("MSX2") == "MSX")
        #expect(PlatformKey.canonical("3DO Interactive Multiplayer") == "3DO")
        #expect(PlatformKey.canonical("Sinclair ZX Spectrum") == "ZX Spectrum")
        // Headings: a maker where there is one, a kind where there is not.
        #expect(PlatformMaker.of("Intellivision") == "Mattel")
        #expect(PlatformMaker.of("3DO") == "Panasonic")
        #expect(PlatformMaker.of("WonderSwan Color") == "Bandai")
        #expect(PlatformMaker.of("MSX") == "Computers", "a standard, not one company's box")
        #expect(PlatformMaker.of("Arcade") == "Arcade")
        // The oldest thing the app can draw, and it sorts that way.
        #expect(PlatformEra.releaseYear("Arcade") == 1972)
        #expect(PlatformEra.years.values.min() == 1972)
    }
}
