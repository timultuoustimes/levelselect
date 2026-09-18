import Testing
import Foundation
@testable import LevelSelect

/// The three V7 items built on 09-18: synced suggestion preferences, your own
/// order inside a Home shelf, and barcodes.
struct SuggestionPrefsSyncTests {
    private func defaults() -> UserDefaults {
        let name = "test.suggest.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func aSnapshotRoundTripsAndIsStable() {
        let d = defaults()
        d.set(["capcom"], forKey: SuggestionPrefs.key(.publisher, .followed))
        d.set(["pc"], forKey: SuggestionPrefs.key(.system, .hidden))
        d.set("Mac,Switch 2", forKey: SuggestionPrefs.upcomingSystemsKey)
        #expect(SuggestionPrefs.encoded(d) == SuggestionPrefs.encoded(d))
        let other = defaults()
        other.set(true, forKey: "levelselect.suggest.synced")
        SuggestionPrefs.apply(SuggestionPrefs.encoded(d), other)
        #expect(SuggestionPrefs.snapshot(other) == SuggestionPrefs.snapshot(d))
    }

    /// A phone's follows aren't wiped by the iPad's the first time they meet.
    @Test func theFirstMeetingMergesAndHiddenWins() throws {
        let phone = defaults()
        phone.set(["capcom", "konami"], forKey: SuggestionPrefs.key(.publisher, .followed))
        let ipad = defaults()
        ipad.set(["atlus"], forKey: SuggestionPrefs.key(.publisher, .followed))
        ipad.set(["konami"], forKey: SuggestionPrefs.key(.publisher, .hidden))
        let sendBack = try #require(SuggestionPrefs.apply(SuggestionPrefs.encoded(ipad), phone))
        let merged = SuggestionPrefs.snapshot(phone)
        #expect(merged.lists["publisher.followed"] == ["atlus", "capcom"])
        #expect(merged.lists["publisher.hidden"] == ["konami"])
        #expect(!sendBack.isEmpty)
        // After that, the synced copy simply wins.
        let later = defaults()
        later.set(["sega"], forKey: SuggestionPrefs.key(.publisher, .followed))
        SuggestionPrefs.apply(SuggestionPrefs.encoded(later), phone)
        #expect(SuggestionPrefs.snapshot(phone).lists["publisher.followed"] == ["sega"])
    }
}

struct ShelfOrderTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test func noOrderKeepsTheAutomaticOne() {
        #expect(ShelfOrder.arrange([a, b, c], id: { $0 }, order: nil) == [a, b, c])
    }

    @Test func yourOrderWinsAndNewcomersGoFirst() {
        // You arranged c, a, b; then d joined the shelf.
        let arranged = ShelfOrder.arrange([d, a, b, c], id: { $0 }, order: [c, a, b])
        #expect(arranged == [d, c, a, b])
    }

    @Test func gamesThatLeftDropOut() {
        #expect(ShelfOrder.arrange([a, c], id: { $0 }, order: [c, b, a]) == [c, a])
    }

    @Test func encodesPerStatusAndEmptyMeansAutomatic() {
        let raw = ShelfOrder.encode(["playing": [b, a], "backlog": []])
        let back = ShelfOrder.decode(raw)
        #expect(back["playing"] == [b, a])
        #expect(back["backlog"] == nil)
        #expect(ShelfOrder.encode([:]) == nil)
    }
}

struct BarcodeTests {
    @Test func upcAndEANTwinsAreOneBox() {
        #expect(BarcodeService.normalized("0711719546658") == "711719546658")
        #expect(BarcodeService.same("0711719546658", "711719546658"))
        #expect(BarcodeService.normalized("0-45496-59643-9") == "045496596439")
        #expect(BarcodeService.normalized("123") == nil)
        #expect(BarcodeService.normalized("0000000000000") == nil)
    }

    /// Checked against IGDB on 09-18 — ScanDex's create endpoint needs the id.
    @Test func platformIDsForTheCommonBoxes() {
        #expect(BarcodeService.igdbPlatformIDs["Nintendo Switch 2"] == 508)
        #expect(BarcodeService.igdbPlatformIDs["Nintendo Switch"] == 130)
        #expect(BarcodeService.igdbPlatformIDs["PlayStation 5"] == 167)
        #expect(BarcodeService.igdbPlatformIDs["Xbox Series X|S"] == 169)
    }
}
