import SwiftUI
import SwiftData

@main
struct LevelSelectApp: App {
    let container: ModelContainer = LevelSelectStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { NotificationManager.configure(container: container) }
        }
        .modelContainer(container)
    }
}
