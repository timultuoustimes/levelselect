import SwiftUI
import SwiftData

/// App shell: Home / Library / Stats tabs (web-app parity) on the themed accent.
struct RootView: View {
    @Query private var themeSettings: [ThemeSettings]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var context
    @State private var persistence = PersistenceMonitor.shared
    @State private var generation = TrackerGenerationStore.shared
    @State private var syncStatus = SyncStatusMonitor.shared
    // Palette version bump forces dependent views to re-read theme colors.
    @State private var showingSplash = true
    @State private var nav = AppNavigator.shared

    /// Banners slide up from the tab bar — unless the system asks for less
    /// motion, in which case they simply appear.
    private var slideIn: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

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
            .overlappingTimerGuard()
            .id(nav.themeRevision)

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
                .transition(slideIn)
                .zIndex(2)
            }

            // Generation takes a minute or two and the user has usually
            // navigated away by the time it finishes — without an app-wide
            // surface, a background failure was completely silent and a
            // success went unnoticed until they wandered back.
            if let roll = nav.shuffleRoll {
                VStack {
                    Spacer()
                    ShuffleToast(roll: roll) {
                        route(roll.sourceURL)          // re-roll, same filters
                    } dismiss: {
                        nav.shuffleRoll = nil
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 64)
                }
                .transition(slideIn)
                .zIndex(3)
                .task(id: roll.id) {
                    DiceHaptics.tumble()
                    try? await Task.sleep(for: .seconds(5))
                    if nav.shuffleRoll?.id == roll.id { nav.shuffleRoll = nil }
                }
            }

            if let notice = generation.notice {
                VStack {
                    Spacer()
                    GenerationNoticeBanner(notice: notice) {
                        nav.open(gameID: notice.gameID)
                        generation.clearNotice()
                    } dismiss: {
                        generation.clearNotice()
                    }
                    .padding(.horizontal)
                    // Stack above the save-failure banner when both are up.
                    .padding(.bottom, persistence.lastErrorMessage != nil ? 128 : 64)
                }
                .transition(slideIn)
                .zIndex(2)
                // Successes clear themselves; failures wait to be seen.
                .task(id: notice.id) {
                    guard notice.success else { return }
                    try? await Task.sleep(for: .seconds(6))
                    if generation.notice?.id == notice.id { generation.clearNotice() }
                }
            }
        }
        .animation(.spring(duration: 0.35), value: persistence.lastErrorMessage == nil)
        .animation(.spring(duration: 0.35), value: generation.notice?.id)
        .preferredColorScheme(.dark)
        .onOpenURL { route($0) }
        .onAppear {
            ThemePalette.refresh(from: themeSettings.first)
        }
        .onChange(of: themeSettings.first?.updatedAt) { _, _ in
            // Refresh the values, but do NOT re-key the tree here — see
            // `AppNavigator.themeRevision`. Settings bumps that on close.
            ThemePalette.refresh(from: themeSettings.first)
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding is the last reliable moment to persist — commit
            // explicitly so a suspend/kill can't lose the latest edits.
            if phase == .background || phase == .inactive {
                PersistenceMonitor.shared.commit(context)
            }
            // Foregrounding is when CloudKit changes that arrived while
            // backgrounded have just landed — the moment sync races surface
            // as duplicate rows. This sweep is deliberately BOUNDED: it only
            // closes doubled sessions (one small fetch — the sole duplicate
            // that corrupts library-wide numbers while just sitting there).
            // Full per-game repair runs when a game's page opens and before
            // schema merges, so foregrounding never walks the whole library
            // on the main actor. Nothing is ever deleted by inference —
            // emptiness can be another device's record mid-sync.
            if phase == .active {
                repairSyncedData()
            }
            // Active repair refreshes the widget after reconciliation. Keep
            // the separate background write as the last snapshot of edits
            // made anywhere in the app.
            if phase == .background {
                WidgetBridge.refresh()
            }
        }
        // CloudKit imports routinely finish seconds AFTER foregrounding. The
        // old scenePhase-only hook had already run by then, so two synced
        // timers could remain live until the user switched apps or opened the
        // affected game. Every successful import emits this sequence. task(id:)
        // cancels and restarts the sleep when imports arrive in a burst, then
        // repairs once after the batch settles.
        .task(id: syncStatus.successfulImportSequence) {
            guard syncStatus.successfulImportSequence > 0 else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, scenePhase == .active else { return }
            repairSyncedData()
        }
        .task {
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeOut(duration: 0.5)) { showingSplash = false }
        }
    }

    /// Keep every import/foreground repair side effect in one ordered unit.
    /// Live Activities read the post-reconcile set, and the widget snapshot is
    /// written last from that same repaired context.
    private func repairSyncedData() {
        let repo = Repository(context)
        repo.reconcileLibrary()
        LiveActivityManager.sync(unstopped: repo.unstoppedSessions())
        WidgetBridge.refresh()
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
        case "shuffle":
            // The lock-screen die: every tap is a fresh roll, made HERE at
            // launch — a widget URL is baked per timeline entry, so rolling
            // app-side is the only way a tap is genuinely random each time.
            rollShuffle(from: url)
        case "status":
            if let raw = url.pathComponents.last,
               let status = GameStatus(rawValue: raw) {
                nav.push(status)
            }
        case "platform":
            if let name = url.pathComponents.last?.removingPercentEncoding {
                nav.push(PlatformRoute(platform: name))
            }
        case "collection":
            if let last = url.pathComponents.last, let id = UUID(uuidString: last) {
                nav.push(CollectionRoute(id: id))
            }
        default: nav.go(to: .home)
        }
    }

    /// Pick a random game matching the die's filters and open it. Same
    /// semantics as the Home Screen shuffler's pool: wishlist and abandoned
    /// never qualify, completed only when the toggle says so.
    private func rollShuffle(from url: URL) {
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        func value(_ name: String) -> String? {
            params.first { $0.name == name }?.value
        }
        let statuses: Set<String> = Set((value("s") ?? "playing,paused,queued,backlog")
            .split(separator: ",").map(String.init))
        let platform = value("p")
        let includeCompleted = value("c") == "1"

        let descriptor = FetchDescriptor<Game>(predicate: #Predicate { $0.deletedAt == nil })
        let games = (try? context.fetch(descriptor)) ?? []
        let candidates = games.filter { g in
            let statusOK = statuses.contains(g.status.rawValue)
                || (includeCompleted && g.status == .completed)
            let platformOK = platform == nil
                || PlatformShort.name(PlatformPreference.owned(g.platforms) ?? "Other") == platform
            return statusOK && platformOK && g.status != .abandoned && g.status != .wishlist
        }
        if let pick = candidates.randomElement() {
            nav.open(gameID: pick.id)
            // The roll happened invisibly during launch — the toast is what
            // makes it feel like dice instead of an arbitrary landing.
            nav.shuffleRoll = .init(gameName: pick.name, sourceURL: url)
        } else {
            nav.go(to: .library)
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

/// "Tracker ready / generation failed" toast — the app-wide answer to a
/// generation finishing while the user is anywhere else. Open jumps straight
/// to the game.
/// "🎲 Rolled: Spyro the Dragon" — the die's landing, announced. Re-roll
/// repeats the exact same filters without touching the widget again.
private struct ShuffleToast: View {
    let roll: AppNavigator.ShuffleRoll
    var reroll: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dice.fill")
                .font(.title3)
                .foregroundStyle(LSTheme.torch)
            VStack(alignment: .leading, spacing: 1) {
                Text("Rolled")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(roll.gameName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Re-roll") { reroll() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(LSTheme.accent)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
    }
}

private struct GenerationNoticeBanner: View {
    let notice: GenerationNotice
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.success
                  ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(notice.success ? AnyShapeStyle(.green) : AnyShapeStyle(.yellow))
            Text(notice.text)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Open") { open() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button {
                dismiss()
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
    @Query private var profiles: [PlayerProfile]

    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var editingProfile = false
    /// Whether Home's header is currently painting art to its own top edge.
    /// The toolbar needs this and cannot see inside `home`.
    @State private var homeHeaderBleeds = false
    @State private var showingCSVImport = false
    @State private var showingWelcome = false
    /// What the welcome's button asked for, fired from its onDismiss so the
    /// next sheet never races the one still animating away.
    @State private var welcomeChoice: WelcomeView.Choice?
    @State private var path = NavigationPath()
    @State private var nav = AppNavigator.shared
    /// Once per device, not synced: seeing the welcome on your phone says
    /// nothing about whether your iPad has shown it.
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    /// Home categories the user has collapsed (comma-joined status raw values).
    @AppStorage("homeCollapsedStatuses") private var collapsedRaw = ""
    /// Statuses kept off Home. Device-local on purpose, and not synced: which
    /// shelves you want on the front page of the phone in your pocket is not
    /// obviously the same answer as for the iPad on the desk. Saying so here
    /// because a preference that silently doesn't sync is otherwise read as a
    /// bug rather than a decision.
    @AppStorage("homeHiddenStatuses") private var hiddenRaw = ""

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
            // Same reason as iOS below: the window toolbar draws an opaque
            // background that both hides the art behind it and flattens the
            // controls sitting on it. Hidden while the header paints art, the
            // tab pills and the gear/plus render as glass over the artwork,
            // which is what iPad already did.
            .toolbarBackground(homeHeaderBleeds ? .hidden : .automatic,
                               for: .windowToolbar)
            #else
            // The toolbar lockup IS the title on iOS; an empty title keeps
            // the system's text title from doubling it.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Hide the bar's OWN background when the header paints art.
            //
            // iPhone draws a navigation-bar background that stops with a hard
            // horizontal line; iPad's does not, which is why the same header
            // read as a gradient on one and a hard-edged glass band on the
            // other. With it hidden, the header's mask is the only fade and
            // both match. The toolbar's own controls keep their glass
            // capsules — this removes the slab behind them, not the chrome.
            .toolbarBackground(homeHeaderBleeds ? .hidden : .automatic,
                               for: .navigationBar)
            #endif
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameFacet.self) { FacetGamesView(facet: $0) }
            .navigationDestination(for: GameStatus.self) { StatusListView(status: $0) }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .navigationDestination(for: PlatformRoute.self) { PlatformGamesView(platform: $0.platform) }
            .navigationDestination(for: CollectionRoute.self) { CollectionRouteView(route: $0) }
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
        // `onDismiss`, not the sheet's own `onDisappear`: this fires ONCE when
        // Settings actually closes, where that fired on any disappearance —
        // including pushing a subscreen onto the Settings stack, which re-keyed
        // the tab tree and tore down the sheet mid-tap.
        .sheet(isPresented: $showingSettings, onDismiss: {
            AppNavigator.shared.themeRevision += 1
        }) { SettingsView() }
        .sheet(isPresented: $editingProfile) { ProfileEditor() }
        .sheet(isPresented: $showingCSVImport) { CSVImportView() }
        .sheet(isPresented: $showingWelcome, onDismiss: {
            // Any way out counts as seen — including a swipe-down. A welcome
            // that nags twice is a tour.
            hasSeenWelcome = true
            switch welcomeChoice {
            case .addGame: showingAdd = true
            case .importCSV: showingCSVImport = true
            case nil: break
            }
            welcomeChoice = nil
        }) {
            WelcomeView { welcomeChoice = $0 }
                .interactiveDismissDisabled(false)
        }
        // Consume navigation requested by widgets / App Intents.
        .onAppear {
            // First run only: an empty library and an unseen flag. Existing
            // libraries (every current device) never see it.
            if !hasSeenWelcome && games.isEmpty {
                showingWelcome = true
            } else if !hasSeenWelcome {
                // A populated library predates the welcome — mark it seen so
                // emptying the library later doesn't resurrect a "first run".
                hasSeenWelcome = true
            }
            consumePendingNavigation()
        }
        .onChange(of: nav.pendingGameID) { _, _ in consumePendingNavigation() }
        .onChange(of: nav.pendingContinue) { _, _ in consumePendingNavigation() }
        .onChange(of: nav.pendingRoute) { _, _ in consumePendingNavigation() }
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
        if let route = nav.pendingRoute {
            nav.pendingRoute = nil
            path = NavigationPath()
            // Launcher deep links: status shelf, system shelf, or collection.
            if let status = route as? GameStatus { path.append(status) }
            else if let platform = route as? PlatformRoute { path.append(platform) }
            else if let collection = route as? CollectionRoute { path.append(collection) }
        }
    }

    /// Fallback for "Continue" when nothing is playing/paused: most recent play.
    private var mostRecentGame: Game? {
        games.max { sortKey($0) < sortKey($1) }
    }

    private var home: some View {
        // Built once here rather than inside the header's body: it walks every
        // game's sessions, and `body` runs far more often than the data changes.
        let summary = PlayerSummary.make(from: games)
        let headerBleeds = ProfileHeader.drawsArt(profile: profiles.first, summary: summary)

        // The GeometryReader is here for one number: the top safe-area inset,
        // which is how far the art has to reach up to sit under the toolbar.
        return GeometryReader { outer in
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                // Whose shelf this is, before what is on it. Draws nothing
                // until someone has actually put something in it.
                ProfileHeader(profile: profiles.first, summary: summary,
                              topOverscan: headerBleeds ? outer.safeAreaInsets.top : 0) {
                    editingProfile = true
                }

                if let cp = continueGame {
                    VStack(alignment: .leading, spacing: 10) {
                        // Capped, and only this. At Accessibility XXL a
                        // `.caption` all-caps eyebrow scaled into the largest
                        // thing on Home — bigger than the hero's own title and
                        // its cover — which inverts the hierarchy it exists to
                        // introduce. It still grows, just not past the content
                        // it labels. Nothing here is truncated or hidden.
                        Text("CONTINUE PLAYING")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .kerning(1)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        BouncyTap {
                            path.append(cp)
                        } label: {
                            ContinueHeroCard(game: cp) {
                                play(cp)
                            } onPauseResume: {
                                togglePause(cp)
                            } onStop: {
                                stop(cp)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Any OTHER live timer, with its own controls. A running
                // session used to be unreachable from Home unless it happened
                // to be the Continue Playing game, which is how a forgotten
                // timer turns into hours of imaginary playtime.
                RunningTimersStrip(excluding: continueGame) { game in
                    path.append(game)
                }

                // `homeOrder`, not `displayOrder`. Home carries what is live
                // and what is next; the backlog, the finished pile, the
                // shelved and the abandoned are facts about a collection and
                // live in Library. Wishlist has its own tab.
                ForEach(GameStatus.homeOrder, id: \.self) { status in
                    let items = grouped[status] ?? []
                    if !items.isEmpty, !hiddenStatuses.contains(status.rawValue) {
                        StatusCarousel(
                            status: status, games: items,
                            collapsed: collapsedStatuses.contains(status.rawValue),
                            onOpen: { path.append($0) },
                            onSeeAll: {
                                nav.pendingLibraryStatus = status
                                nav.selectedTab = .library
                            },
                            onToggleCollapse: { toggleCollapse(status) },
                            onHide: { setHidden(status, true) }
                        )
                    }
                }
                hiddenStatusesFooter
                // After the shelves, not above them: an ask, never a nag.
                BetaQuestionCard()
            }
                .padding(.bottom)
                // The art runs to the top edge, under the toolbar. Everything
                // else keeps the ordinary inset.
                .padding(.top, headerBleeds ? 0 : 16)
            }
            .scrollIndicators(.hidden)
            // ONLY when the header paints art. Without a header, letting
            // content start under the bar would put Continue Playing behind
            // the toolbar at rest, which is a bug rather than an effect.
            .ignoresSafeArea(.container, edges: headerBleeds ? .top : [])
            .onAppear { homeHeaderBleeds = headerBleeds }
            .onChange(of: headerBleeds) { _, now in homeHeaderBleeds = now }
        }
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

    private var hiddenStatuses: Set<String> {
        Set(hiddenRaw.split(separator: ",").map(String.init))
    }

    private func setHidden(_ status: GameStatus, _ hidden: Bool) {
        var set = hiddenStatuses
        if hidden { set.insert(status.rawValue) } else { set.remove(status.rawValue) }
        hiddenRaw = set.sorted().joined(separator: ",")
    }

    /// The way back. A shelf that vanishes with no trace of how to restore it
    /// is a bug from the user's side, however deliberate the tap was.
    @ViewBuilder
    private var hiddenStatusesFooter: some View {
        // Only shelves Home actually draws can be restored here. Anyone who
        // had hidden Completed or Wishlist before they moved to Library would
        // otherwise be offered a button restoring a shelf that no longer
        // exists on this screen.
        let hidden = GameStatus.homeOrder.filter {
            hiddenStatuses.contains($0.rawValue) && !(grouped[$0] ?? []).isEmpty
        }
        if !hidden.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hidden from Home")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(hidden, id: \.self) { status in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { setHidden(status, false) }
                        } label: {
                            Label("\(status.sectionTitle) (\((grouped[status] ?? []).count))",
                                  systemImage: status.systemImage)
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    private func toggleCollapse(_ status: GameStatus) {
        var set = collapsedStatuses
        if set.contains(status.rawValue) { set.remove(status.rawValue) }
        else { set.insert(status.rawValue) }
        collapsedRaw = set.sorted().joined(separator: ",")
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

    private func togglePause(_ game: Game) {
        guard let active = game.activePlaythrough?.activeSession else { return }
        let repo = Repository(context)
        if active.state == .running { repo.pauseSession(active) }
        else { repo.resumeSession(active) }
    }

    private func stop(_ game: Game) {
        guard let active = game.activePlaythrough?.activeSession else { return }
        Repository(context).stopSession(active)
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

    /// One preference for every status shelf, not one per status — the way
    /// you like reading a shelf is about you, not about which shelf it is.
    @AppStorage("statusList.sort") private var sortRaw = StatusSort.name.rawValue
    @AppStorage("statusList.grid") private var asGrid = false
    @AppStorage("libraryGridSize") private var gridSizeRaw = GridSize.medium.rawValue

    private var sort: StatusSort { StatusSort(rawValue: sortRaw) ?? .name }
    private var gridSize: GridSize { GridSize(rawValue: gridSizeRaw) ?? .medium }

    enum StatusSort: String, CaseIterable {
        case name, lastPlayed, added, rating, releaseYear

        var label: String {
            switch self {
            case .name:        "Name"
            case .lastPlayed:  "Last played"
            case .added:       "Recently added"
            case .rating:      "Rating"
            case .releaseYear: "Release year"
            }
        }
    }

    private var games: [Game] {
        let filtered = allGames.filter { $0.status == status }
        switch sort {
        case .name:
            return filtered
        case .lastPlayed:
            return filtered.sorted {
                ($0.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? .distantPast)
                    > ($1.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? .distantPast)
            }
        case .added:
            return filtered.sorted { $0.addedAt > $1.addedAt }
        case .rating:
            return filtered.sorted {
                if ($0.rating ?? -1) != ($1.rating ?? -1) { return ($0.rating ?? -1) > ($1.rating ?? -1) }
                return $0.name < $1.name
            }
        case .releaseYear:
            return filtered.sorted { ($0.firstReleaseDate ?? .distantPast) > ($1.firstReleaseDate ?? .distantPast) }
        }
    }

    var body: some View {
        Group {
            if asGrid {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: gridSize.minWidth), spacing: 12)],
                        spacing: 16
                    ) {
                        ForEach(games) { game in
                            NavigationLink(value: game) {
                                LibraryGridCell(game: game, size: gridSize)
                            }
                            .buttonStyle(PressableCardStyle())
                            .gameContextMenu(game)
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
            } else {
                List {
                    ForEach(games) { game in
                        NavigationLink(value: game) { GameRow(game: game) }
                            .listRowBackground(Color.clear)
                            .gameContextMenu(game)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .lsBackground()
        .navigationTitle(status.sectionTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $sortRaw) {
                        ForEach(StatusSort.allCases, id: \.rawValue) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                    Divider()
                    Button {
                        asGrid.toggle()
                    } label: {
                        Label(asGrid ? "Show as List" : "Show as Grid",
                              systemImage: asGrid ? "list.bullet" : "square.grid.2x2")
                    }
                } label: {
                    Label("Sort and layout", systemImage: "arrow.up.arrow.down")
                }
            }
        }
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
