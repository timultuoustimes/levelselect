import SwiftUI
import SwiftData

@main
struct LevelSelectApp: App {
    /// Observed rather than stored, so switching to the demo library swaps the
    /// container out from under the whole app.
    @State private var library = LibrarySwitcher.shared

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Forces a clean rebuild on a library switch. Without it,
                // @Query results from the previous container can linger.
                .id(library.isDemo)
                .task(id: library.isDemo) {
                    let container = library.container
                    NotificationManager.configure(container: container)
                    BuiltinTrackers.installMissing(context: container.mainContext)
                    WidgetBridge.refresh()
                    SyncStatusMonitor.shared.start()
                }
        }
        .modelContainer(library.container)
    }
}
