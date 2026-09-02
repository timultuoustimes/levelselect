import SwiftUI
import SwiftData
#if canImport(AuthenticationServices) && !os(watchOS)
import AuthenticationServices
#endif

/// Connecting itch.io, and bringing its games in.
///
/// The shape RetroAchievements already established: a connection you make
/// once, a credential that stays on the device, and an import that only ever
/// adds. Nothing here signs you up for anything — an itch account is one you
/// already have, and the app is asking for permission to read it.
struct ItchSettings: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil })
    private var games: [Game]

    @State private var connected = ItchCredentials.isConfigured
    @State private var username = ItchCredentials.current?.username
    @State private var working = false
    @State private var message: String?
    @State private var lastImport: Report?

    var body: some View {
        Section {
            if !ItchService.isAvailable {
                Label("itch.io isn't configured in this build.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if connected {
                LabeledContent("Connected") {
                    Text(username.map { "@\($0)" } ?? "itch.io")
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await importLibrary() }
                } label: {
                    if working {
                        HStack { ProgressView().controlSize(.small); Text("Reading your itch.io library…") }
                    } else {
                        Label("Import my itch.io games", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(working)

                Button(role: .destructive) {
                    // False means the Keychain delete failed, and claiming
                    // "disconnected" over a token still on the device is the
                    // one lie this screen must not tell.
                    if ItchCredentials.clear() {
                        connected = false
                        username = nil
                        message = nil
                    } else {
                        message = "Couldn't remove the token. Still connected."
                    }
                } label: {
                    Text("Disconnect")
                }
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    Label("Connect itch.io", systemImage: "link")
                }
                .disabled(working)
            }

            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let lastImport {
                Text(.init(lastImport.summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("itch.io")
        } footer: {
            Text("Brings in the games you bought or claimed on itch.io, so ones IGDB has never heard of can still be tracked. It cannot see your collections — itch reports how many games one holds but not which — and a free game taken straight to the downloads leaves no record at all, so those are added by hand. Your token stays in this device's Keychain, is never synced, and goes to itch.io directly — never through our server.")
        }
    }

    #if canImport(AuthenticationServices) && !os(watchOS)
    @MainActor
    private func connect() async {
        // A fresh, unguessable value per attempt: the callback is a URL
        // anything on the device could open, and `state` is what says this
        // response answers the request we made.
        let state = UUID().uuidString
        guard let url = ItchService.authorizationURL(state: state) else { return }
        working = true
        defer { working = false }

        do {
            let callback = try await ItchAuth.run(url: url, scheme: "levelselect")
            guard let token = ItchService.token(from: callback, expecting: state) else {
                message = "That response didn't match the request. Try connecting again."
                return
            }
            guard ItchCredentials.save(.init(token: token, username: nil)) else {
                message = "Couldn't save the token to the Keychain."
                return
            }
            connected = true
            message = nil
        } catch is CancellationError {
            // Backing out of a permission screen is an answer, not an error.
        } catch {
            message = "Connection cancelled."
        }
    }
    #else
    private func connect() async {}
    #endif

    /// Additive only, matching every other import in the app.
    ///
    /// Matched by name because itch games have no IGDB id to match on — which
    /// is the whole reason they need this. A name collision costs a duplicate,
    /// which is recoverable; overwriting a game someone has played is not.
    @MainActor
    private func importLibrary() async {
        working = true
        defer { working = false }
        do {
            var ownedProbe = ItchService.Probe()
            let owned = try await ItchService.ownedGames(probe: &ownedProbe)

            var byID: [Int: ItchService.OwnedGame] = [:]
            for game in owned { byID[game.id] = game }

            let existing = Set(games.map { $0.name.lowercased() })
            let repo = Repository(context)
            var added = 0
            for game in byID.values where !existing.contains(game.name.lowercased()) {
                let new = repo.addGame(name: game.name, status: .backlog)
                repo.edit(new) {
                    $0.platforms = ["itch.io"]
                    $0.ownedPlatforms = ["itch.io"]
                    if let cover = game.coverURL { $0.coverURLString = cover }
                }
                added += 1
            }
            lastImport = Report(added: added,
                                already: byID.count - added,
                                owned: owned.count,
                                ownedProbe: ownedProbe.line)
            message = nil
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "Couldn't read your itch.io library."
        }
    }
}

/// What the import actually saw, per source.
///
/// The first version reported only "0 games added", which is the least useful
/// true sentence available — Tim: "nothing comes through into the app... I'm
/// not sure what it's supposed to be from." Owned keys and collections are
/// different things on itch and a library can be entirely one of them, so the
/// report names both and an empty result says which was empty.
struct Report {
    var added: Int
    var already: Int
    var owned: Int
    /// What the endpoint actually answered. Shown only when nothing came
    /// back, because at that point "0 games" is a symptom and this is the
    /// only thing separating a wrong call from an empty account.
    var ownedProbe: String

    var summary: String {
        guard owned > 0 else {
            return "itch.io has no owned games on this account. A game only lands there when you BUY or CLAIM it — "
                 + "the \"No thanks, just take me to the downloads\" link records nothing at all, not even a "
                 + "zero-dollar purchase. Collections cannot help: itch's API reports how many games a collection holds but not which ones, so those need adding by hand."
                 + "\n\nowned-keys: \(ownedProbe)"
        }
        return "^[\(added) game](inflect: true) added, \(already) already in your library, "
             + "from \(owned) owned on itch.io."
    }
}
