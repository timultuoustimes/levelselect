import SwiftUI
import SwiftData

/// One color, edited properly.
///
/// Replaces a bare `ColorPicker` row, which wrote straight through and opened
/// Apple's picker — so there was no way to change your mind, no way to put a
/// single color back to its default without resetting every color, and no
/// control over a sheet that arrived needing a scroll to reach its own tabs.
///
/// Pushed onto the Settings stack rather than presented: a `.sheet` inside a
/// `Form` attaches to a `Section`, which SwiftUI applies per child, and the
/// row dismissed Settings instead of opening anything.
///
/// Everything here is a draft until Done. Cancel restores what was there when
/// the sheet opened, including the live theme, so nothing is committed by
/// looking.
/// One color this editor can change.
struct ColorTarget: Identifiable {
    let id: String
    let label: String
    /// The color this reverts to. Nil when there is no default to go back to.
    let defaultColor: Color?
    /// Whether a custom value is currently stored — Reset is pointless without.
    let isCustomised: Bool
    let binding: Binding<Color>
    let onReset: () -> Void
    /// The ground this color will be read ON, when it has to stay legible.
    ///
    /// Set for accents, which are ink. Nil for backgrounds, which are not:
    /// `LSTheme.ground` takes only hue and saturation from a picked color and
    /// fixes brightness per appearance (0.97 light, 0.16 dark), so a ground
    /// cannot be dialled into illegibility no matter what is picked.
    var contrastGround: Color? = nil
    /// Which appearance this value belongs to, for the readout's wording.
    var appearanceLabel: String? = nil
    /// Draw the preview as THIS NAME in the pixel face, rather than as the
    /// accent's buttons.
    ///
    /// The preview's job is to show what the color is a color OF. A Play
    /// button and a Sample chip say that for an accent and say nothing for a
    /// profile name, which is 22pt Press Start 2P with a hard step under it —
    /// a completely different specimen with completely different legibility.
    /// Tim: *"This color preview doesn't make sense for the profile name."*
    var specimenName: String? = nil
}

struct ColorEditor: View {
    let title: String
    /// Every color editable here. More than one gets a picker at the top.
    ///
    /// Accent and background arrive together because they are chosen against
    /// each other. Tim: *"you should be able to choose accent and background
    /// color in the same single screen, so that you can pick colors that work
    /// together, as opposed to picking one, moving over to another and then
    /// choosing the other."* Two sheets made the pair a memory test.
    let targets: [ColorTarget]
    @State private var selectedID: String

    @Environment(\.dismiss) private var dismiss

    init(title: String, targets: [ColorTarget], initial: String? = nil) {
        self.title = title
        self.targets = targets
        _selectedID = State(initialValue: initial ?? targets.first?.id ?? "")
    }

    private var target: ColorTarget {
        targets.first { $0.id == selectedID } ?? targets[0]
    }

    /// The two colors the preview needs, live — whichever one is being
    /// edited comes from the sliders, the other from its stored binding.
    ///
    /// Resolved for the appearance being edited. Build 37 split each color in
    /// two, so the ids became `accent-light`/`accent-dark` and this matched
    /// neither: every lookup fell through to `.clear` and the preview stopped
    /// responding to the picker entirely. Editing the light accent must
    /// preview the light accent on the LIGHT ground, not a mix of the two.
    private func live(_ kind: String) -> Color {
        let appearance = selectedID.hasSuffix("-dark") ? "dark" : "light"
        let id = "\(kind)-\(appearance)"
        if id == selectedID { return current }
        return targets.first { $0.id == id }?.binding.wrappedValue ?? .clear
    }

    /// **The appearance the preview must be drawn in.**
    ///
    /// Not the one the phone is in. Editing the LIGHT ground while the device
    /// is dark drew the preview dark, because every surface in it resolves
    /// through `lsDynamic`, which asks the environment — so the one control
    /// whose whole job is showing you a light ground showed you a dark one.
    /// Tim: *"Background preview for light is showing as dark (system is
    /// currently dark)."*
    ///
    /// nil for the single-target editors (the status colors), which have no
    /// light/dark split and should stay in the appearance you are actually
    /// looking at.
    private var previewScheme: ColorScheme? {
        if selectedID.hasSuffix("-dark") { return .dark }
        if selectedID.hasSuffix("-light") { return .light }
        return nil
    }

    @Environment(\.colorScheme) private var deviceScheme

    /// What the theme looked like when the sheet opened, for Cancel — one
    /// per target, because Cancel now has to undo everything the sheet
    /// touched rather than just the last thing.
    @State private var originals: [String: Color] = [:]
    @State private var hue: Double = 0
    @State private var saturation: Double = 0.7
    @State private var brightness: Double = 0.9
    @State private var loaded = false
    @State private var hexDraft = ""
    @State private var hexBad = false

