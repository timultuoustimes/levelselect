import SwiftUI
import SwiftData

/// LevelSelect on the wrist — same SwiftData + CloudKit store as the phone, so
/// your current game, playtime, and sessions stay in sync automatically.
@main
struct LevelSelectWatchApp: App {
    let container: ModelContainer = LevelSelectStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(container)
    }
}
