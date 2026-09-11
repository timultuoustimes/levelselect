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

    /// **Resolved at init, not in `body`.**
    ///
    /// `artName` reads `PlatformIcon.variantOverrides`, which is a plain
    /// static — SwiftUI cannot see it change, so a view whose stored values
    /// are unchanged is skipped and keeps drawing yesterday's machine. Picking
    /// a different Mac moved the checkmark and left the tile behind it alone,
    /// 2026-09-08. Holding the answer as a stored property makes the choice
    /// part of this view's VALUE, which is what the diff actually compares.
    private let asset: String?

    init(platform: String, size: CGFloat = 52) {
        self.platform = platform
        self.size = size
        // `artName`, not `assetName`: the model someone owns changes what is
        // drawn and nothing else. See `PlatformVariant`.
        self.asset = PlatformIcon.artName(platform)
    }

    var body: some View {
        Group {
            if let asset {
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
            // `ShelfHeader` owns the accessibility-size split now, so the
            // local `ViewThatFits` that kept "Systems" from hyphenating to
            // "Sys-tems" went with it. The glyph is a console rather than the
            // generic layered stack — a shelf of hardware should not wear the
            // same symbol as a shelf of games.
            ShelfHeader(title: "Systems",
                        count: groups.count,
                        systemImage: "arcade.stick.console.fill",
                        tint: LSTheme.accent)

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
    /// Choosing several of this console's games — see `GameSelectionBar`.
    @State private var selecting = false
    @State private var selected: Set<UUID> = []

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
            // **The hardware above the games.** This page was a filtered list
            // that happened to be titled "Genesis"; the console is a thing you
            // own and the games are what you have on it.
            ConsoleCard(platform: platform, games: allGames)
            filterBar
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting {
                GameSelectionBar(selected: $selected, all: allGames, visible: visible) {
                    withAnimation(.snappy) { selecting = false; selected = [] }
                }
            }
        }
        .lsBackground()
        .navigationTitle(PlatformShort.name(platform))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // **Only when there is something to search.** A pinned search field
        // over eight covers is a control that costs more room than the list it
        // filters — Fable's 5.8. The threshold is `onPlatform`, not `visible`,
        // so a filter that narrows the page to three does not make the field
        // vanish out from under you mid-search.
        .modifier(SearchWhenWorthIt(text: $searchText,
                                    enabled: onPlatform.count >= 8,
                                    prompt: "Search this console"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    PlatformIconView(platform: platform, size: 24)
                    Text(PlatformShort.name(platform)).font(.headline)
                }
            }
            ToolbarItem {
                Menu {
                    Button {
                        withAnimation(.snappy) { selecting = true }
                    } label: {
                        Label("Select Games…", systemImage: "checkmark.circle")
                    }
                    Divider()
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
                    // **Empty and filtered-empty are different sentences.**
                    // Until build 39 a console page could only be reached
                    // THROUGH a game, so "nothing matches those filters" was
                    // always true. A console record can now exist with nothing
                    // on it — the Dreamcast in the display case — and telling
                    // that person their filters are wrong would be the app
                    // being confidently incorrect about their own shelf.
                    if onPlatform.isEmpty {
                        emptyConsole
                    } else {
                        ContentUnavailableView {
                            Label("Nothing here", systemImage: "gamecontroller")
                        } description: {
                            Text("No games on this console match those filters.")
                        }
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    /// **A shelf with nothing on it yet, drawn as a shelf.**
    ///
    /// It was a sentence in the middle of a blank page. Three empty covers say
    /// the same thing in the page's own language and, more usefully, say what
    /// the page is FOR — this is where games on this console will stand.
    ///
    /// The words underneath are about time, not about being empty: a console
    /// you own with nothing on it yet and a console you had twenty years ago
    /// are both real, and neither is a mistake to be corrected.
    private var emptyConsole: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LSTheme.accent.opacity(0.28),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .frame(width: 64, height: 96)
                        // Slightly fainter to the right, so it reads as a
                        // shelf continuing rather than three of a set.
                        .opacity(1 - Double(i) * 0.22)
                }
            }
            VStack(spacing: 6) {
                Text("Nothing on it yet")
                    .font(.headline)
                Text(emptyConsoleBlurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 300)
        }
        .padding(24)
    }

    /// Arcade is not a machine in a cupboard, so the sentence about adding
    /// games to a console you own does not describe it. Tim, 2026-09-09:
    /// *"Games you played in an arcade, or on a cabinet you own."*
    private var emptyConsoleBlurb: String {
        PlatformKey.canonical(platform) == "Arcade"
            ? "Games you played in an arcade, or on a cabinet you own."
            : "Games you add on this console show up here — the ones you play now, and the ones you played back then."
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
    }

    private func grid(_ items: [Game]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: gridSize.minWidth), spacing: 12)],
                  spacing: 16) {
            ForEach(items) { game in
                if selecting {
                    Button { toggle(game) } label: {
                        LibraryGridCell(game: game, size: gridSize,
                                        selection: selected.contains(game.id))
                    }
                    .buttonStyle(PressableCardStyle())
                } else {
                    NavigationLink(value: game) {
                        LibraryGridCell(game: game, size: gridSize)
                    }
                    .buttonStyle(PressableCardStyle())
                    .gameContextMenu(game)
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(sort.apply(to: visible)) { game in
                if selecting {
                    Button { toggle(game) } label: {
                        HStack(spacing: 12) {
                            GameSelectionMark(on: selected.contains(game.id))
                            GameRow(game: game)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(GameSelectionRowBackground(on: selected.contains(game.id)))
                } else {
                    NavigationLink(value: game) { GameRow(game: game) }
                        .listRowBackground(Color.clear)
                        .gameContextMenu(game)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func toggle(_ game: Game) {
        if selected.contains(game.id) { selected.remove(game.id) } else { selected.insert(game.id) }
    }
}


/// `.searchable`, applied conditionally.
///
/// A `#if`/`if` around a modifier changes the view's TYPE, which SwiftUI reads
/// as a different view — the page rebuilt and lost its scroll position every
/// time the count crossed the threshold. A modifier keeps one type and moves
/// the condition inside it.
private struct SearchWhenWorthIt: ViewModifier {
    @Binding var text: String
    let enabled: Bool
    let prompt: String

    func body(content: Content) -> some View {
        if enabled {
            #if os(macOS)
            content.searchable(text: $text, prompt: prompt)
            #else
            content.searchable(text: $text,
                               placement: .navigationBarDrawer(displayMode: .always),
                               prompt: prompt)
            #endif
        } else {
            content
        }
    }
}
