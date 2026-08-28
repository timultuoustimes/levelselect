import SwiftUI
import SwiftData

/// Theming controls (Tim's layered plan): global accent, per-status colors,
/// and the game-page backdrop choice. Stored in a synced SwiftData record so
/// choices follow the iCloud account across devices.
struct AppearanceSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Query private var themeSettings: [ThemeSettings]
    /// Device-local, not synced: it's a display preference, like stats order.
    @AppStorage("levelselect.showRAArt") private var showRAArt = true

    /// Star-name editing buffer. Always exactly five entries so the fields can
    /// index it directly; loaded when the group opens, written back when it
    /// closes or a field is submitted.
    @State private var starDrafts = Array(repeating: "", count: 5)
    @State private var starNamesExpanded = false
    @State private var arrangingPages = false
    // Same keys the game page reads — this sheet is the one editor for them.
    @AppStorage("gameSectionOrder") private var sectionOrderRaw = ""
    @AppStorage("gameHiddenSections") private var hiddenSectionsRaw = ""

    private var settings: ThemeSettings? { themeSettings.first }

    var body: some View {
        // TWO sections, not one.
        //
        // "Appearance" was doing three jobs at once: personal theming, tracker
        // layout, and third-party content toggles. Someone looking for colours
        // has no reason to expect "do tracker descriptions appear" to live
        // beside them — and the theming half is the part the notebook
        // direction expects to keep growing, so it needs room of its own.
        // Split per the 2026-08-28 settings audit.
        personalization
        gamePagesAndTrackers
            .sheet(isPresented: $arrangingPages) {
                GameArrangeSheet(orderRaw: $sectionOrderRaw, hiddenRaw: $hiddenSectionsRaw)
            }
    }

    private var personalization: some View {
        Section {
            ColorPicker("Accent color", selection: accentBinding, supportsOpacity: false)

            Picker("Game page background", selection: pageBackgroundBinding) {
                ForEach(ThemePageBackground.allCases, id: \.rawValue) { choice in
                    Text(choice.label).tag(choice)
                }
            }

            if pageBackgroundBinding.wrappedValue.usesArtwork {
                Picker("Backdrop strength", selection: backdropIntensityBinding) {
                    ForEach(BackdropIntensity.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }

            // Each family resets on its own now. One "Reset colors, background
            // & rating labels" button meant that fixing a backdrop you'd
            // wandered too far from also threw away five rating labels you'd
            // written by hand — and the labels are authored personal content,
            // not a setting. The old button also silently skipped backdrop
            // strength, so "reset background" didn't.
            //
            // Each appears only when there is something to undo. Three
            // permanent red buttons that mostly do nothing are their own kind
            // of noise.
            if backgroundIsCustomised {
                Button("Reset background", role: .destructive) {
                    let s = ensureSettings()
                    s.pageBackgroundRaw = ThemePageBackground.cover.rawValue
                    s.backdropIntensityRaw = nil
                    save(s)
                }
            }

            DisclosureGroup("Status colors") {
                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    ColorPicker(selection: statusBinding(status), supportsOpacity: false) {
                        Label(status.sectionTitle, systemImage: status.systemImage)
                    }
                }
            }

            if colorsAreCustomised {
                Button("Reset colors", role: .destructive) {
                    let s = ensureSettings()
                    s.accentHex = nil
                    s.statusColorsData = nil
                    save(s)
                }
            }

            // Typing edits LOCAL state and commits at a boundary (submit, or
            // closing the group), never per keystroke. A binding that wrote
            // straight through committed the context on every character —
            // which republished the @Query, re-ran ThemePalette.refresh from
            // inside a binding setter, and trimmed whitespace mid-word so a
            // space could never be typed. Same rule the game page follows for
            // its notes and review fields.
            DisclosureGroup("Rating labels", isExpanded: $starNamesExpanded) {
                ForEach(1...5, id: \.self) { star in
                    HStack {
                        Text("\(star)★")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                        TextField(RatingControl.labels[star - 1], text: $starDrafts[star - 1])
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { commitStarNames() }
                    }
                }
                // Inside the group, because these are five things you wrote
                // and this is the only thing that unwrites them.
                if settings?.starNamesData != nil {
                    Button("Reset rating labels", role: .destructive) {
                        let s = ensureSettings()
                        s.starNamesData = nil
                        starDrafts = Array(repeating: "", count: 5)
                        save(s)
                    }
                }
            }
            .onChange(of: starNamesExpanded) { _, open in
                if open { loadStarDrafts() } else { commitStarNames() }
            }

        } header: {
            Text("Personalization")
        } footer: {
            Text("Everything here syncs to your other devices through iCloud. A blank rating label keeps the built-in word.")
        }
    }

    /// What shows up ON game and tracker surfaces — as opposed to what the app
    /// looks like. Both defaults here are overridden per game from that game's
    /// Tracker section.
    private var gamePagesAndTrackers: some View {
        Section {
            Picker("Default tracker layout", selection: trackerDisplayBinding) {
                ForEach(TrackerDisplay.allCases, id: \.rawValue) { choice in
                    Text(choice.label).tag(choice)
                }
            }

            Toggle("Show tracker hints", isOn: Binding(
                get: { settings?.showItemHints ?? true },
                set: { newValue in
                    let s = ensureSettings()
                    s.showItemHints = newValue
                    save(s)
                }
            ))

            Toggle("Show achievement badges", isOn: $showRAArt)

            // This used to open from a single game's ⋯ menu while changing
            // every game page on the device. Placement declares scope: a
            // library-wide, device-local layout preference belongs beside the
            // other library-wide defaults, not anchored to Super Metroid.
            Button {
                arrangingPages = true
            } label: {
                Label("Arrange game pages…", systemImage: "arrow.up.arrow.down")
            }
        } header: {
            Text("Game pages & trackers")
        } footer: {
            // States the sync rule once, and names the exception, rather than
            // leaving someone to infer storage from section membership — a
            // preference that changes on one device and not another otherwise
            // looks like broken iCloud sync.
            Text("These are library-wide defaults; a game's own Tracker section overrides them for that game. Layout and hints sync through iCloud. Achievement badges and page arrangement are set per device. With hints off, tracker rows show just their names — press and hold a row to peek at its hint and location. Badge art comes from RetroAchievements and appears only on imported sets.")
        }
    }

    private var colorsAreCustomised: Bool {
        settings?.accentHex != nil || settings?.statusColorsData != nil
    }

    /// `backdropIntensityRaw` counts even though the strength picker is hidden
    /// unless the background uses artwork — a stored value the UI isn't
    /// currently showing is exactly the kind that gets stranded.
    private var backgroundIsCustomised: Bool {
        (settings?.pageBackgroundRaw ?? ThemePageBackground.cover.rawValue)
            != ThemePageBackground.cover.rawValue
            || settings?.backdropIntensityRaw != nil
    }

    // MARK: Bindings

    private var accentBinding: Binding<Color> {
        Binding(
            get: { settings?.accentHex.flatMap { Color(hex: $0) } ?? LSTheme.purple },
            set: { color in
                let s = ensureSettings()
                s.accentHex = color.hexString()
                save(s)
            }
        )
    }

    private var trackerDisplayBinding: Binding<TrackerDisplay> {
        Binding(
            get: {
                settings.flatMap { TrackerDisplay(rawValue: $0.defaultTrackerDisplayRaw) } ?? .inline
            },
            set: { choice in
                let s = ensureSettings()
                s.defaultTrackerDisplayRaw = choice.rawValue
                save(s)
            }
        )
    }

    private var pageBackgroundBinding: Binding<ThemePageBackground> {
        Binding(
            get: {
                settings.flatMap { ThemePageBackground(rawValue: $0.pageBackgroundRaw) } ?? .cover
            },
            set: { choice in
                let s = ensureSettings()
                s.pageBackgroundRaw = choice.rawValue
                save(s)
            }
        )
    }

    private func statusBinding(_ status: GameStatus) -> Binding<Color> {
        Binding(
            get: {
                settings?.statusColors[status.rawValue].flatMap { Color(hex: $0) }
                    ?? ThemePalette.defaultColor(for: status)
            },
            set: { color in
                let s = ensureSettings()
                var map = s.statusColors
                map[status.rawValue] = color.hexString()
                s.statusColors = map
                save(s)
            }
        )
    }

    private var backdropIntensityBinding: Binding<BackdropIntensity> {
        Binding(
            get: {
                settings?.backdropIntensityRaw
                    .flatMap(BackdropIntensity.init(rawValue:)) ?? .standard
            },
            set: { choice in
                let s = ensureSettings()
                s.backdropIntensityRaw = choice.rawValue
                save(s)
            }
        )
    }

    /// Stored names → the five-slot buffer.
    private func loadStarDrafts() {
        let names = settings?.starNames ?? []
        starDrafts = (0..<5).map { $0 < names.count ? names[$0] : "" }
    }

    /// Buffer → stored names, once, and only when something actually changed.
    /// (The group can close for reasons other than an edit — a scroll that
    /// recycles the row, leaving the screen — and a no-op write would still
    /// stamp sync metadata on the theme record.)
    private func commitStarNames() {
        let trimmed = starDrafts.map { $0.trimmingCharacters(in: .whitespaces) }
        let stored = settings?.starNames ?? []
        let current = (0..<5).map { $0 < stored.count ? stored[$0] : "" }
        guard trimmed != current else { return }
        let s = ensureSettings()
        s.starNames = trimmed
        save(s)
    }

    private func ensureSettings() -> ThemeSettings {
        ThemePalette.fetchOrCreate(in: context)
    }

    private func save(_ s: ThemeSettings) {
        s.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
        ThemePalette.refresh(from: s)
    }
}
