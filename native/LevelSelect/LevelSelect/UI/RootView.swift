import SwiftUI
import SwiftData

/// App shell: Home / Library / Stats tabs (web-app parity) on the themed accent.
struct RootView: View {
    @Query private var themeSettings: [ThemeSettings]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @State private var persistence = PersistenceMonitor.shared
    // Palette version bump forces dependent views to re-read theme colors.
    @State private var themeVersion = 0
    @State private var showingSplash = true
    @State private var nav = AppNavigator.shared

    var body: some View {
        ZStack {
            TabView(selection: Binding(get: { nav.selectedTab },
                                       set: { nav.selectedTab = $0 })) {
                Tab("Home", systemImage: "house.fill", value: LSTab.home) { HomeTab() }
                Tab("Library", systemImage: "square.grid.2x2.fill", value: LSTab.library) { LibraryTab() }
                // Bag, not a heart: the wishlist is things to buy, and a heart
                // reads as "favorited" (which is what `pinned` already means).
                Tab("Wishlist", systemImage: "bag.fill", value: LSTab.wishlist) { WishlistTab() }
                Tab("Stats", systemImage: "chart.bar.fill", value: LSTab.stats) { StatsTab() }
            }
            .tint(LSTheme.accent)
            .staleSessionGuard()
            .id(themeVersion)

            if showingSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Persistence failure surface (beta P0): a save failed and the
            // change is still pending in the context — offer a real retry.
            if persistence.lastErrorMessage != nil {
                VStack {
                    Spacer()
                    SaveFailureBanner(monitor: persistence)
                        .padding(.horizontal)
                        .padding(.bottom, 64)  // clear the tab bar
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.spring(duration: 0.35), value: persistence.lastErrorMessage == nil)
        .preferredColorScheme(.dark)
        .onOpenURL { route($0) }
        .onAppear {
            ThemePalette.refresh(from: themeSettings.first)
        }
        .onChange(of: themeSettings.first?.updatedAt) { _, _ in
            ThemePalette.refresh(from: themeSettings.first)
            themeVersion += 1
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding is the last reliable moment to persist — commit
            // explicitly so a suspend/kill can't lose the latest edits.
            if phase == .background || phase == .inactive {
                PersistenceMonitor.shared.commit(context)
            }
            // Foregrounding is when CloudKit changes that arrived while
            // backgrounded have just landed — the moment sync races surface as
            // duplicate rows. The sweep folds duplicate tracker states, closes
            // doubled sessions, and drops empty duplicate default playthroughs;
            // it writes nothing when there's nothing to repair.
            if phase == .active {
                Repository(context).reconcileLibrary()
            }
            // Keep the widget snapshot current whenever the app surfaces or
            // backs out — catches edits made anywhere in the app.
            if phase == .active || phase == .background {
                WidgetBridge.refresh()
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeOut(duration: 0.5)) { showingSplash = false }
        }
    }

    /// Route a `levelselect://` deep link (widgets + App Intents) through the
    /// shared navigator.
    private func route(_ url: URL) {
        guard url.scheme == "levelselect" else { return }
        switch url.host {
        case "game":
            if let last = url.pathComponents.last, let id = UUID(uuidString: last) {
                nav.open(gameID: id)
            }
        case "continue": nav.continuePlaying()
        case "library": nav.go(to: .library)
        case "wishlist": nav.go(to: .wishlist)
        case "stats": nav.go(to: .stats)
        default: nav.go(to: .home)
        }
    }
}

/// Compact failure banner for a failed SwiftData save. The pending change is
/// still held by the context, so Retry genuinely re-attempts it.
private struct SaveFailureBanner: View {
    let monitor: PersistenceMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(monitor.lastErrorMessage ?? "Couldn't save.")
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Retry") { monitor.retry() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                monitor.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.yellow.opacity(0.35))
        )
        .accessibilityElement(children: .combine)
    }
}

/// Pixel-matches the static launch screen (stacked lockup centered on the
/// navy brand color) so the OS launch image hands off invisibly, letting the
/// splash linger a beat before fading into the app.
private struct SplashView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            Image("LaunchLogo")
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Home

