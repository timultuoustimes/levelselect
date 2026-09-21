import Foundation

/// The app's four top-level tabs.
enum LSTab: String, Hashable, CaseIterable {
    /// **The raw value stays `"stats"` on purpose, and must keep staying.**
    ///
    /// The charts were the whole tab until the journal took it over, and that
    /// name leaked outward: widget deep links are baked as `levelselect://stats`
    /// per timeline entry, and `LSSection` is an `AppEnum`, which persists the
    /// raw value inside whatever Shortcuts anyone has already built. Renaming
    /// the case is a readability change; renaming the raw value silently
    /// breaks a shortcut somebody wrote, months later, with no error.
    /// `news` is build 39 (schema V7), and sits before the journal to match
    /// the tab bar. Shown only once `SchemaDeploy.v7Fields` holds — see
    /// `isAvailable`.
    case home, library, wishlist, news, journal = "stats"
    /// Universal search — the tab bar's search circle, which iOS draws only
    /// beside four tabs (measured 09-18). See `wishlistInLibrary`.
    case search

    /// Whether this build shows the tab. News writes record types CloudKit
    /// Production lacks until V7 is deployed there.
    var isAvailable: Bool {
        switch self {
        case .news: SchemaDeploy.v7Fields
        case .wishlist: !Self.wishlistInLibrary
        case .search: Self.wishlistInLibrary
        default: true
        }
    }

    /// **Wishlist is half of Library** (09-18). Tim: *"wishlist is essentially
    /// future library and games you hope to add to your library."* Four tabs
    /// is also what lets universal search be the tab bar's own circle — with
    /// five, iOS made it a sixth tab and put Journal behind "More".
    ///
    /// Built to reverse: false brings back the Wishlist tab and the
    /// magnifying glass on every toolbar, and nothing else changes.
    static let wishlistInLibrary = true

    /// The tabs the menu numbers ⌘1–⌘4, in tab-bar order. Search sits apart.
    static var numbered: [LSTab] { allCases.filter { $0 != .search && $0.isAvailable } }
}