    /// Colors the user has kept. Synced, so a palette built on the phone is
    /// on the iPad — it was `@AppStorage` until `savedSwatchesData` existed.
    @Environment(\.modelContext) private var context
    @Query(sort: \ThemeSettings.createdAt) private var themeSettings: [ThemeSettings]

    private var saved: [String] { themeSettings.first?.savedSwatches ?? [] }

    // MARK: The linked palette

    /// One hue for both appearances, or two independent choices.
    ///
    /// Only offered where there is something to link — the Colors editor with
    /// its accent pair. A single-target editor (status colors) has no second
    /// appearance to match.
    private var offersLinking: Bool { targets.contains { $0.id.hasPrefix("accent-") } }

    private var linked: Bool {
        get { themeSettings.first?.paletteLinked ?? true }
        nonmutating set {
            let theme = ThemePalette.fetchOrCreate(in: context)
            theme.paletteLinked = newValue
            // Seed the hue from whatever is on screen, so turning this on does
            // not blank the accent while the user works out what it does.
            if newValue, theme.accentHue == nil {
                let hs = current.lsHueSaturation
                theme.accentHue = hs?.hue ?? hue
                theme.accentSaturation = hs?.saturation ?? saturation
            }
            commitTheme(theme)
        }
    }

    /// **Linked mode edits two things, not one.**
    ///
    /// It used to edit only the accent, so turning "Match light and dark" on
    /// took the ground away entirely — Tim: *"why aren't they able to choose a
    /// background and accent color for the 'match light and dark'? They're
    /// just choosing one color."* Nothing about matching the appearances
    /// implies giving up the ground; that was an omission, not a design.
    ///
    /// Two segments here against the unlinked editor's four, which is exactly
    /// the difference the toggle describes: one hue per role instead of one
    /// per role per appearance.
    enum LinkedKind: String, CaseIterable, Identifiable {
        case accent, ground
        var id: String { rawValue }
        var label: String { self == .accent ? "Accent" : "Ground" }
    }
    @State private var linkedKind: LinkedKind = .accent

    /// The ground needs no new stored fields to be "linked".
    ///
    /// `LSTheme.ground(tintedBy:)` keeps only hue and saturation and supplies
    /// the luminance per appearance, so writing one color to BOTH stored
    /// grounds already produces a matched pair. The accent is different — it
    /// has a real linked hue of its own, because its brightness is derived
    /// rather than fixed.
    private var linkedHue: Binding<Double> {
        switch linkedKind {
        case .accent:
            return Binding(get: { themeSettings.first?.accentHue ?? hue },
                           set: { v in
                               let theme = ThemePalette.fetchOrCreate(in: context)
                               theme.accentHue = v
                               commitTheme(theme)
                           })
        case .ground:
            return Binding(get: { groundHueSaturation.h },
                           set: { writeLinkedGround(hue: $0,
                                                    saturation: groundHueSaturation.s) })
        }
    }

    private var linkedSaturation: Binding<Double> {
        switch linkedKind {
        case .accent:
            return Binding(get: { themeSettings.first?.accentSaturation ?? saturation },
                           set: { v in
                               let theme = ThemePalette.fetchOrCreate(in: context)
                               theme.accentSaturation = v
                               commitTheme(theme)
                           })
        case .ground:
            return Binding(get: { groundHueSaturation.s },
                           set: { writeLinkedGround(hue: groundHueSaturation.h,
                                                    saturation: $0) })
        }
    }

    /// The targets one linked role covers — both appearances of it.
    private var linkedTargets: [ColorTarget] {
        let prefix = linkedKind == .accent ? "accent-" : "background-"
        return targets.filter { $0.id.hasPrefix(prefix) }
    }

    /// The stored ground's hue and saturation, or the default's.
    private var groundHueSaturation: (h: Double, s: Double) {
        let stored = themeSettings.first?.backgroundHex(dark: true)
            .flatMap { Color(hex: $0) } ?? LSTheme.purpleDeep
        let v = ColorEditor.hsb(stored)
        return (v.h, v.s)
    }

    /// Both grounds at once — that is what "matched" means here.
    ///
    /// Brightness is arbitrary and discarded downstream, so it is set to
    /// something mid-range rather than pretending to be meaningful.
    private func writeLinkedGround(hue h: Double, saturation sat: Double) {
        let color = Color(hue: h, saturation: sat, brightness: 0.6)
        for t in targets where t.id.hasPrefix("background-") {
            t.binding.wrappedValue = color
        }
    }

    private func commitTheme(_ theme: ThemeSettings) {
        theme.updatedAt = .now
        try? context.save()
        ThemePalette.refresh(from: theme)
    }

    /// Linking only applies where a hue has been chosen and there is a pair to
    /// link — the same gate the palette resolution uses, so the editor can
    /// never show a mode the app is not actually in.
    private var linkedMode: Bool {
        offersLinking && linked && themeSettings.first?.accentHue != nil
    }

