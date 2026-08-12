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
