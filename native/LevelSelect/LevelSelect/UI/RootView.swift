import SwiftUI
import SwiftData

/// The library. NavigationSplitView on iPad/Mac, collapses to a stack on iPhone.
/// Continue Playing card + status-grouped sections + search + status filter.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var selectionID: UUID?
    @State private var searchText = ""
    @State private var statusFilter: GameStatus?
    @State private var showingAdd = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("LevelSelect")
                .searchable(text: $searchText, prompt: "Search games")
                .toolbar { toolbarContent }
        } detail: {
            if let id = selectionID, let game = games.first(where: { $0.id == id }) {
                NavigationStack { GameDetailView(game: game) }
            } else {
                ContentUnavailableView("Select a game", systemImage: "gamecontroller")
            }
        }
        .sheet(isPresented: $showingAdd) { AddGameSheet() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if games.isEmpty {
            ContentUnavailableView {
                Label("Your library is empty", systemImage: "gamecontroller")
            } description: {
                Text("Add a game to get started.")
            } actions: {
                Button("Add Game") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List(selection: $selectionID) {
                if showContinue, let cp = continueGame {
                    Section("Continue Playing") {
                        ContinueRow(game: cp).tag(cp.id)
                    }
                }
                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    let items = grouped[status] ?? []
                    if !items.isEmpty {
                        Section("\(status.sectionTitle) (\(items.count))") {
                            ForEach(items) { game in
                                GameRow(game: game).tag(game.id)
                            }
                        }
                    }
                }
            }
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    Text("All").tag(GameStatus?.none)
                    ForEach(GameStatus.displayOrder, id: \.self) { s in
                        Text(s.sectionTitle).tag(GameStatus?.some(s))
                    }
                }
            } label: {
                Label("Filter", systemImage: statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingAdd = true
            } label: {
                Label("Add Game", systemImage: "plus")
            }
        }
        ToolbarItem {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    // MARK: Derived data

    private var showContinue: Bool { searchText.isEmpty && statusFilter == nil }

    private var visible: [Game] {
        games.filter { g in
            (statusFilter == nil || g.status == statusFilter)
                && (searchText.isEmpty || g.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var grouped: [GameStatus: [Game]] {
        Dictionary(grouping: visible, by: \.status)
    }

    private var continueGame: Game? {
        games
            .filter { $0.status == .playing || $0.status == .paused }
            .max { lastActivity($0) < lastActivity($1) }
    }

    private func lastActivity(_ g: Game) -> Date {
        (g.playthroughs ?? []).compactMap(\.lastPlayedAt).max() ?? g.addedAt
    }
}

/// Richer "Continue Playing" row: cover, name, status, and last-session hint.
private struct ContinueRow: View {
    let game: Game

    private var playthrough: Playthrough? {
        (game.playthroughs ?? []).first { $0.deletedAt == nil }
    }

    var body: some View {
        HStack(spacing: 12) {
            CoverThumb(urlString: game.coverURLString)
                .frame(width: 56, height: 74)

            VStack(alignment: .leading, spacing: 4) {
                Text(game.name).font(.headline).lineLimit(1)

                if let active = playthrough?.activeSession {
                    Label(active.state == .running ? "In progress" : "Paused",
                          systemImage: active.state == .running ? "record.circle" : "pause.circle")
                        .font(.caption)
                        .foregroundStyle(active.state == .running ? .green : .orange)
                } else if let last = playthrough?.lastPlayedAt {
                    Text("Last played \(last, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let total = playthrough?.totalPlaytime() ?? 0
                if total > 0 {
                    Text(Format.duration(total) + " played")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RootView()
        .modelContainer(LevelSelectStore.makeContainer(inMemory: true))
}
