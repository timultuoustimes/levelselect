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
    @State private var nav = AppNavigator.shared
    @State private var tagFilter: String?
    @State private var platformFilter: String?
    @State private var ownershipFilter: OwnershipFilter?
    /// One sheet slot, not two. Presentation here is single-occupancy and two
    /// `.sheet` modifiers on one view have swallowed each other twice in this
    /// app — same fix as OverlappingTimerGuard: an enum through one binding.
    @State private var sheet: LibrarySheet?
    /// Bound so a collection created from a prompt can be pushed straight
    /// after creating it. Without a path there was nowhere to send anyone, so
    /// the sheet just closed and left them at their old scroll position with
    /// no sign the tap had done anything.
    @State private var path = NavigationPath()
    /// Driven by ⌘F from the menu bar. See LevelSelectCommands.
    @FocusState private var searchFocused: Bool

    private enum LibrarySheet: String, Identifiable {
        case addGame, collectionTemplates
        var id: String { rawValue }
    }
    @State private var newCollection = false
    @State private var newCollectionName = ""
    @AppStorage("libraryHideBundled") private var hideBundled = false

    // A–Z.
    //
    // Status-first opened the page on "Backlog (98)" — the pile rather than
    // the collection. Recently-played was the next guess and Tim's answer was
    // simpler: the whole library, alphabetical. It is the one order that makes
    // no claim about you, which is the right thing for a shelf you are about
    // to look for something on.
    //
    // Only ever a STARTING point. The picker writes straight to this key, so
    // whatever anyone chooses is what they get from then on.
    @AppStorage("librarySort") private var sortRaw = LibrarySort.name.rawValue
    @AppStorage("libraryViewMode") private var viewModeRaw = LibraryViewMode.grid.rawValue
    @AppStorage("libraryGridSize") private var gridSizeRaw = GridSize.medium.rawValue

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .status }
    private var viewMode: LibraryViewMode { LibraryViewMode(rawValue: viewModeRaw) ?? .grid }
    private var gridSize: GridSize { GridSize(rawValue: gridSizeRaw) ?? .medium }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                filterBar
                content
            }
            .lsBackground()
            // "See all" on a Home shelf lands here, filtered, rather than
            // pushing a list onto Home's own stack. Consumed on arrival so
            // returning to Library later doesn't silently re-apply it.
            .onChange(of: nav.pendingLibraryStatus) { _, status in
                guard let status else { return }
                path = NavigationPath()
                statusFilter = status
                nav.pendingLibraryStatus = nil
            }
            // Menu bar (Mac and iPad). See LevelSelectCommands.
            .onChange(of: nav.newCollectionRequest) { _, _ in
                newCollectionName = ""
                newCollection = true
            }
            .onChange(of: nav.searchRequest) { _, _ in searchFocused = true }
            .onChange(of: nav.clearFiltersRequest) { _, _ in
                statusFilter = nil
                platformFilter = nil
                ownershipFilter = nil
                tagFilter = nil
                searchText = ""
            }
            .navigationTitle("Library")
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameFacet.self) { FacetGamesView(facet: $0) }
            // Each tab owns its stack, so a route appended here has to be
            // registered here — the systems shelf moved over from Home in
            // cb2469f and this did not come with it, which left every console
            // on the shelf opening a blank page.
            .navigationDestination(for: PlatformRoute.self) {
                PlatformGamesView(platform: $0.platform, ownership: $0.ownership)
            }
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
            .searchable(text: $searchText, prompt: "Search games, studios, genres")
            #else
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search games, studios, genres")
            #endif
            .searchFocused($searchFocused)
            .toolbar { toolbarContent }
            // Glass, like Home. Each tab owns its own NavigationStack, so the
            // window toolbar is configured per tab — Home alone was hidden and
            // the other three kept an opaque slab, which is why the window
            // changed character as you moved across the tabs.
            #if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            #endif
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .addGame:            AddGameSheet()
            case .collectionTemplates:
                CollectionTemplatePicker { collection in
                    path.append(CollectionRoute(id: collection.id))
                }
            }
        }
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
            case .shelves: shelvesView
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
                        Button("Add a Game") { sheet = .addGame }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    /// Systems moved here from Home.
    ///
    /// It was Home's second block, which put a hardware index above the games
    /// themselves — you saw a way to browse the same games by console before
    /// you saw the games. Browsing is Library's job, and here it sits beside
    /// Collections as one of several ways into the shelf rather than as a peer
    /// of "what am I playing".
    @ViewBuilder
    private var systemsShelf: some View {
        if platformGroups.count > 1 {
            SystemsRow(groups: platformGroups) { platform in
                path.append(PlatformRoute(platform: platform, ownership: ownershipFilter))
            }
        }
    }

    /// Same grouping Home used: by the game's most-preferred owned platform,
    /// largest groups first. Counts follow the CURRENT filters, unlike Home's
    /// which always counted the whole library — here the shelf sits inside a
    /// filtered view and should agree with what's on screen.
    /// Counted per console you own the game ON, so a game owned on two stands
    /// on both shelves. The counts therefore sum to more than the library, the
    /// same way the ownership chips do — and for the same reason: these are
    /// facts about copies, not a partition of the games.
    private var platformGroups: [(platform: String, count: Int)] {
        var counts: [String: Int] = [:]
        for game in visible {
            let owned = game.ownedPlatformNames
            for platform in (owned.isEmpty ? ["Other"] : owned) {
                counts[platform, default: 0] += 1
            }
        }
        return counts
            .map { (platform: $0.key, count: $0.value) }
            .sorted { ($1.count, $0.platform) < ($0.count, $1.platform) }
    }

    @ViewBuilder
    private var collectionShelf: some View {
        if !collections.isEmpty {
            CollectionShelf(
                collections: collections, games: games,
                onNew: { newCollectionName = ""; newCollection = true },
                onNewFromTemplate: { sheet = .collectionTemplates })
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                systemsShelf
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
        // Soft, not the default `.hard`. See RootView: iOS 26's scroll edge
        // effect draws a crisp line where content meets a bar unless told
        // otherwise, and one screen fading while the rest cut is worse than
        // either done consistently.
        .scrollEdgeEffectStyle(.hard, for: .top)
    }

    /// Home's shape, brought to Library as a CHOICE rather than a duplicate.
    ///
    /// Home's limited rows and "See all" stay Home's, because Home stops at
    /// what is live and what is next. Here it is a third layout beside grid
    /// and list — the same games, shelved — and "See all" lands in this tab's
    /// own grid with that shelf's filter applied, rather than pushing a
    /// separate list nobody can get back out of.
    private var shelvesView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                systemsShelf
                collectionShelf
                ForEach(shelfGroups.indices, id: \.self) { i in
                    let group = shelfGroups[i]
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(title: group.title, status: group.status,
                                      platform: group.platform, count: group.items.count,
                                      onSeeAll: { seeAll(group) })
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(group.items.prefix(Self.shelfLimit)) { game in
                                    NavigationLink(value: game) {
                                        CoverCard(game: game)
                                    }
                                    .buttonStyle(PressableCardStyle())
                                    .gameContextMenu(game)
                                    .scrollTransition(axis: .horizontal) { content, phase in
                                        content
                                            .scaleEffect(phase.isIdentity ? 1 : 0.86)
                                            .opacity(phase.isIdentity ? 1 : 0.6)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
    }

    /// Enough to browse, few enough that the shelf below it is still reachable.
    private static let shelfLimit = 12

    /// "See all" stays inside Library: it applies the shelf's own filter and
    /// drops you into the grid, which is a place you can filter further and
    /// get back out of.
    private func seeAll(_ group: LibGroup) {
        withAnimation {
            if let status = group.status { statusFilter = status }
            if let platform = group.platform { platformFilter = PlatformShort.name(platform) }
            viewModeRaw = LibraryViewMode.grid.rawValue
        }
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

    /// One header for grid, list and shelves.
    ///
    /// Sized and iconed to match Home, which is the app's reference for what a
    /// shelf label looks like — but one step down (`.headline`, not
    /// `.title3`). Home has four shelves and you scan between them; Library's
    /// status sort can run to six sections plus systems and collections, and
    /// at Home's size the labels start eating the grid they are labelling.
    private func sectionHeader(title: String, status: GameStatus?, platform: String? = nil,
                               count: Int, onSeeAll: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            if let asset = platform.flatMap(PlatformIcon.assetName) {
                Image(asset).resizable().scaledToFit().frame(width: 26, height: 26)
            } else if let status {
                Image(systemName: status.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(status == .playing
                                     ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(status.color))
                    .frame(width: 26)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.subheadline)
                    .foregroundStyle(LSTheme.accent)
                    .frame(width: 26)
            }
            Text(title)
                .font(.headline)
            Text("(\(count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let onSeeAll {
                Spacer()
                // Only worth offering when the shelf is actually holding
                // something back.
                if count > Self.shelfLimit {
                    Button("See all", action: onSeeAll)
                        .font(.subheadline)
                        .foregroundStyle(LSTheme.accent)
                        .buttonStyle(.plain)
                }
            }
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

    private var statusGroups: [LibGroup] {
        GameStatus.displayOrder.filter { $0 != .wishlist }.compactMap { s in
            let items = grouped[s] ?? []
            return items.isEmpty ? nil : LibGroup(title: s.sectionTitle, status: s, items: items)
        }
    }

    /// Shelves always group — a shelf without a label is just a row. When the
    /// sort has no grouping of its own (A–Z, Recently Played…), status is the
    /// fallback, since it is the vocabulary the rest of the app shelves by.
    private var shelfGroups: [LibGroup] {
        sectionGroups ?? statusGroups
    }

    private var sectionGroups: [LibGroup]? {
        switch sort {
        case .status:
            return statusGroups
        case .system:
            // Group by the game's most-preferred platform (Switch 2 → Switch →
            // PC → Mac → …), not IGDB's arbitrary first entry.
            // Grouped by the name shown, not the string stored. Keying on the
            // raw value put "Nintendo Switch 2" and "Switch 2" in separate
            // buckets that then rendered the same heading twice, one with 14
            // games and one with 3, with nothing on screen to tell them apart.
            // A game owned on two consoles appears under both headings. It
            // is one game seen from two shelves, not a duplicate — which is
            // why this builds membership rather than partitioning with
            // `Dictionary(grouping:)`.
            var byPlatform: [String: (raw: String, items: [Game])] = [:]
            for game in visible {
                let owned = game.ownedPlatformNames
                for platform in (owned.isEmpty ? ["Other"] : owned) {
                    let short = PlatformShort.name(platform)
                    var entry = byPlatform[short] ?? (raw: platform, items: [])
                    entry.items.append(game)
                    byPlatform[short] = entry
                }
            }
            return byPlatform
                .map { short, entry in
                    LibGroup(title: short, status: nil, platform: entry.raw,
                             items: entry.items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                }
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

    /// Ownership, tags, and whatever the toolbar menu has set — one row.
    /// See `LibraryFilterBar`: the three axes are peers, and a combination of
    /// them has to be visible or it reads as an empty library.
    @ViewBuilder
    private var filterBar: some View {
        let bar = LibraryFilterBar(
            statusFilter: $statusFilter, platformFilter: $platformFilter,
            ownershipFilter: $ownershipFilter, tagFilter: $tagFilter,
            ownershipCounts: ownershipCounts, tags: allTags)
        if !bar.isEmpty { bar }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    // Counts exclude the wishlist, like the shelves do. "All"
                    // that quietly included six games you don't own would not
                    // reconcile with anything else on the screen.
                    Label("All (\(games.filter { $0.status != .wishlist }.count))",
                          systemImage: "circle.grid.2x2").tag(GameStatus?.none)
                    ForEach(GameStatus.displayOrder.filter { $0 != .wishlist }, id: \.self) { s in
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
                    ForEach(allPlatforms, id: \.short) { entry in
                        Label {
                            Text(entry.short)
                        } icon: {
                            PlatformMenuIcon(platform: entry.icon)
                        }
                        .tag(String?.some(entry.short))
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
                    ForEach(LibraryViewMode.allCases, id: \.rawValue) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode.rawValue)
                    }
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
                Button { sheet = .addGame } label: {
                    Label("Add Game", systemImage: "gamecontroller")
                }
                Divider()
                // "Start from a Template" never says a template of WHAT.
                // Both of these now name the thing they make.
                Button { sheet = .collectionTemplates } label: {
                    Label("Collection from a Prompt", systemImage: "sparkles.rectangle.stack")
                }
                Button { newCollectionName = ""; newCollection = true } label: {
                    Label("Empty Collection", systemImage: "square.stack")
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

    /// The systems in the library, one row per name the user actually sees.
    /// See `PlatformShort.systems(in:)` for why it groups.
    ///
    /// Built from the platform each game is YOURS on, not every platform it
    /// was released for. `Game.platforms` carries IGDB's full list, so the
    /// menu was offering Linux, Vita and PS2 off the back of one Switch copy
    /// of Crypt of the NecroDancer — systems Tim has never owned a game on,
    /// sitting in a list titled "your systems". The shelf beside it always
    /// counted the owned platform only, so the two disagreed.
    private var allPlatforms: [(short: String, icon: String)] {
        PlatformShort.systems(in: games.map(\.ownedPlatformNames))
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
        return games.filter { matches($0, hidden: hidden) }
    }

    /// `ignoringOwnership` powers the chip counts: a facet count should say
    /// what you would get by tapping it, which means every filter but its own.
    private func matches(_ g: Game, hidden: Set<String>, ignoringOwnership: Bool = false) -> Bool {
        // A wishlisted game is not in your library — you don't own it. It
        // has its own tab, and appearing here as well is the same
        // duplication Home had, one tab over. This also makes "All" mean
        // what it says: everything you actually have.
        g.status != .wishlist
        && (statusFilter == nil || g.status == statusFilter)
        && (tagFilter == nil || g.userTags.contains(tagFilter!))
        // Matched on the platform the game is YOURS on, by displayed name —
        // so picking "Switch 2" finds what is stored as "Nintendo Switch 2",
        // and picking "Linux" does not find a Switch game that merely also
        // shipped on Linux.
        && (platformFilter == nil || PlatformShort.ownedMatches(g.ownedPlatformNames, short: platformFilter!))
        && (ignoringOwnership || ownershipFilter?.matches(g) ?? true)
        && (hidden.isEmpty || !hidden.contains(g.id.uuidString))
        && matchesSearch(g)
    }

    /// Overlapping by design — a game can be owned physically AND emulated,
    /// which is the case that made ownership worth browsing rather than
    /// picking. So these will not sum to the library size, and shouldn't.
    private var ownershipCounts: OwnershipFacet.Counts {
        let hidden = bundledGameIDs
        return OwnershipFacet.counts(games.filter {
            matches($0, hidden: hidden, ignoringOwnership: true)
        })
    }

    private func matchesSearch(_ g: Game) -> Bool {
        LibrarySearch.matches(g, query: searchText)
    }

    private var grouped: [GameStatus: [Game]] {
        Dictionary(grouping: visible, by: \.status)
    }

    private var sorted: [Game] { sort.apply(to: visible) }

}

// MARK: - Options

extension LibrarySort {
    /// `games` must arrive already sorted by name — every caller queries that
    /// way, and the name/status/system cases lean on it rather than re-sorting.
    func apply(to games: [Game]) -> [Game] {
        switch self {
        case .status, .name, .system:
            return games
        case .recentlyAdded:
            return games.sorted { $0.addedAt > $1.addedAt }
        case .recentlyPlayed:
            // Key computed once per game, not once per COMPARISON — the
            // comparator form rescanned every playthrough and session for both
            // operands on each of the O(n log n) comparisons.
            //
            // Name breaks the ties. Swift's sort is not stable and most of a
            // library has never been played, so without a second key those
            // games shuffle between renders.
            return games.map { ($0, Self.lastPlayed($0)) }
                .sorted { ($0.1, $1.0.name) > ($1.1, $0.0.name) }
                .map(\.0)
        case .mostPlayed:
            return games.map { ($0, Self.playtime($0)) }
                .sorted { ($0.1, $1.0.name) > ($1.1, $0.0.name) }
                .map(\.0)
        case .rating:
            return games.sorted { ($0.rating ?? -1, $1.name) > ($1.rating ?? -1, $0.name) }
        }
    }

    static func lastPlayed(_ g: Game) -> Date {
        g.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? .distantPast
    }

    static func playtime(_ g: Game) -> TimeInterval {
        g.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() }
    }
}

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

/// Short display names for long IGDB platform strings (grouping headers /
/// filters). Placeholder icons for now — swappable for the soft-3D console
/// icons later.
enum PlatformShort {
    /// IGDB's platform names are formal and long — "Super Nintendo
    /// Entertainment System" stacks across four lines beside a cover. These
    /// are the names people actually use. Anything unmapped falls through
    /// unchanged, which is why the retro half of this list matters: without
    /// it every console older than the Wii printed its full legal name.
    static func name(_ p: String) -> String {
        switch p {
        case "PC (Microsoft Windows)": "PC"
        case "Nintendo Switch": "Switch"
        case "Nintendo Switch 2": "Switch 2"
        case "PlayStation 5": "PS5"
        case "PlayStation 4": "PS4"
        case "PlayStation 3": "PS3"
        case "PlayStation 2": "PS2"
        // IGDB calls the original console simply "PlayStation"; PS1 is
        // clearer beside PS2/PS3 and is what everyone says anyway.
        case "PlayStation": "PS1"
        case "PlayStation Portable": "PSP"
        case "PlayStation Vita", "PlayStation Vita (PS Vita)": "Vita"
        case "Xbox Series X|S", "Xbox Series X/S", "Xbox Series X", "Xbox Series": "Xbox Series"
        case "Xbox One": "Xbox One"
        case "Xbox 360": "Xbox 360"
        case "Nintendo 3DS", "New Nintendo 3DS": "3DS"
        case "Nintendo DS", "Nintendo DSi": "DS"
        case "Wii U": "Wii U"
        case "Nintendo Wii", "Wii": "Wii"
        case "Super Nintendo Entertainment System", "SNES", "Super NES": "SNES"
        case "Nintendo Entertainment System", "NES": "NES"
        case "Family Computer", "Famicom", "Family Computer Disk System": "Famicom"
        case "Super Famicom": "Super Famicom"
        case "Nintendo 64": "N64"
        case "Nintendo GameCube", "GameCube": "GameCube"
        case "Game Boy Advance": "GBA"
        case "Game Boy Color": "GBC"
        case "Sega Mega Drive/Genesis", "Sega Genesis", "Genesis", "Mega Drive": "Genesis"
        case "Sega Master System/Mark III", "Sega Master System": "Master System"
        case "Sega Dreamcast", "Dreamcast": "Dreamcast"
        case "Sega Saturn": "Saturn"
        case "Sega Game Gear", "Game Gear": "Game Gear"
        case "Sega 32X", "Sega Mega-CD", "Sega CD": p
        case "TurboGrafx-16/PC Engine", "TurboGrafx-16": "TurboGrafx-16"
        case "Other", "": "Other"
        default: p
        }
    }

    /// The systems present across these games' platform lists, one entry per
    /// name the user actually sees.
    ///
    /// Grouped by short name rather than by stored string, because `name(_:)`
    /// collapses IGDB's "Nintendo Switch 2" and the short "Switch 2" for
    /// DISPLAY only. A menu built from distinct raw values therefore offered
    /// both, labeled identically, filtering 14 games and 3 — two rows that
    /// looked like one thing and were not.
    ///
    /// Deliberately a view-layer fix rather than a data migration. The
    /// vocabulary split arrived with an import, so the library is full of
    /// variants nobody chose, and nobody should have to edit 164 games to see
    /// a correct list of their own systems.
    ///
    /// `icon` is the highest-ranked variant behind the name, so each row keeps
    /// the art it had.
    static func systems(in lists: [[String]]) -> [(short: String, icon: String)] {
        var byShort: [String: String] = [:]
        for list in lists {
            for p in list {
                let short = name(p)
                if let held = byShort[short], PlatformPreference.rank(held) <= PlatformPreference.rank(p) { continue }
                byShort[short] = p
            }
        }
        return byShort
            .map { (short: $0.key, icon: $0.value) }
            .sorted { (PlatformPreference.rank($0.icon), $0.short) < (PlatformPreference.rank($1.icon), $1.short) }
    }

    /// Whether any of these stored platforms is displayed as `short` — so
    /// picking "Switch 2" also finds what's stored as "Nintendo Switch 2".
    ///
    /// This asks about AVAILABILITY. For "is this game mine on that system",
    /// which is what the library filter means, use `ownedMatches`.
    static func matches(_ platforms: [String], short: String) -> Bool {
        platforms.contains { name($0) == short }
    }

    /// Yours first, then the rest, each keeping its existing relative order.
    ///
    /// The stored list is IGDB's, in IGDB's order, which has nothing to do
    /// with you: on Alien: Isolation that put Switch first and Mac sixth with
    /// four consoles you do not own in between, so the two chips that say
    /// something about YOU sat at opposite ends of two wrapped rows.
    ///
    /// Display-only. The stored array is untouched — `ownedPlatforms` is the
    /// ownership record now, so reordering `platforms` would be a write and a
    /// sync in service of a purely visual concern, and it would also move the
    /// position-zero fallback that pre-V3 games still read.
    static func ownedFirst(_ platforms: [String], owned: [String]) -> [String] {
        let mine = Set(owned)
        return platforms.filter { mine.contains($0) } + platforms.filter { !mine.contains($0) }
    }

    /// Whether any platform this game is YOURS on is displayed as `short`.
    ///
    /// Takes `Game.ownedPlatformNames`, not the whole availability list.
    /// Crypt of the NecroDancer lists eight platforms and is owned on one or
    /// two; the library filter means the ones you own.
    static func ownedMatches(_ ownedNames: [String], short: String) -> Bool {
        ownedNames.contains { name($0) == short }
    }
}

/// What the library's search field matches.
///
/// Lifted out of the view so the suite can reach it — the predicate lived
/// inside `LibraryTab`, which these tests cannot construct.
///
/// "Capcom" was unreachable before this widened. Tapping a developer opens
/// that developer's games, but `GameFacet.Kind` keeps developer and publisher
/// apart, so no tap can express "published OR developed by Capcom" — and
/// finding a game to tap requires already owning one. Matching one string
/// against both arrays IS that union, which is what a filter sheet would
/// otherwise need an explicit any/all control for.
///
/// Deliberately not everything: status, ownership and platform have their own
/// filters in the menu beside the field, and folding them in here would make
/// "playing" match on a status the user was not searching for.
enum LibrarySearch {
    static func matches(_ g: Game, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if g.name.localizedCaseInsensitiveContains(query) { return true }
        if let f = g.franchise, f.localizedCaseInsensitiveContains(query) { return true }
        if g.userTags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        for list in [g.developers, g.publishers, g.genres, g.themes,
                     g.playerPerspectives, g.gameModes, g.platforms] {
            if list.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        }
        return false
    }
}

enum LibraryViewMode: String, CaseIterable {
    case grid, list, shelves

    var label: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        case .shelves: "Shelves"
        }
    }

    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        case .shelves: "rectangle.grid.1x2"
        }
    }
}

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
    /// A line under the name — the wishlist's release date, for instance.
    ///
    /// Belongs INSIDE the cell rather than stacked under it. The name reserves
    /// a second line so covers align across a row, and anything appended
    /// outside therefore starts a full line low: on the wishlist the date
    /// floated away from the game it belonged to, the same way a collection's
    /// count did before 08-31.
    var subtitle: String? = nil
    var subtitleTint: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            CoverThumb(urlString: game.displayCoverURLString)
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
                        .glassEffect(.regular, in: .capsule)
                        .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if game.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .padding(4)
                            .glassEffect(.regular, in: .circle)
                            .padding(5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if size != .small && !game.ownership.isEmpty {
                        OwnershipBadges(ownership: game.ownership, size: 9, tint: .primary)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .glassEffect(.regular, in: .capsule)
                            .padding(5)
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)

            if size != .small {
                Text(game.name)
                    .font(size == .large ? .footnote.weight(.medium) : .caption)
                    // Reserve the second line ONLY when nothing follows.
                    //
                    // The reserved line exists so covers align across a row
                    // when some names wrap and others don't. With a subtitle
                    // under it that same line becomes a gap: "Future Knight"
                    // is one line, reserves two, and the release date lands
                    // below the blank one — reading as unattached to the game
                    // it describes. Coupling a label to its own name matters
                    // more than aligning labels to each other, which is the
                    // same call made for `CollectionCard` on 08-31.
                    .lineLimit(2, reservesSpace: subtitle == nil)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(subtitleTint)
                        .lineLimit(1)
                }

                if size == .large, let platform = game.platforms.first {
                    // Short name here too — a grid cell has even less room for
                    // a console's full legal title than the hero card did.
                    Text(PlatformShort.name(platform))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
