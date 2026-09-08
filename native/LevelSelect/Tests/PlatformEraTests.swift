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
        let missingYear = slugs.subtracting(PlatformEra.years.keys)
        let missingArt = Set(PlatformEra.years.keys).subtracting(slugs)
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

    /// Sanity on the shape of the data itself.
    @Test func everyYearIsPlausible() {
        for (slug, year) in PlatformEra.years {
            #expect(year >= 1975 && year <= 2030, Comment(rawValue: "\(slug) = \(year)"))
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
        #expect(noArt == ["itch.io"], Comment(rawValue: "catalogue entries with no icon: \(noArt)"))
    }
}
