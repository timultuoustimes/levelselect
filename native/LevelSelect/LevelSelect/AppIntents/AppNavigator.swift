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
    /// colour, or moving any slider in the colour picker, threw you back to
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
}
