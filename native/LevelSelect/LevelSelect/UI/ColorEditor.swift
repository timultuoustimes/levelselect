import SwiftUI

/// One colour, edited properly.
///
/// Replaces a bare `ColorPicker` row, which wrote straight through and opened
/// Apple's picker — so there was no way to change your mind, no way to put a
/// single colour back to its default without resetting every colour, and no
/// control over a sheet that arrived needing a scroll to reach its own tabs.
///
/// Pushed onto the Settings stack rather than presented: a `.sheet` inside a
/// `Form` attaches to a `Section`, which SwiftUI applies per child, and the
/// row dismissed Settings instead of opening anything.
///
/// Everything here is a draft until Done. Cancel restores what was there when
/// the sheet opened, including the live theme, so nothing is committed by
/// looking.
struct ColorEditor: View {
    let title: String
    /// The colour this reverts to. Nil when there is no default to go back to.
    let defaultColor: Color?
    /// Whether a custom value is currently stored — Reset is pointless without.
    let isCustomised: Bool
    @Binding var color: Color
    var onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// What the theme looked like when the sheet opened, for Cancel.
    @State private var original: Color = .clear
    @State private var originalWasCustom = false
    @State private var hue: Double = 0
    @State private var saturation: Double = 0.7
    @State private var brightness: Double = 0.9
    @State private var loaded = false

    /// A dark-UI palette, not a full spectrum.
    ///
    /// The app is near-black everywhere, so pale washes and muddy mid-tones
    /// are choices nobody can use — a grid that offers them mostly offers
    /// disappointment. These are picked to read on the ground they land on.
    private static let swatches: [String] = [
        "#F5A34D", "#FF8A5B", "#FF6B6B", "#F2547D", "#D65DB1", "#A66BFF",
        "#945CFA", "#6C7BFF", "#4D9BFF", "#37C6E0", "#2FD4B6", "#3FD07A",
        "#8BD450", "#D4D450", "#FFC93C", "#FF9F1C", "#E4572E", "#C1272D",
        "#B36BFF", "#7A5CFF", "#5AA9E6", "#54C6C6", "#57C785", "#9BC53D",
    ]

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                preview

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Self.swatches, id: \.self) { hex in
                        swatch(hex)
                    }
                }

                VStack(spacing: 10) {
                    slider("Hue", value: $hue, track: hueTrack)
                    slider("Saturation", value: $saturation, track: satTrack)
                    slider("Brightness", value: $brightness, track: brightTrack)
                }

                Spacer(minLength: 0)

                if isCustomised || defaultColor != nil {
                    Button {
                        onReset()
                        if let d = defaultColor { setFromColor(d) }
                        dismiss()
                    } label: {
                        Label("Use the default", systemImage: "arrow.uturn.backward")
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
                    // the preview writes through so you can see a colour on
                    // the real app behind the sheet.
                    Button("Cancel") { color = original; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                original = color
                originalWasCustom = isCustomised
                setFromColor(color)
            }
            .onChange(of: hue) { _, _ in push() }
            .onChange(of: saturation) { _, _ in push() }
            .onChange(of: brightness) { _, _ in push() }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 560)
        #endif
    }

    /// The colour doing the job it will actually do, rather than a square.
    private var preview: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                Text("Play").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ThemePalette.onColor(for: current))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                LinearGradient(colors: [current, current.opacity(0.82)],
                               startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: 12))

            Text("Sample")
                .font(.caption.weight(.semibold))
                .foregroundStyle(current)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(current.opacity(0.16), in: .capsule)
                .overlay(Capsule().strokeBorder(current.opacity(0.5), lineWidth: 1))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 14))
    }

    private func swatch(_ hex: String) -> some View {
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
    }

    private func slider(_ label: String, value: Binding<Double>,
                        track: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ZStack {
                Capsule().fill(track).frame(height: 8)
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

    private func push() { color = current }

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
