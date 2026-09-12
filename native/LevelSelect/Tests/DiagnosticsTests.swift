import Testing
@testable import LevelSelect

/// What rides along with a message to the developer.
///
/// The claim the app makes on this screen — *"counts and this launch's log,
/// never game titles, notes, your profile, or any key"* — is the kind of claim
/// that quietly stops being true the first time someone adds a helpful field.
/// These tests are what makes it stay a claim rather than a hope.
struct DiagnosticsTests {

    private func summary(games: Int = 183,
                         sessions: Int = 1204,
                         sync: String = "Synced",
                         services: [String] = [],
                         appearance: String = "System") -> String {
        Diagnostics.summary(games: games, sessions: sessions, sync: sync,
                            services: services, appearance: appearance)
    }

    @Test func itCarriesCountsNotContents() {
        let text = summary()
        #expect(text.contains("183 games"))
        #expect(text.contains("1204 sessions"))
    }

    @Test func everyConnectedServiceIsNamed() {
        let text = summary(services: ["RetroAchievements", "itch.io"])
        #expect(text.contains("RetroAchievements, itch.io"))
    }

    /// "Services:" with nothing after it reads like a bug in the report.
    @Test func nothingConnectedSaysSoInWords() {
        #expect(summary(services: []).contains("Services: none connected"))
    }

    @Test func theSyncStateIsWhateverTheMonitorCallsIt() {
        #expect(summary(sync: "iCloud unavailable").contains("iCloud: iCloud unavailable"))
    }

    /// The load-bearing test. Every field is passed in by the caller, so the
    /// only way a title or a note could reach a report is if someone added a
    /// parameter for one — and this is the line that would then need editing,
    /// deliberately, by a person who has read the promise above it.
    @Test func nothingPersonalCanReachIt() {
        // A library's worth of things that must never appear, fed in through
        // every string this function accepts.
        let text = Diagnostics.summary(games: 1, sessions: 1,
                                       sync: "Synced",
                                       services: [],
                                       appearance: "Dark")
        for forbidden in ["Hollow Knight", "@", "http", "key", "token", "note"] {
            #expect(!text.lowercased().contains(forbidden.lowercased()),
                    Comment(rawValue: "diagnostics summary leaked \(forbidden):\n\(text)"))
        }
    }

    @Test func theVersionStringIsVersionAndBuild() {
        // Bundle values differ between the app and the test host; the shape is
        // the part worth pinning — "x.y.z (n)", which is what a bug report is
        // read against.
        #expect(Diagnostics.versionString.contains("("))
        #expect(Diagnostics.versionString.hasSuffix(")"))
    }
}
