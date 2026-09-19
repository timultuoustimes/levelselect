import SwiftUI
import SwiftData

/// App shell: Home / Library / Stats tabs (web-app parity) on the themed accent.
struct RootView: View {
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
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
                // A scroll, not a house — and the pair is the point.
                //
                // The app icon is literally a checklist scroll in a dungeon
                // door, so the scroll is this app's own vocabulary rather than
                // a borrowed one. Tim: *"Home is really the active running
                // log."* An open scroll is a list still being worked through;
                // a closed book is a history already written. Open and closed
                // is the whole distinction between these two tabs, and the
                // glyphs now carry it.
                Tab("Home", systemImage: "scroll.fill", value: LSTab.home) { HomeTab() }
                // A shelf, not a grid. The grid named a LAYOUT — and Library
                // has three of them — so the icon was advertising one setting
                // as the tab's identity. Spines on a shelf are what a
                // collection actually looks like, which is the same reason
                // the systems shelf draws real console art.
                Tab("Library", systemImage: "books.vertical.fill", value: LSTab.library) { LibraryTab() }
                // Bag, not a heart: the wishlist is things to buy, and a heart
                // reads as "favorited" (which is what `pinned` already means).
                Tab("Wishlist", systemImage: "bag.fill", value: LSTab.wishlist) { WishlistTab() }
                Tab("Journal", systemImage: "book.closed.fill", value: LSTab.journal) { JournalTab() }
            }
            .tint(LSTheme.accent)
            .staleSessionGuard()
            .sessionNotePrompt()
            .releaseRemindersPrompt()
            .overlappingTimerGuard()
            .whatsNewOnUpdate()
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

            // Deleting a game is confirmed and recoverable, but recovery was
            // three taps away in Settings. This is the same banner surface the
            // shuffle and generation notices use.
            if let deleted = nav.deletedGame {
                VStack {
                    Spacer()
                    UndoDeleteToast(deleted: deleted) {
                        Repository(context).restoreGame(id: deleted.id)
                        nav.deletedGame = nil
                    } dismiss: {
                        nav.deletedGame = nil
                    }
                    .padding(.horizontal)
                    .padding(.bottom, persistence.lastErrorMessage != nil ? 128 : 64)
                }
                .transition(slideIn)
                .zIndex(3)
                .task(id: deleted.id) {
                    // Long enough to notice and act, short enough not to sit
                    // over the shelf you are trying to look at.
                    try? await Task.sleep(for: .seconds(8))
                    if nav.deletedGame?.id == deleted.id { nav.deletedGame = nil }
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
        .animation(.spring(duration: 0.35), value: nav.deletedGame?.id)
        // Was hard-pinned to .dark for thirty-six builds — the one line that
        // made every other color decision moot. `.system` resolves to nil,
        // which is exactly what this modifier wants for "follow the phone".
        .preferredColorScheme(ThemePalette.appearance.colorScheme)
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
        // Recently Deleted empties itself after thirty days. Here rather than
        // on a timer because there is nothing to do while the app is closed,
        // and a sweep on foreground is the same moment sync repair already
        // runs — one fetch of rows that have a `deletedAt`, which on a healthy
        // library is none.
        repo.purgeExpiredTrash()
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
        // Both spellings: "stats" is what every widget already baked.
        case "journal", "stats": nav.go(to: .journal)
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
                || PlatformShort.ownedMatches(g.ownedPlatformNames, short: platform!)
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
            .lsTapTarget()
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LSTheme.hairline))
    }
}

