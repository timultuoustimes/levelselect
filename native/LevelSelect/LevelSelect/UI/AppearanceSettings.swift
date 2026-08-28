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

    private var settings: ThemeSettings? { themeSettings.first }

    var body: some View {
        Section {
            ColorPicker("Accent color", selection: accentBinding, supportsOpacity: false)

            Picker("Tracker display", selection: trackerDisplayBinding) {
                ForEach(TrackerDisplay.allCases, id: \.rawValue) { choice in
                    Text(choice.label).tag(choice)
                }
            }

            Picker("Game page background", selection: pageBackgroundBinding) {
                ForEach(ThemePageBackground.allCases, id: \.rawValue) { choice in
                    Text(choice.label).tag(choice)
                }
            }

            if pageBackgroundBinding.wrappedValue == .cover {
                Picker("Backdrop strength", selection: backdropIntensityBinding) {
                    ForEach(BackdropIntensity.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }

            Toggle("Show RetroAchievements art", isOn: $showRAArt)

            Toggle("Show item hints", isOn: Binding(
                get: { settings?.showItemHints ?? true },
                set: { newValue in
                    let s = ensureSettings()
                    s.showItemHints = newValue
                    save(s)
                }
            ))

            DisclosureGroup("Status colors") {
                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    ColorPicker(selection: statusBinding(status), supportsOpacity: false) {
                        Label(status.sectionTitle, systemImage: status.systemImage)
                    }
                }
            }

            // Typing edits LOCAL state and commits at a boundary (submit, or
            // closing the group), never per keystroke. A binding that wrote
            // straight through committed the context on every character —
            // which republished the @Query, re-ran ThemePalette.refresh from
            // inside a binding setter, and trimmed whitespace mid-word so a
            // space could never be typed. Same rule the game page follows for
            // its notes and review fields.
            DisclosureGroup("Star names", isExpanded: $starNamesExpanded) {
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
            }
            .onChange(of: starNamesExpanded) { _, open in
                if open { loadStarDrafts() } else { commitStarNames() }
            }

            Button("Reset to defaults", role: .destructive) {
                let s = ensureSettings()
                s.accentHex = nil
                s.statusColorsData = nil
                s.pageBackgroundRaw = ThemePageBackground.cover.rawValue
                s.starNamesData = nil
                starDrafts = Array(repeating: "", count: 5)
                save(s)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Colors and star names sync to your other devices via iCloud. A blank star name keeps the built-in word. Achievement art comes from RetroAchievements and is shown only on imported sets. With hints off, tracker rows show just their names — press and hold a row to peek at its hint and location.")
        }
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
