import SwiftUI
import SwiftData

/// Navigation target for a platform's games.
///
/// `ownership` carries the Library filter that was active when the tile was
/// tapped. Without it the shelf counted "Genesis 1" under an Emulated filter
/// and then opened a page listing every Genesis game — the tile and the page
/// disagreeing about the same word. Home passes none, and gets all of them.
struct PlatformRoute: Hashable {
    let platform: String
    var ownership: OwnershipFilter? = nil

    /// On this console's page if you own it on this console — which since
    /// Schema V3 can be more than one, so a game bought twice appears on both
    /// pages. Games with nothing recorded fall to "Other", matching the shelf.
    static func matches(_ game: Game, platform: String, ownership: OwnershipFilter?) -> Bool {
        let owned = game.ownedPlatformNames
        let mine = owned.isEmpty ? ["Other"] : owned
        return mine.contains(platform) && (ownership?.matches(game) ?? true)
    }
}

/// The soft-3D console icon for a platform (falls back to a controller glyph).
struct PlatformIconView: View {
    let platform: String
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let asset = PlatformIcon.assetName(platform) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    // ONE light rig for the whole set.
                    //
                    // Every icon used to carry its own baked contact shadow,
                    // generated in a separate session — so direction, softness
                    // and placement differed console to console, and five had
                    // no shadow at all. Measured 2026-08-31: shadow alpha ran
                    // 0 to 181 across thirty icons, which is what made them
                    // read as "obviously generated". Tux's did not even sit
                    // where the object met the ground.
                    //
                    // The baked shadows are stripped from the art now, and
                    // this draws the only one. Derived from the alpha
                    // silhouette, so it cannot drift: a new icon inherits the
                    // set's lighting by existing. Scaled to `size` so a 24pt
                    // toolbar icon and a 54pt shelf tile stay in proportion.
                    .shadow(color: .black.opacity(0.5),
                            radius: size * 0.07, y: size * 0.055)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(LSTheme.accent)
                    .padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Home "Systems" shelf — scroll your consoles, tap one to see its games.
struct SystemsRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let groups: [(platform: String, count: Int)]
    var onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(LSTheme.accent)
                Text("Systems").font(.title3.bold())
                Text("(\(groups.count))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(groups, id: \.platform) { g in
                        BouncyTap {
                            onOpen(g.platform)
                        } label: {
                            VStack(spacing: 6) {
                                PlatformIconView(platform: g.platform, size: 54)
                                    .frame(width: 84, height: 84)
                                    .background(LSTheme.cardFill, in: .rect(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(LSTheme.hairline))
                                // Two lines, not one. `lineLimit(1)` turned
                                // "Other" and "SNES" into "Oth…" and "SN…" at
                                // accessibility sizes — the shortest names the
                                // app has, so nothing longer stood a chance.
                                Text(PlatformShort.name(g.platform))
                                    .font(.caption.weight(.medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                Text("\(g.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            // The tile widens with the type rather than
                            // holding a phone-sized 90pt and clipping.
                            .frame(width: typeSize.isAccessibilitySize ? 150 : 90)
                        }
                        .scrollTransition(axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.9)
                                .opacity(phase.isIdentity ? 1 : 0.65)
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

/// One console's library — reached by tapping a Systems icon.
///
/// Tim, 08-31: *"I think it needs to give me the same filters and sort options
/// as library, since this is each individual console's library of games."*
/// Right, and it was a bare grid: no search, no sort, no filters, on a page
/// that can hold 51 games. Everything here is Library's own machinery scoped
/// to one platform — same sort vocabulary, same chips, same layouts.
///
/// Sort and layout share Library's stored keys on purpose: choosing List in
/// Library and then finding a grid one tap later would read as two apps. The
/// FILTERS are local, because you arrived here by filtering already and those
/// choices are about this console, not about the shelf you came from.
struct PlatformGamesView: View {
    let platform: String
    var ownership: OwnershipFilter? = nil

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var allGames: [Game]

    @State private var searchText = ""
    @State private var statusFilter: GameStatus?
    @State private var ownershipFilter: OwnershipFilter?
    @State private var tagFilter: String?

    @AppStorage("librarySort") private var sortRaw = LibrarySort.name.rawValue
    @AppStorage("libraryViewMode") private var viewModeRaw = LibraryViewMode.grid.rawValue
    @AppStorage("libraryGridSize") private var gridSizeRaw = GridSize.medium.rawValue

    /// Grouping by system is the one sort that means nothing on a page that is
    /// already one system — it would draw a single heading over everything.
    private var sort: LibrarySort {
        let stored = LibrarySort(rawValue: sortRaw) ?? .name
        return stored == .system ? .name : stored
    }
    private var viewMode: LibraryViewMode { LibraryViewMode(rawValue: viewModeRaw) ?? .grid }
    private var gridSize: GridSize { GridSize(rawValue: gridSizeRaw) ?? .medium }

    /// Every game on this console, before the page's own filters — the pool
    /// the chips count against.
    private var onPlatform: [Game] {
        allGames.filter { PlatformRoute.matches($0, platform: platform, ownership: nil) }
    }

    private var visible: [Game] {
        onPlatform.filter { matches($0) }
    }

    private func matches(_ g: Game, ignoringOwnership: Bool = false) -> Bool {
        (statusFilter == nil || g.status == statusFilter)
        && (tagFilter == nil || g.userTags.contains(tagFilter!))
        && (ignoringOwnership || ownershipFilter?.matches(g) ?? true)
        && LibrarySearch.matches(g, query: searchText)
    }

    private var ownershipCounts: OwnershipFacet.Counts {
        OwnershipFacet.counts(onPlatform.filter { matches($0, ignoringOwnership: true) })
    }

    private var allTags: [String] {
        var counts: [String: Int] = [:]
        for g in onPlatform { for t in g.userTags { counts[t, default: 0] += 1 } }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
    }

    private var statusCounts: [GameStatus: Int] {
        Dictionary(grouping: onPlatform, by: \.status).mapValues(\.count)
    }

    private var groups: [(title: String, status: GameStatus?, items: [Game])] {
        guard sort == .status else { return [] }
        return GameStatus.displayOrder.compactMap { s in
            let items = visible.filter { $0.status == s }
            return items.isEmpty ? nil : (title: s.sectionTitle, status: s, items: items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            content
        }
        .lsBackground()
        .navigationTitle(PlatformShort.name(platform))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search this console")
        #else
        .searchable(text: $searchText, prompt: "Search this console")
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    PlatformIconView(platform: platform, size: 24)
                    Text(PlatformShort.name(platform)).font(.headline)
                }
            }
            ToolbarItem {
                Menu {
                    Picker("Status", selection: $statusFilter) {
                        Label("All (\(onPlatform.count))", systemImage: "circle.grid.2x2")
                            .tag(GameStatus?.none)
                        ForEach(GameStatus.displayOrder, id: \.self) { s in
                            let count = statusCounts[s] ?? 0
                            if count > 0 {
                                Label("\(s.sectionTitle) (\(count))", systemImage: s.systemImage)
                                    .tag(GameStatus?.some(s))
                            }
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
                        // No "By System" here — see `sort`.
                        ForEach(LibrarySort.allCases.filter { $0 != .system }, id: \.rawValue) { s in
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
                } label: {
                    Label("Sort & View", systemImage: "arrow.up.arrow.down.circle")
                }
            }
        }
        .onAppear {
            // The ownership you were filtering by in Library when you tapped
            // the console, so the tile's count and this page agree. Seeded
            // once — changing it here is then this page's own business.
            if ownershipFilter == nil { ownershipFilter = ownership }
        }
    }

    private var anyFilterActive: Bool {
        statusFilter != nil || ownershipFilter != nil || tagFilter != nil
    }

    @ViewBuilder
    private var filterBar: some View {
        let bar = LibraryFilterBar(
            statusFilter: $statusFilter,
            // No system chip: this page IS the system.
            platformFilter: .constant(nil),
            ownershipFilter: $ownershipFilter, tagFilter: $tagFilter,
            ownershipCounts: ownershipCounts, tags: allTags)
        if !bar.isEmpty { bar }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch viewMode {
            case .grid, .shelves: gridOrShelves
            case .list: list
            }
        }
        .overlay {
            if visible.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing here", systemImage: "gamecontroller")
                    } description: {
                        Text("No games on this console match those filters.")
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    /// Shelves collapse to the grouped grid here rather than growing rows of
    /// their own: one console's games are already one shelf, and a page of
    /// horizontal rows inside a vertical scroll for a single system reads as
    /// scrolling for its own sake.
    private var gridOrShelves: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if groups.isEmpty {
                    grid(sort.apply(to: visible))
                } else {
                    ForEach(groups.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            if let status = groups[i].status {
                                Image(systemName: status.systemImage)
                                    .font(.subheadline)
                                    .foregroundStyle(status.color)
                                    .frame(width: 26)
                            }
                            Text(groups[i].title).font(.headline)
                            Text("(\(groups[i].items.count))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        grid(groups[i].items)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func grid(_ items: [Game]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: gridSize.minWidth), spacing: 12)],
                  spacing: 16) {
            ForEach(items) { game in
                NavigationLink(value: game) {
                    LibraryGridCell(game: game, size: gridSize)
                }
                .buttonStyle(PressableCardStyle())
                .gameContextMenu(game)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(sort.apply(to: visible)) { game in
                NavigationLink(value: game) { GameRow(game: game) }
                    .listRowBackground(Color.clear)
                    .gameContextMenu(game)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
