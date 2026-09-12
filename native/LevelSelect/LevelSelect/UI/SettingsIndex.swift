import SwiftUI
import SwiftData

/// The pieces Settings is built from once it became an index rather than a
/// scroll.
///
/// Settings was one `Form` holding eighteen groups and about forty-five
/// controls, and the first screen of it was a wordmark, a profile row and an
/// iCloud status. Everything else was below the fold with no map. Tim, after
/// looking at Gamery's: *"it's much tighter and not a giant scroll to start."*
///
/// Nothing was deleted and nothing moved more than one tap further away. The
/// sections themselves are the same views they always were — they just live on
/// a page each now instead of end to end.

// MARK: - A page

/// One destination: an optional hero, then whatever sections it holds.
///
/// The hero is the idea worth stealing from Gamery. We already write a long
/// explanatory footer for nearly every group; a footer is read *after* someone
/// has found a row, so it can never repair a wrong guess. The same sentence at
/// the top of a page arrives before the decision instead of after it.
struct SettingsPage<Content: View>: View {
    let title: String
    var icon: String?
    var blurb: String?
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            if let icon, let blurb {
                SettingsHero(title: title, icon: icon, blurb: blurb)
            }
            content
        }
        #if !os(macOS)
        .listSectionSpacing(.compact)
        #endif
        // Same reasons as the root sheet: macOS renders a bare Form in its old
        // left-label style, and a sheet that keeps the platform gray reads as
        // a different app bolted on.
        #if os(macOS)
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(LSTheme.background)
        #endif
        .navigationTitle(title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The card at the top of a destination: what this page is, in one sentence.
struct SettingsHero: View {
    let title: String
    let icon: String
    let blurb: String

    /// Grows with the type rather than being overrun by it — the same fix the
    /// profile avatar needed.
    @ScaledMetric(relativeTo: .title2) private var box: CGFloat = 46

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(LSTheme.accent)
                    .frame(width: box, height: box)
                    .background(LSTheme.accent.opacity(0.16),
                                in: .rect(cornerRadius: box * 0.26))
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - A row on the index

/// A row that goes somewhere, with the answer already on it.
///
/// The `value` is the other half of what makes an index better than a scroll:
/// "Synced", "183 games", "2 connected". Most visits to Settings are to check
/// one of those, and now none of them costs a tap.
struct SettingsRow<Destination: View>: View {
    let title: String
    let icon: String
    var value: String?
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            LabeledContent {
                if let value {
                    Text(value)
                }
            } label: {
                Label(title, systemImage: icon)
            }
        }
    }
}

// MARK: - Destinations

struct ICloudSettingsPage: View {
    var body: some View {
        SettingsPage(title: "iCloud",
                     icon: "checkmark.icloud",
                     blurb: "Your library lives in your own private iCloud database. There's no account here and nobody else can read it.") {
            SyncStatusSection()
        }
    }
}

struct LibrarySettingsPage: View {
    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]

    var body: some View {
        SettingsPage(title: "Library",
                     icon: "books.vertical",
                     blurb: "Everything about the games themselves — filling in what's missing, tidying tags, and getting things back.") {
            Section {
                LabeledContent("Games", value: Format.gameCount(games.count))
            }
            DataSettingsSection(scope: .tools)
        }
    }
}

struct TransferSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Import & Export",
                     icon: "arrow.up.arrow.down.circle",
                     blurb: "iCloud keeps your devices in step. This is how you get a copy you hold yourself.") {
            DataSettingsSection(scope: .transfer)
        }
    }
}

struct ServicesSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Services",
                     icon: "link",
                     blurb: "Bring in games and achievements you already have somewhere else. Keys stay in this device's Keychain and go to the service directly — never through a server of ours.") {
            RetroAchievementsSettings()
            ItchSettings()
        }
    }
}

struct NotificationSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Notifications",
                     icon: "bell.badge",
                     blurb: "A game you are waiting for is the one thing the app knows about before you do.") {
            ReleaseRemindersSettings()
        }
    }
}

struct ThemeSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Theme & colors",
                     icon: "circle.lefthalf.filled",
                     blurb: "Light or dark, the accent and ground you chose, and what your stars are called.") {
            AppearanceSettingsSection(scope: .theme)
        }
    }
}

