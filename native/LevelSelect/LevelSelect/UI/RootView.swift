import SwiftUI
import SwiftData

/// Home: Continue Playing hero + horizontal cover carousels per status,
/// on the purple-gradient dark theme (web-app parity). Searching switches to
/// a results list.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var searchText = ""
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if games.isEmpty {
                    emptyState
                } else if searching {
                    searchResults
                } else {
                    home
                }
            }
            .lsBackground()
            .navigationTitle("LevelSelect")
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameStatus.self) { StatusListView(status: $0) }
            .searchable(text: $searchText, prompt: "Search games")
            .toolbar { toolbarContent }
        }
        .tint(LSTheme.purple)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAdd) { AddGameSheet() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    // MARK: Home

    private var home: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let cp = continueGame {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONTINUE PLAYING")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .kerning(1)
                        NavigationLink(value: cp) {
                            ContinueHeroCard(game: cp) { play(cp) }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    let items = grouped[status] ?? []
                    if !items.isEmpty {
                        StatusCarousel(status: status, games: items) {
                            path.append(status)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .scrollIndicators(.hidden)
    }

    private var searchResults: some View {
        List {
            ForEach(visible) { game in
                NavigationLink(value: game) { GameRow(game: game) }
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if visible.isEmpty { ContentUnavailableView.search(text: searchText) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your library is empty", systemImage: "gamecontroller")
        } description: {
            Text("Add a game or import your library from Settings.")
        } actions: {
            Button("Add Game") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showingAdd = true } label: {
                Label("Add Game", systemImage: "plus")
            }
        }
    }

    // MARK: Derived

    private var searching: Bool { !searchText.isEmpty }

    private var visible: [Game] {
        games.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var grouped: [GameStatus: [Game]] {
        Dictionary(grouping: games, by: \.status)
            .mapValues { $0.sorted { sortKey($0) > sortKey($1) } }
    }

    private var continueGame: Game? {
        games
            .filter { $0.status == .playing || $0.status == .paused }
            .max { sortKey($0) < sortKey($1) }
    }

    /// Pinned first, then most recent activity.
    private func sortKey(_ g: Game) -> (Bool, Date) {
        (g.pinned, (g.playthroughs ?? []).compactMap(\.lastPlayedAt).max() ?? g.addedAt)
    }

    private func play(_ game: Game) {
        let repo = Repository(context)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        if pt.activeSession == nil {
            repo.startSession(on: pt)
        }
        // Stay on Home; the hero card flips to "Session in progress".
    }
}

/// "See all" for one status: vertical rows.
struct StatusListView: View {
    let status: GameStatus
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var allGames: [Game]

    private var games: [Game] { allGames.filter { $0.status == status } }

    var body: some View {
        List {
            ForEach(games) { game in
                NavigationLink(value: game) { GameRow(game: game) }
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .lsBackground()
        .navigationTitle(status.sectionTitle)
    }
}

// Tuple comparison helper for (Bool, Date) sort keys: pinned wins, then date.
private func > (lhs: (Bool, Date), rhs: (Bool, Date)) -> Bool {
    if lhs.0 != rhs.0 { return lhs.0 }
    return lhs.1 > rhs.1
}
private func < (lhs: (Bool, Date), rhs: (Bool, Date)) -> Bool { rhs > lhs }

#Preview {
    RootView()
        .modelContainer(LevelSelectStore.makeContainer(inMemory: true))
}
