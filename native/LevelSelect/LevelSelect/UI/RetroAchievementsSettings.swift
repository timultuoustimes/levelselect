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

    var body: some View {
        Section {
            if let connectedAs {
                HStack {
                    Label(connectedAs, systemImage: "trophy.fill")
                        .foregroundStyle(LSTheme.accent)
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        RACredentials.clear()
                        self.connectedAs = nil
                        username = ""; apiKey = ""
                    }
                    .font(.caption)
                }
            } else {
                TextField("RetroAchievements username", text: $username)
                    .textContentType(.username)
                    #if !os(macOS)
                    .autocapitalization(.none)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Web API key", text: $apiKey)
                    .autocorrectionDisabled()

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(LSTheme.working)
                }

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
        } header: {
            Text("RetroAchievements")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Find your Web API key on retroachievements.org under Settings → Keys. It reads your account, so it's kept in the Keychain and sent only when syncing.")
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
            let confirmed = try await RetroAchievementsService.verify(
                username: username, apiKey: apiKey)
            // Save the name RA itself reports, so the casing matches theirs.
            guard RACredentials.save(.init(username: confirmed, apiKey: apiKey)) else {
                error = "Couldn't save to the Keychain."
                return
            }
            connectedAs = confirmed
            apiKey = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}
