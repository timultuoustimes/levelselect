import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// What you call your consoles.
///
/// Tim: *"the user should be able to choose which one they want displayed, not
/// forced to see Genesis if they don't call it that."* The rule worth pinning
/// is not the list of names — that will grow — but the three properties that
/// make renaming safe: it reaches every caller, it never invents a name, and
/// choosing the default back leaves nothing behind.
@MainActor
struct PlatformNamingTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// Reset between tests: the override cache is process-wide, exactly so
    /// that every call site sees it.
    private func withOverrides(_ overrides: [String: String], _ body: () -> Void) {
        let previous = PlatformShort.displayOverrides
        PlatformShort.displayOverrides = overrides
        body()
        PlatformShort.displayOverrides = previous
    }

    // MARK: The folding underneath

    /// Every spelling of one machine folds to one console, so a single choice
    /// covers a library that holds several of them.
    @Test func everySpellingOfAMachineIsOneConsole() {
        for stored in ["Sega Mega Drive/Genesis", "Sega Genesis", "Genesis", "Mega Drive"] {
            #expect(PlatformShort.builtinName(stored) == "Genesis")
        }
        for stored in ["Sega Mega-CD", "Sega CD", "Mega-CD"] {
            #expect(PlatformShort.builtinName(stored) == "Sega CD")
        }
    }

    /// The 32X is a different device, not another word for a Mega Drive.
    @Test func the32XIsNotFoldedIntoTheMegaDrive() {
        #expect(PlatformShort.builtinName("Sega 32X") != "Genesis")
        #expect(PlatformShort.builtinName("Sega 32X") != "Sega CD")
    }

    /// Famicom and Super Famicom are separate machines, and someone with an
    /// import collection cares about the distinction.
    @Test func famicomIsNotAnAliasForNES() {
        #expect(PlatformShort.builtinName("Famicom") == "Famicom")
        #expect(PlatformShort.builtinName("Super Famicom") == "Super Famicom")
        #expect(PlatformNaming.alternatives["Famicom"] == nil)
        #expect(PlatformNaming.alternatives["Super Famicom"] == nil)
    }

    // MARK: Choosing

    /// The choice reaches the shortener every caller already uses — that is
    /// the whole design, and it is what makes twenty-one call sites free.
    @Test func aChosenNameReachesEveryCaller() {
        withOverrides(["Genesis": "Mega Drive"]) {
            #expect(PlatformShort.name("Sega Mega Drive/Genesis") == "Mega Drive")
            #expect(PlatformShort.name("Sega Genesis") == "Mega Drive")
        }
    }

    @Test func consolesWithNoChoiceAreUntouched() {
        withOverrides(["Genesis": "Mega Drive"]) {
            #expect(PlatformShort.name("Nintendo Switch") == "Switch")
            #expect(PlatformShort.name("Nintendo GameCube") == "GameCube")
        }
    }

    /// A name this build does not offer must never render. The value comes
    /// from CloudKit and from backups, so it is not the app's to trust.
    @Test func aNameTheConsoleDoesNotGoByIsIgnored() {
        withOverrides(["Genesis": "Mega Drive II"]) {
            #expect(PlatformShort.name("Sega Genesis") == "Genesis")
        }
        withOverrides(["Switch": "Nintendo Switch Deluxe"]) {
            #expect(PlatformShort.name("Nintendo Switch") == "Switch")
        }
    }

    /// Every alternative listed actually resolves — a typo in the table would
    /// otherwise be a silently dead option in the picker.
    @Test func everyOfferedNameIsAcceptedForItsConsole() {
        for (short, names) in PlatformNaming.alternatives {
            for name in names {
                #expect(PlatformNaming.isValid(name, for: short),
                        "\(name) is offered for \(short) but not accepted")
            }
        }
    }

    /// The default is the first listed, and it is what the app shipped —
    /// so nobody's shelves change until they choose.
    @Test func theDefaultIsWhatTheAppAlreadyShowed() {
        for short in PlatformNaming.alternatives.keys {
            #expect(PlatformNaming.defaultName(for: short) == short)
        }
    }

    /// Every console has a hardware label, or its settings row falls back to
    /// the short name and reads "Genesis → Genesis" again.
    @Test func everyConsoleHasAHardwareLabel() {
        for short in PlatformNaming.alternatives.keys {
            #expect(PlatformNaming.hardware[short] != nil, "\(short) has no hardware label")
        }
    }

    /// The settings screen's order covers the table exactly. A console in one
    /// and not the other is either an unreachable option or an empty row.
    @Test func theOrderAndTheTableAgree() {
        #expect(Set(PlatformNaming.order) == Set(PlatformNaming.alternatives.keys))
        #expect(PlatformNaming.order.count == Set(PlatformNaming.order).count)
    }

    // MARK: Storing

    /// Choosing the default back stores nothing. A row saying "Genesis is
    /// called Genesis" would sync, merge, and outlive the build that wrote it.
    @Test func pickingTheDefaultLeavesNothingStored() {
        #expect(PlatformNaming.sanitized(["Genesis": "Genesis"]).isEmpty)
        #expect(PlatformNaming.sanitized(["Genesis": "Mega Drive"]) == ["Genesis": "Mega Drive"])
    }

    @Test func anUnknownConsoleIsDroppedRatherThanKept() {
        #expect(PlatformNaming.sanitized(["Dreamcast": "DC"]).isEmpty)
        #expect(PlatformNaming.sanitized(["Genesis": "Saturn"]).isEmpty)
    }

    /// It round-trips through the record the way `statusNames` does.
    @Test func theChoiceSurvivesTheStore() {
        let context = makeContext()
        let settings = ThemeSettings()
        settings.platformNames = ["Genesis": "Mega Drive", "NES": "Nintendo"]
        context.insert(settings)

        #expect(settings.platformNames["Genesis"] == "Mega Drive")
        #expect(settings.platformNames["NES"] == "Nintendo")

        // Empty clears the column rather than storing "{}" forever.
        settings.platformNames = [:]
        #expect(settings.platformNamesData == nil)
    }

    /// `refresh` is what pushes the choice out to the shortener, so a palette
    /// refresh has to carry it — and has to sanitize on the way.
    @Test func refreshPublishesTheChoiceAndDropsBadOnes() {
        let context = makeContext()
        let settings = ThemeSettings()
        settings.platformNames = ["Genesis": "Mega Drive", "NES": "Nintendo 64"]
        context.insert(settings)

        let previous = PlatformShort.displayOverrides
        ThemePalette.refresh(from: settings)
        #expect(PlatformShort.name("Sega Genesis") == "Mega Drive")
        #expect(PlatformShort.name("Nintendo Entertainment System") == "NES")
        PlatformShort.displayOverrides = previous
    }
}
