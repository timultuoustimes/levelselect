import SwiftUI
import SwiftData

/// App shell: Home / Library / Stats tabs (web-app parity) on the themed accent.
struct RootView: View {
    @Query private var themeSettings: [ThemeSettings]
    // Palette version bump forces dependent views to re-read theme colors.
    @State private var themeVersion = 0
    @State private var showingSplash = true

    var body: some View {
        ZStack {
            TabView {
                Tab("Home", systemImage: "house.fill") { HomeTab() }
                Tab("Library", systemImage: "square.grid.2x2.fill") { LibraryTab() }
                Tab("Wishlist", systemImage: "heart.fill") { WishlistTab() }
                Tab("Stats", systemImage: "chart.bar.fill") { StatsTab() }
            }
            .tint(LSTheme.accent)
            .staleSessionGuard()
            .id(themeVersion)

            if showingSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            ThemePalette.refresh(from: themeSettings.first)
        }
        .onChange(of: themeSettings.first?.updatedAt) { _, _ in
            ThemePalette.refresh(from: themeSettings.first)
            themeVersion += 1
        }
        .task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeOut(duration: 0.5)) { showingSplash = false }
        }
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
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if games.isEmpty { emptyState } else { home }
            }
            .lsBackground()
            .navigationTitle("LevelSelect")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameStatus.self) { StatusListView(status: $0) }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Image("DoorMark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 26)
                        Text("LevelSelect")
                            .font(LSTheme.pixel(12))
                            .foregroundStyle(LSTheme.torch)
                            // Press Start 2P's tall line box centers oddly;
                            // optically center the glyphs on the door.
                            .offset(y: -0.5)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("LevelSelect")
                    .accessibilityAddTraits(.isHeader)
                }
                #endif
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
        }
        .sheet(isPresented: $showingAdd) { AddGameSheet() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
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

                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    let items = grouped[status] ?? []
                    if !items.isEmpty {
                        StatusCarousel(status: status, games: items) { game in
                            path.append(game)
                        } onSeeAll: {
                            path.append(status)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .scrollIndicators(.hidden)
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

    // MARK: Derived

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
