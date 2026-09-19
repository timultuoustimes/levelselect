import SwiftUI

/// The Mac and iPad menu bar.
///
/// One implementation covers both: iPadOS 26 draws a real menu bar from the
/// same `Commands`, and holding ⌘ has always surfaced them as a shortcut
/// sheet. Until now the app declared none, so the Mac shipped stock File/Edit
/// menus that could not add a game and iPad's ⌘ sheet was empty.
///
/// The shape follows the platform rather than any one app: creation in File,
/// presentation and navigation in View. Gamery (checked 08-31) does the same,
/// with tab navigation on ⌘1–⌘4 and destinations after it, which is the part
/// worth copying. Its ⌘S for "Add Game" is not — ⌘N is where "new" lives, and
/// this app has no document to save.
struct LevelSelectCommands: Commands {
    // The Library reads these straight out of UserDefaults, so setting them
    // here needs no plumbing — the menu and the toolbar drive one state.
    @AppStorage("librarySort") private var sortRaw = LibrarySort.status.rawValue
    @AppStorage("libraryViewMode") private var viewModeRaw = LibraryViewMode.grid.rawValue
    @AppStorage("libraryGridSize") private var gridSizeRaw = GridSize.medium.rawValue

    private var nav: AppNavigator { AppNavigator.shared }

    var body: some Commands {
        // Replaces "New Window": this app's "new" is a game, and a second
        // window of the same library is not what ⌘N should mean here.
        CommandGroup(replacing: .newItem) {
            Button("Add Game…") { nav.requestAddGame() }
                .keyboardShortcut("n")
            Button("New Collection…") { nav.requestNewCollection() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Import a CSV…") { nav.requestCSVImport() }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { nav.requestSettings() }
                .keyboardShortcut(",")
        }

        // Find belongs in Edit, beside the pasteboard items, which is where
        // every Mac app puts it and where the muscle memory looks.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find a Game") { nav.requestSearch() }
                .keyboardShortcut("f")
        }

        // Sits with the system's own View items (sidebar, toolbar) rather than
        // in a menu of its own, because that is what these are.
        CommandGroup(after: .toolbar) {
            Picker("Library View", selection: $viewModeRaw) {
                Text("As Grid").tag(LibraryViewMode.grid.rawValue)
                Text("As List").tag(LibraryViewMode.list.rawValue)
            }
            .pickerStyle(.inline)

            Menu("Grid Size") {
                Picker("Grid Size", selection: $gridSizeRaw) {
                    ForEach(GridSize.allCases, id: \.rawValue) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Menu("Sort Library By") {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases, id: \.rawValue) { sort in
                        Text(sort.label).tag(sort.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }

            Button("Clear Library Filters") { nav.requestClearFilters() }
                .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            // ⌘1–⌘4, in tab order. The same four the tab bar shows, so the
            // number you press matches the position you see.
            ForEach(Array(LSTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.menuTitle) { nav.go(to: tab) }
                    .keyboardShortcut(
                        KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

extension LSTab {
    /// Title case for the menu, matching the tab bar's own labels.
    var menuTitle: String {
        switch self {
        case .home: "Home"
        case .library: "Library"
        case .wishlist: "Wishlist"
        case .journal: "Journal"
        }
    }
}
