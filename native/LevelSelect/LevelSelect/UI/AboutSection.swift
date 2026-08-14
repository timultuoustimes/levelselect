import SwiftUI

/// Settings "About" section (beta P0 metadata): version/build, the privacy
/// policy (bundled in-app so it works offline; the same text lives at
/// PRIVACY.md in the repo for the App Store URL), and a feedback path.
struct AboutSection: View {
    private static let repoURL = URL(string: "https://github.com/timultuoustimes/levelselect")!
    private static let issuesURL = URL(string: "https://github.com/timultuoustimes/levelselect/issues")!

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        Section {
            LabeledContent("Version", value: versionString)
            NavigationLink("Privacy Policy") { PrivacyPolicyView() }
            Link(destination: Self.issuesURL) {
                Label("Report an Issue", systemImage: "ladybug")
            }
        } header: {
            Text("About")
        } footer: {
            Text("Beta feedback is best sent through TestFlight — take a screenshot in the app or use the TestFlight app's Send Feedback.")
        }
    }
}

/// Native, offline copy of the privacy policy. Keep in sync with PRIVACY.md
/// at the repo root — that file is the canonical App Store version.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Last updated: August 13, 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                block("Your data stays yours",
                      "LevelSelect has no accounts, no ads, no analytics, and no tracking. Your library — games, sessions, tracker progress, playthroughs, runs, collections, ratings, and notes — is stored on your device and synced to your private iCloud database when iCloud is available. The developer cannot read it.")

                block("What leaves your device",
                      "Three features talk to LevelSelect's backend:\n\n• Game search sends the text or game id you look up, so IGDB (a Twitch service) can return titles, cover art, and metadata.\n\n• AI tracker generation sends the game's name, its public IGDB metadata, and any guide text or URL you provide to Anthropic's Claude, which may web-search for a guide.\n\n• Map search (a future feature) sends the game's name and an optional wiki URL the same way.\n\nSeparately, your device fetches your public Deku Deals wishlist directly if you configure one, loads cover art from IGDB's image servers, and fetches YouTube titles/thumbnails for video links you add.")

                block("The install identifier",
                      "Backend requests carry a random identifier the app generates on first launch, used only for fair-use rate limiting. It isn't derived from your device's hardware, isn't linked to you or your iCloud account, and resets if you reinstall the app.")

                block("What LevelSelect never does",
                      "No accounts or passwords. No advertising or data sales. No analytics SDKs. No tracking across apps or websites. No access to contacts, photos, location, microphone, or camera.")

                block("TestFlight",
                      "During the beta, Apple's TestFlight may share crash logs and feedback you choose to submit, under Apple's privacy policy.")

                block("Contact",
                      "Questions? Open an issue on the GitHub repository (linked from Settings) or use TestFlight feedback.")
            }
            .padding()
            .frame(maxWidth: 600)
        }
        .lsBackground()
        .navigationTitle("Privacy Policy")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
