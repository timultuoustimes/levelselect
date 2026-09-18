import SwiftUI
import SwiftData

/// **The game-page settings, reachable from a game page.**
///
/// Tim, twice: *"it's weird that I have to jump out of a game page, go back to
/// the home tab, tap settings, scroll until I find game page and tracker
/// settings"* — and then, choosing the wording: *"Game page settings is fine."*
///
/// It holds the same two groups Settings does, not copies of them. Nothing is
/// removed from Settings; this is a second door into one room.
///
/// The sheet's own title says the scope out loud, which is what answers the
/// objection that moved these out of a game's menu in the first place: a
/// library-wide setting reached from one game read as a per-game setting. "All
/// Game Pages" cannot be misread that way.
struct GamePageSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LSForm {
                AppearanceSettingsSection(scope: .gamePages)
                AppearanceSettingsSection(scope: .trackers)
            }
            #if os(macOS)
            .formStyle(.grouped)
            // In its own window on the Mac, painted by the window's container
            // background — see `GamePageSettingsWindow`.
            .scrollContentBackground(.hidden)
            #endif
            .navigationTitle("All Game Pages")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}

#if os(macOS)
/// **All Game Pages, as a window you can move out of the way.**
///
/// Tim, 2026-09-11: *"are we able to make the settings sheets movable on mac?
/// i'm trying to change the game page layouts, but it is stuck covering the
/// game page and I can't see the header layout."* A Mac sheet is fixed to its
/// window. This is a real window instead: it floats above the app so it stays
/// in reach, it can be dragged anywhere, and every change lands on the game
/// page behind it as it is made. iPhone and iPad keep the sheet.
///
/// An inspector was the other candidate and is wrong here: the pages this
/// pushes (Ownership & access) hide the window toolbar to draw their own
/// header, and inside an inspector that would take the MAIN window's toolbar,
/// nav pill and all, with it.
struct GamePageSettingsWindow: Scene {
    static let id = "game-page-settings"
    let container: ModelContainer

    var body: some Scene {
        Window("All Game Pages", id: Self.id) {
            GamePageSettingsSheet()
                // A new window starts with none of the main one's
                // environment: the accent comes from `RootView`'s `.tint`.
                .tint(LSTheme.accent)
                .preferredColorScheme(ThemePalette.appearance.colorScheme)
                .containerBackground(LSTheme.liveSheetGround, for: .window)
                .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .modelContainer(container)
        .windowLevel(.floating)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 460, height: 640)
    }
}
#endif
