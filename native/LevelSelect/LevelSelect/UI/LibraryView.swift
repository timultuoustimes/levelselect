import SwiftUI
import SwiftData

/// Library tab: the whole collection as status-grouped rows with search and a
/// status filter. Complements Home's carousels with a dense, scannable view.
struct LibraryTab: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var searchText = ""
    @State private var statusFilter: GameStatus?
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    let items = grouped[status] ?? []
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { game in
                                NavigationLink(value: game) { GameRow(game: game) }
                                    .listRowBackground(Color.clear)
                            }
                        } header: {
                            Label("\(status.sectionTitle) (\(items.count))", systemImage: status.systemImage)
                                .foregroundStyle(status == .playing ? AnyShapeStyle(LSTheme.purple) : AnyShapeStyle(.secondary))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .lsBackground()
            .overlay {
                if visible.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("No games", systemImage: "gamecontroller")
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .searchable(text: $searchText, prompt: "Search games")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("Status", selection: $statusFilter) {
                            Text("All").tag(GameStatus?.none)
                            ForEach(GameStatus.displayOrder, id: \.self) { s in
                                Label(s.sectionTitle, systemImage: s.systemImage).tag(GameStatus?.some(s))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: statusFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Label("Add Game", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddGameSheet() }
    }

    private var visible: [Game] {
        games.filter { g in
            (statusFilter == nil || g.status == statusFilter)
                && (searchText.isEmpty || g.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var grouped: [GameStatus: [Game]] {
        Dictionary(grouping: visible, by: \.status)
    }
}
