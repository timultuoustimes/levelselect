import SwiftUI

/// A hue ring around a saturation/brightness square.
///
/// The second way into the *same* three numbers the sliders already drive —
/// `ColorEditor` keeps one hue/saturation/brightness model and this is another
/// input onto it, not a second colour system. Everything downstream (the hex
/// field, saved swatches, the live preview) carries on unchanged.
///
/// **A square rather than Affinity's triangle**, which was Tim's reference.
/// A triangle rotates with the hue, so hit-testing it means mapping a touch
/// into barycentric coordinates of a shape that is moving — real work, and
/// under a thumb it gives you corners that are hard to reach and edges that
/// are easy to fall off. A square holds saturation on one axis and brightness
/// on the other, which is also easier to *say*, and it does not spin.
struct ColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    @Binding var brightness: Double

    /// How thick the hue ring is, as a share of the whole control.
    private let ringWidth: CGFloat = 0.14

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let ring = side * ringWidth
            // The square inscribed in the ring's inner circle, inset so its
            // corners do not touch — a corner that overlaps the ring steals
            // touches meant for the hue.
            let inner = side - ring * 2
            // 0.68 rather than the geometric fit: the knob is drawn centred on
            // the square's edge, so it needs room to sit outside without
            // landing on the ring and stealing its touches.
            let square = inner * 0.68

            ZStack {
                hueRing(side: side, thickness: ring)
                shadeSquare(side: square)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: The ring

    private func hueRing(side: CGFloat, thickness: CGFloat) -> some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    // 0 and 1 are the same hue; both ends are named so the
                    // wheel closes rather than seaming at red.
                    gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12)
                        .map { Color(hue: $0, saturation: 0.9, brightness: 0.95) }),
                    center: .center),
                lineWidth: thickness)
            .frame(width: side, height: side)
            .overlay { ringKnob(side: side, thickness: thickness) }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let center = CGPoint(x: side / 2, y: side / 2)
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        guard dx != 0 || dy != 0 else { return }
                        // **No quarter turn.** `AngularGradient` starts at 3
                        // o'clock, not 12 — correcting for a top start put the
                        // knob 90° from its own colour, orange sitting in the
                        // magenta. atan2 measures from the same positive
                        // x-axis, so the two already agree.
                        var angle = atan2(dy, dx)
                        if angle < 0 { angle += 2 * .pi }
                        hue = angle / (2 * .pi)
                    })
    }

    private func ringKnob(side: CGFloat, thickness: CGFloat) -> some View {
        let radius = (side - thickness) / 2
        // Matches the gradient's 3 o'clock origin — see the drag handler.
        let angle = hue * 2 * .pi
        return Circle()
            .fill(Color(hue: hue, saturation: 1, brightness: 1))
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 2)
            .frame(width: thickness * 1.15, height: thickness * 1.15)
            .offset(x: radius * cos(angle), y: radius * sin(angle))
            .allowsHitTesting(false)
    }

    // MARK: The square

    private func shadeSquare(side: CGFloat) -> some View {
        ZStack {
            // Saturation left→right over the chosen hue, brightness top→bottom
            // laid on as black. Two gradients rather than a bitmap, so it
            // stays sharp at any size and costs nothing to redraw as the hue
            // moves.
            LinearGradient(colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LSTheme.hairline))
        .overlay { squareKnob(side: side) }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    saturation = min(max(value.location.x / side, 0), 1)
                    brightness = 1 - min(max(value.location.y / side, 0), 1)
                })
    }

    private func squareKnob(side: CGFloat) -> some View {
        Circle()
            .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 2)
            .frame(width: 24, height: 24)
            .position(x: saturation * side, y: (1 - brightness) * side)
            .allowsHitTesting(false)
    }
}
