import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @Query(filter: #Predicate<Game> { $0.deletedAt == nil }) private var games: [Game]
    @Query private var profiles: [PlayerProfile]

    @State private var editingProfile = false

    // Tim's one-time migration from the web app. Debug builds only — the
    // bundled export is personal data and the actions are a developer tool,
    // so neither ships in a Release build. See project.yml.
    #if LEGACY_IMPORT
    @Query private var receipts: [MigrationReceipt]

    @State private var importing = false
    @State private var result: ImportReport?
    @State private var errorMessage: String?
    @State private var progressSynced: Int?

    // The canonical legacy device this bundled export came from.
    private let sourceDeviceID = "7f86df1b-a815-4798-a9d5-00974419eec3"

    /// Result text from the CloudKit schema seeder/purge and demo library.
    @State private var seedResult: String?
    @State private var seedingDemo = false
    @State private var library = LibrarySwitcher.shared
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Live type rather than the baked lockup PNG: stays crisp
                    // at any size and follows the user's accent color.
                    //
                    // Pinned to one line and dropped entirely at accessibility
                    // sizes: unconstrained, it wrapped mid-word — "LevelSe /
                    // lect" across two oversized lines, which is a broken
                    // logo rather than a large one. A decorative banner is
                    // also the first thing that should give up its space when
                    // every control below it needs more.
                    if !typeSize.isAccessibilitySize {
                        Wordmark(size: 22, showsIcon: true)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                // The only way in. `ProfileHeader` on Home deliberately draws
                // nothing until there is something to draw — which, on its
                // own, made the profile unreachable: no header meant no way
                // to open the editor, so an empty profile could never stop
                // being empty. This row is always here, the way the account
                // card is always at the top of iOS Settings.
                Section {
                    Button { editingProfile = true } label: {
                        HStack(spacing: 12) {
                            profileAvatar
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profileTitle)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(profileSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                // Two groups, because these settings answer two different
                // questions and were interleaved.
                //
                // Tim asked whether each tab should get its own settings
                // button. The answer was no — Library's Sort & View menu
                // already IS its per-tab settings, one tap from what it
                // affects — but the observation underneath was right: things
                // about YOUR GAMES (tracker layout, critic scores, achievement
                // badges) were sitting among things about THE APP (accent
                // colour, iCloud, this device) with nothing marking the
                // difference. Grouping them costs no new surface.
                SettingsGroupHeader(
                    "Your library",
                    "How your games are shown, and where their information comes from.")

                Section {
                    LabeledContent("Games", value: "\(games.count)")
                }

                AppearanceSettingsSection(scope: .gamePages)

                CriticScoreSettings()

                RetroAchievementsSettings()

                DataSettingsSection()

                SettingsGroupHeader(
                    "This app",
                    "How LevelSelect looks and syncs, across your devices.")

                AppearanceSettingsSection(scope: .personalization)

                SyncStatusSection()

                #if LEGACY_IMPORT
                Section {
                    if let r = result {
                        importSummary(r)
                    }
                    if importing {
                        HStack { ProgressView(); Text("Importing…") }
                    }
                    Button {
                        runImport()
                    } label: {
                        Label(receipts.isEmpty ? "Import from LevelSelect web" : "Re-run import",
                              systemImage: "square.and.arrow.down")
                    }
                    .disabled(importing)

                    if !receipts.isEmpty && result == nil {
                        Text("Already imported — re-running is a no-op (idempotent).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = errorMessage {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Import legacy library")
                } footer: {
                    Text("Brings your existing library in from the web app's data. Safe to tap more than once. Syncs to your other devices via iCloud.")
                }

                Section {
                    if let n = progressSynced {
                        Label("Synced \(n) tracker items", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        syncProgress()
                    } label: {
                        Label("Sync tracker progress", systemImage: "checklist")
                    }
                } footer: {
                    Text("Backfills checked-off tracker items from the web app's data into an already-imported library. Safe to repeat.")
                }

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
                #endif

                AboutSection()
            }
            // macOS renders a bare `Form` in its old left-label style: labels
            // in a right-aligned gutter, controls crammed into what's left,
            // and every footer truncated to one line with an ellipsis. It is
            // why the Developer section at the bottom of this screen was
            // unreachable — the content did not fit and had nowhere to go.
            //
            // `.grouped` is the same style the iPhone gets: full-width rows,
            // footers that wrap, sections that read as sections.
            #if os(macOS)
            .formStyle(.grouped)
            // The app's own ground, not the system's gray. A sheet that keeps
            // the platform default reads as a different app bolted on — most
            // obvious on the Mac, where the window behind it is the purple
            // gradient and the sheet was flat gray.
            .scrollContentBackground(.hidden)
            .background(LSTheme.background)
            #endif
            .navigationTitle("Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // The bump lives on the PRESENTER's `onDismiss` now, not here.
            //
            // `.onDisappear` fires whenever this view leaves the screen — and
            // pushing a color editor onto this stack does exactly that. The
            // tab tree is keyed off `themeRevision`, so the push bumped it,
            // re-keyed the tree, destroyed the TabView and took the Settings
            // sheet with it: tapping a color row closed Settings instead of
            // opening anything. Same failure as the build-32 color picker,
            // reached by a different route. See RootView's `.sheet(onDismiss:)`.
            .sheet(isPresented: $editingProfile) { ProfileEditor() }
        }
        // A sheet with no size on macOS gets whatever the system guesses,
        // which was too short for a screen with eight sections — the last of
        // them could not be scrolled to at all. Sized to fit the longest
        // section, and resizable past it.
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 560, idealHeight: 780)
        #endif
    }

    private var profile: PlayerProfile? { profiles.first }

    private var profileTitle: String {
        let name = profile?.displayName ?? ""
        return name.isEmpty ? "Your profile" : name
    }

    /// Says what the row will DO, and for a filled-in profile says what is
    /// already in it — so the row is never a mystery in either state.
    private var profileSubtitle: String {
        guard let profile else { return "Add your name, picture and handles" }
        // Only ever offers what is actually still missing. Saying "add your
        // name" under someone's name is the row telling them it didn't work.
        let handles = profile.groupedHandles.count
        if handles > 0 { return handles == 1 ? "1 handle" : "\(handles) handles" }
        var missing: [String] = []
        if (profile.displayName ?? "").isEmpty { missing.append("name") }
        if profile.avatarData == nil { missing.append("picture") }
        missing.append("handles")
        return "Add your " + ListFormatter.localizedString(byJoining: missing)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let data = profile?.avatarData {
            LocalArtworkThumb(data: data, contentMode: .fit)
                .frame(width: 34, height: 34)
        } else if let initial = profile?.displayName?
            .trimmingCharacters(in: .whitespaces).first {
            Text(String(initial).uppercased())
                .font(.headline)
                .foregroundStyle(LSTheme.accent)
                .frame(width: 34, height: 34)
                .background(LSTheme.accent.opacity(0.16), in: .circle)
        } else {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
        }
    }

    #if LEGACY_IMPORT
    private func importSummary(_ r: ImportReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if r.alreadyImported {
                Label("Already imported — nothing to do.", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Imported \(r.games) games", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(r.playthroughs) playthroughs · \(r.sessions) sessions · \(r.completionEvents) completions · \(r.trackerSchemas) trackers · \(r.maps) maps")
                    .font(.caption).foregroundStyle(.secondary)
                if !r.skipped.isEmpty {
                    Text("Skipped \(r.skipped.count)").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .font(.subheadline)
    }

    private func syncProgress() {
        errorMessage = nil
        guard let url = Bundle.main.url(forResource: "legacy-import", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "Bundled export not found."
            return
        }
        do {
            progressSynced = try LegacyImporter(context).syncTrackerProgress(data: data)
            try context.save()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func runImport() {
        importing = true
        errorMessage = nil
        result = nil
        defer { importing = false }
        guard let url = Bundle.main.url(forResource: "legacy-import", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            errorMessage = "Bundled export not found."
            return
        }
        do {
            let report = try LegacyImporter(context).import(
                data: data,
                sourceDeviceID: sourceDeviceID,
                appVersion: "0.1.0"
            )
            try context.save()
            result = report
        } catch {
            errorMessage = String(describing: error)
        }
    }
    #endif
}


/// The boundary between Settings' two groups.
///
/// A plain row rather than a `Section` header: real headers already label the
/// sections inside each group ("Personalization", "Game pages & trackers"),
/// and nesting a header inside a header reads as a mistake. This is the
/// heading those headers sit under.
struct SettingsGroupHeader: View {
    let title: String
    let subtitle: String

    init(_ title: String, _ subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // No `listRowInsets` override and no `fixedSize`.
        //
        // Overriding the insets takes over ALL of them, and a 4pt leading
        // inset put the text hard against the row's clip bounds: every
        // WRAPPED line lost a sliver of its first glyph, which read as a
        // stray vertical tick before the "H" of "How" and the "c" of "comes".
        // The default row insets already align this with the cards below it.
        .padding(.top, 16)
        .padding(.bottom, 2)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
    }
}
