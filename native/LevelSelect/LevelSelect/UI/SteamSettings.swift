import SwiftUI
import SwiftData

/// Connect Steam with your own Web API key, and bring its library in.
///
/// RetroAchievements' shape: verified before saving, kept in this device's
/// Keychain, sent only to Steam. The library goes through the CSV import's
/// review, so Steam games are matched to IGDB the same careful way — by Steam
/// app id where IGDB records one, by name where it doesn't — and nothing is
/// added until the review says go.
struct SteamSettings: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    @State private var profile = ""
    @State private var apiKey = ""
    @State private var checking = false
    @State private var error: String?
    @State private var connected = SteamCredentials.current
    @State private var reading = false
    @State private var message: String?
    @State private var reviewing: LibraryRows?
    @State private var link: DekuLinkTarget?
    /// The last library read, so closing the review can give the games it
    /// just added their Steam playtime too.
    @State private var lastRead: (owned: [SteamService.OwnedGame], igdbByApp: [Int: Int])?

    struct LibraryRows: Identifiable {
        let id = UUID()
        let rows: [CSVImport.Row]
    }

    var body: some View {
        Section {
            if let connected {
                LabeledContent("Connected") {
                    Text(connected.personaName ?? connected.steamID)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await readLibrary(connected) }
                } label: {
                    if reading {
                        HStack { ProgressView().controlSize(.small); Text("Reading your Steam library…") }
                    } else {
                        Label("Import my Steam library", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(reading)
                // On the row, not the Section — a sheet on a Section becomes
                // one per child and flickers.
                .sheet(item: $reviewing, onDismiss: applyLastReadPlaytime) { batch in
                    CSVImportView(rows: batch.rows, title: "Import from Steam", sourceLabel: "Steam")
                        .lsSheet()
                }

                Button {
                    link = SteamService.profilePage(connected.steamID).map { DekuLinkTarget(url: $0) }
                } label: {
                    Label("Open your profile", systemImage: "arrow.up.right.square")
                }
                .dekuBrowser(target: $link)

                Button("Disconnect", role: .destructive) {
                    // Reported, not assumed, as in RetroAchievementsSettings.
                    guard SteamCredentials.clear() else {
                        error = "Couldn't remove the key from the Keychain. Still connected."
                        return
                    }
                    error = nil
                    message = nil
                    self.connected = nil
                    profile = ""; apiKey = ""
                }
            } else {
                TextField("Steam profile link or name", text: $profile)
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
                          || profile.trimmingCharacters(in: .whitespaces).isEmpty
                          || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    link = DekuLinkTarget(url: SteamService.apiKeyPage)
                } label: {
                    Label("Get a key from Steam", systemImage: "key")
                }
                .dekuBrowser(target: $link)
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(LSTheme.working)
            }
        } header: {
            Text("Steam")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("A game's Steam achievement list needs nothing from you — pick Import from Steam on its tracker. Connecting adds your library and the achievements you've earned, which Steam only shares with a Web API key you register on Steam (its form asks for a domain name) and with Privacy → Game details set to Public. The key reads your account, so it's kept in the Keychain and sent only to Steam.")
                Text("Stays on this device — enter it separately on each one.")
            }
            .font(.caption2)
        }
    }

    /// Steam's playtime onto each library game it belongs to, in that game's
    /// Steam playthrough. Returns how many games got some.
    @discardableResult
    private func applyPlaytime(_ owned: [SteamService.OwnedGame], _ igdbByApp: [Int: Int]) -> Int {
        let matches = SteamService.playtimeMatches(
            owned: owned, igdbByApp: igdbByApp,
            library: games.map { (id: $0.id, igdbID: $0.igdbID, name: $0.name) })
        let repo = Repository(context)
        var count = 0
        for game in games {
            if let minutes = matches[game.id], repo.applySteamPlaytime(minutes: minutes, to: game) {
                count += 1
            }
        }
        return count
    }

    private func applyLastReadPlaytime() {
        guard let lastRead else { return }
        applyPlaytime(lastRead.owned, lastRead.igdbByApp)
    }

    private func connect() async {
        checking = true
        error = nil
        defer { checking = false }
        do {
            let confirmed = try await SteamService.verify(profile: profile, apiKey: apiKey)
            guard SteamCredentials.save(confirmed) else {
                error = "Couldn't save to the Keychain."
                return
            }
            connected = confirmed
            apiKey = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func readLibrary(_ credentials: SteamCredentials.Value) async {
        reading = true
        error = nil
        message = nil
        defer { reading = false }
        do {
            let owned = try await SteamService.ownedGames(credentials: credentials)
            let igdbByApp = await SteamService.igdbIDs(forAppIDs: owned.map(\.appID))
            let keys = CSVImport.LibraryKeys(games)
            let rows = CSVImport.dropNothingToAdd(SteamService.libraryRows(
                from: owned, igdbByApp: igdbByApp,
                existingIGDBIDs: keys.wishlistIGDBIDs,
                existingNames: keys.wishlistNames,
                libraryByIGDB: keys.byIGDB, library: keys.byName), context: context)
            let newRows = rows.filter { $0.existingGameID == nil }.count
            // Playtime for the games already here, now; the ones the review
            // adds get theirs when it closes.
            lastRead = (owned, igdbByApp)
            let timed = applyPlaytime(owned, igdbByApp)
            let playtime = timed > 0 ? " Steam playtime is on \(timed) of your games." : ""
            guard !rows.isEmpty else {
                message = owned.isEmpty
                    ? "Steam lists no games on this account."
                    : "All \(owned.count) of your Steam games are already in your library, on PC." + playtime
                return
            }
            let already = owned.count - newRows
            message = "\(owned.count) games on Steam" + (already > 0 ? ", \(already) already in your library." : ".") + playtime
            reviewing = LibraryRows(rows: rows)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
