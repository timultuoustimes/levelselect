import SwiftUI
import AppIntents

/// Siri & Shortcuts, under General (build 39, 09-18).
///
/// Tim asked for a way to build a shortcut from a game. Apple offers no way
/// to open the Shortcuts editor with a game filled in, so this is a page in
/// Settings rather than an item on a game's menu, where it would promise
/// more than it can do. It links out to the app's Shortcuts page, where every
/// game already has its own tile.
///
/// "If Siri doesn't answer" is here because of King Kai: every spoken phrase
/// failed until the Siri switch on LevelSelect's Shortcuts page was turned
/// on, and nothing anywhere said that switch existed.
struct SiriShortcutsSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Siri & Shortcuts",
                     icon: "waveform",
                     blurb: "Open a game, start a session or search your library without opening the app first.") {
            Section {
                phrase("Open Hades in LevelSelect", "Opens the game's page.")
                phrase("Start a session for Hades in LevelSelect", "Starts the clock without opening the app.")
                phrase("Continue playing in LevelSelect", "Opens the game you're playing.")
                phrase("Search LevelSelect for Silksong", "Opens search with the words filled in.")
                phrase("Open LevelSelect news", "Also works for your library, wishlist and journal.")
            } header: {
                Text("Say to Siri")
            } footer: {
                Text("Any game in your library works in place of Hades. Siri has to hear the name as it's written, so an unusual title can land in search instead — the game is usually at the top.")
            }

            Section {
                // One row, so the button and what it opens share a card. As
                // two rows with the button's cleared, the card started under
                // the button and read as a stray gray slab (King Kai, 09-18).
                VStack(spacing: 14) {
                    #if os(iOS)
                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                    #endif
                    Text("LevelSelect's page in the Shortcuts app has an Open Game and a Start Session tile for each of your games. Use one as it is, or add it to a shortcut of your own and give it any name you like to say.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
            } header: {
                Text("Shortcuts")
            }

            Section {
                Text("In the Shortcuts app, find LevelSelect, tap \(Image(systemName: "info.circle")) and turn on Siri. It can be off without anything saying so, and then Siri answers every phrase with a web search.")
                    .font(.footnote)
            } header: {
                Text("If Siri doesn't answer")
            }

            Section {
                #if os(iOS)
                row("magnifyingglass", "Spotlight",
                    "Swipe down on the Home Screen and type a game's name. Your games show with their system, status and hours.")
                #else
                row("magnifyingglass", "Spotlight",
                    "Press ⌘-Space and type a game's name. Your games show with their system, status and hours.")
                #endif
                #if os(iOS)
                row("switch.2", "Control Center",
                    "Add the Play Session control to start and stop the clock on your current game.")
                #endif
                row("square.grid.2x2", "Widgets",
                    "Your current game, what's next, your week, your streak and more, on the Home Screen and Lock Screen.")
            } header: {
                Text("Elsewhere")
            }
        }
    }

    private func phrase(_ words: String, _ what: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("“\(words)”")
            Text(what)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(LSTheme.accent)
        }
    }
}
