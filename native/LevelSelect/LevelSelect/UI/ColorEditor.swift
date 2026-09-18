import SwiftUI
import SwiftData

/// One color the editor can set.
///
/// The shape survives from the build 37 editor because three callers build
/// it — the theme page (four targets: accent and ground, light and dark),
/// the status page (one target) and the profile's name color (one target,
/// drawn as the name). What changed is what sits under it.
struct ColorTarget: Identifiable {
    let id: String
    let label: String
    /// The color this reverts to. Nil when there is no default to go back to.
    let defaultColor: Color?
    /// Whether a custom value is currently stored — Reset is pointless without.
    let isCustomised: Bool
    let binding: Binding<Color>
    let onReset: () -> Void
    /// Kept for the callers that still pass it; the palette carries its own
    /// legibility now (a pair's ink is authored), so nothing is measured here.
    var contrastGround: Color? = nil
    var appearanceLabel: String? = nil
    /// Draw the preview as THIS NAME in the pixel face, rather than as the
    /// accent's buttons — the profile name is 22pt Press Start 2P with a hard
    /// step under it, a completely different specimen.
    var specimenName: String? = nil
}

/// **Seven circles, a preview, and nothing else.**
///
/// Tim, 2026-09-08, after two builds of hue planes, hex fields, saved
/// swatches and a linked-mode toggle: *"scrap the old color picker all
/// together, it should be simplified to look almost exactly like this"* — and
/// a sheet with an Accent/Background segment, the preview on both grounds,
/// and the seven pairs in a row. So that is the whole editor. A pair is an
/// authored accent with its own step; choosing one for the accent writes it
/// to both appearances, choosing one for the background makes the ground its
/// overlay on the base gray and charcoal (`LSPalette.ground`).
///
/// Everything here is a draft until Done. Cancel puts back what the sheet
/// changed, and only that.
struct ColorEditor: View {
    let title: String
    let targets: [ColorTarget]

    enum Role: String, CaseIterable, Identifiable {
        case accent, background, hero
        var id: String { rawValue }
        var label: String {
            switch self {
            case .accent: "Accent"
            case .background: "Background"
            // The Continue Playing card. Tim, 09-09: a third target beside
            // Accent and Ground.
            case .hero: "Card"
            }
        }
    }

    /// **Which appearance a tap on a circle writes to.** Nil is both, which
    /// is what it has always done and what almost everyone wants.
    ///
    /// Tim, 2026-09-09: *"can we make it so that I can pick one set of colors
    /// for light mode and another set for dark mode."* The preview already
    /// showed the two grounds side by side and already labelled them with a
    /// sun and a moon, so it becomes the control rather than the sheet
    /// growing a second segmented picker — which is exactly the build-37
    /// linked-mode toggle he had cut.
    enum Half { case light, dark }

    @State private var role: Role = .accent
    @State private var half: Half?
    @State private var originals: [String: Color] = [:]
    /// What this sheet has chosen so far, by target. The bindings write
    /// through to the model, but a write there is not a state change HERE —
    /// so without this mirror a tap changed the app behind the sheet and
    /// left the preview and the checkmark where they were.
    @State private var picked: [String: Color] = [:]
    /// Which targets already held a stored color when the sheet opened, so
    /// Cancel can tell "put the old color back" from "put it back to nothing".
    @State private var wasCustom: Set<String> = []
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var deviceScheme

    init(title: String, targets: [ColorTarget], initial: String? = nil) {
        self.title = title
        self.targets = targets
        _role = State(initialValue: initial.flatMap { id in
            Role.allCases.first { id.hasPrefix("\($0.rawValue)-") }
        } ?? .accent)
    }

    // MARK: What is being edited

    /// The theme editor carries accent and ground targets; anything else is
    /// a single color — a status, a name.
    private var isThemeEditor: Bool { targets.contains { $0.id.hasPrefix("accent-") } }
    private var offersBackground: Bool { targets.contains { $0.id.hasPrefix("background-") } }

    private func targets(for role: Role) -> [ColorTarget] {
        targets.filter { $0.id.hasPrefix("\(role.rawValue)-") }
    }

    private var roles: [Role] { Role.allCases.filter { !targets(for: $0).isEmpty } }

