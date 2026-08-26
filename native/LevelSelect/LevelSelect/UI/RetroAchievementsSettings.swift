import SwiftUI

/// Connect a RetroAchievements account, so imported sets can arrive already
/// ticked.
///
/// Verified before saving, on purpose. A mistyped key would otherwise fail
/// silently at the first sync days later, and look like the sync is broken
/// rather than the credentials.
struct RetroAchievementsSettings: View {
    @State private var username = ""
    @State private var apiKey = ""
    @State private var checking = false
    @State private var error: String?
    @State private var connectedAs: String?
    @State private var profileTarget: DekuLinkTarget?

    var body: some View {
        Section {
            if let connectedAs {
                HStack {
                    Label(connectedAs, systemImage: "trophy.fill")
                        .foregroundStyle(LSTheme.accent)
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        // Reported, not assumed. `clear()` returns false when
                        // the Keychain refused, and showing a disconnected
                        // screen over a key that is still there is a lie about
                        // where someone's credential is.
                        guard RACredentials.clear() else {
                            error = "Couldn't remove the key from the Keychain. Still connected."
                            return
                        }
                        error = nil
                        self.connectedAs = nil
                        username = ""; apiKey = ""
                        // The wall is drawn from this account; keeping it
                        // after disconnect would show someone else's trophies
                        // to the next account.
                        RAAwardsCache.clear()
                    }
                    .font(.caption)
                }
                Button {
                    if let url = RAArt.profilePage(username: connectedAs) {
                        profileTarget = DekuLinkTarget(url: url)
                    }
                } label: {
                    Label("Open your profile", systemImage: "arrow.up.right.square")
                }
                // On the row, NOT the Section — a sheet on a Section becomes
                // one per child and flickers.
                .dekuBrowser(target: $profileTarget)
            } else {
                TextField("RetroAchievements username", text: $username)
                    .textContentType(.username)
                    #if !os(macOS)
                    .autocapitalization(.none)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Web API key", text: $apiKey)
                    .autocorrectionDisabled()

                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        if checking { ProgressView().controlSize(.small) }
                        Text(checking ? "Checking…" : "Connect")
                    }
                }
                .disabled(checking
                          || username.trimmingCharacters(in: .whitespaces).isEmpty
                          || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Disconnect can fail while the connected branch stays visible.
            // Keeping the error inside the form-only branch made that failure
            // invisible even though `clear()` correctly reported it.
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(LSTheme.working)
            }
        } header: {
            Text("RetroAchievements")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Find your Web API key on retroachievements.org under Settings → Keys. It reads your account, so it's kept in the Keychain and sent only to RetroAchievements when connecting or syncing.")
                // Said plainly, because a preference that quietly doesn't sync
                // reads as a bug. The key never rides iCloud Keychain.
                Text("Stays on this device — enter it separately on each one.")
            }
            .font(.caption2)
        }
        .task {
            connectedAs = RACredentials.current?.username
        }
    }

    private func connect() async {
        checking = true
        error = nil
        defer { checking = false }
        do {
            // Comes back with the name RA itself reports (so the casing is
            // theirs) and the ULID, which is what later calls actually use.
            let confirmed = try await RetroAchievementsService.verify(
                username: username, apiKey: apiKey)
            guard RACredentials.save(confirmed) else {
                error = "Couldn't save to the Keychain."
                return
            }
            connectedAs = confirmed.username
            apiKey = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
