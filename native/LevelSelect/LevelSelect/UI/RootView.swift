import SwiftUI
import SwiftData

/// Placeholder Library shell. NavigationSplitView on iPad/Mac, collapses to a
/// stack on iPhone. Real Library sections (Continue Playing, Now Playing, …)
/// come in Phase 1.6.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    var body: some View {
        NavigationSplitView {
            Group {
                if games.isEmpty {
                    ContentUnavailableView(
                        "Your library is empty",
                        systemImage: "gamecontroller",
                        description: Text("Add a game to get started.")
                    )
                } else {
                    List(games) { game in
                        VStack(alignment: .leading) {
                            Text(game.name).font(.headline)
                            Text(game.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("LevelSelect")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add sample", systemImage: "plus") {
                        Repository(context).addGame(name: "Sample Game", status: .playing)
                    }
                }
            }
        } detail: {
            Text("Select a game")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(LevelSelectStore.makeContainer(inMemory: true))
}