struct StatusSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Statuses",
                     icon: "circle.grid.2x1.left.filled",
                     blurb: "The ten words the app uses for where a game stands with you — in your colors, and your words if you disagree with mine.") {
            AppearanceSettingsSection(scope: .statuses)
        }
    }
}

struct GamePagesSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Game pages",
                     icon: "rectangle.topthird.inset.filled",
                     blurb: "How every game's page is laid out, and which sections it opens with.") {
            AppearanceSettingsSection(scope: .gamePages)
            CriticScoreSettings()
        }
    }
}

struct TrackerSettingsPage: View {
    var body: some View {
        SettingsPage(title: "Trackers",
                     icon: "checklist",
                     blurb: "Library-wide defaults for every tracker. A game's own Tracker section overrides them for that game.") {
            AppearanceSettingsSection(scope: .trackers)
        }
    }
}

/// A row that leaves the app, and looks like it.
///
/// The old footer said "Opens levelselect.app in your browser" under three
/// rows that looked exactly like the ones that didn't. The glyph says it on
/// each row instead, which is where the guess is made.
struct ExternalSettingsRow: View {
    let title: String
    let icon: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            LabeledContent {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            } label: {
                Label(title, systemImage: icon)
            }
        }
    }
}

#if DEV_TOOLS
/// Debug-only tools, on a page of their own.
///
/// These were two full sections at the bottom of the root — the CloudKit
/// seeder with its capitalised warning, and the demo-library switcher with a
/// four-line footer — which is a lot of scroll to put between a tester and
/// anything they actually came for. None of it ships in a Release build; see
/// project.yml.
struct DeveloperSettingsPage: View {
    @Environment(\.modelContext) private var context

    /// Result text from the CloudKit schema seeder/purge and demo library.
    @State private var seedResult: String?
    @State private var seedingDemo = false
    @State private var library = LibrarySwitcher.shared

    var body: some View {
        SettingsPage(title: "Developer",
                     icon: "hammer",
                     blurb: "Debug builds only. Seeding writes to whichever CloudKit container this build is signed for — check before you tap.") {
        Section {
            Button {
                seedResult = CloudKitSchemaSeeder.seed(context: context)
            } label: {
                Label("Seed CloudKit schema", systemImage: "cloud.bolt")
            }
            Button(role: .destructive) {
                seedResult = CloudKitSchemaSeeder.purge(context: context)
            } label: {
                Label("Purge seed records", systemImage: "trash")
            }
            if let seedResult {
                Text(seedResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Developer — CloudKit schema")
        } footer: {
            Text("Writes one hidden, fully-populated record of every model so the Development schema gains every field. Seed → wait for Synced → Deploy Schema Changes to Production in CloudKit Console → Purge.")
        }

        Section {
            Toggle(isOn: Binding(
                get: { library.isDemo },
                set: { library.setDemo($0) }
            )) {
                Label("Use demo library", systemImage: "theatermasks")
            }

            if library.isDemo {
                Button {
                    seedingDemo = true
                    Task {
                        seedResult = await DemoLibrarySeeder.seed(context: context)
                        seedingDemo = false
                        // Push the demo library out to the widgets so
                        // Home Screen shots match what's on screen.
                        WidgetBridge.refresh()
                    }
                } label: {
                    if seedingDemo {
                        HStack { ProgressView(); Text("Building demo library…") }
                    } else {
                        Label("Load demo games", systemImage: "sparkles")
                    }
                }
                .disabled(seedingDemo)
                Button(role: .destructive) {
                    seedResult = DemoLibrarySeeder.purge(context: context)
                    // Widgets read a snapshot, not the store, so they
                    // need telling — otherwise the Home Screen keeps
                    // showing games the library no longer has.
                    WidgetBridge.refresh()
                } label: {
                    Label("Empty demo library", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    library.destroyDemoStore()
                    seedResult = "Demo library file deleted."
                } label: {
                    Label("Delete demo library file", systemImage: "trash.slash")
                }
            }
        } header: {
            Text("Developer — screenshots")
        } footer: {
            Text(library.isDemo
                 ? "You're in the demo library. Your real library is untouched in its own file — switch back any time. Demo data is local only and never syncs to iCloud."
                 : "Switches to a separate, disposable library for screenshots and video. Your real library isn't hidden or filtered — it's a different file, left exactly as it is. 14 well-known games with real IGDB art, play history, a populated tracker, a run record, and a collection. Deterministic, so retakes look identical.")
        }
        }
    }
}
#endif
