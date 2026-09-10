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
        case accent, background
        var id: String { rawValue }
        var label: String { self == .accent ? "Accent" : "Background" }
    }

    @State private var role: Role = .accent
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
        _role = State(initialValue: initial?.hasPrefix("background") == true ? .background : .accent)
    }

    // MARK: What is being edited

    /// The theme editor carries accent and ground targets; anything else is
    /// a single color — a status, a name.
    private var isThemeEditor: Bool { targets.contains { $0.id.hasPrefix("accent-") } }
    private var offersBackground: Bool { targets.contains { $0.id.hasPrefix("background-") } }

    private func targets(for role: Role) -> [ColorTarget] {
        targets.filter { $0.id.hasPrefix(role == .accent ? "accent-" : "background-") }
    }

    /// The targets a tap on a circle writes to.
    private var editing: [ColorTarget] {
        isThemeEditor ? targets(for: role) : Array(targets.prefix(1))
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
    private var chosen: LSPalette.Pair? { LSPalette.pair(matching: current?.hexString()) }

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

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if isThemeEditor, offersBackground {
                    Picker("Editing", selection: $role) {
                        ForEach(Role.allCases) { Text($0.label).tag($0) }
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
                Button("Cancel") {
                    for t in targets where picked[t.id] != nil {
                        if wasCustom.contains(t.id), let was = originals[t.id] {
                            t.binding.wrappedValue = was
                        } else {
                            t.onReset()
                        }
                    }
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
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
        return role == .accent
            ? "The accent is the same color on both grounds. On light it writes in its darker step; on dark it writes as itself."
            : "The ground is the color laid over the app's gray and charcoal, so nothing on it can become unreadable."
    }

    // MARK: The seven

    private var circles: some View {
        HStack(spacing: 10) {
            ForEach(LSPalette.pairs) { pair in
                let picked = chosen?.id == pair.id
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
            previewHalf(dark: false)
            previewHalf(dark: true)
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(LSTheme.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(previewDescription)
    }

    /// What the preview shows, for anyone who cannot see it.
    private var previewDescription: String {
        let name = chosen?.name ?? "A custom color"
        if isThemeEditor, role == .background {
            return "Preview: \(name) as the ground, light and dark."
        }
        return "Preview: \(name) as a button and a tinted pill, on the light ground and the dark one."
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
