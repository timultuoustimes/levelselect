import SwiftUI
import SwiftData

/// Connect PlayStation with a pasted NPSSO, and bring the library in.
///
/// Sony has no public API, so this is the PlayStation App's own sign-in (see
/// `PlayStationService`). The NPSSO works like a password: it is exchanged once
/// and never kept. What stays is a refresh token in this device's Keychain.
struct PlayStationSettings: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    @State private var npsso = ""
    @State private var checking = false
    @State private var error: String?
    @State private var connected = PlayStationCredentials.current
    @State private var reading = false
    @State private var message: String?
    @State private var reviewing: SteamSettings.LibraryRows?
    @State private var lastRead: [PlayStationService.PlayedGame]?

    var body: some View {
        Section {
            if connected != nil {
                LabeledContent("Connected") {
                    Text("PlayStation Network").foregroundStyle(.secondary)
                }
                Button {
                    Task { await readLibrary() }
                } label: {
                    if reading {
                        HStack { ProgressView().controlSize(.small); Text("Reading your PlayStation games…") }
                    } else {
                        Label("Import my PlayStation library", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(reading)
                .sheet(item: $reviewing, onDismiss: applyLastReadPlaytime) { batch in
                    CSVImportView(rows: batch.rows, title: "Import from PlayStation", sourceLabel: "PlayStation")
                        .lsSheet()
                }

                Button("Disconnect", role: .destructive) {
                    guard PlayStationCredentials.clear() else {
                        error = "Couldn't remove the sign-in from the Keychain. Still connected."
                        return
                    }
                    PlayStationService.forget()
                    error = nil
                    message = nil
                    connected = nil
                }
            } else {
                Button {
                    openURL(PlayStationService.signInPage)
                } label: {
                    Label("1. Sign in on playstation.com", systemImage: "person.crop.circle")
                }
                Button {
                    openURL(PlayStationService.npssoPage)
                } label: {
                    Label("2. Open the NPSSO page and copy the value", systemImage: "doc.on.doc")
                }
                HStack {
                    SecureField("3. Paste the NPSSO", text: $npsso)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { npsso = first }
                    }
                    .labelStyle(.iconOnly)
                }
                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        if checking { ProgressView().controlSize(.small) }
                        Text(checking ? "Checking…" : "Connect")
                    }
                }
                .disabled(checking || npsso.trimmingCharacters(in: .whitespaces).isEmpty)
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
            Text("PlayStation")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("PlayStation has no public way in, so this uses the same sign-in as Sony's PlayStation App. The NPSSO works like your password: LevelSelect trades it with Sony once and doesn't keep it. What it keeps is a sign-in token in this device's Keychain, sent only to Sony. Connect again if it expires, about every two months.")
                Text("Stays on this device — enter it separately on each one.")
            }
            .font(.caption2)
        }
    }

    private func connect() async {
        checking = true
        error = nil
        defer { checking = false }
        do {
            let value = try await PlayStationService.connect(npsso: npsso)
            guard PlayStationCredentials.save(value) else {
                error = "Couldn't save to the Keychain."
                return
            }
            connected = value
            npsso = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func readLibrary() async {
        reading = true
        error = nil
        message = nil
        defer { reading = false }
        do {
            let played = try await PlayStationService.playedGames()
            lastRead = played
            let timed = applyPlaytime(played)
            let keys = CSVImport.LibraryKeys(games)
            let rows = CSVImport.dropNothingToAdd(
                PlayStationService.libraryRows(from: played, existingNames: keys.wishlistNames,
                                               library: keys.byName),
                context: context)
            let playtime = timed > 0 ? " PlayStation playtime is on \(timed) of your games." : ""
            guard !rows.isEmpty else {
                message = played.isEmpty
                    ? "PlayStation lists no PS4 or PS5 games on this account."
                    : "Every PlayStation game here is already in your library, on its console." + playtime
                return
            }
            message = "\(rows.count) PlayStation games to review." + playtime
            reviewing = SteamSettings.LibraryRows(rows: rows)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    private func applyPlaytime(_ played: [PlayStationService.PlayedGame]) -> Int {
        let matches = PlayStationService.playtimeMatches(
            games: played, library: games.map { (id: $0.id, name: $0.name) })
        let repo = Repository(context)
        var count = 0
        for game in games {
            if let minutes = matches[game.id], repo.applyPlayStationPlaytime(minutes: minutes, to: game) {
                count += 1
            }
        }
        return count
    }

    private func applyLastReadPlaytime() {
        guard let lastRead else { return }
        applyPlaytime(lastRead)
    }
}
