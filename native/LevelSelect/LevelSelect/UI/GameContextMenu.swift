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

    private var repo: Repository { Repository(context) }
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
                game.pinned.toggle()
            } label: {
                Label(game.pinned ? "Unpin" : "Pin",
                      systemImage: game.pinned ? "pin.slash" : "pin")
            }

            // Status
            Menu {
                ForEach(GameStatus.allCases, id: \.self) { s in
                    Button {
                        game.status = s
                    } label: {
                        Label(s.sectionTitle,
                              systemImage: game.status == s ? "checkmark" : s.systemImage)
                    }
                }
            } label: {
                Label("Status", systemImage: game.status.systemImage)
            }

            // Ownership (multi-select toggles)
            Menu {
                ForEach(Ownership.allCases, id: \.self) { kind in
                    let on = game.ownership.contains(kind.rawValue)
                    Button {
                        if on { game.ownership.removeAll { $0 == kind.rawValue } }
                        else { game.ownership.append(kind.rawValue) }
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
                        game.rating = stars
                    } label: {
                        Label(String(repeating: "★", count: stars),
                              systemImage: game.rating == stars ? "checkmark" : "star")
                    }
                }
                if game.rating != nil {
                    Button("Clear Rating") { game.rating = nil }
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
                Label("Add to Collection", systemImage: "square.stack")
            }

            Divider()

            Button(role: .destructive) {
                repo.softDelete(game)
            } label: {
                Label("Delete", systemImage: "trash")
            }
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
    }
}

extension View {
    func gameContextMenu(_ game: Game) -> some View {
        modifier(GameContextMenuModifier(game: game))
    }
}
