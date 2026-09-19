import SwiftUI
import SwiftData

/// What you call your consoles.
///
/// `PlatformShort` folds IGDB's spellings to one short name per machine, and
/// for a handful of machines that name is a matter of where you grew up or
/// what you have always said. The app was picking for everyone. Tim: *"the
/// user should be able to choose which one they want displayed, not forced to
/// see Genesis if they don't call it that."*
///
/// The choice reaches every shelf heading, chip, filter, menu and widget,
/// because it is applied inside `PlatformShort.name` rather than at any of the
/// twenty-one places that call it.
struct SystemNamesSettingsPage: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    var body: some View {
        SettingsPage(title: "System names",
                     icon: "textformat",
                     blurb: "Some consoles were sold under two names, and some just have a name you actually say. Pick yours — it changes every shelf, chip and widget that names that system.") {
            if !mine.isEmpty {
                Section {
                    ForEach(mine, id: \.self) { row($0) }
                } header: {
                    Text("Your systems")
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.self) { row($0) }
                } header: {
                    Text(mine.isEmpty ? "Systems" : "Others")
                } footer: {
                    // Said once, and only where it applies: these rows do
                    // nothing visible today, which without a word looks like a
                    // setting that failed rather than one waiting.
                    Text("You don't own anything on these yet. Your choice is remembered for when you do.")
                }
            }
        }
    }

    /// One console, its names, and the one in force.
    private func row(_ short: String) -> some View {
        let names = PlatformNaming.alternatives[short] ?? [short]
        return Picker(selection: binding(for: short)) {
            ForEach(names, id: \.self) { Text($0).tag($0) }
        } label: {
            Label {
                Text(PlatformNaming.hardwareName(for: short))
            } icon: {
                // The console's own art, so the row is recognizable before the
                // words are read — the same tile the systems shelf draws.
                PlatformMenuIcon(platform: iconSource[short] ?? short)
            }
        }
    }

    /// Writes the choice, and removes it again when you pick the default back.
    ///
    /// Storing "Genesis" for Genesis would be a row of data that says nothing,
    /// and it would then sync, merge and outlive the build that wrote it. An
    /// absent key is the same answer with none of that.
    private func binding(for short: String) -> Binding<String> {
        Binding(
            get: {
                let stored = themeSettings.first?.platformNames[short]
                guard let stored, PlatformNaming.isValid(stored, for: short) else {
                    return PlatformNaming.defaultName(for: short)
                }
                return stored
            },
            set: { chosen in
                let settings = ThemePalette.fetchOrCreate(in: context)
                var map = settings.platformNames
                if chosen == PlatformNaming.defaultName(for: short) {
                    map.removeValue(forKey: short)
                } else {
                    map[short] = chosen
                }
                settings.platformNames = PlatformNaming.sanitized(map)
                settings.updatedAt = .now
                PersistenceMonitor.shared.commit(context)
                ThemePalette.refresh(from: settings)
                // Widgets read a snapshot, not the store — without this the
                // Home Screen keeps the old name until something else changes.
                WidgetBridge.refresh()
            })
    }

    // MARK: What you own

    /// The stored platform string to draw art from, per short name — so the
    /// row shows a real Mega Drive rather than a generic controller.
    private var iconSource: [String: String] {
        var found: [String: String] = [:]
        for game in games {
            for stored in game.ownedPlatformNames {
                let short = PlatformShort.builtinName(stored)
                if found[short] == nil { found[short] = stored }
            }
        }
        return found
    }

    /// Consoles with a choice that you actually own something on.
    ///
    /// Matched on `builtinName`, not `name`, or a console would leave this
    /// list the moment you renamed it — the row would vanish under you as you
    /// used it.
    private var mine: [String] {
        let owned = Set(games.flatMap(\.ownedPlatformNames).map(PlatformShort.builtinName))
        return PlatformNaming.order.filter { owned.contains($0) }
    }

    private var others: [String] {
        let mineSet = Set(mine)
        return PlatformNaming.order.filter { !mineSet.contains($0) }
    }
}