    /// The targets a tap on a circle writes to: the current role's, narrowed
    /// to one appearance when a half is selected.
    private var editing: [ColorTarget] {
        guard isThemeEditor else { return Array(targets.prefix(1)) }
        let both = targets(for: role)
        guard let half else { return both }
        let suffix = half == .dark ? "-dark" : "-light"
        return both.filter { $0.id.hasSuffix(suffix) }
    }

    private func value(of t: ColorTarget) -> Color { picked[t.id] ?? t.binding.wrappedValue }

    // MARK: Putting it back

    /// **Everything the default button restores: the whole look, not a half.**
    ///
    /// Accent and ground are one decision — the sheet says so by editing them
    /// side by side — and a button that put back only the segment you happened
    /// to be on left the app in a state that was neither yours nor the app's.
    /// Tim, 2026-09-09: *"I think the default button should maybe be to use
    /// the default pair, and it just resets the accent and ground colors to
    /// what the colors are when it's an empty library."*
    private var resetable: [ColorTarget] {
        isThemeEditor ? targets : Array(targets.prefix(1))
    }

    /// Whether a target already sits on the value an empty library gives it.
    ///
    /// Asked of the sheet's own mirror rather than of `isCustomised`, which is
    /// read off a `@Query` when the row is PUSHED and does not move again —
    /// so after a reset the flag still said "custom", the button stayed, and
    /// the circles still ticked the color that had just been thrown away.
    /// A target with no default has nothing to put back, so it counts as
    /// already there.
    private func isDefault(_ t: ColorTarget) -> Bool {
        guard let target = t.defaultColor?.hexString() else { return true }
        return value(of: t).hexString() == target
    }

    private var canReset: Bool { resetable.contains { !isDefault($0) } }

    /// Named for what it actually does. In the theme editor that is both
    /// colors at once; a status or a name has only itself.
    private var resetLabel: String {
        isThemeEditor ? "Use the default colors" : "Use the default"
    }

    /// The color the circles mark as chosen.
    private var current: Color? { editing.first.map(value(of:)) }

    /// **Every pair a tap would replace** — one when the two appearances
    /// agree or a half is selected, two when they have been set apart.
    ///
    /// A single `chosen` had to pick a side, and picking light while dark
    /// held something else drew a checkmark on a color half the app is not
    /// wearing. Two ticks is the honest answer to "what is set", and it is
    /// also the only thing that tells you the appearances have diverged.
    private var chosenIDs: Set<String> {
        Set(editing.compactMap { LSPalette.pair(matching: value(of: $0).hexString())?.id })
    }

    /// A stored value per appearance, read live so the preview follows every tap.
    private func stored(_ role: Role, dark: Bool) -> Color? {
        targets.first { $0.id == "\(role.rawValue)-\(dark ? "dark" : "light")" }.map(value(of:))
    }

    /// The ground binding hands back the RESOLVED ground when nothing is
    /// stored, so it cannot be fed straight back in as a tint. A pair's hex
    /// is a tint; anything else only if it was chosen; otherwise the default.
    private func previewGround(dark: Bool) -> Color {
        guard isThemeEditor else { return ThemePalette.groundBase(dark: dark) }
        let t = targets.first { $0.id == "background-\(dark ? "dark" : "light")" }
        let value = t.map(value(of:))
        let tint = LSPalette.pair(matching: value?.hexString())?.accentColor
            ?? ((t?.isCustomised == true || (t.map { picked[$0.id] != nil } ?? false)) ? value : nil)
        return LSPalette.ground(tint: tint, dark: dark)
    }

    private func previewAccent(dark: Bool) -> Color {
        if isThemeEditor { return stored(.accent, dark: dark) ?? LSTheme.torch }
        return current ?? LSTheme.torch
    }