    /// Preview, palette, your own colors, a hex field, the plane, and
    /// whatever readout the mode wants — in that order, in both modes.
    @ViewBuilder
    private func pickerStack<Readout: View>(
        hue: Binding<Double>,
        saturation: Binding<Double>,
        @ViewBuilder readout: () -> Readout
    ) -> some View {
        preview

        // One grid, no headed rows. There is no "Not readable on this ground"
        // group — every entry resolves for the appearance being edited — and
        // no "LevelSelect" group either, because the app's own two are now the
        // first two circles in the ring.
        hueGroup(nil, Self.palette, hue: hue, saturation: saturation)

        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Yours")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(saved, id: \.self) { hex in
                        swatch(hex, removable: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        hexRow

        // Three sliders and a color wheel were two ways into three numbers,
        // and one of the three is no longer the user's to set. With lightness
        // derived, the choice is two-dimensional, and a plane is the honest
        // shape for it — Tim: *"It should just be the hue and saturation like
        // we had."*
        VStack(spacing: 10) {
            HueSaturationField(hue: hue, saturation: saturation,
                               darkGround: ThemePalette.groundBase(dark: true))
            readout()
        }
    }

    /// What the hue actually becomes in each appearance.
    private func derived(dark: Bool) -> LSTheme.DerivedAccent {
        LSTheme.derivedAccent(hue: linkedHue.wrappedValue,
                              saturation: linkedSaturation.wrappedValue,
                              dark: dark,
                              ground: ThemePalette.groundBase(dark: dark))
    }

    /// A dark-UI palette, not a full spectrum.
    ///
    /// The app is near-black everywhere, so pale washes and muddy mid-tones
    /// are choices nobody can use — a grid that offers them mostly offers
    /// disappointment. These are picked to read on the ground they land on.
/// The app's own colors, first and together.
    ///
    /// They were in the grid already — torch orange, the two purples — but
    /// scattered among two dozen hues, so there was no way to tell they were a
    /// set rather than a coincidence. Tim: *"I can't tell if they're part of
    /// the same brand palette."* A palette you cannot recognize is not a
    /// palette, so these lead and the rest follow.
    private static let brandSwatches: [String] = [
        "#F5A34D",   // torch orange — the wordmark, and the default accent
        "#8A5CF6",   // brand purple
        "#4C2A8C",   // deep purple — the ground's own hue
        "#8A4B12",   // torch shadow, the darker orange under pixel type
    ]

    /// The rest of the palette — and deliberately **no near-copies of the
    /// brand four above**. Tim: *"if they're in the top 4 brand colors, they
    /// shouldn't also be in the other color circles below."*
    ///
    /// Three were within a hair of a brand color and are gone: `#A66BFF` and
    /// `#7A5CFF` sat 0.017 and 0.019 in hue from the brand purple, and
    /// `#FF9F1C` sat 0.011 from torch orange. `#B36BFF` and `#FF8A5B` stay —
    /// a lighter purple and a coral read as their own hues rather than as the
    /// brand color repeated.
    private static let swatches: [String] = [
        "#FF8A5B", "#FF6B6B", "#F2547D", "#D65DB1", "#B36BFF",
        "#6C7BFF", "#4D9BFF", "#37C6E0", "#2FD4B6", "#3FD07A",
        "#8BD450", "#D4D450", "#FFC93C", "#E4572E", "#C1272D",
        "#5AA9E6", "#54C6C6", "#57C785", "#9BC53D",
    ]

    /// **The palette, as hue and saturation rather than fixed colors.**
    ///
    /// Fixed hexes could not be a palette here. Each one is a single lightness,
    /// so it reads on one ground and not the other, and the grid came back
    /// mostly struck through — what survived was a remainder, not a set. These
    /// resolve through `resolved(hue:saturation:)`, so every entry works on
    /// whichever appearance is being edited.
    ///
    /// **Spaced evenly in OKLCH, not in HSB — that is the whole point.**
    ///
    /// The previous set was twelve hues at `Double(i) / 12`, which is even
    /// arithmetic and uneven to the eye: HSB hue is not perceptually uniform.
    /// Green sprawls across a third of the wheel with every step looking like
    /// the same green, while the teal-to-blue arc changes fast and got two
    /// entries to cover four distinguishable colors. Tim, looking at the
    /// result: *"a few variations of similar colors that give basically the
    /// same end result as each other."* He was describing a measurable fact
    /// about the color space, not a matter of taste.
    ///
    /// So the ring is fourteen hues spaced 360/14 apart in **OKLCH**, which is
    /// built to be perceptually uniform, then converted to the (hue,
    /// saturation) this pipeline stores. In HSB terms they look bunched —
    /// four entries between 0.45 and 0.57 — and that is exactly right: those
    /// four are green-teal, teal, cyan and blue, and a person can tell them
    /// apart. Meanwhile the yellow-to-green span that used to eat four slots
    /// now takes three.
    ///
    /// Anchored on the app's own two so they are members of the ring rather
    /// than a separate row above it. Tim: *"I don't think we need the row
    /// labeled level select. I think that any of the level select colors we
    /// offer can just be the first 2 colors in the options."* Torch sits at
    /// OKLCH 64.3° and brand purple at 292.4°; a fourteen-step ring from torch
    /// lands on 295.7°, 3.3° away, so purple takes that slot exactly and
    /// nothing in the set is a near-copy of either.
    ///
    /// **Twelve, not fourteen — and the two that went are the lesson.**
    ///
    /// A perceptually even ring is even in OKLCH, and then this app applies
    /// its own transform on top: `derivedAccent` softens the saturation of any
    /// hue that cannot be read on a dark ground. Cyan cannot be dark, so the
    /// ring's teal, cyan and blue-cyan all got pulled toward the same muted
    /// teal and arrived as three circles of one color — the exact complaint,
    /// reintroduced by the fix for it. Seen on the simulator, not reasoned
    /// about: the grid had to be looked at after resolution, not before.
    ///
    /// So the two that collided are gone and the arc from green-teal to blue
    /// is a single step. Tim, sizing this: *"Even if that narrows what we have
    /// there as just 7 or 14 colors."*
    ///
    /// Derived once, offline, and written down: an OKLCH conversion in the app
    /// would be a lot of arithmetic to produce twelve constants that never
    /// change.
    private static let palette: [(h: Double, s: Double)] = [
        // The app's own two, first.
        (h: 0.0853, s: 0.69),   // #F5A34D torch orange — the wordmark's
        (h: 0.7165, s: 0.63),   // #8A5CF6 brand purple
        // The rest of the ring, in wheel order from torch.
        (h: 0.1310, s: 0.65),   // gold
        (h: 0.1812, s: 0.65),   // olive
        (h: 0.3146, s: 0.65),   // green
        (h: 0.4567, s: 0.65),   // green-teal
        (h: 0.5640, s: 0.65),   // blue
        (h: 0.6294, s: 0.65),   // indigo
        (h: 0.8088, s: 0.65),   // violet
        (h: 0.9057, s: 0.65),   // magenta
        (h: 0.9734, s: 0.65),   // pink
        (h: 0.0414, s: 0.65),   // coral
    ]

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if offersLinking {
                    // Bound to `linkedMode`, not the raw flag.
                    //
                    // `paletteLinked` defaults true so a NEW library gets the
                    // simpler model, but resolution is gated on a hue existing
                    // — which is what stops an accent someone already chose
                    // from being silently replaced. Binding the toggle to the
                    // raw flag therefore showed it ON while the app was still
                    // in the unlinked editor, claiming a state it was not in.
                    // Switching it on is what seeds the hue and makes it true.
                    Toggle("Match light and dark", isOn: Binding(
                        get: { linkedMode }, set: { linked = $0 }))
                        .font(.subheadline)
                    if !linkedMode {
                        Text("One hue, with brightness chosen per appearance so it reads on both grounds.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // **One editor, two modes — the same controls in the same
                // order.**
                //
                // These had drifted into two different screens: the linked one
                // put the plane first, then previews, then swatches; the
                // unlinked one put a segmented picker, a preview, swatches, a
                // hex field and then the plane. Tim: *"The picker layout with
                // the preview should be almost exactly the same as the other
                // one. It's weird that you hit the toggle and the dots are
                // down below, the picker is above, and the preview looks
                // extremely different."*
                //
                // So the only thing the toggle changes now is what the
                // segments say — four appearance-specific targets, or two
                // roles — and what the readout underneath reports.
                if linkedMode {
                    Picker("Editing", selection: $linkedKind) {
                        ForEach(LinkedKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    pickerStack(hue: linkedHue, saturation: linkedSaturation) {
                        // The split card above reports both appearances now, so
                        // this is the rule rather than a second set of numbers.
                        Text(linkedKind == .accent
                             ? "Brightness is chosen for you, per appearance, so the accent stays readable on each ground."
                             : "Only the hue is kept — the app supplies the lightness for each appearance, so no ground can make text unreadable.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if targets.count > 1 {
                        Picker("Editing", selection: $selectedID) {
                            ForEach(targets) { Text($0.label).tag($0.id) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    pickerStack(hue: $hue, saturation: $saturation) {
                        contrastReadout
                    }
                }
            }
            .padding(20)
            // **Pinned, not the last thing in the scroll.** It sat after a
            // `Spacer` that a ScrollView gives no room to, so it landed exactly
            // at the sheet's edge and drew half-sliced — Tim: *"'Use the default
            // background' and 'use the default accent' are off the bottom."*
            // A reset is the one control you go looking for when the color is
            // wrong, so it should not be a scroll away from the thing that made
            // it wrong.
            .safeAreaInset(edge: .bottom) { resetControl }
            .navigationTitle(title)
            // Cancel and a back chevron would be two exits that mean different
            // things — back keeps the change, Cancel throws it away — and
            // nothing on screen says which is which. One way out per outcome.
            .navigationBarBackButtonHidden(true)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Puts the LIVE theme back, not just the stored value —
                    // the preview writes through so you can see a color on
                    // the real app behind the sheet.
                    Button("Cancel") {
                        // Everything the sheet touched, not just the last one.
                        for t in targets {
                            if let was = originals[t.id] { t.binding.wrappedValue = was }
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
                for t in targets { originals[t.id] = t.binding.wrappedValue }
                setFromColor(target.binding.wrappedValue)
            }
            // Switching target loads ITS color without writing — otherwise
            // the sliders' current position would immediately overwrite the
            // color you just switched to with the one you switched from.
            .onChange(of: selectedID) { _, _ in
                loading = true
                setFromColor(target.binding.wrappedValue)
                loading = false
                // The typed hex belongs to the target it was typed for.
                //
                // Fable 2.4: type 8A5CF6 on Accent, switch to Background, and
                // the field still reads 8A5CF6 — one tap of Use away from
                // setting the wrong color deliberately. Typing appended to the
                // stale text instead of replacing it, so the only way to clear
                // it was Cancel and reopen.
                hexDraft = ""
                hexBad = false
            }
            .onChange(of: hue) { _, _ in push() }
            .onChange(of: saturation) { _, _ in push() }
            .onChange(of: brightness) { _, _ in push() }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 560)
        #endif
    }

    @ViewBuilder
    private var resetControl: some View {
        // **Resets what you are editing.**
        //
        // `target` follows the four-way segmented picker, which linked mode
        // does not use — so with linking on it offered to reset the accent
        // while you were editing the ground, and did. In linked mode the reset
        // clears every target of that role, both appearances, because that is
        // what one linked value covers.
        if linkedMode {
            Button {
                for t in linkedTargets { t.onReset() }
            } label: {
                Label("Use the default \(linkedKind.label.lowercased())",
                      systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(.bar)
        } else if target.isCustomised || target.defaultColor != nil {
            Button {
                target.onReset()
                if let d = target.defaultColor { setFromColor(d) }
            } label: {
                Label("Use the default \(target.label.lowercased())",
                      systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            // Opaque, so the swatches do not scroll through it.
            .background(.bar)
        }
    }

    /// **Both appearances, side by side, in one card.**
    ///
    /// This used to be one sample drawn in whichever appearance you happened
    /// to be editing, with the other one reported underneath as two small "Aa"
    /// chips and a contrast ratio. Tim, drawing on it: *"can the picker sample
    /// be split like this for matched dark and light, rather than the smaller
    /// samples popping up at the bottom?"*
    ///
    /// Which is the right shape, because the whole difficulty this editor
    /// exists for is that one hue has to work on two grounds. Showing them
    /// apart made that a comparison you had to hold in your head; showing them
    /// touching makes it the thing you are looking at.
    ///
    /// The background used to be painted ON the button, which is the one place
    /// it never goes — so choosing a background showed a blue Play button and
    /// told you nothing. Now the ground is the ground and the accent is the
    /// button, in both halves.
    private var preview: some View {
        HStack(spacing: 0) {
            previewHalf(dark: false)
            previewHalf(dark: true)
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(LSTheme.hairline, lineWidth: 1))
    }

    /// One appearance's half: its ground, its accent, and what that pair
    /// actually measures.
    private func previewHalf(dark: Bool) -> some View {
        // A name is one color across both grounds, so it previews the live
        // edit on each; an accent has a value per appearance.
        let accent = target.specimenName == nil ? previewAccent(dark: dark) : current
        let ground = ThemePalette.groundBase(dark: dark)
        let ratio = ThemePalette.contrast(accent, ground)
        let softened = linkedMode && linkedKind == .accent
            ? derived(dark: dark).saturation < derived(dark: dark).requested - 0.001
            : false
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: dark ? "moon.fill" : "sun.max.fill")
                    .font(.caption2)
                Text(dark ? "Dark" : "Light")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
                // The number belongs beside the thing it measures, not in a
                // separate row that has to name which appearance it means.
                Text(String(format: "%.2f:1", ratio))
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(dark ? Color.white.opacity(0.55) : Color.black.opacity(0.45))

            // **Centered under the label, not in the card.**
            //
            // Tim, drawing the axis he wanted them on: the label row belongs at
            // the top, and the buttons belong in the middle of what is left —
            // which is not the middle of the whole half once a heading is
            // sitting above them. `.leading` on a `maxHeight: .infinity` frame
            // is vertically centered, horizontally leading, which is exactly
            // that.
            VStack(alignment: .leading, spacing: 6) {
            if let specimen = target.specimenName {
                // The real thing: the face, the step, the ground it lands on.
                HStack(spacing: 0) {
                    Text(specimen)
                        .font(LSTheme.pixel(13))
                        .fontDesign(nil)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        // **No `minimumScaleFactor`.** It shrank the glyphs and
                        // not the step, so the shadow drifted away from the
                        // letters it belongs to — the offset is one block of
                        // the face at THIS size, and scaling the face made the
                        // block a lie. Tim: *"Preview name in color picker has
                        // the wrong distance for dark shadow."* Truncating a
                        // long name is the honest trade; the specimen is there
                        // to show a colour, not to spell a name.
                        .truncationMode(.tail)
                        .shadow(color: LSTheme.hardStep(under: accent), radius: 0,
                                y: LSTheme.pixelStep(for: 13))
                    Spacer(minLength: 0)
                }
            } else {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.caption)
                    Text("Play").font(.caption.weight(.semibold))
                }
                .foregroundStyle(ThemePalette.knockoutPreview(on: accent, ground: ground))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [accent, accent.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 10))

                Text("Sample")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.16), in: .capsule)
                    .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1))

                Spacer(minLength: 0)
            }
            }

            if softened {
                // The one thing the old rows said that a swatch cannot: the
                // app had to give ground to make this hue legible here.
                Text("Saturation softened to keep this readable.")
                    .font(.caption2)
                    .foregroundStyle(LSTheme.working)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(ground)
    }

    /// What the accent resolves to for one appearance, in whichever mode.
    private func previewAccent(dark: Bool) -> Color {
        // **Derived from the accent's hue — only when the accent is the thing
        // being edited.**
        //
        // `linkedHue` follows `linkedKind`, so calling `derived` unconditionally
        // meant selecting Ground derived the "accent" from the GROUND's hue and
        // repainted the preview's buttons with it. Tim: *"choosing ground
        // changes the preview color for accent and ground."* The buttons exist
        // to show the accent standing on the new ground, so they have to go on
        // being the accent.
        if linkedMode, linkedKind == .accent { return derived(dark: dark).color }
        if linkedMode, let theme = themeSettings.first, let hue = theme.accentHue {
            return LSTheme.derivedAccent(hue: hue,
                                         saturation: theme.accentSaturation ?? 0.7,
                                         dark: dark,
                                         ground: ThemePalette.groundBase(dark: dark)).color
        }
        let id = "accent-\(dark ? "dark" : "light")"
        if id == selectedID { return current }
        return targets.first { $0.id == id }?.binding.wrappedValue ?? .clear
    }

    private var hexRow: some View {
        HStack(spacing: 10) {
            Text("#")
                .foregroundStyle(.tertiary)
            // The CURRENT color, not the app's default forever.
            //
            // This read "F5A34D" whatever was on screen, so there was no way
            // to read a color back out of the editor — you could type one in
            // and never see what you had. Fable, 2026-09-07.
            TextField(String(currentHex.dropFirst()), text: $hexDraft)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit(applyHex)
                .onChange(of: hexDraft) { _, _ in hexBad = false }
            if hexBad {
                Text("Not a color")
                    .font(.caption2)
                    .foregroundStyle(LSTheme.working)
            }
            Button("Use", action: applyHex)
                .buttonStyle(.borderless)
                .disabled(hexDraft.trimmingCharacters(in: .whitespaces).isEmpty)

            Divider().frame(height: 22)

            Button {
                keepCurrent()
            } label: {
                Image(systemName: saved.contains(currentHex) ? "checkmark" : "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(LSTheme.accent.opacity(0.16), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(saved.contains(currentHex))
            // 30 points, and the last control in the row — the only thing to
            // its left is a non-interactive Divider, so 7 points each side
            // reaches 44 with nothing to collide with. The family named in
            // Codex A7 that nobody had touched.
            .lsTapTargetInline(7)
            .accessibilityLabel("Keep this color")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 12))
    }

    private func applyHex() {
        let raw = hexDraft.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
        guard let c = Color(hex: "#" + raw) else { hexBad = true; return }
        // Same floor as everything else here — a typed value is still a choice.
        guard passes(c) else { hexBad = true; return }
        hexBad = false
        // The same rule the swatches follow: in linked mode the value lives on
        // the settings record, not in this view's state, so a typed hex has to
        // go through the mode's own bindings or it lands nowhere visible.
        let v = ColorEditor.hsb(c)
        if linkedMode {
            linkedHue.wrappedValue = v.h
            linkedSaturation.wrappedValue = v.s
        } else {
            setFromColor(c)
            push()
        }
    }

    private func keepCurrent() {
        let hex = currentHex
        guard !saved.contains(hex) else { return }
        // Newest first, capped — an unbounded list of near-identical purples
        // stops being a palette and becomes a scroll.
        write([hex] + saved)
    }

    private func forget(_ hex: String) {
        write(saved.filter { $0 != hex })
    }

    private func write(_ list: [String]) {
        let settings: ThemeSettings
        if let existing = themeSettings.first {
            settings = existing
        } else {
            settings = ThemeSettings()
            context.insert(settings)
        }
        settings.savedSwatches = list
        settings.updatedAt = .now
        PersistenceMonitor.shared.commit(context)
    }

    /// The current color as `#RRGGBB`.
    private var currentHex: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(current).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        let n = NSColor(current).usingColorSpace(.sRGB) ?? .white
        let r = n.redComponent, g = n.greenComponent, b = n.blueComponent
        #endif
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    /// The one swatch that counts as "the color you are on".
    ///
    /// **Singular by construction, because selection is.** `matches` is a
    /// tolerance test — 0.02 in hue, 0.05 in saturation and brightness — so
    /// picking the brand purple lit three circles at once: `#A66BFF` and
    /// `#7A5CFF` both fall inside it. Tightening the tolerance would only move
    /// the problem, since any two neighboring swatches can be closer to each
    /// other than to the value you dragged the sliders to. So the ring goes to
    /// the *nearest* swatch across every row, and only if it is near at all.
    private var selectedSwatch: String? {
        let all = Self.brandSwatches + Self.swatches + saved
        return all
            .compactMap { hex -> (String, Double)? in
                guard let c = Color(hex: hex), matches(c) else { return nil }
                return (hex, distance(to: c))
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// How far `current` is from a color, in the same three axes `matches`
    /// uses. Hue counts most: two purples of different brightness still read
    /// as the same color, two hues apart do not.
    private func distance(to other: Color) -> Double {
        let a = ColorEditor.hsb(current), b = ColorEditor.hsb(other)
        let dh = min(abs(a.h - b.h), 1 - abs(a.h - b.h))
        return dh * 4 + abs(a.s - b.s) + abs(a.b - b.b)
    }

    private func usable(_ hex: String) -> Bool {
        guard let c = Color(hex: hex) else { return false }
        return passes(c)
    }

    @ViewBuilder
    private func hueGroup(_ title: String?, _ entries: [(h: Double, s: Double)],
                          hue: Binding<Double>,
                          saturation: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.caption2).foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entries.indices, id: \.self) { i in
                    hueSwatch(entries[i], hue: hue, saturation: saturation)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A swatch of the color this hue actually becomes here.
    ///
    /// **Writes the bindings it was handed, not this view's `hue`/`saturation`
    /// state.** Those two belong to the unlinked editor; in linked mode the
    /// value lives on the settings record. Tapping a swatch used to set the
    /// unlinked state and call `push()` regardless, so in linked mode — the
    /// mode almost everyone is in — nothing moved and the ring settled on a
    /// color nobody had chosen. Tim: *"Picking a color here isn't changing
    /// the previews."* The selection ring reads the same bindings back, so it
    /// can no longer disagree with what is on screen.
    private func hueSwatch(_ e: (h: Double, s: Double),
                           hue: Binding<Double>,
                           saturation: Binding<Double>) -> some View {
        let c = resolved(hue: e.h, saturation: e.s)
        let selected = abs(hue.wrappedValue - e.h) < 0.02
            && abs(saturation.wrappedValue - e.s) < 0.08
        return Button {
            hue.wrappedValue = e.h
            saturation.wrappedValue = e.s
        } label: {
            Circle()
                .fill(c)
                .frame(width: 46, height: 46)
                .overlay {
                    Circle().strokeBorder(selected ? Color.primary : LSTheme.hairline,
                                          lineWidth: selected ? 3 : 1)
                }
        }
        .buttonStyle(.plain)
        .lsTapTargetInline()
        .accessibilityLabel("Hue \(Int((e.h * 360).rounded())) degrees")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func swatchGroup(_ title: String?, _ hexes: [String]) -> some View {
        if !hexes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(hexes, id: \.self) { swatch($0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func swatch(_ hex: String, removable: Bool = false) -> some View {
        let c = Color(hex: hex) ?? .gray
        let selected = (hex == selectedSwatch)
        // Shown and struck through rather than hidden: "this color exists and
        // will not work here" is more use than a palette that silently differs
        // between the light and dark tabs.
        let usable = passes(c)
        return Button {
            setFromColor(c)
            push()
        } label: {
            Circle()
                .fill(c)
                .frame(height: 46)
                .opacity(usable ? 1 : 0.22)
                .overlay {
                    Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0.12),
                                          lineWidth: selected ? 2.5 : 1)
                }
                .overlay {
                    if !usable {
                        Capsule().fill(.primary)
                            .frame(width: 30, height: 2)
                            .rotationEffect(.degrees(-45))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!usable)
        .accessibilityLabel(usable ? hex : "\(hex), not readable on this ground")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .contextMenu {
            if removable {
                Button("Remove", role: .destructive) { forget(hex) }
            }
        }
    }

    private func slider(_ label: String, value: Binding<Double>,
                        track: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ZStack {
                Capsule().fill(track).frame(height: 18)
                Slider(value: value, in: 0...1).tint(.clear)
            }
        }
    }

    /// Which ground this target will be read on.
    private var derivedDark: Bool {
        if selectedID.hasSuffix("-dark") { return true }
        if selectedID.hasSuffix("-light") { return false }
        // Status colors have no appearance of their own; they are drawn on
        // whichever ground you are looking at.
        return deviceScheme == .dark
    }

    private var editingGround: Bool { selectedID.hasPrefix("background") }

    /// **Hue and saturation are the choice; lightness is derived.**
    ///
    /// This used to be `Color(hue:saturation:brightness:)` straight off three
    /// sliders, which is why the palette was full of struck-through circles: a
    /// color readable on the dark ground is usually unreadable on the light
    /// one, so whichever appearance you were editing rejected most of the grid.
    /// Tim: *"we've got giant blocks of 'doesn't work here' all crossed out and
    /// then just a few colors they can choose from... I don't think we need to
    /// give them the brightness option."*
    ///
    /// Deriving instead means every hue lands, on both appearances, with no
    /// third number to get wrong — the same model the linked editor has used
    /// since Block C, now used everywhere.
    private func resolved(hue h: Double, saturation sat: Double) -> Color {
        if editingGround {
            // A ground tint contributes hue and saturation only; `LSTheme.ground`
            // shades its own lightness per appearance from them.
            return Color(hue: h, saturation: sat, brightness: 0.55)
        }
        return LSTheme.derivedAccent(hue: h, saturation: sat, dark: derivedDark,
                                     ground: ThemePalette.groundBase(dark: derivedDark)).color
    }

    /// The color being edited, wherever this mode keeps it. Used by the hex
    /// field, "keep this color", and the contrast readout — all of which
    /// reported the unlinked state regardless of mode before.
    private var current: Color {
        linkedMode
            ? resolved(hue: linkedHue.wrappedValue, saturation: linkedSaturation.wrappedValue)
            : resolved(hue: hue, saturation: saturation)
    }

    private var hueTrack: LinearGradient {
        LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1)
            .map { Color(hue: $0, saturation: saturation, brightness: brightness) },
                       startPoint: .leading, endPoint: .trailing)
    }
    private var satTrack: LinearGradient {
        LinearGradient(colors: [Color(hue: hue, saturation: 0, brightness: brightness),
                                Color(hue: hue, saturation: 1, brightness: brightness)],
                       startPoint: .leading, endPoint: .trailing)
    }
    private var brightTrack: LinearGradient {
        LinearGradient(colors: [.black, Color(hue: hue, saturation: saturation, brightness: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    private func matches(_ other: Color) -> Bool {
        let a = ColorEditor.hsb(current), b = ColorEditor.hsb(other)
        return abs(a.h - b.h) < 0.02 && abs(a.s - b.s) < 0.05 && abs(a.b - b.b) < 0.05
    }

    /// Guards the write while a target switch is loading values in.
    @State private var loading = false

    /// WCAG contrast of a candidate against the ground it will sit on.
    /// Nil when this target is not ink and has nothing to fail against.
    private func ratio(_ candidate: Color) -> Double? {
        guard let ground = target.contrastGround else { return nil }
        return ThemePalette.contrast(candidate, ground)
    }

    /// 4.5:1 — the floor for normal text. Not 3:1: the accent is used at
    /// caption and subheadline sizes all over the app, so the graphical
    /// threshold would still leave "See all" and "Left off" unreadable.
    private static let floor = 4.5

    private func passes(_ candidate: Color) -> Bool {
        guard let r = ratio(candidate) else { return true }
        return r >= Self.floor
    }

    private func push() {
        guard !loading else { return }
        // **A failing color is never committed.**
        //
        // Build 37: an accent has to be legible on the ground of the
        // appearance it belongs to, and no single color manages both — torch
        // is 8.74:1 on dark and 1.90:1 on light. Rather than let someone pick
        // an unreadable app and fix it at render time, the choice itself is
        // constrained. Dragging into a failing region shows the readout and
        // leaves the last good value in place, so this narrows the choice
        // without trapping anyone mid-gesture.
        guard passes(current) else { return }
        target.binding.wrappedValue = current
    }

    /// Live contrast readout, shown only where a value can actually fail.
    @ViewBuilder
    private var contrastReadout: some View {
        if let r = ratio(current) {
            let ok = r >= Self.floor
            HStack(spacing: 7) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(ok
                     ? "Readable on the \(target.appearanceLabel ?? "") ground — \(r, specifier: "%.2f"):1"
                     : "Too close to the \(target.appearanceLabel ?? "") ground — \(r, specifier: "%.2f"):1, needs 4.5")
                .font(.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(ok ? Color.secondary : Color.orange)
            .accessibilityElement(children: .combine)
        }
    }

    private func setFromColor(_ c: Color) {
        let v = ColorEditor.hsb(c)
        hue = v.h; saturation = v.s; brightness = v.b
    }

    static func hsb(_ color: Color) -> (h: Double, s: Double, b: Double) {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #else
        let native = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        let h = native.hueComponent, s = native.saturationComponent, b = native.brightnessComponent
        #endif
        return (Double(h), Double(s), Double(b))
    }
}
