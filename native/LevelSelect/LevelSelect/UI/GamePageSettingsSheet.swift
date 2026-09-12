import SwiftUI

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
            Form {
                AppearanceSettingsSection(scope: .gamePages)
                AppearanceSettingsSection(scope: .trackers)
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("All Game Pages")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}
