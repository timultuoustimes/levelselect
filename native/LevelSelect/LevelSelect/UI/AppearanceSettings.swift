import SwiftUI
import SwiftData

/// Theming controls (Tim's layered plan): global accent, per-status colors,
/// and the game-page backdrop choice. Stored in a synced SwiftData record so
/// choices follow the iCloud account across devices.
struct AppearanceSettingsSection: View {
    /// Which half to render.
    ///
    /// The two halves belong to different GROUPS in Settings, not just
    /// different sections: theming is about the app, while tracker layout and
    /// badges are about your games. They still share this view's state and
    /// helpers, so the split is a parameter rather than a second type.
    /// **Three groups, not two.** They were split by whether a setting was
    /// about color or about content — a real distinction, and not one anybody
    /// has in mind when they want to change how a game page works. Tim:
    /// *"Things are oddly split here."*
    ///
    /// Trackers keep a group of their own at his call: *"it's not about the
    /// game page as a whole, it's a very specifically scoped item within a
    /// game page."*
    ///
    /// **Four now.** Personalization split again when Settings became an
    /// index: a page per destination, and statuses earned one of their own —
    /// they were six color rows and ten name fields folded into two
    /// disclosure groups inside a section about something else. Tim, on the
    /// same question: *"its own page."*
    enum Scope { case theme, statuses, gamePages, trackers }
    var scope: Scope = .theme