/// Shared navigation bus that App Intents (and widget deep links) drive.
/// The app UI observes it and reacts: switching tabs, opening a game, or
/// continuing the current game.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()
    private init() {}

    /// Currently selected tab (bound to the RootView TabView).
    var selectedTab: LSTab = .home

    /// Bumped when the theme has finished changing, to force the tab tree to
    /// re-read `ThemePalette`'s statics.
    ///
    /// It lives here, and is bumped only when Settings CLOSES, because the
    /// tree is keyed off it — and re-keying a view destroys it. Bumping this
    /// on every theme edit tore down the whole TabView mid-edit, which reset
    /// HomeTab's `@State` and slammed the Settings sheet shut. Tapping any
    /// color, or moving any slider in the color picker, threw you back to
    /// Home before you could choose: the first touch was the last one.
    ///
    /// The real fix is making `ThemePalette` observable so views re-render
    /// where they read it, rather than the tree being rebuilt wholesale. That
    /// is 156 call sites and a separate job.
    var themeRevision = 0

    /// A status to show in Library, set by "See all" on a Home shelf.
    ///
    /// Home stops at what is live and what is next; seeing all of a status is
    /// browsing, and browsing is Library's job. Sending it here rather than
    /// pushing `StatusListView` onto Home's own stack keeps Home from growing
    /// a second browsing surface beside the one it just handed over.
    var pendingLibraryStatus: GameStatus?

    /// Which half of Library shows — see `LSTab.wishlistInLibrary`.
    var libraryHalf: LibraryHalf = .collection

    /// A game to push onto the Home stack (consumed by HomeTab).
    var pendingGameID: UUID?

    /// Request to open the current "continue playing" game.
    var pendingContinue = false

    /// A game whose pushed tracker page just dismissed itself because the
    /// window became wide enough to show that tracker beside the page. The
    /// detail page consumes this and opens the pane, so rotating with the
    /// tracker open lands on the split rather than dropping you back to the
    /// game page with the tracker closed.
    var trackerStageRequest: UUID?

    /// A route value to push onto the Home stack (StatusListView,
    /// PlatformGamesView, CollectionDetailView…) — consumed by HomeTab.
    var pendingRoute: AnyHashable?

    func push(_ route: AnyHashable) {
        selectedTab = .home
        pendingRoute = route
    }

    /// The die's last roll, for the toast: which game, and the URL that
    /// rolled it (so Re-roll repeats the same filters).
    struct ShuffleRoll: Equatable {
        let id = UUID()
        let gameName: String
        let sourceURL: URL
    }
    var shuffleRoll: ShuffleRoll?

    /// A game just moved to Recently Deleted, and can be put back from here.
    ///
    /// Deleting is confirmed and recoverable, but recovery lived three taps
    /// away in Settings — true, and no help at the moment you realise you
    /// tapped the wrong row. Tim, asked whether Delete Game should have an
    /// inline undo: *"yours"* — a toast, on the surface the app already has
    /// for exactly this.
    ///
    /// The id rather than the object: the row is tombstoned, and holding a
    /// model object across a toast's lifetime is how a deleted-object crash
    /// happens. The name is captured because the toast has to say it after
    /// the game has left every live query.
    struct DeletedGame: Identifiable {
        let id: UUID
        let name: String
        /// The rest of a batch deleted together (Library's select mode,
        /// 09-21). Undo puts back all of them, because a selection is one
        /// action to the person who made it.
        var alsoDeleted: [UUID] = []
        var allIDs: [UUID] { [id] + alsoDeleted }
    }
    var deletedGame: DeletedGame?

    /// **Badges earned a moment ago, waiting to be celebrated** (build 40).
    ///
    /// Set by `BadgeAwarder` through `WidgetBridge.refresh`, consumed by the
    /// root view's confetti and toast. A queue rather than one, because
    /// finishing a tracker can land three at once — they celebrate together.
    var earnedBadges: [Badges.Definition] = []

    /// Holds a badge back while a sheet covers the root — see
    /// `BadgeCelebrationQueue`.
    /// `@ObservationIgnored` because the queue is plumbing, not state a view
    /// reads — and because `@Observable` rewrites a plain stored property
    /// into a computed one, which `lazy` cannot be.
    @ObservationIgnored private lazy var badgeQueue: BadgeCelebrationQueue = {
        BadgeCelebrationQueue { [weak self] badges in self?.earnedBadges += badges }
    }()

    /// Celebrate now, or as soon as there is a screen to celebrate on.
    func celebrate(_ badges: [Badges.Definition]) { badgeQueue.celebrate(badges) }

    func sheetOpened() { badgeQueue.sheetOpened() }
    func sheetClosed() { badgeQueue.sheetClosed() }

    /// Which Journal lens to open — the badge toast's "See" lands on Badges.
    /// A raw value rather than the enum, because `JournalTab.Lens` is a view
    /// type and the navigator is the one place that must not import the UI.
    var journalLens: String?

    func open(gameID: UUID) {
        selectedTab = .home
        pendingGameID = gameID
    }

    func continuePlaying() {
        selectedTab = .home
        pendingContinue = true
    }

    func go(to tab: LSTab) {
        // Shortcuts, widget links and "See all" still name the wishlist;
        // it lives in Library now.
        if tab == .wishlist && LSTab.wishlistInLibrary {
            selectedTab = .library
            libraryHalf = .wishlist
            return
        }
        // Search is a tab only beside four tabs; otherwise it's the cover.
        if tab == .search && !LSTab.search.isAvailable {
            searchPresented = true
            return
        }
        if tab == .library { libraryHalf = .collection }
        selectedTab = tab
    }

    // MARK: Menu bar requests
    //
    // The menu bar lives in the Scene, outside the view tree that owns these
    // sheets, so a command raises a request here and the view consumes it.
    //
    // Counters, not Bools: pressing ⌘N twice has to open the sheet twice, and
    // setting a Bool that is already true changes nothing — so the second
    // press would be silently swallowed.
    var addGameRequest = 0
    var csvImportRequest = 0
    var settingsRequest = 0
    var newCollectionRequest = 0
    var clearFiltersRequest = 0

    func requestAddGame() { addGameRequest += 1 }
    func requestCSVImport() { csvImportRequest += 1 }
    func requestSettings() { settingsRequest += 1 }

    /// Both of these act on the Library, so they take you there first —
    /// a new collection appearing on a tab that cannot show it, or filters
    /// clearing out of sight, would read as the command having done nothing.
    func requestNewCollection() {
        selectedTab = .library
        newCollectionRequest += 1
    }

    /// ⌘F focuses the search field on the tab you are already on — Library
    /// and Wishlist each have their own, and jumping you to Library from a
    /// wishlist you were searching would be the wrong kind of helpful.
    ///
    /// From Home or Stats, which have no search, it goes to Library: that way
    /// ⌘F always means "find a game" rather than sometimes meaning nothing.
    var searchRequest = 0
    /// Universal search, over whatever tab you're on (`SearchScreen`).
    var searchPresented = false
    /// Words for universal search to start with — Siri's "search LevelSelect
    /// for …". `SearchScreen` takes them and clears this.
    var pendingSearchTerm: String?

    func search(_ term: String) {
        pendingSearchTerm = term
        go(to: .search)
    }

    func requestSearch() {
        // Library and Wishlist search within themselves; everywhere else,
        // ⌘F opens universal search (09-18). It used to jump to Library,
        // back when that was the only search there was.
        if selectedTab != .library && selectedTab != .wishlist {
            if LSTab.wishlistInLibrary { selectedTab = .search } else { searchPresented = true }
            return
        }
        searchRequest += 1
    }

    func requestClearFilters() {
        selectedTab = .library
        clearFiltersRequest += 1
    }
}

/// The two halves of Library. See `LSTab.wishlistInLibrary`.
enum LibraryHalf: String, CaseIterable, Identifiable, Sendable {
    case collection, wishlist
    var id: String { rawValue }
    var label: String { self == .collection ? "Collection" : "Wishlist" }
}