    /// Puts back only what this sheet touched — see the note on the Cancel
    /// button for why `picked` is the thing that knows.
    private func cancel() {
        for t in targets where picked[t.id] != nil {
            if wasCustom.contains(t.id), let was = originals[t.id] {
                t.binding.wrappedValue = was
            } else {
                t.onReset()
            }
        }
        dismiss()
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if isThemeEditor, offersBackground {
                    Picker("Editing", selection: $role) {
                        ForEach(roles) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                preview

                circles

                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if canReset {
                    Button {
                        for t in resetable {
                            // The mirror is SET to the default rather than
                            // cleared. Clearing it hands the circles back to
                            // the bindings, and those read a `@Query` this
                            // sheet stopped seeing republish the moment it was
                            // pushed — so the reset changed the app behind the
                            // sheet while the sheet went on showing the old
                            // color, which reads as nothing having happened.
                            picked[t.id] = t.defaultColor
                            t.onReset()
                        }
                    } label: {
                        Label(resetLabel, systemImage: "arrow.uturn.backward")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(LSTheme.liveSheetGround)
        .navigationTitle(title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        #endif
        #if os(macOS)
        // **The Mac's Cancel and Done sit on the sheet's ground.** As toolbar
        // items the system drew them in a white footer under the editor,
        // below Settings' own purple bar. Escape is Cancel here rather than
        // "close all of Settings", and Return is Done.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Cancel") { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(LSTheme.liveSheetGround)
        }
        #else
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                // Puts the LIVE theme back — the preview writes through, so a
                // color shows on the real app behind the sheet and has to be
                // undone. **Only what this sheet touched**, and `picked` is
                // what knows that: comparing the binding against the original
                // asks a `@Query` that stopped republishing when the row was
                // pushed, and got the same answer either way.
                //
                // A target that held nothing when the sheet opened goes back
                // to nothing rather than being written with the value the
                // binding hands back for "unset" — that value is now a real
                // palette hex, and storing it would leave an untouched library
                // reading as Custom for a color it never chose.
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        #endif
        .onAppear {
            guard !loaded else { return }
            loaded = true
            for t in targets {
                originals[t.id] = t.binding.wrappedValue
                if t.isCustomised { wasCustom.insert(t.id) }
            }
        }
    }

    private var caption: String {
        if let name = targets.first?.specimenName, !isThemeEditor {
            return "How \"\(name)\" reads at the top of Home, on both grounds. The darker shade is its step."
        }
        if !isThemeEditor { return "One color for this status, everywhere it appears." }
        let noun = role == .accent ? "accent" : role == .hero ? "card" : "ground"
        if role == .hero, half == nil {
            return "The Continue Playing card's own color, lifted off the ground the way the ground is laid over gray. Until you pick one it follows the ground. Tap Light or Dark above to give each its own."
        }
        switch half {
        case .light: return "Setting the light \(noun). Tap Light again to set both at once."
        case .dark:  return "Setting the dark \(noun). Tap Dark again to set both at once."
        case nil:
            return role == .accent
                ? "On light the accent writes in its darker step; on dark it writes as itself. Tap Light or Dark above to give each its own."
                : "The ground is the color laid over the app's gray and charcoal, so nothing on it can become unreadable. Tap Light or Dark above to give each its own."
        }
    }

    // MARK: The seven

    private var circles: some View {
        HStack(spacing: 10) {
            let ticked = chosenIDs
            ForEach(LSPalette.pairs) { pair in
                let picked = ticked.contains(pair.id)
                Button {
                    choose(pair)
                } label: {
                    Circle()
                        .fill(pair.accentColor)
                        .overlay {
                            // 1.5 in Tim's sheet, at his sheet's scale — this is
                            // the same weight on a 40pt circle, so the step is
                            // visible while choosing.
                            Circle().strokeBorder(pair.stepColor, lineWidth: picked ? 4 : 2.5)
                        }
                        .overlay {
                            if picked {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(pair.stepColor)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pair.name)
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
        }
        .frame(maxHeight: 48)
    }

    private func choose(_ pair: LSPalette.Pair) {
        for t in editing {
            picked[t.id] = pair.accentColor
            t.binding.wrappedValue = pair.accentColor
        }
    }

    // MARK: Preview

    /// Both grounds, touching, so the pair is judged as one thing.
    ///
    /// **Its type is capped, and that is not an accessibility lapse.** This is
    /// a picture of the app's own controls — a specimen, the way a paint chip
    /// is a picture of a wall. At Accessibility XXXL the words inside it grew
    /// past their pills and "Sample" came apart into a column of single
    /// letters, which destroys the one thing the preview exists to show: what
    /// this color looks like as a button. The words are not the content here;
    /// the color is. Everything that IS reading — the caption under the
    /// circles, the segment, the titles — scales all the way, and VoiceOver
    /// reads the halves regardless.
    private var preview: some View {
        HStack(spacing: 0) {
            previewSide(.light)
            previewSide(.dark)
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(LSTheme.hairline, lineWidth: 1))
    }

    /// One half: the specimen, and — in the theme editor — the control that
    /// aims the circles at this appearance.
    ///
    /// Outside the theme editor a status or a name has one color for both
    /// grounds, so there is nothing to aim and the halves stay inert.
    @ViewBuilder
    private func previewSide(_ which: Half) -> some View {
        let isDark = which == .dark
        let selected = half == which
        if isThemeEditor {
            Button {
                // Tapping the selected half releases it, so "both" is always
                // one tap away from wherever you are.
                half = selected ? nil : which
            } label: {
                previewHalf(dark: isDark)
                    .overlay {
                        if selected {
                            Rectangle().strokeBorder(
                                isDark ? Color.white.opacity(0.8) : Color.black.opacity(0.5),
                                lineWidth: 3)
                        }
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(previewDescription(dark: isDark))
            .accessibilityHint(selected
                ? "Selected. Activate to set both appearances at once."
                : "Activate to set only this appearance.")
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            previewHalf(dark: isDark)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(previewDescription(dark: isDark))
        }
    }

    /// What one half shows, for anyone who cannot see it.
    private func previewDescription(dark: Bool) -> String {
        let word = dark ? "dark" : "light"
        let shown = targets.first { $0.id == "\(role.rawValue)-\(word)" }.map(value(of:))
            ?? current
        let name = LSPalette.pair(matching: shown?.hexString())?.name ?? "A custom color"
        if isThemeEditor, role == .background {
            return "\(name) as the \(word) ground."
        }
        return "\(name) as a button and a tinted pill, on the \(word) ground."
    }

    private func previewHalf(dark: Bool) -> some View {
        let ground = previewGround(dark: dark)
        let accent = previewAccent(dark: dark)
        let pair = LSPalette.pair(matching: accent.hexString())
        let step = pair?.stepColor ?? LSTheme.hardStep(under: accent)
        // The palette's rule: the step is the ink on light, the accent on dark.
        let ink = dark ? accent : step
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: dark ? "moon.fill" : "sun.max.fill")
                    .font(.caption2)
                Text(dark ? "Dark" : "Light")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(dark ? Color.white.opacity(0.55) : Color.black.opacity(0.45))

            Group {
                if let specimen = targets.first?.specimenName, !isThemeEditor {
                    // The real thing: the face, the step, the ground it lands on.
                    Text(specimen)
                        .font(LSTheme.pixel(13))
                        .fontDesign(nil)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .shadow(color: step, radius: 0, y: LSTheme.pixelStep(for: 13))
                } else if !isThemeEditor {
                    // A status: its dot and its word, the way a shelf shows it.
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 10, height: 10)
                        Text(targets.first?.label ?? "Status")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(accent.opacity(0.15), in: .capsule)
                } else if role == .hero {
                    // The card itself, in this appearance, with the accent's
                    // Play on it — the thing the color is for.
                    HStack(spacing: 8) {
                        Text("Continue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                        Spacer(minLength: 0)
                        PairButtonLabel(text: "Play", icon: "play.fill", accent: accent, step: step)
                    }
                    .padding(8)
                    .background(LinearGradient(colors: LSTheme.heroStops(tint: stored(.hero, dark: dark), dark: dark),
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.35)))
                } else {
                    HStack(spacing: 8) {
                        PairButtonLabel(text: "Play", icon: "play.fill", accent: accent, step: step)
                        // The tinted pill: the accent at half over the ground,
                        // the ink is the step on light and the accent on dark.
                        Text("Sample")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent.opacity(LSPalette.tintFillOpacity), in: .capsule)
                            .overlay(Capsule().strokeBorder(ink, lineWidth: 1.5))
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            LinearGradient(colors: [ground, ground.mix(with: .black, by: dark ? 0.45 : 0.06)],
                           startPoint: .top, endPoint: .bottom))
    }
}

/// The primary button as the palette draws it, with explicit colors so a
/// preview can show a candidate pair before it is stored. The live one is
/// `LSPrimaryButtonStyle`, which reads the theme.
struct PairButtonLabel: View {
    let text: String
    var icon: String? = nil
    let accent: Color
    let step: Color

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.caption) }
            Text(text).font(.caption.weight(.bold))
        }
        .foregroundStyle(step)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent)
                .shadow(color: step, radius: 0, y: 3)
        }
        .padding(.bottom, 3)
    }
}
