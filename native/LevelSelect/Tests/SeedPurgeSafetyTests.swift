import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import LevelSelect

/// **Seeding must not be able to destroy a real preference.**
///
/// On 2026-09-04 a schema seed ran against a live library and purge deleted the
/// developer's own accent, `#8A5CF6` — which happened to be the exact string
/// `CloudKitSchemaSeeder.seededAccent` held. The seeder never wrote that field
/// (it only fills nils, and this one was set), but purge nils anything equal to
/// the constant and had no way to tell "the value I seeded" from "the value you
/// picked". The seeder's own comment promised the opposite: that purge exists
/// "so a seeding run never leaves the user with an accent they didn't pick".
///
/// The rule these tests hold: **every seed marker must be a value no person
/// could plausibly have chosen**, so the equality check purge relies on can
/// never match real user data.
@MainActor
struct SeedPurgeSafetyTests {

    private func store() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// The exact incident, as a test.
    @Test func seedAndPurgeLeaveAUsersOwnThemeAlone() throws {
        let context = store()
        let theme = ThemePalette.fetchOrCreate(in: context)

        // A real library's settings, as they were that morning.
        theme.accentHex = "#8A5CF6"
        theme.backgroundHex = "#F5A34D"
        theme.appearanceRaw = "dark"
        theme.gamePageLayoutRaw = "showcase"
        theme.statusColors = [GameStatus.playing.rawValue: "#123456"]
        theme.starNames = ["", "", "", "", "Adored it"]
        try? context.save()

        _ = CloudKitSchemaSeeder.seed(context: context)
        _ = CloudKitSchemaSeeder.purge(context: context)

        let after = try #require(try context.fetch(FetchDescriptor<ThemeSettings>()).first)
        #expect(after.accentHex == "#8A5CF6", "purge destroyed an accent the seeder never wrote")
        #expect(after.backgroundHex == "#F5A34D")
        #expect(after.appearanceRaw == "dark")
        #expect(after.gamePageLayoutRaw == "showcase")
        #expect(after.statusColors[GameStatus.playing.rawValue] == "#123456")
        #expect(after.starNames.last == "Adored it")
    }

    /// The rule itself, so a future marker cannot reintroduce the collision.
    ///
    /// A marker that parses as a color is a marker a user could have picked.
    @Test func noSeedMarkerIsAValueAUserCouldChoose() {
        #expect(Color(hex: CloudKitSchemaSeeder.seededAccent) == nil,
                "seededAccent parses as a real color, so purge cannot tell it from a user's choice")
        #expect(Color(hex: CloudKitSchemaSeeder.marker) == nil)
        // Markers are also implausible as free text — nobody types this into a
        // wishlist URL or a rating label.
        #expect(CloudKitSchemaSeeder.marker.contains("__"))
    }

    /// Purge must still do its job: a row the seeder DID populate comes back nil.
    @Test func purgeStillClearsWhatTheSeedActuallyWrote() throws {
        let context = store()
        let theme = ThemePalette.fetchOrCreate(in: context)
        // Everything nil — the case the seeder is allowed to fill.
        theme.accentHex = nil
        theme.backgroundHex = nil
        try? context.save()

        _ = CloudKitSchemaSeeder.seed(context: context)
        let seeded = try #require(try context.fetch(FetchDescriptor<ThemeSettings>()).first)
        #expect(seeded.accentHex != nil, "seed must populate the field or CloudKit never sees it")

        _ = CloudKitSchemaSeeder.purge(context: context)
        let purged = try #require(try context.fetch(FetchDescriptor<ThemeSettings>()).first)
        #expect(purged.accentHex == nil, "purge left a seeded value behind")
        #expect(purged.backgroundHex == nil)
    }
}