/// "Deleted — Undo", for the eight seconds after a game goes.
private struct UndoDeleteToast: View {
    let deleted: AppNavigator.DeletedGame
    var undo: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Deleted")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(deleted.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Undo") { undo() }
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
            .lsTapTarget()
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LSTheme.hairline))
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
    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    /// Only to tell whether Settings actually changed the theme — see the
    /// settings sheet's `onDismiss`.
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    @State private var showingAdd = false
    @State private var showingSettings = false
    /// The theme's `updatedAt` at the moment Settings opened.
    @State private var themeStampAtOpen: Date?
    @State private var editingProfile = false
    @State private var showingCSVImport = false
    @State private var showingWelcome = false
    /// What the welcome's button asked for, fired from its onDismiss so the
    /// next sheet never races the one still animating away.
    @State private var welcomeChoice: WelcomeView.Choice?
    /// Whether Home's content has moved under the bar — drives the scroll
    /// edge effect while the header's art bleeds. See the scroll view below.
    @State private var scrolledUnderBar = false
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
        // Computed HERE, not carried in @State.
        //
        // It was a `@State` flag set from the scroll view's `.onAppear` — so
        // on the very first render the toolbar was configured with the flag
        // still false, and the update afterwards did not always re-apply to a
        // bar the system had already laid out. The simulator won that race and
        // King Kai lost it, which is exactly the kind of bug that looks like
        // "works on my machine". Deriving it in `body` means the toolbar and
        // the scroll view cannot disagree.
        // Home already holds every game, so the counts behind the "Most used"
        let summary = PlayerSummary.make(from: games)
        let bleeds = ProfileHeader.drawsArt(profile: profiles.first, summary: summary)

        return NavigationStack(path: $path) {
            Group {
                // Home draws its shelves even with nothing on them. F1 —
                // and Tim, on the first build of it: *"you opened an empty app
                // before loading the demo library, and it wasn't showing the
                // new empty state."* He was right. Sending a zero-game library
                // down a different branch meant the one moment the promises
                // were written for — the screen straight after the welcome —
                // was the one screen that never showed them.
                home(summary, bleeds)
            }
            .lsBackground()
            // Home already holds every game, so the counts behind the
            // "Most used" chip order are free here and a fetch anywhere else.
            // In a `task` rather than in the body: it writes a static, which
            // invalidates nothing, but a body that has side effects is a body
            // that will eventually have a surprising one.
            .task(id: games.count) {
                ThemePalette.refreshOwnershipUsage(from: games)
            }
            #if os(macOS)
            .navigationTitle("LevelSelect")
            // Same reason as iOS below: the window toolbar draws an opaque
            // background that both hides the art behind it and flattens the
            // controls sitting on it. Hidden while the header paints art, the
            // tab pills and the gear/plus render as glass over the artwork,
            // which is what iPad already did.
            // Unconditional on macOS, matching Library, Wishlist and Stats.
            // Keying it to `bleeds` meant Home lost its glass whenever the
            // header had no art to draw — an empty demo library, say — so the
            // window changed character depending on which library was loaded.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
            // `toolbarBackgroundVisibility`, not `toolbarBackground`. The older
            // modifier still compiles and did nothing here — the bar kept
            // drawing its own translucent slab with a hard bottom edge, which
            // is what King Kai kept showing after two "fixes".
            .toolbarBackgroundVisibility(bleeds ? .hidden : .automatic, for: .navigationBar)
            #endif
            .navigationDestination(for: Game.self) { GameDetailView(game: $0) }
            .navigationDestination(for: GameFacet.self) { FacetGamesView(facet: $0) }
            .navigationDestination(for: GameStatus.self) { StatusListView(status: $0) }
            .navigationDestination(for: TrackerRoute.self) { TrackerPageView(game: $0.game) }
            .navigationDestination(for: PlatformRoute.self) { PlatformGamesView(platform: $0.platform) }
            .navigationDestination(for: CollectionRoute.self) { CollectionRouteView(route: $0) }
            .toolbar {
                #if !os(macOS)
                ToolbarItem(placement: .topBarLeading) {
                    // Leading, not principal. Centered, it drifted with the
                    // number of buttons beside it; pinned, it is the same
                    // anchor on every tab. See `lsWordmarkHeader`.
                    Wordmark(size: 13)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                // Not a control, so not a glass capsule. See `lsWordmarkHeader`.
                .sharedBackgroundVisibility(.hidden)
                #endif
                // Tinted per item rather than relying on an inherited tint:
                // the window toolbar sits outside the TabView on macOS, so
                // whatever `.tint` the tab tree carries does not reliably
                // reach it.
                // Colored EXPLICITLY, not via tint.
                //
                // Library's sort/filter/add take the accent from the same
                // inherited `.tint` these buttons get — Library sets none of
                // its own. The difference is the control: macOS applies a
                // toolbar tint to a `Menu`'s symbol and ignores it for a plain
                // `Button`'s. Neither `.tint` nor `.buttonStyle(.bordered)`
                // moved them; `foregroundStyle` on the label does, because it
                // stops asking and just says the color.
                ToolbarItem(placement: Self.trailing) {
                    Button {
                        themeStampAtOpen = themeSettings.first?.updatedAt
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .foregroundStyle(LSTheme.accent)
                    }
                }
                ToolbarItem(placement: Self.trailing) {
                    Button { showingAdd = true } label: {
                        Label("Add Game", systemImage: "plus")
                            .foregroundStyle(LSTheme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) { AddGameSheet().lsSheet() }
        // `onDismiss`, not the sheet's own `onDisappear`: this fires ONCE when
        // Settings actually closes, where that fired on any disappearance —
        // including pushing a subscreen onto the Settings stack, which re-keyed
        // the tab tree and tore down the sheet mid-tap.
        .sheet(isPresented: $showingSettings, onDismiss: {
            // **Only if the theme actually changed.**
            //
            // Bumping this re-keys the whole tab tree (`.id(nav.themeRevision)`
            // above), which tears down all four tabs and builds them again. Done
            // unconditionally, that happened on EVERY Settings close — and the
            // rebuilt tree lays out from zero width inside the sheet's dismissal
            // animation, so Home visibly grew back from the left edge with white
            // to the right of it. Measured off Tim's recording: 0%, 64%, 81%,
            // 92%, 98% of the screen width across about 230ms.
            //
            // Most visits to Settings do not touch the theme, so most of them
            // now cost nothing. `updatedAt` is the model's own change stamp, and
            // it is what `RootView` already watches to refresh the palette.
            let stamp = themeSettings.first?.updatedAt
            defer { themeStampAtOpen = nil }
            guard stamp != themeStampAtOpen else { return }
            // And when it DID change, re-key without animating — the rebuild is
            // a swap, not a movement, and animating it is what made the relayout
            // legible in the first place.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { AppNavigator.shared.themeRevision += 1 }
        }) { SettingsView().lsSheet() }
        .sheet(isPresented: $editingProfile) { ProfileEditor().lsSheet() }
        .sheet(isPresented: $showingCSVImport) { CSVImportView().lsSheet() }
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
                // **Full height, unlike every other sheet.**
                //
                // Fable's 5.9 is that the welcome should appear on iPad, and it
                // does — the trigger is an empty library and an unseen flag,
                // with no idiom gate anywhere. What it did NOT survive was
                // today's move to a partial detent for every menu sheet: on a
                // 13-inch iPad that renders the app's introduction as a small
                // floating card. A first run is the one sheet with nothing
                // behind it worth seeing through to.
                .lsSheet([.large])
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
        // Menu bar (Mac and iPad). See LevelSelectCommands.
        .onChange(of: nav.addGameRequest) { _, _ in showingAdd = true }
        .onChange(of: nav.csvImportRequest) { _, _ in showingCSVImport = true }
        .onChange(of: nav.settingsRequest) { _, _ in
            themeStampAtOpen = themeSettings.first?.updatedAt
            showingSettings = true
        }
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

    private func home(_ summary: PlayerSummary, _ headerBleeds: Bool) -> some View {
        // The GeometryReader is here for one number: the top safe-area inset,
        // which is how far the art has to reach up to sit under the toolbar.
        GeometryReader { outer in
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                // Whose shelf this is, before what is on it. Draws nothing
                // until someone has actually put something in it.
                // At zero games the band draws itself empty — see
                // `ProfileHeader.placeholderWhenEmpty`. The page then has the
                // shape it will always have, and the first game fills it in
                // rather than rearranging it.
                ProfileHeader(profile: profiles.first, summary: summary,
                              topOverscan: headerBleeds ? outer.safeAreaInsets.top : 0,
                              placeholderWhenEmpty: games.isEmpty) {
                    editingProfile = true
                }

                // Nothing to continue and nothing on any shelf: the call to
                // action takes the hero's place, and the promise shelves carry
                // on underneath it. Both, not either — the buttons are the
                // only way to add a game, and the shelves are what the app is.
                if games.isEmpty { emptyState }

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
                    // A new library draws its empty shelves instead of hiding
                    // them, captioned with the welcome's own promises. See
                    // `AppPromise` and F1: one game in a screen of nothing
                    // teaches nobody what the screen is, and the shelves are
                    // the part of the app that keeps the promises.
                    if items.isEmpty, showsPromiseShelves,
                       !hiddenStatuses.contains(status.rawValue),
                       let caption = status.emptyShelfCaption {
                        PromiseShelf(status: status, caption: caption)
                    }
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
                // After what's live and what's next, because that is when it
                // happened. Beating a game is the one event Home had no words
                // for — the game simply left Now Playing and nothing marked
                // it. Empties itself after a month; the permanent record is
                // Library's Finished shelf.
                if !recentlyBeaten.isEmpty {
                    RecentlyBeatenShelf(games: recentlyBeaten) { path.append($0) }
                }
                hiddenStatusesFooter
                // The fourth promise, in the one place it fits.
                //
                // Privacy has no shelf — it is about the whole app — so on a
                // new library it closes the page, which is where the welcome
                // puts it too. It leaves with the captions.
                if showsPromiseShelves { privacyPromiseFooter }
                // After the shelves, not above them: an ask, never a nag —
                // and not before there is anything to have an opinion about.
                //
                // The first question is "what were you using to keep track
                // before this?", which at zero games is being asked of someone
                // who has not used the app for a second. Fable, 2026-09-07:
                // *"it asks what you used before you have added anything; it
                // belongs after the first game."* The card already answers
                // through the same composer as Send feedback, so the only
                // thing wrong with it was when it appeared.
                if !games.isEmpty { BetaQuestionCard() }
            }
                .padding(.bottom)
                // The art runs to the top edge, under the toolbar. Everything
                // else keeps the ordinary inset.
                .padding(.top, headerBleeds ? 0 : 16)
            }
            .scrollIndicators(.hidden)
            // THE hard edge, finally named.
            //
            // iOS 26 draws a "scroll edge effect" where content meets a bar,
            // and its default style is literally `.hard` — a crisp line. That
            // is what King Kai kept showing through two toolbar-background
            // fixes: the bar's background was not drawing it, this was. `.soft`
            // is the gradual fade, which is what the art wants.
            // **Do not put `.scrollEdgeEffectStyle(.soft)` back.**
            //
            // Every scroll view in the app carried it, added to kill "a crisp
            // line where content meets a bar". That line is not a defect — it
            // is the EDGE of iOS 26's glass, and `.soft` trades the material
            // away for a plain fade. Which is why the frosted header looked
            // broken for three days and looked broken on every surface except
            // Settings, the one screen that never had the modifier. Tim
            // settled it by pointing at another app: *"It's also not the beta
            // breaking the header turning to glass, because gamery's works."*
            // Reproduced on the simulator by scrolling — something none of the
            // earlier passes had done — and fixed in one line.
            // ONLY when the header paints art. Without a header, letting
            // content start under the bar would put Continue Playing behind
            // the toolbar at rest, which is a bug rather than an effect.
            .ignoresSafeArea(.container, edges: headerBleeds ? .top : [])
            // **Clear at rest, frosted once you move.**
            //
            // Home's art deliberately starts UNDER the bar, so the scroll edge
            // effect has something to frost from the very first frame — and it
            // did, putting a glass band across the top of the artwork before
            // anyone had scrolled. Tim: *"Home is now opening with the glass bar
            // across the top, as opposed to showing when a scroll starts."*
            //
            // The bar's own background is already hidden while the header
            // bleeds; this is the other half, the edge effect. Hidden while the
            // content is where it started, so the art is unobstructed, and back
            // the moment anything passes under the bar.
            //
            // Only when the header bleeds. Without art there is nothing under
            // the bar at rest anyway, and the system's own timing is right.
            .scrollEdgeEffectHidden(headerBleeds && !scrolledUnderBar, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > 1
            } action: { _, moved in
                scrolledUnderBar = moved
            }
        }
    }

    /// Whether Home is still in the stretch just after the welcome, where an
    /// empty shelf is worth drawing.
    ///
    /// Tied to the size of the library rather than to a "seen it" flag, so it
    /// answers the question that actually matters — is there enough here to
    /// explain itself? — and so it comes back for anyone who clears their
    /// library out and starts again.
    private var showsPromiseShelves: Bool {
        games.count <= AppPromise.newLibraryLimit
    }

    /// The privacy promise, repeated verbatim from the welcome.
    private var privacyPromiseFooter: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: AppPromise.privacy.symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppPromise.privacy.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(AppPromise.privacy.body)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    /// Finished in the last month. See `RecentlyBeaten`.
    private var recentlyBeaten: [Game] {
        RecentlyBeaten.games(from: games).map(\.game)
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
    /// **The first thing the eye lands on should look like the app.**
    ///
    /// This was a `ContentUnavailableView`: a gray system glyph, system type
    /// and two system buttons, on a screen where the shelves, the rules and
    /// the footer had all been designed. Fable, 2026-09-07: *"it is the least
    /// designed object on the page and it is the first thing the eye lands
    /// on."* Tim agreed, and named why it had survived: *"mostly because I
    /// forget about it, since my library has games in it."*
    ///
    /// Same words, same two actions, in the app's own surface — the card
    /// treatment every other block on Home wears, an accent glyph instead of a
    /// gray one, and the primary action carrying the accent it opens into.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 34))
                .foregroundStyle(LSTheme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Start your shelf")
                    .font(.title3.weight(.semibold))
                Text("Add a game you're playing — then give it a tracker: paste a checklist you already have, or let LevelSelect draft one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                // Matches the sheet it opens, and the menu item. Codex P5.
                Button { showingAdd = true } label: {
                    Text("Add Game")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LSTheme.onAccent)
                .background(LSTheme.accent, in: .capsule)
                // A spreadsheet is how most people arrive with a backlog. This
                // opened the whole Settings form and left them to find the
                // importer — a dead end at the exact moment someone is deciding
                // whether the app is worth the effort.
                Button("Import a CSV") { showingCSVImport = true }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(LSTheme.accent)
                    .lsTapTargetTall()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .lsCard()
        .padding(.horizontal)
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
