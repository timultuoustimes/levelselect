import Foundation

/// The app's four top-level tabs.
enum LSTab: String, Hashable, CaseIterable {
    case home, library, wishlist, stats
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

    func open(gameID: UUID) {
        selectedTab = .home
        pendingGameID = gameID
    }

    func continuePlaying() {
        selectedTab = .home
        pendingContinue = true
    }

    func go(to tab: LSTab) {
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

    func requestSearch() {
        if selectedTab != .library && selectedTab != .wishlist {
            selectedTab = .library
        }
        searchRequest += 1
    }

    func requestClearFilters() {
        selectedTab = .library
        clearFiltersRequest += 1
    }
}
