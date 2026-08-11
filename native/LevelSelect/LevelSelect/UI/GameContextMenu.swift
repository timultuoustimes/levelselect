import SwiftUI
import SwiftData

/// Press-and-hold menu for any game surface (covers, rows): quick session
/// control, status change, rating, pin, delete — without opening the page.
struct GameContextMenuModifier: ViewModifier {
    let game: Game
    @Environment(\.modelContext) private var context

    private var repo: Repository { Repository(context) }
    private var playthrough: Playthrough? {
        (game.playthroughs ?? []).first { $0.deletedAt == nil }
    }

    func body(content: Content) -> some View {
        content.contextMenu {
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

            Divider()

            Button(role: .destructive) {
                repo.softDelete(game)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

extension View {
    func gameContextMenu(_ game: Game) -> some View {
        modifier(GameContextMenuModifier(game: game))
    }
}
