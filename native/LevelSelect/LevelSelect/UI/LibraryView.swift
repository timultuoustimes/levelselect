import SwiftUI
import SwiftData

/// Library tab — web-app parity: search (games/franchises/tags), status
/// filter with counts, sort menu, tag chips, and a cover GRID with
/// adjustable size (or a dense list). Everything persists.
struct LibraryTab: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]
    @Query(filter: #Predicate<GameCollection> { $0.deletedAt == nil }, sort: \GameCollection.sortIndex)
    private var collections: [GameCollection]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var statusFilter: GameStatus?
    @State private var tagFilter: String?
    @State private var platformFilter: String?
    @State private var ownershipFilter: String?
    @State private var showingAdd = false
    @State private var newCollection = false
    @State private var newCollectionName = ""
    @AppStorage("libraryHideBundled") private var hideBundled = false

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
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .navigationDestination(for: CollectionRoute.self) { route in
                if let collection = collections.first(where: { $0.id == route.id }) {
                    CollectionDetailView(collection: collection)
                }
            }
            // Always shown, not revealed by scrolling. The default drawer
            // hides until you pull down, and with the tag chips sitting above
            // the grid the gesture landed inconsistently — sometimes a scroll
            // up worked, sometimes a pull on the header, sometimes neither.
            // A library this size wants search at hand, not hidden behind a
            // gesture that has to be discovered twice.
            #if os(macOS)
            .searchable(text: $searchText, prompt: "Search games or franchises")
            #else
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search games or franchises")
            #endif
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showingAdd) { AddGameSheet() }
        .alert("New Collection", isPresented: $newCollection) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { Repository(context).createCollection(name: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Group games into a bundle or a list (e.g. comfort games).")
        }
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
                    // "No games" with no action is a dead end for anyone who
                    // opens this tab first — it names the problem and offers
                    // nothing to do about it.
                    ContentUnavailableView {
                        Label("No games yet", systemImage: "gamecontroller")
                    } description: {
                        Text("Add the games you're playing and they'll be grouped by system here.")
                    } actions: {
                        Button("Add a Game") { showingAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    @ViewBuilder
    private var collectionShelf: some View {
        if !collections.isEmpty {
            CollectionShelf(collections: collections, games: games) {
                newCollectionName = ""; newCollection = true
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                collectionShelf
                if let groups = sectionGroups {
                    ForEach(groups.indices, id: \.self) { i in
                        sectionHeader(title: groups[i].title, status: groups[i].status,
                                      platform: groups[i].platform, count: groups[i].items.count)
                        grid(groups[i].items)
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
            if !collections.isEmpty {
                collectionShelf
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            }
            if let groups = sectionGroups {
                ForEach(groups.indices, id: \.self) { i in
                    Section {
                        ForEach(groups[i].items) { game in
                            NavigationLink(value: game) { GameRow(game: game) }
                                .listRowBackground(Color.clear)
                                .gameContextMenu(game)
                        }
                    } header: {
                        let g = groups[i]
                        if let asset = g.platform.flatMap(PlatformIcon.assetName) {
                            HStack(spacing: 6) {
                                Image(asset).resizable().scaledToFit().frame(width: 20, height: 20)
                                Text("\(g.title) (\(g.items.count))")
                            }
                        } else {
                            Label("\(g.title) (\(g.items.count))",
                                  systemImage: g.status?.systemImage ?? "gamecontroller.fill")
                                .foregroundStyle(g.status.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(LSTheme.accent))
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

    private func sectionHeader(title: String, status: GameStatus?, platform: String? = nil, count: Int) -> some View {
        HStack(spacing: 6) {
            if let asset = platform.flatMap(PlatformIcon.assetName) {
                Image(asset).resizable().scaledToFit().frame(width: 24, height: 24)
            } else if let status {
                Circle().fill(status.color).frame(width: 8, height: 8)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.caption2)
                    .foregroundStyle(LSTheme.accent)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("(\(count))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    /// Grouped sections for the grid/list (status or system), else nil = flat.
    private struct LibGroup {
        let title: String
        let status: GameStatus?
        var platform: String? = nil   // raw platform key (system sort) for its icon
        let items: [Game]
    }

    private var sectionGroups: [LibGroup]? {
        switch sort {
        case .status:
            return GameStatus.displayOrder.compactMap { s in
                let items = grouped[s] ?? []
                return items.isEmpty ? nil : LibGroup(title: s.sectionTitle, status: s, items: items)
            }
        case .system:
            // Group by the game's most-preferred platform (Switch 2 → Switch →
            // PC → Mac → …), not IGDB's arbitrary first entry.
            let byPlatform = Dictionary(grouping: visible) {
                PlatformPreference.owned($0.platforms) ?? "Other"
            }
            return byPlatform
                .map { LibGroup(title: PlatformShort.name($0.key), status: nil, platform: $0.key,
                                items: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
                .sorted { ($1.items.count, $0.title) < ($0.items.count, $1.title) }
        default:
            return nil
        }
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
                Divider()
                Picker("System", selection: $platformFilter) {
                    Text("All systems").tag(String?.none)
                    ForEach(allPlatforms, id: \.self) { p in
                        Group {
                            if let asset = PlatformIcon.assetName(p) {
                                Label { Text(PlatformShort.name(p)) } icon: { Image(asset) }
                            } else {
                                Label(PlatformShort.name(p), systemImage: "gamecontroller")
                            }
                        }
                        .tag(String?.some(p))
                    }
                }
                Divider()
                Picker("Ownership", selection: $ownershipFilter) {
                    Text("Any ownership").tag(String?.none)
                    ForEach(Ownership.allCases, id: \.self) { k in
                        Label(k.label, systemImage: k.systemImage).tag(String?.some(k.rawValue))
                    }
                }
            } label: {
                Label("Filter", systemImage: anyFilterActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
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
                if collections.contains(where: \.isBundle) {
                    Divider()
                    Toggle(isOn: $hideBundled) {
                        Label("Hide games in bundles", systemImage: "shippingbox")
                    }
                }
            } label: {
                Label("Sort & View", systemImage: "arrow.up.arrow.down.circle")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showingAdd = true } label: {
                    Label("Add Game", systemImage: "gamecontroller")
                }
                Button { newCollectionName = ""; newCollection = true } label: {
                    Label("New Collection", systemImage: "square.stack")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    // MARK: Filtering + sorting

    private var statusCounts: [GameStatus: Int] {
        Dictionary(grouping: games, by: \.status).mapValues(\.count)
    }

    /// Distinct platforms across the library, in Tim's preferred order.
    private var allPlatforms: [String] {
        var seen = Set<String>()
        for g in games { for p in g.platforms { seen.insert(p) } }
        return seen.sorted { (PlatformPreference.rank($0), $0) < (PlatformPreference.rank($1), $1) }
    }

    private var anyFilterActive: Bool {
        statusFilter != nil || platformFilter != nil || ownershipFilter != nil
    }

    /// Game ids that live inside a bundle collection (hidden from the main
    /// library when "Hide games in bundles" is on).
    private var bundledGameIDs: Set<String> {
        guard hideBundled else { return [] }
        var ids = Set<String>()
        for c in collections where c.isBundle { ids.formUnion(c.gameIDs) }
        return ids
    }

    private var visible: [Game] {
        let hidden = bundledGameIDs
        return games.filter { g in
            (statusFilter == nil || g.status == statusFilter)
            && (tagFilter == nil || g.userTags.contains(tagFilter!))
            && (platformFilter == nil || g.platforms.contains(platformFilter!))
            && (ownershipFilter == nil || g.ownership.contains(ownershipFilter!))
            && (hidden.isEmpty || !hidden.contains(g.id.uuidString))
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
        case .status, .name, .system:
            return visible
        case .recentlyAdded:
            return visible.sorted { $0.addedAt > $1.addedAt }
        case .recentlyPlayed:
            // Key computed once per game, not once per COMPARISON — the
            // comparator form rescanned every playthrough and session for both
            // operands on each of the O(n log n) comparisons.
            return visible.map { ($0, lastPlayed($0)) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        case .mostPlayed:
            return visible.map { ($0, playtime($0)) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        case .rating:
            return visible.sorted { ($0.rating ?? -1, $0.name) > ($1.rating ?? -1, $1.name) }
        }
    }

    private func lastPlayed(_ g: Game) -> Date {
        g.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? .distantPast
    }

    private func playtime(_ g: Game) -> TimeInterval {
        g.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() }
    }
}

// MARK: - Options

enum LibrarySort: String, CaseIterable {
    case status, system, name, recentlyAdded, recentlyPlayed, mostPlayed, rating

    var label: String {
        switch self {
        case .status: "By Status"
        case .system: "By System"
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
        case .system: "gamecontroller"
        case .name: "textformat.abc"
        case .recentlyAdded: "plus.circle"
        case .recentlyPlayed: "clock"
        case .mostPlayed: "trophy"
        case .rating: "star"
        }
    }
}

/// Maps a platform to its soft-3D console icon asset. Matches both the short
/// legacy names ("Switch", "Genesis") and IGDB's long names ("Nintendo Switch",
/// "Sega Mega Drive/Genesis"). Order matters (Switch 2 before Switch, Xbox 360
/// before Xbox, Super Nintendo before Nintendo 64/NES). nil → controller glyph.
enum PlatformIcon {
    static func assetName(_ platform: String) -> String? {
        let p = platform.lowercased()
        if p.contains("switch 2")                              { return "platform-switch2" }
        if p.contains("switch")                                { return "platform-switch" }
        if p.contains("super nintendo") || p == "snes"
            || p.contains("super famicom")                     { return "platform-snes" }
        if p.contains("nintendo 64") || p == "n64"             { return "platform-n64" }
        if p == "nes" || p.contains("nintendo entertainment")  { return "platform-nes" }
        if p.contains("gamecube")                              { return "platform-gamecube" }
        if p.contains("genesis") || p.contains("mega drive")   { return "platform-genesis" }
        if p.contains("xbox 360")                              { return "platform-xbox360" }
        if p.contains("xbox")                                  { return "platform-xbox" }
        if p.contains("recalbox")                              { return "platform-recalbox" }
        // Order matters: more specific strings first, since these are
        // substring matches ("xbox series" before "xbox", "ps5" before "ps").
        if p.contains("xbox series")                           { return "platform-xbox-series" }
        if p.contains("steam deck")                            { return "platform-steamdeck" }
        if p.contains("playstation 5") || p == "ps5"           { return "platform-ps5" }
        if p.contains("playstation 4") || p == "ps4"           { return "platform-ps4" }
        if p.contains("playstation 3") || p == "ps3"           { return "platform-ps3" }
        if p == "playstation" || p.contains("playstation 1")
            || p == "ps1" || p == "psx"                        { return "platform-ps1" }
        if p.contains("3ds")                                   { return "platform-3ds" }
        if p.contains("wii u")                                 { return "platform-wiiu" }
        if p.contains("wii")                                   { return "platform-wii" }
        if p.contains("microsoft windows") || p == "pc"
            || p == "windows" || p == "steam"                  { return "platform-pc" }
        // Game Boy family: the longer names contain "game boy", so they must
        // be tested first or every handheld collapses to the 1989 DMG.
        if p.contains("game boy advance") || p == "gba"        { return "platform-gba" }
        if p.contains("game boy color") || p == "gbc"          { return "platform-gbc" }
        if p.contains("game boy")                              { return "platform-gameboy" }
        if p == "ios" || p.contains("iphone")                  { return "platform-iphone" }
        if p.contains("ipad")                                  { return "platform-ipad" }
        if p == "android"                                      { return "platform-android" }
        if p == "mac" || p.contains("macintosh") || p.contains("macos") { return "platform-mac" }
        return nil
    }
}

/// Short display names for long IGDB platform strings (grouping headers /
/// filters). Placeholder icons for now — swappable for the soft-3D console
/// icons later.
enum PlatformShort {
    static func name(_ p: String) -> String {
        switch p {
        case "PC (Microsoft Windows)": "PC"
        case "Nintendo Switch": "Switch"
        case "Nintendo Switch 2": "Switch 2"
        case "PlayStation 5": "PS5"
        case "PlayStation 4": "PS4"
        case "PlayStation 3": "PS3"
        case "Xbox Series X|S", "Xbox Series X/S", "Xbox Series X", "Xbox Series": "Xbox Series"
        case "Xbox One": "Xbox One"
        case "Xbox 360": "Xbox 360"
        case "Nintendo 3DS", "New Nintendo 3DS": "3DS"
        case "Wii U": "Wii U"
        case "Other", "": "Other"
        default: p
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
                .overlay(alignment: .bottomTrailing) {
                    if size != .small && !game.ownership.isEmpty {
                        OwnershipBadges(ownership: game.ownership, size: 9, tint: .primary)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: .capsule)
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
