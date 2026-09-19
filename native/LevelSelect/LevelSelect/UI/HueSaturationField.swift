import SwiftUI

/// Hue and saturation in one gesture, with the region that cannot be honored
/// drawn on it.
///
/// Two skinny sliders could not express this. The constraint on a linked
/// palette is genuinely two-dimensional — saturated blues and violets cannot be
/// made legible on a dark ground at ANY brightness, because blue contributes
/// 0.0722 to relative luminance against green's 0.7152 — so the unusable part
/// of the space is a *shape*, and a shape needs a plane to live on. Tim asked
/// for this after seeing the sliders: *"It definitely would give a finer
/// control of your two choices than two skinnier bars."*
///
/// Brightness is absent on purpose. The app derives it per appearance, so the
/// two axes here are exactly the two decisions a person makes.
struct HueSaturationField: View {
    @Binding var hue: Double
    @Binding var saturation: Double

    /// The ground the DARK accent will be read on. Marking is driven by real
    /// contrast against it rather than a hard-coded hue range, so if the ground
    /// changes the marks move with it.
    let darkGround: Color

    /// Sampling resolution for the marked region. 40×16 is fine enough that the
    /// boundary reads as a curve and coarse enough to stay cheap in a Canvas
    /// that redraws on every drag.
    private let cols = 40
    private let rows = 16

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                spectrum
                marks(width: w, height: h)
                knob(width: w, height: h)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(value.location.x / w, 0), 1)
                        // Saturation runs top (0, washed out) to bottom (1,
                        // full), matching the system picker people already know.
                        saturation = min(max(value.location.y / h, 0), 1)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Accent hue and saturation")
            .accessibilityValue(Text(accessibilityValue))
            .accessibilityAdjustableAction { direction in
                let step = 1.0 / 24
                hue = min(max(hue + (direction == .increment ? step : -step), 0), 1)
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LSTheme.hairline, lineWidth: 1))
    }

    /// Hue across, saturation down. Drawn at full brightness because this is
    /// the INPUT space — the derived results are shown beside it, since a field
    /// that previewed the derivation would have to redraw per pixel and would
    /// still only show one appearance's answer.
    private var spectrum: some View {
        LinearGradient(
            colors: stride(from: 0.0, through: 1.0, by: 1.0 / 24)
                .map { Color(hue: $0, saturation: 1, brightness: 1) },
            startPoint: .leading, endPoint: .trailing
        )
        .overlay(
            LinearGradient(colors: [.white, .white.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// A diagonal tick on every cell whose saturation cannot be honored in
    /// dark mode — the same language the swatches use for a color that cannot
    /// be read, so "struck through" means one thing across the picker.
    private func marks(width w: CGFloat, height h: CGFloat) -> some View {
        Canvas { context, _ in
            let cw = w / CGFloat(cols), ch = h / CGFloat(rows)
            for col in 0..<cols {
                let hueAt = (Double(col) + 0.5) / Double(cols)
                for row in 0..<rows {
                    let satAt = (Double(row) + 0.5) / Double(rows)
                    let derived = LSTheme.derivedAccent(hue: hueAt, saturation: satAt,
                                                        dark: true, ground: darkGround)
                    guard derived.softened else { continue }
                    let x = CGFloat(col) * cw, y = CGFloat(row) * ch
                    var line = Path()
                    line.move(to: CGPoint(x: x + cw * 0.25, y: y + ch * 0.75))
                    line.addLine(to: CGPoint(x: x + cw * 0.75, y: y + ch * 0.25))
                    context.stroke(line, with: .color(.black.opacity(0.35)), lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func knob(width w: CGFloat, height h: CGFloat) -> some View {
        Circle()
            .strokeBorder(.white, lineWidth: 2.5)
            .background(Circle().fill(Color(hue: hue, saturation: saturation, brightness: 1)))
            .frame(width: 26, height: 26)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .position(x: hue * w, y: saturation * h)
            .allowsHitTesting(false)
    }

    private var accessibilityValue: String {
        let degrees = Int((hue * 360).rounded())
        let percent = Int((saturation * 100).rounded())
        return "Hue \(degrees) degrees, saturation \(percent) percent"
    }
}
