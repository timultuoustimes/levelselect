import SwiftUI
import SwiftData

@main
struct LevelSelectApp: App {
    let container: ModelContainer = LevelSelectStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