/// Continue Playing hero + horizontal cover carousels per status.
struct HomeTab: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }, sort: \Game.name)
    private var games: [Game]

    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var showingCSVImport = false
    @State private var path = NavigationPath()
    @State private var nav = AppNavigator.shared
    /// Home categories the user has collapsed (comma-joined status raw values).
    @AppStorage("homeCollapsedStatuses") private var collapsedRaw = ""

    /// Trailing toolbar placement; declaration order controls layout there
    /// (lockup, then gear, then add).
    private static var trailing: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .topBarTrailing
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if games.isEmpty { emptyState } else { home }
            }
            .lsBackground()
            #if os(macOS)
            .navigationTitle("LevelSelect")
            #else
            // The toolbar lockup IS the title on iOS; an empty title keeps
            // the system's text title from doubling it.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameStatus.self) { StatusListView(status: $0) }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .navigationDestination(for: PlatformRoute.self) { PlatformGamesView(platform: $0.platform) }
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .principal) {
                    Wordmark(size: 13)
                        .lineLimit(1)
                        .fixedSize()
                }
                #endif
                ToolbarItem(placement: Self.trailing) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: Self.trailing) {
                    Button { showingAdd = true } label: {
                        Label("Add Game", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddGameSheet() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingCSVImport) { CSVImportView() }
        // Consume navigation requested by widgets / App Intents.
        .onAppear { consumePendingNavigation() }
        .onChange(of: nav.pendingGameID) { _, _ in consumePendingNavigation() }
        .onChange(of: nav.pendingContinue) { _, _ in consumePendingNavigation() }
    }

    /// Push a game the navigator asked for (deep link or App Intent).
    private func consumePendingNavigation() {
        if let id = nav.pendingGameID {
            nav.pendingGameID = nil
            let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.id == id })
            if let game = try? context.fetch(descriptor).first {
                path = NavigationPath()
                path.append(game)
            }
        }
        if nav.pendingContinue {
            nav.pendingContinue = false
            if let game = continueGame ?? mostRecentGame {
                path = NavigationPath()
                path.append(game)
            }
        }
    }

    /// Fallback for "Continue" when nothing is playing/paused: most recent play.
    private var mostRecentGame: Game? {
        games.max { sortKey($0) < sortKey($1) }
    }

    private var home: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let cp = continueGame {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONTINUE PLAYING")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .kerning(1)
                        BouncyTap {
                            path.append(cp)
                        } label: {
                            ContinueHeroCard(game: cp) { play(cp) }
                        }
                    }
                    .padding(.horizontal)
                }

                if platformGroups.count > 1 {
                    SystemsRow(groups: platformGroups) { platform in
                        path.append(PlatformRoute(platform: platform))
                    }
                }

                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    let items = grouped[status] ?? []
                    if !items.isEmpty {
                        StatusCarousel(
                            status: status, games: items,
                            collapsed: collapsedStatuses.contains(status.rawValue),
                            onOpen: { path.append($0) },
                            onSeeAll: { path.append(status) },
                            onToggleCollapse: { toggleCollapse(status) }
                        )
                    }
                }
            }
            .padding(.vertical)
        }
        .scrollIndicators(.hidden)
    }

    /// First thing a new person sees, and the app's only onboarding — there is
    /// no tour, deliberately.
    ///
    /// This used to read "Add a game or import your library from Settings",
    /// which names the two most ordinary things the app does and says nothing
    /// about why anyone would keep using it. Someone adds a game, lands on a
    /// page of sections, and never learns that the tracker is the point or
    /// that they can paste a checklist into it in seconds. The copy now names
    /// the actual first move and what comes after it.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("Start your shelf", systemImage: "gamecontroller")
        } description: {
            Text("Add a game you're playing — then give it a tracker: paste a checklist you already have, or let LevelSelect draft one.")
        } actions: {
            VStack(spacing: 10) {
                Button("Add a Game") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
                // A spreadsheet is how most people arrive with a backlog. This
                // opened the whole Settings form and left them to find the
                // importer — a dead end at the exact moment someone is deciding
                // whether the app is worth the effort.
                Button("Import a CSV") { showingCSVImport = true }
                    .buttonStyle(.borderless)
            }
        }
    }

    // MARK: Derived

    private var grouped: [GameStatus: [Game]] {
        Dictionary(grouping: games, by: \.status)
            .mapValues { $0.sorted { sortKey($0) > sortKey($1) } }
    }

    private var collapsedStatuses: Set<String> {
        Set(collapsedRaw.split(separator: ",").map(String.init))
    }

    private func toggleCollapse(_ status: GameStatus) {
        var set = collapsedStatuses
        if set.contains(status.rawValue) { set.remove(status.rawValue) }
        else { set.insert(status.rawValue) }
        collapsedRaw = set.sorted().joined(separator: ",")
    }

    /// Platforms across the library (by leading platform) with counts, biggest
    /// first — the Home "Systems" shelf.
    private var platformGroups: [(platform: String, count: Int)] {
        Dictionary(grouping: games) { PlatformPreference.sorted($0.platforms).first ?? "Other" }
            .map { (platform: $0.key, count: $0.value.count) }
            .sorted { ($1.count, $0.platform) < ($0.count, $1.platform) }
    }

    private var continueGame: Game? {
        games
            .filter { $0.status == .playing || $0.status == .paused }
            .max { sortKey($0) < sortKey($1) }
    }

    /// Pinned first, then most recent activity.
    private func sortKey(_ g: Game) -> (Bool, Date) {
        (g.pinned, g.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? g.addedAt)
    }

    private func play(_ game: Game) {
        let repo = Repository(context)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        if pt.activeSession == nil {
            repo.startSession(on: pt)
        }
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
                    .gameContextMenu(game)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .lsBackground()
        .navigationTitle(status.sectionTitle)
    }
}

// Tuple comparison helpers for (pinned, lastActivity) sort keys.
func > (lhs: (Bool, Date), rhs: (Bool, Date)) -> Bool {
    if lhs.0 != rhs.0 { return lhs.0 }
    return lhs.1 > rhs.1
}
func < (lhs: (Bool, Date), rhs: (Bool, Date)) -> Bool { rhs > lhs }

#Preview {
    RootView()
        .modelContainer(LevelSelectStore.makeContainer(inMemory: true))
}
