import SwiftUI
import SwiftData

/// Library tab — web-app parity: search (games/franchises/tags), status
/// filter with counts, sort menu, tag chips, and a cover GRID with
/// adjustable size (or a dense list). Everything persists.
struct LibraryTab: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var searchText = ""
    @State private var statusFilter: GameStatus?
    @State private var tagFilter: String?
    @State private var showingAdd = false

    @AppStorage("librarySort") private var sortRaw = LibrarySort.status.rawValue
    @AppStorage("libraryViewMode") private var viewModeRaw = LibraryViewMode.grid.rawValue
    @AppStorage("libraryGridSize") private var gridSizeRaw = GridSize.medium.rawValue

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .status }
    private var viewMode: LibraryViewMode { LibraryViewMode(rawValue: viewModeRaw) ?? .grid }
    private var gridSize: GridSize { GridSize(rawValue: gridSizeRaw) ?? .medium }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !allTags.isEmpty { tagChips }
                content
            }
            .lsBackground()
            .navigationTitle("Library")
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .searchable(text: $searchText, prompt: "Search games or franchises")
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showingAdd) { AddGameSheet() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        Group {
            switch viewMode {
            case .grid: gridView
            case .list: listView
            }
        }
        .overlay {
            if visible.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No games", systemImage: "gamecontroller")
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if sort == .status {
                    ForEach(GameStatus.displayOrder, id: \.self) { status in
                        let items = grouped[status] ?? []
                        if !items.isEmpty {
                            sectionHeader(status, count: items.count)
                            grid(items)
                        }
                    }
                } else {
                    grid(sorted)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private func grid(_ items: [Game]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: gridSize.minWidth), spacing: 12)],
            spacing: 16
        ) {
            ForEach(items) { game in
                NavigationLink(value: game) {
                    LibraryGridCell(game: game, size: gridSize)
                }
                .buttonStyle(PressableCardStyle())
                .gameContextMenu(game)
            }
        }
    }

    private var listView: some View {
        List {
            if sort == .status {
                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    let items = grouped[status] ?? []
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { game in
                                NavigationLink(value: game) { GameRow(game: game) }
                                    .listRowBackground(Color.clear)
                                    .gameContextMenu(game)
                            }
                        } header: {
                            Label("\(status.sectionTitle) (\(items.count))", systemImage: status.systemImage)
                                .foregroundStyle(AnyShapeStyle(status.color))
                        }
                    }
                }
            } else {
                ForEach(sorted) { game in
                    NavigationLink(value: game) { GameRow(game: game) }
                        .listRowBackground(Color.clear)
                        .gameContextMenu(game)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func sectionHeader(_ status: GameStatus, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(status.sectionTitle)
                .font(.subheadline.weight(.semibold))
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: Tag chips

    private var allTags: [String] {
        var counts: [String: Int] = [:]
        for g in games { for t in g.userTags { counts[t, default: 0] += 1 } }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    let active = tagFilter == tag
                    Button {
                        tagFilter = active ? nil : tag
                    } label: {
                        Text("#\(tag)")
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                active ? LSTheme.accent.opacity(0.45) : .white.opacity(0.07),
                                in: .capsule)
                            .overlay(Capsule().strokeBorder(
                                active ? LSTheme.accent : .white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    Label("All (\(games.count))", systemImage: "circle.grid.2x2").tag(GameStatus?.none)
                    ForEach(GameStatus.displayOrder, id: \.self) { s in
                        let count = statusCounts[s] ?? 0
                        if count > 0 {
                            Label("\(s.sectionTitle) (\(count))", systemImage: s.systemImage)
                                .tag(GameStatus?.some(s))
                        }
                    }
                }
            } label: {
                Label("Filter", systemImage: statusFilter == nil
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
            }
        }
        ToolbarItem {
            Menu {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases, id: \.rawValue) { s in
                        Label(s.label, systemImage: s.icon).tag(s.rawValue)
                    }
                }
                Divider()
                Picker("View", selection: $viewModeRaw) {
                    Label("Grid", systemImage: "square.grid.2x2").tag(LibraryViewMode.grid.rawValue)
                    Label("List", systemImage: "list.bullet").tag(LibraryViewMode.list.rawValue)
                }
                if viewMode == .grid {
                    Picker("Grid Size", selection: $gridSizeRaw) {
                        ForEach(GridSize.allCases, id: \.rawValue) { size in
                            Text(size.label).tag(size.rawValue)
                        }
                    }
                }
            } label: {
                Label("Sort & View", systemImage: "arrow.up.arrow.down.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showingAdd = true } label: {
                Label("Add Game", systemImage: "plus")
            }
        }
    }

    // MARK: Filtering + sorting

    private var statusCounts: [GameStatus: Int] {
        Dictionary(grouping: games, by: \.status).mapValues(\.count)
    }

    private var visible: [Game] {
        games.filter { g in
            (statusFilter == nil || g.status == statusFilter)
            && (tagFilter == nil || g.userTags.contains(tagFilter!))
            && matchesSearch(g)
        }
    }

    private func matchesSearch(_ g: Game) -> Bool {
        guard !searchText.isEmpty else { return true }
        if g.name.localizedCaseInsensitiveContains(searchText) { return true }
        if let f = g.franchise, f.localizedCaseInsensitiveContains(searchText) { return true }
        return g.userTags.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var grouped: [GameStatus: [Game]] {
        Dictionary(grouping: visible, by: \.status)
    }

    private var sorted: [Game] {
        switch sort {
        case .status, .name:
            return visible
        case .recentlyAdded:
            return visible.sorted { $0.addedAt > $1.addedAt }
        case .recentlyPlayed:
            return visible.sorted { lastPlayed($0) > lastPlayed($1) }
        case .mostPlayed:
            return visible.sorted { playtime($0) > playtime($1) }
        case .rating:
            return visible.sorted { ($0.rating ?? -1, $0.name) > ($1.rating ?? -1, $1.name) }
        }
    }

    private func lastPlayed(_ g: Game) -> Date {
        (g.playthroughs ?? []).compactMap(\.lastPlayedAt).max() ?? .distantPast
    }

    private func playtime(_ g: Game) -> TimeInterval {
        (g.playthroughs ?? []).reduce(0) { $0 + $1.totalPlaytime() }
    }
}

// MARK: - Options

enum LibrarySort: String, CaseIterable {
    case status, name, recentlyAdded, recentlyPlayed, mostPlayed, rating

    var label: String {
        switch self {
        case .status: "By Status"
        case .name: "A – Z"
        case .recentlyAdded: "Recently Added"
        case .recentlyPlayed: "Recently Played"
        case .mostPlayed: "Most Played"
        case .rating: "By Rating"
        }
    }

    var icon: String {
        switch self {
        case .status: "circle.grid.2x2"
        case .name: "textformat.abc"
        case .recentlyAdded: "plus.circle"
        case .recentlyPlayed: "clock"
        case .mostPlayed: "trophy"
        case .rating: "star"
        }
    }
}

enum LibraryViewMode: String { case grid, list }

enum GridSize: String, CaseIterable {
    case large, medium, small

    var label: String {
        switch self {
        case .large: "Large"
        case .medium: "Medium"
        case .small: "Small"
        }
    }

    /// Minimum cell width for the adaptive grid — bigger minimum = fewer,
    /// larger covers per row.
    var minWidth: CGFloat {
        switch self {
        case .large: 150
        case .medium: 105
        case .small: 76
        }
    }
}

// MARK: - Grid cell

struct LibraryGridCell: View {
    let game: Game
    let size: GridSize

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CoverThumb(urlString: game.coverURLString)
                .aspectRatio(3 / 4, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if size != .small {
                        HStack(spacing: 4) {
                            Circle().fill(game.status.color).frame(width: 6, height: 6)
                            if size == .large {
                                Text(game.status.label)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: .capsule)
                        .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if game.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .padding(4)
                            .background(.ultraThinMaterial, in: .circle)
                            .padding(5)
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)

            if size != .small {
                Text(game.name)
                    .font(size == .large ? .footnote.weight(.medium) : .caption)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)

                if size == .large, let platform = game.platforms.first {
                    Text(platform)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
