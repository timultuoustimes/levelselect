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
                .containerBackground(LSTheme.liveGround, for: .window)
                // **And now the toolbar can lose its own.**
                //
                // Hiding it was tried once and reverted, for the reason above:
                // the toolbar material WAS the window's ground, so hiding it
                // dropped the whole window to system gray. `containerBackground`
                // is that ground now, which is what makes this safe — and
                // without it a game page wore a 48pt band of flat #1C1C1C
                // between the title bar and its own key art, measured off the
                // window. Tim, 2026-09-10: *"game pages have the grey header
                // space under the nav pill."*
                .toolbarBackground(.hidden, for: .windowToolbar)
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
