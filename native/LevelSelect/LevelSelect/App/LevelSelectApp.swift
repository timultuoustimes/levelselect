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
                // The window paints its OWN ground on macOS.
                //
                // Hiding the window toolbar background to get glass took the
                // window's own ground with it — the toolbar material was what
                // made the window solid — so the empty state rendered on the
                // system's default window color, a flat gray. `lsBackground()`
                // lives inside the NavigationStack and never reached the
                // window itself.
                #if os(macOS)
                .containerBackground(LSTheme.background, for: .window)
                #endif
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
        .commands { LevelSelectCommands() }
    }
}
