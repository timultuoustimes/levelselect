import SwiftUI
import SwiftData

@main
struct LevelSelectApp: App {
    let container: ModelContainer = LevelSelectStore.shared

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    NotificationManager.configure(container: container)
                    BuiltinTrackers.installMissing(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}
