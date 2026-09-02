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
/// One colour this editor can change.
struct ColorTarget: Identifiable {
    let id: String
    let label: String
    /// The colour this reverts to. Nil when there is no default to go back to.
    let defaultColor: Color?
    /// Whether a custom value is currently stored — Reset is pointless without.
    let isCustomised: Bool
    let binding: Binding<Color>
    let onReset: () -> Void
}

struct ColorEditor: View {
    let title: String
    /// Every colour editable here. More than one gets a picker at the top.
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

    /// The two colours the preview needs, live — whichever one is being
    /// edited comes from the sliders, the other from its stored binding.
    private func live(_ id: String) -> Color {
        id == selectedID ? current : (targets.first { $0.id == id }?.binding.wrappedValue ?? .clear)
    }

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
    @Query private var themeSettings: [ThemeSettings]

    private var saved: [String] { themeSettings.first?.savedSwatches ?? [] }

    /// A dark-UI palette, not a full spectrum.
    ///
    /// The app is near-black everywhere, so pale washes and muddy mid-tones
    /// are choices nobody can use — a grid that offers them mostly offers
    /// disappointment. These are picked to read on the ground they land on.
/// The app's own colours, first and together.
    ///
    /// They were in the grid already — torch orange, the two purples — but
    /// scattered among two dozen hues, so there was no way to tell they were a
    /// set rather than a coincidence. Tim: *"I can't tell if they're part of
    /// the same brand palette."* A palette you cannot recognise is not a
    /// palette, so these lead and the rest follow.
    private static let brandSwatches: [String] = [
        "#F5A34D",   // torch orange — the wordmark, and the default accent
        "#8A5CF6",   // brand purple
        "#4C2A8C",   // deep purple — the ground's own hue
        "#8A4B12",   // torch shadow, the darker orange under pixel type
    ]

    private static let swatches: [String] = [
        "#FF8A5B", "#FF6B6B", "#F2547D", "#D65DB1", "#A66BFF",
        "#6C7BFF", "#4D9BFF", "#37C6E0", "#2FD4B6", "#3FD07A",
        "#8BD450", "#D4D450", "#FFC93C", "#FF9F1C", "#E4572E", "#C1272D",
        "#B36BFF", "#7A5CFF", "#5AA9E6", "#54C6C6", "#57C785", "#9BC53D",
    ]

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if targets.count > 1 {
                    Picker("Editing", selection: $selectedID) {
                        ForEach(targets) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                preview

                VStack(alignment: .leading, spacing: 8) {
                    Text("LevelSelect")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Self.brandSwatches, id: \.self) { hex in
                            swatch(hex)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Self.swatches, id: \.self) { hex in
                        swatch(hex)
                    }
                }

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

                // Two ways into the same three numbers. Sliders are precise
                // and say what they are; a wheel is faster when you are
                // hunting rather than adjusting. Neither is a second colour
                // model — swiping between them changes nothing but the input.
                TabView {
                    VStack(spacing: 10) {
                        slider("Hue", value: $hue, track: hueTrack)
                        slider("Saturation", value: $saturation, track: satTrack)
                        slider("Brightness", value: $brightness, track: brightTrack)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 28)

                    ColorWheel(hue: $hue, saturation: $saturation, brightness: $brightness)
                        .padding(.horizontal, 12)
                        // Clears the page dots, which draw over the content.
                        .padding(.bottom, 36)
                }
                #if !os(macOS)
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                #endif
                // A page view has no intrinsic height, so it needs one; the
                // wheel is square and the sliders are shorter, so the wheel
                // sets it.
                .frame(height: 300)

                Spacer(minLength: 0)

                if target.isCustomised || target.defaultColor != nil {
                    Button {
                        target.onReset()
                        if let d = target.defaultColor { setFromColor(d) }
                    } label: {
                        Label("Use the default \(target.label.lowercased())",
                              systemImage: "arrow.uturn.backward")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
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
            // Switching target loads ITS colour without writing — otherwise
            // the sliders' current position would immediately overwrite the
            // colour you just switched to with the one you switched from.
            .onChange(of: selectedID) { _, _ in
                loading = true
                setFromColor(target.binding.wrappedValue)
                loading = false
            }
            .onChange(of: hue) { _, _ in push() }
            .onChange(of: saturation) { _, _ in push() }
            .onChange(of: brightness) { _, _ in push() }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 560)
        #endif
    }

    /// Both colours doing the jobs they will actually do.
    ///
    /// The background used to be painted ON the button, which is the one place
    /// it never goes — so choosing a background showed a blue Play button and
    /// told you nothing. Now the ground is the ground and the accent is the
    /// button, whichever of the two you happen to be editing.
    private var preview: some View {
        let accent = live("accent")
        let ground = live("background")
        return HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                Text("Play").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ThemePalette.knockoutPreview(on: accent, ground: ground))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                LinearGradient(colors: [current, current.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 12))

            Text("Sample")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accent.opacity(0.16), in: .capsule)
                .overlay(Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 1))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        // The real ground, derived exactly as the app derives it, so the two
        // colours are judged against each other in the arrangement they will
        // actually appear in.
        .background(LSTheme.ground(tintedBy: ground), in: .rect(cornerRadius: 14))
    }

    /// A hex field and a keep button.
    ///
    /// Hex because a color often comes from somewhere else — a game's art, a
    /// brand, a palette someone already has — and re-finding it by dragging
    /// three sliders is guesswork. Keep, because having found it once, nobody
    /// should have to find it again.
    private var hexRow: some View {
        HStack(spacing: 10) {
            Text("#")
                .foregroundStyle(.tertiary)
            TextField("F5A34D", text: $hexDraft)
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
        hexBad = false
        setFromColor(c)
        push()
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

    private func swatch(_ hex: String, removable: Bool = false) -> some View {
        let c = Color(hex: hex) ?? .gray
        let selected = matches(c)
        return Button {
            setFromColor(c)
            push()
        } label: {
            Circle()
                .fill(c)
                .frame(height: 46)
                .overlay {
                    Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0.12),
                                          lineWidth: selected ? 2.5 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hex)
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

    private var current: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
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

    private func push() {
        guard !loading else { return }
        target.binding.wrappedValue = current
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
