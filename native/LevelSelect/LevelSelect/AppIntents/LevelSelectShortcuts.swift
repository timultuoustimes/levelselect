import AppIntents

/// App Shortcuts — these appear automatically in the Shortcuts app, Spotlight,
/// and Siri, and can be added to the Home Screen as single-icon launchers.
struct LevelSelectShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinuePlayingIntent(),
            phrases: [
                "Continue playing in \(.applicationName)",
                "Resume my game in \(.applicationName)",
                "\(.applicationName) continue",
            ],
            shortTitle: "Continue",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: OpenSectionIntent(.journal),
            phrases: [
                "Open \(.applicationName) journal",
                "Show my \(.applicationName) journal",
                // Kept: the tab answered to "stats" for thirty-five builds,
                // and a phrase someone already says out loud should not stop
                // working because the tab grew.
                "Open \(.applicationName) stats",
                "Show my \(.applicationName) stats",
            ],
            shortTitle: "Journal",
            systemImageName: "book.closed.fill"
        )
        AppShortcut(
            intent: OpenSectionIntent(.library),
            phrases: [
                "Open my \(.applicationName) library",
                "Show my \(.applicationName) library",
            ],
            shortTitle: "Library",
            systemImageName: "square.grid.2x2.fill"
        )
        AppShortcut(
            intent: OpenSectionIntent(.wishlist),
            phrases: [
                "Open my \(.applicationName) wishlist",
                "Show my \(.applicationName) wishlist",
            ],
            shortTitle: "Wishlist",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: OpenGameIntent(),
            phrases: [
                "Open \(\.$game) in \(.applicationName)",
            ],
            shortTitle: "Open Game",
            systemImageName: "gamecontroller.fill"
        )
        AppShortcut(
            intent: PlayGameIntent(),
            phrases: [
                "Play \(\.$game) in \(.applicationName)",
                "Start a session for \(\.$game) in \(.applicationName)",
            ],
            shortTitle: "Start Session",
            systemImageName: "play.circle.fill"
        )
    }
}
