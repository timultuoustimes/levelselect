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

            Toggle("Show RetroAchievements art", isOn: $showRAArt)

            DisclosureGroup("Status colors") {
                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    ColorPicker(selection: statusBinding(status), supportsOpacity: false) {
                        Label(status.sectionTitle, systemImage: status.systemImage)
                    }
                }
            }

            Button("Reset to defaults", role: .destructive) {
                let s = ensureSettings()
                s.accentHex = nil
                s.statusColorsData = nil
                s.pageBackgroundRaw = ThemePageBackground.cover.rawValue
                save(s)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Colors sync to your other devices via iCloud. Achievement art comes from RetroAchievements and is shown only on imported sets.")
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

    private func ensureSettings() -> ThemeSettings {
        ThemePalette.fetchOrCreate(in: context)
    }

    private func save(_ s: ThemeSettings) {
        s.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
        ThemePalette.refresh(from: s)
    }
}
