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