    @Environment(\.modelContext) private var context
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]
    /// Device-local, not synced: it's a display preference, like stats order.
    @AppStorage("levelselect.showRAArt") private var showRAArt = true

    /// Star-name editing buffer. Always exactly five entries so the fields can
    /// index it directly; loaded when the group opens, written back when it
    /// closes or a field is submitted.
    @State private var starDrafts = Array(repeating: "", count: 5)
    @State private var starNamesExpanded = false
    /// Status-name editing buffer, keyed by raw value. Same shape as the star
    /// drafts and for the same reason: edit freely, write once on close.
    @State private var statusDrafts: [String: String] = [:]
    @State private var statusNamesExpanded = false
    @State private var arrangingPages = false
    /// Pending debounced write for the color pickers. See `scheduleSave`.
    @State private var themeCommit: Task<Void, Never>?
    // Same keys the game page reads — this sheet is the one editor for them.
    @AppStorage("gameSectionOrder") private var sectionOrderRaw = ""
    @AppStorage("gameHiddenSections") private var hiddenSectionsRaw = ""

    private var settings: ThemeSettings? { themeSettings.first }

    var body: some View {
        // TWO sections, not one.
        //
        // "Appearance" was doing three jobs at once: personal theming, tracker
        // layout, and third-party content toggles. Someone looking for colors
        // has no reason to expect "do tracker descriptions appear" to live
        // beside them — and the theming half is the part the notebook
        // direction expects to keep growing, so it needs room of its own.
        // Split per the 2026-08-28 settings audit.
        Group {
            switch scope {
            case .theme:
                theme
                    .onDisappear { flushThemeCommit() }
            case .statuses:
                statuses
                    .onDisappear { flushThemeCommit() }
            case .gamePages:
                gamePages
            case .trackers:
                trackers
            }
        }
        // **Rebuilt when the theme changes, because `.tint` is baked.**
        //
        // Fable 2.3: change the accent in Colors, tap Done, and the two menu
        // pickers on this page kept the OLD one — orange while everything
        // else had gone purple — until Settings was closed and reopened.
        // `LSTheme.accent` is a static, not observed state, so a `.tint` on a
        // Picker is fixed at the moment the row is constructed; the toggles
        // looked right only because they resolve their tint later.
        //
        // The tab tree is re-keyed on `themeRevision` when Settings CLOSES
        // (see RootView), which is exactly too late for a sheet that is still
        // open. Keying on the record's own `updatedAt` rebuilds these rows the
        // moment the color editor writes, and costs nothing the rest of the
        // time — the value only moves when a theme setting actually changes.
        .id(themeSettings.first?.updatedAt)
    }

    private var theme: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance")
                Picker("Appearance", selection: Binding(
                    get: { LSAppearance(raw: settings?.appearanceRaw) },
                    set: { pick in
                        let s = ensureSettings()
                        s.appearanceRaw = pick.rawValue
                        save(s)
                    })) {
                    ForEach(LSAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 2)

            // One row, because they are one decision. An accent is chosen
            // against a ground and a ground against an accent; two sheets
            // turned a comparison into a memory test.
            colorRow("Colors", swatch: LSTheme.accent,
                     isCustom: anyAccentChosen || anyBackgroundChosen) {
                ColorEditor(title: "Colors", targets: themeColorTargets)
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
            }
            .onChange(of: starNamesExpanded) { _, open in
                if open { loadStarDrafts() } else { commitStarNames() }
            }

            // Collapsed, and only present when something can actually be
            // undone. Three loose red rows interleaved with the controls they
            // undid put the section straight back to the clutter the settings
            // audit was about — a destructive action shouting between two
            // ordinary ones. Folded away, they're still one tap from where
            // they apply, and invisible on a library nobody has themed.
            if colorsAreCustomised || backgroundIsCustomised || settings?.starNamesData != nil {
                DisclosureGroup("Reset") {
                    // Still here, and still useful — one tap to undo a whole
                    // theme. Each color now also resets on its own from
                    // inside its own editor, which is where you are when you
                    // decide you preferred the default.
                    if colorsAreCustomised {
                        Button("Reset all colors", role: .destructive) {
                            let s = ensureSettings()
                            s.accentHex = nil
                            s.accentHexLight = nil
                            s.accentHexDark = nil
                            s.statusColorsData = nil
                            save(s)
                        }
                    }
                    if backgroundIsCustomised {
                        // Named for everything it clears. It always claimed
                        // "background" and reset only the art settings.
                        Button("Reset background color and art", role: .destructive) {
                            let s = ensureSettings()
                            s.pageBackgroundRaw = ThemePageBackground.cover.rawValue
                            s.backdropIntensityRaw = nil
                            s.backgroundHex = nil
                            s.backgroundHexLight = nil
                            s.backgroundHexDark = nil
                            save(s)
                        }
                    }
                    if settings?.starNamesData != nil {
                        Button("Reset rating labels", role: .destructive) {
                            let s = ensureSettings()
                            s.starNamesData = nil
                            starDrafts = Array(repeating: "", count: 5)
                            save(s)
                        }
                    }
                }
            }

        } footer: {
            // No header any more: the page it sits on is the header now.
            //
            // The stars get a sentence because they are the one thing on the
            // page that does NOT follow the accent, and an unexplained
            // exception reads as an oversight. Tim: *"gold"* — the same
            // answer as the wordmark's orange, and for the same reason.
            Text("Everything here syncs to your other devices through iCloud. A blank rating label keeps the built-in word. The stars themselves are always gold, whatever your accent — like the wordmark's orange.")
        }
    }

    /// Statuses get a page rather than two disclosure groups.
    ///
    /// Color and name are the same decision made twice — you rename
    /// "Abandoned" for the same reason you recolor it — and they were folded
    /// away in separate collapsed groups inside a section about the app's
    /// theme. On their own page the ten statuses are just a list, one row
    /// each, which is also the shape the show/hide switch will need.
    @ViewBuilder
    private var statuses: some View {
        Section {
            ForEach(GameStatus.displayOrder, id: \.self) { status in
                colorRow(status.sectionTitle, icon: status.systemImage,
                         swatch: status.color,
                         isCustom: settings?.statusColors[status.rawValue] != nil) {
                    // A single target: a status color is chosen on its
                    // own, so there is nothing to compare it against and
                    // the picker stays hidden.
                    ColorEditor(title: status.sectionTitle, targets: [
                        ColorTarget(id: status.rawValue,
                                    label: status.sectionTitle,
                                    defaultColor: ThemePalette.defaultColor(for: status),
                                    isCustomised: settings?.statusColors[status.rawValue] != nil,
                                    binding: statusBinding(status),
                                    onReset: {
                                        let s = ensureSettings()
                                        var map = s.statusColors
                                        map[status.rawValue] = nil
                                        s.statusColors = map
                                        save(s)
                                    }),
                    ])
                }
            }
        } footer: {
            Text("Tap a status to change its color. Colors and names sync through iCloud, and a blank name keeps the built-in word.")
        }

        Section {
            // The app says what each status means; this is where you disagree.
            // One person's "Abandoned" is another's "played it to bits", and
            // that is not settled by choosing a better default word.
            DisclosureGroup("Status names", isExpanded: $statusNamesExpanded) {
                ForEach(GameStatus.displayOrder, id: \.self) { status in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label {
                                Text(status.defaultTitle)
                            } icon: {
                                Image(systemName: status.systemImage)
                                    .foregroundStyle(status.color)
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            TextField(status.defaultTitle, text: Binding(
                                get: { statusDrafts[status.rawValue] ?? "" },
                                set: { statusDrafts[status.rawValue] = $0 }))
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .submitLabel(.done)
                                .onSubmit { commitStatusNames() }
                        }
                        // The blurb here as well as in the picker: renaming a
                        // status is exactly when you need to know what it was
                        // for, and it is the one screen where all ten sit
                        // together.
                        Text(status.blurb)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .onChange(of: statusNamesExpanded) { _, open in
                if open { loadStatusDrafts() } else { commitStatusNames() }
            }
        }
    }

    /// How a game page looks — the four that moved out of Personalization,
    /// plus the sections list.
    private var gamePages: some View {
        Section {
            Picker("Background", selection: pageBackgroundBinding) {
                ForEach(ThemePageBackground.allCases, id: \.rawValue) { choice in
                    Text(choice.label).tag(choice)
                }
            }

            Picker("Layout", selection: gamePageLayoutBinding) {
                ForEach(GamePageLayout.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            // "Showcase" and "Classic" name nothing on their own, so the
            // choice says what it does rather than making you try both.
            Text(gamePageLayoutBinding.wrappedValue.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .listRowSeparator(.hidden)

            Toggle("Use game logos", isOn: Binding(
                get: { ThemePalette.showGameLogos },
                set: { on in
                    let s = ensureSettings()
                    s.showGameLogos = on
                    save(s)
                }
            ))
            .tint(LSTheme.accent)

            if pageBackgroundBinding.wrappedValue.usesArtwork {
                Picker("Backdrop strength", selection: backdropIntensityBinding) {
                    ForEach(BackdropIntensity.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }

            Button {
                arrangingPages = true
            } label: {
                Label("Sections…", systemImage: "arrow.up.arrow.down")
            }
            NavigationLink {
                OwnershipChipsView()
            } label: {
                Label("Ownership chips", systemImage: "shippingbox")
            }
            // On the row, not on the Section — see the note in `trackers`.
            .sheet(isPresented: $arrangingPages) {
                GameArrangeSheet(orderRaw: $sectionOrderRaw, hiddenRaw: $hiddenSectionsRaw)
                    .lsSheet()
            }
        } footer: {
            Text("Applies to every game page. Colors and layout sync through iCloud; section order and hiding are set per device.")
        }
    }

    /// What shows up ON game and tracker surfaces — as opposed to what the app
    /// looks like. Both defaults here are overridden per game from that game's
    /// Tracker section.
    private var trackers: some View {
        Section {
            Picker("Default layout", selection: trackerDisplayBinding) {
                ForEach(TrackerDisplay.allCases, id: \.rawValue) { choice in
                    Text(choice.label).tag(choice)
                }
            }

            Toggle("Show hints", isOn: Binding(
                get: { settings?.showItemHints ?? true },
                set: { newValue in
                    let s = ensureSettings()
                    s.showItemHints = newValue
                    save(s)
                }
            ))

            Toggle("Show achievement badges", isOn: $showRAArt)

            // **A `.sheet` goes on a ROW, never on the Section.**
            //
            // A modifier on a `Section` is applied to each of its CHILDREN, so
            // one flag raised four presentations at once and they cancelled
            // each other: the sheet slid up and shut again immediately. Tim:
            // *"when I tap 'arrange game pages' it starts to slide up and then
            // closes almost immediately."* Same fix and same reasoning as
            // `DataSettingsSection`, and it has to be an UNCONDITIONAL row —
            // hang it on something that can disappear and the sheet goes too.
        } footer: {
            // States the sync rule once, and names the exception, rather than
            // leaving someone to infer storage from section membership — a
            // preference that changes on one device and not another otherwise
            // looks like broken iCloud sync.
            Text("These are library-wide defaults; a game's own Tracker section overrides them for that game. Layout and hints sync through iCloud. Achievement badges and page arrangement are set per device. With hints off, tracker rows show just their names — press and hold a row to peek at its hint and location. Badge art comes from RetroAchievements and appears only on imported sets.")
        }
    }

    /// A color row: what it is, what it is set to, and whether it has been
    /// changed from the default — the last of which is why this is not a
    /// plain `ColorPicker`. "Is this mine or the app's?" was unanswerable.
    /// A color row: what it is, what it is set to, and whether it has been
    /// changed from the default — the last of which is why this is not a
    /// plain `ColorPicker`. "Is this mine or the app's?" was unanswerable.
    ///
    /// PUSHES rather than presenting a sheet. `.sheet` attached inside a
    /// `Form` lands on a `Section`, which SwiftUI applies once per child —
    /// the row's tap then dismissed Settings instead of opening anything.
    /// Same trap as the tracker sheet in build 30.
    private func colorRow<Destination: View>(
        _ title: String, icon: String? = nil, swatch: Color, isCustom: Bool,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).frame(width: 22) }
                Text(title)
                Spacer(minLength: 8)
                if isCustom {
                    Text("Custom")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Circle()
                    .fill(swatch)
                    .frame(width: 24, height: 24)
                    .overlay { Circle().strokeBorder(LSTheme.hairline, lineWidth: 1) }
            }
        }
    }

    private var gamePageLayoutBinding: Binding<GamePageLayout> {
        Binding(
            get: { ThemePalette.gamePageLayout },
            set: { choice in
                let s = ensureSettings()
                s.gamePageLayoutRaw = choice.rawValue
                save(s)
            }
        )
    }

    /// Any accent at all, in either appearance, plus the legacy single value.
    ///
    /// Build 37 split accent and background per appearance, and these checks
    /// still asked only about the legacy fields — so choosing a light accent
    /// left "Reset" hidden and the row reading as untouched.
    private var anyAccentChosen: Bool {
        settings?.accentHex != nil
            || settings?.accentHexLight != nil
            || settings?.accentHexDark != nil
    }

    private var anyBackgroundChosen: Bool {
        settings?.backgroundHex != nil
            || settings?.backgroundHexLight != nil
            || settings?.backgroundHexDark != nil
    }

    private var colorsAreCustomised: Bool {
        anyAccentChosen || settings?.statusColorsData != nil
    }

    /// `backdropIntensityRaw` counts even though the strength picker is hidden
    /// unless the background uses artwork — a stored value the UI isn't
    /// currently showing is exactly the kind that gets stranded.
    private var backgroundIsCustomised: Bool {
        (settings?.pageBackgroundRaw ?? ThemePageBackground.cover.rawValue)
            != ThemePageBackground.cover.rawValue
            || settings?.backdropIntensityRaw != nil
            // The ground tint counts. It did not, and "Reset background" left
            // it in place — a chosen ground survived every reset the UI
            // offered, with no way back to the default short of matching the
            // original purple by eye. Found in the build 37 UX assessment,
            // whose entire walkthrough ran on a gray ground because of it.
            || anyBackgroundChosen
    }

    // MARK: Bindings

    /// One binding per appearance, for both the accent and the ground.
    ///
    /// Build 37: a single accent could not serve both grounds — torch is
    /// 8.74:1 on dark and 1.90:1 on light — so the palette became a pair the
    /// user chooses, rather than one value the app second-guesses at render
    /// time. `accentHex(dark:)` reads whichever belongs to the appearance on
    /// screen; the legacy `accentHex` is still read as the dark value so
    /// existing libraries keep the color they had.
    private func accentBinding(dark: Bool) -> Binding<Color> {
        Binding(
            get: {
                settings?.accentHex(dark: dark).flatMap { Color(hex: $0) }
                    ?? (dark ? LSTheme.torch : LSTheme.torchInk)
            },
            set: { color in
                let s = ensureSettings()
                if dark { s.accentHexDark = color.hexString() }
                else { s.accentHexLight = color.hexString() }
                scheduleSave(s)
            }
        )
    }

    private func backgroundBinding(dark: Bool) -> Binding<Color> {
        Binding(
            get: {
                // Unset means the built-in ground for THIS appearance, not a
                // fixed purple — the preview renders the accent on whatever
                // this returns, so a light accent was being shown against a
                // dark purple and the contrast it implied was fiction.
                settings?.backgroundHex(dark: dark).flatMap { Color(hex: $0) }
                    ?? ThemePalette.groundBase(dark: dark)
            },
            set: { color in
                let s = ensureSettings()
                if dark { s.backgroundHexDark = color.hexString() }
                else { s.backgroundHexLight = color.hexString() }
                scheduleSave(s)
            }
        )
    }

    /// Accent and background, editable side by side. Order is the order they
    /// appear in the picker, and accent leads because it is the one people
    /// come here to change.
    private var themeColorTargets: [ColorTarget] {
        func accent(_ dark: Bool) -> ColorTarget {
            let word = dark ? "Dark" : "Light"
            return ColorTarget(
                id: "accent-\(word.lowercased())",
                label: dark ? "☾ Accent" : "☀ Accent",
                defaultColor: dark ? LSTheme.torch : LSTheme.torchInk,
                isCustomised: (dark ? settings?.accentHexDark : settings?.accentHexLight) != nil,
                binding: accentBinding(dark: dark),
                onReset: {
                    let s = ensureSettings()
                    if dark { s.accentHexDark = nil } else { s.accentHexLight = nil }
                    save(s)
                },
                // Judged against the ground it will actually be read on.
                contrastGround: ThemePalette.groundBase(dark: dark),
                appearanceLabel: word.lowercased())
        }
        func background(_ dark: Bool) -> ColorTarget {
            let word = dark ? "Dark" : "Light"
            return ColorTarget(
                id: "background-\(word.lowercased())",
                label: dark ? "☾ Ground" : "☀ Ground",
                defaultColor: LSTheme.purpleDeep,
                isCustomised: (dark ? settings?.backgroundHexDark : settings?.backgroundHexLight) != nil,
                binding: backgroundBinding(dark: dark),
                onReset: {
                    let s = ensureSettings()
                    if dark { s.backgroundHexDark = nil } else { s.backgroundHexLight = nil }
                    save(s)
                })
        }
        // Accent first, because it is what people come here to change, and the
        // two appearances adjacent so a pair can be judged together.
        return [accent(false), accent(true), background(false), background(true)]
    }

    /// The ground's tint. Only its hue and saturation are used — the theme
    /// keeps the luminance, so no pick can make text unreadable. See
    /// `LSTheme.ground(tintedBy:)`.
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
                scheduleSave(s)
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

    private func loadStatusDrafts() {
        statusDrafts = settings?.statusNames ?? [:]
    }

    /// Buffer → stored names, once, and only on a real change. A blank field
    /// means "use the built-in", so it is removed rather than stored empty.
    private func commitStatusNames() {
        var trimmed: [String: String] = [:]
        for (key, value) in statusDrafts {
            let clean = value.trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { trimmed[key] = clean }
        }
        guard trimmed != (settings?.statusNames ?? [:]) else { return }
        let s = ensureSettings()
        s.statusNames = trimmed
        save(s)
    }

    private func ensureSettings() -> ThemeSettings {
        ThemePalette.fetchOrCreate(in: context)
    }

    /// A color picker reports EVERY value as you drag through the spectrum,
    /// and `save` commits the context and re-runs `ThemePalette.refresh` —
    /// which writes observable statics the whole app watches. Doing that from
    /// inside a binding setter re-rendered this sheet's ancestors mid-gesture,
    /// so the sheet closed on the first touch and a color could never be
    /// adjusted, only stabbed at.
    ///
    /// Same disease as the rating-label fields, same cure: keep the cheap
    /// in-memory write immediate so the picker stays coherent under your
    /// finger, and commit at a boundary. The boundary for a continuous control
    /// is "you stopped moving it".
    private func scheduleSave(_ s: ThemeSettings) {
        s.updatedAt = .now
        themeCommit?.cancel()
        themeCommit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            PersistenceMonitor.shared.commit(context)
            ThemePalette.refresh(from: s)
        }
    }

    /// Closing the sheet mid-debounce must not lose the color.
    private func flushThemeCommit() {
        guard themeCommit != nil else { return }
        themeCommit?.cancel()
        themeCommit = nil
        guard let s = settings else { return }
        PersistenceMonitor.shared.commit(context)
        ThemePalette.refresh(from: s)
    }

    private func save(_ s: ThemeSettings) {
        s.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
        ThemePalette.refresh(from: s)
    }
}
