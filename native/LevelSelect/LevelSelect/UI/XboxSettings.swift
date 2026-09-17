import SwiftUI
import SwiftData

/// Connect Xbox through Microsoft's own sign-in page, and bring the library in.
struct XboxSettings: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    @State private var connected = XboxCredentials.current
    @State private var working = false
    @State private var reading = false
    @State private var message: String?
    @State private var error: String?
    @State private var reviewing: SteamSettings.LibraryRows?

    var body: some View {
        Section {
            if !XboxService.isAvailable {
                Label("Xbox isn't set up in this build yet.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let connected {
                LabeledContent("Connected") {
                    Text(connected.gamertag ?? "Xbox").foregroundStyle(.secondary)
                }
                Button {
                    Task { await readLibrary() }
                } label: {
                    if reading {
                        HStack { ProgressView().controlSize(.small); Text("Reading your Xbox games…") }
                    } else {
                        Label("Import my Xbox library", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(reading)
                .sheet(item: $reviewing) { batch in
                    CSVImportView(rows: batch.rows, title: "Import from Xbox", sourceLabel: "Xbox")
                        .lsSheet()
                }

                Button("Disconnect", role: .destructive) {
                    guard XboxCredentials.clear() else {
                        error = "Couldn't remove the sign-in from the Keychain. Still connected."
                        return
                    }
                    XboxService.forget()
                    error = nil
                    message = nil
                    self.connected = nil
                }
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        if working { ProgressView().controlSize(.small) }
                        Label("Sign in with Microsoft", systemImage: "person.crop.circle")
                    }
                }
                .disabled(working)
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
            Text("Xbox")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("You sign in on Microsoft's own page; LevelSelect never sees your password. It keeps a sign-in token in this device's Keychain, sent only to Microsoft and Xbox. Xbox doesn't share playtime with apps, so Xbox games come in without hours.")
                Text("Stays on this device — sign in separately on each one.")
            }
            .font(.caption2)
        }
    }

    private func connect() async {
        working = true
        error = nil
        defer { working = false }
        #if canImport(AuthenticationServices) && !os(watchOS)
        do {
            let value = try await XboxService.connect()
            guard XboxCredentials.save(value) else {
                error = "Couldn't save to the Keychain."
                return
            }
            connected = value
        } catch is CancellationError {
            // Backing out of Microsoft's page is an answer, not an error.
        } catch {
            self.error = error.localizedDescription
        }
        #endif
    }

    private func readLibrary() async {
        reading = true
        error = nil
        message = nil
        defer { reading = false }
        do {
            let titles = try await XboxService.titles()
            let keys = CSVImport.LibraryKeys(games)
            let rows = CSVImport.dropNothingToAdd(
                XboxService.libraryRows(from: titles, existingNames: keys.wishlistNames,
                                        library: keys.byName),
                context: context)
            guard !rows.isEmpty else {
                message = titles.isEmpty
                    ? "Xbox lists no played games on this account."
                    : "Every Xbox game here is already in your library, on its console."
                return
            }
            message = "\(rows.count) Xbox games to review."
            reviewing = SteamSettings.LibraryRows(rows: rows)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
