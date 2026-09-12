import SwiftUI
import SwiftData

/// Press-and-hold menu for any game surface (covers, rows): quick session
/// control, status change, rating, pin, delete — without opening the page.
struct GameContextMenuModifier: ViewModifier {
    let game: Game
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil }, sort: \GameCollection.name)
    private var collections: [GameCollection]
    @State private var newCollection = false
    @State private var newCollectionName = ""
    @State private var confirmingDelete = false
    @State private var browserTarget: DekuLinkTarget?

    private var repo: Repository { Repository(context) }

    private var statusBinding: Binding<GameStatus> {
        Binding(get: { game.status },
                set: { newValue in repo.edit(game) { $0.status = newValue } })
    }
    private var playthrough: Playthrough? {
        game.activePlaythrough
    }

    func body(content: Content) -> some View {
        content
        .contextMenu {
            // Session
            if let active = playthrough?.activeSession {
                Button {
                    repo.stopSession(active)
                } label: {
                    Label("Stop Session", systemImage: "stop.fill")
                }
            } else {
                Button {
                    let pt = repo.ensureDefaultPlaythrough(for: game)
                    repo.startSession(on: pt)
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
            }

            Button {
                repo.edit(game) { $0.pinned.toggle() }
            } label: {
                Label(game.pinned ? "Unpin" : "Pin",
                      systemImage: game.pinned ? "pin.slash" : "pin")
            }

            // Status
            Menu {
                Picker("Status", selection: statusBinding) {
                    ForEach(GameStatus.displayOrder, id: \.self) { s in
                        Label(s.label, systemImage: s.systemImage).tag(s)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Status: \(game.status.label)", systemImage: game.status.systemImage)
            }

            // Ownership (multi-select toggles)
            Menu {
                // Same rule as the game page's chips: the ones this library
                // uses, plus any this game already carries.
                ForEach(Ownership.allCases.filter {
                    ThemePalette.ownershipChips.contains($0)
                        || game.ownership.contains($0.rawValue)
                }, id: \.self) { kind in
                    let on = game.ownership.contains(kind.rawValue)
                    Button {
                        repo.edit(game) {
                            if on { $0.ownership.removeAll { $0 == kind.rawValue } }
                            else { $0.ownership.append(kind.rawValue) }
                        }
                    } label: {
                        Label(kind.label, systemImage: on ? "checkmark" : kind.systemImage)
                    }
                }
            } label: {
                Label("Ownership", systemImage: "shippingbox")
            }

            // Rating
            Menu {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        repo.edit(game) { $0.rating = stars }
                    } label: {
                        Label(String(repeating: "★", count: stars),
                              systemImage: game.rating == stars ? "checkmark" : "star")
                    }
                }
                if game.rating != nil {
                    Button("Clear Rating") { repo.edit(game) { $0.rating = nil } }
                }
            } label: {
                Label("Rate", systemImage: "star")
            }

            Menu {
                ForEach(collections) { collection in
                    Button {
                        repo.setMembership(collection, game: game, member: !collection.contains(game))
                    } label: {
                        Label(collection.name,
                              systemImage: collection.contains(game) ? "checkmark" : "square.stack")
                    }
                }
                Divider()
                Button {
                    newCollectionName = ""; newCollection = true
                } label: { Label("New Collection…", systemImage: "plus") }
            } label: {
                Label("Collections", systemImage: "square.stack")
            }

            Divider()

            // The same three links the game page carries, at the depth they
            // are actually wanted.
            //
            // Tim, about the wishlist: *"you don't have to open the game page,
            // scroll down to game info and then click it there."* Checking a
            // price is the most repeated thing anyone does with a wishlist,
            // and it was four interactions deep — a tap, two scrolls and a
            // tap — for something that is one press-and-hold away from every
            // cover in the app.
            //
            // Flat rather than an "Open in…" submenu on purpose: a submenu
            // would put the tap back that this removes.
            Button {
                browserTarget = DekuLinkTarget(url: DekuLinks.search(for: game.name))
            } label: {
                Label("Deku Deals", systemImage: "tag.fill")
            }

            // Same availability rule as the game page: a slug is what makes
            // the link land on the game rather than a search page.
            if let slug = game.igdbSlug,
               let url = URL(string: "https://www.igdb.com/games/\(slug)") {
                Button {
                    browserTarget = DekuLinkTarget(url: url)
                } label: {
                    Label("IGDB", systemImage: "arrow.up.right.square")
                }
            }

            // Rare on a wishlist game and common on a tracked one — the menu
            // is shared by every surface, so it offers what this game has.
            if let raID = game.trackerSchema.flatMap({
                TrackerSchemaJSON.retroAchievementsGameID(in: $0.jsonData)
            }) {
                Button {
                    browserTarget = DekuLinkTarget(url: RAArt.gamePage(raID))
                } label: {
                    Label("RetroAchievements", systemImage: "trophy.fill")
                }
            }

            Divider()

            // The identical delete was confirmed and explained as recoverable
            // from the game page and instant from here, so what "Delete" meant
            // depended on where you happened to be holding. One contract: name
            // the game, say where it goes.
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete Game…", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete “\(game.name)”?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete Game", role: .destructive) {
                let undo = AppNavigator.DeletedGame(id: game.id, name: game.name)
                repo.softDelete(game)
                AppNavigator.shared.deletedGame = undo
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It moves to Recently Deleted in Settings, with its sessions and progress. You can put it back for 30 days.")
        }
        .alert("New Collection", isPresented: $newCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let collection = repo.createCollection(name: name)
                repo.setMembership(collection, game: game, member: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds “\(game.name)” to a new collection.")
        }
        // The same in-app browser the game page opens, not Safari — a price
        // check shouldn't cost leaving the app, and on Deku the signed-in
        // session is the whole point of the shared cookie store.
        .dekuBrowser(target: $browserTarget)
    }
}

extension View {
    func gameContextMenu(_ game: Game) -> some View {
        modifier(GameContextMenuModifier(game: game))
    }
}
