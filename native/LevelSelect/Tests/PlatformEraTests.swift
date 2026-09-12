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
}
