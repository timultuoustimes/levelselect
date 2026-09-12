import SwiftUI

/// Netflix-style enjoyment rating: 1–5 stars named Hated it … Loved it, with a
/// springy, haptic pick and a little sparkle when you hit "Loved it" (5 = a de
/// facto favorite). Tap the current rating again to clear it.
///
/// The words are the user's when they've named them (Settings → Appearance):
/// a rating that says "comfort game" instead of "Liked it" reads like the
/// notebook's owner wrote it. Defaults below.
struct RatingControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var rating: Int?
    var showLabel = true

    static let labels = ["Hated it", "Didn't like it", "Liked it", "Really liked it", "Loved it"]

    @State private var burst = 0

    private var value: Int { rating ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star($0) }
            }
            if showLabel {
                labelView
                    // A scaled MINIMUM keeps short labels from making the row
                    // jump, but still lets "Really liked it" wrap and grow at
                    // accessibility sizes. A scaled fixed height was still a
                    // one-line cap — a larger box that revealed no more text.
                    .frame(minHeight: labelHeight, alignment: .leading)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
                               value: rating)
            }
        }
        // One adjustable control rather than five unlabelled images plus a
        // separately announced visible label. Grouping the entire control
        // keeps VoiceOver's spoken value and the on-screen text in one element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            // Never routed through `set` at the ceiling: `set` treats
            // "the value you already have" as the touch toggle and clears
            // the rating, so incrementing a 5-star game unrated it.
            case .increment:
                if value < 5 { set(value + 1) }
            case .decrement:
                // Down from one star clears it, which is what tapping the
                // filled first star already does.
                if value <= 1 { rating = nil } else { set(value - 1) }
            @unknown default: break
            }
        }
    }

    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 15

    @ViewBuilder
    private var labelView: some View {
        if let r = rating {
            Text(ThemePalette.starLabel(for: r))
                .font(.caption.weight(.semibold))
                .foregroundStyle(labelColor(r))
                .id(r)   // new identity per rating → the transition re-fires
                // A push travels; a fade does not. Reduce Motion keeps the
                // label change, drops the movement.
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .push(from: .bottom).combined(with: .opacity),
                                          removal: .opacity))
        } else {
            Text("Rate it")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityValue: String {
        guard value > 0 else { return "Not rated" }
        return "\(value) of 5, \(ThemePalette.starLabel(for: value))"
    }

    private func star(_ i: Int) -> some View {
        let filled = value >= i
        return Image(systemName: filled ? "star.fill" : "star")
            .font(.title3)
            .foregroundStyle(filled ? Color.yellow : Color.secondary.opacity(0.5))
            .symbolEffect(.bounce, value: reduceMotion ? false : filled)  // pops as it fills
            .scaleEffect(reduceMotion ? 1 : (filled ? 1 : 0.9))
            .overlay {
                if i == 5 && value == 5 && !reduceMotion { SparkleBurst(trigger: burst) }
            }
            // Vertical only. Five stars sit side by side, so a 44-point
            // square around each would overlap its neighbors and the wrong
            // star would win the tap — worse than a small target.
            //
            // **And it must not cost layout.** `frame(minHeight: 44)` around
            // a `.title3` glyph left about twelve points of dead space under
            // the stars, which pushed the star label away from the very thing
            // it names. Tim, after a first attempt tightened the wrong gap:
            // *"it's not closer to the stars."* It wasn't — the label had
            // been pulled down to the critic score instead of up to the
            // stars, because this was the space actually holding it away.
            //
            // Padding out and back in gives the same 44-point target and
            // occupies nothing, so the label sits where it belongs.
            // Sideways as far as the 6-point gap allows and no further: 3
            // points each side fills the gap exactly, so each star reaches 26
            // points wide with no overlap.
            //
            // **It does not reach 44 wide, and that is a layout decision
            // rather than a bug.** Five 44-point stars are 220 points against
            // the ~124 this row occupies now, and this control sits inside the
            // game page's measured hero panel — widening it by ninety-odd
            // points is a visible change to a row Tim has already had opinions
            // about twice. Codex A7 is right that the horizontal target is
            // small; it is not right that the fix is free. Flagged rather than
            // taken unilaterally.
            .lsTapTargetTall(12, horizontal: 3)
            .onTapGesture { set(i) }
    }

    /// Tapping the star you're already on clears the rating; that toggle is
    /// deliberate for touch, but an adjustable action must never use it, or
    /// incrementing to the current value would wipe the rating instead.
    private func set(_ i: Int) {
        let newValue = (rating == i) ? nil : i
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) {
            rating = newValue
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: newValue == 5 ? .heavy : .light).impactOccurred()
        #endif
        if newValue == 5 { burst += 1 }
    }

    private func labelColor(_ r: Int) -> Color {
        switch r {
        case 1: .red.opacity(0.9)
        case 2: .orange.opacity(0.9)
        case 3: .secondary
        case 4: .green.opacity(0.85)
        default: .yellow
        }
    }
}

/// A quick radial sparkle pop for the 5-star "Loved it" moment.
private struct SparkleBurst: View {
    let trigger: Int
    @State private var t: CGFloat = 0

    // Hexagon of unit directions.
    private let dirs: [(CGFloat, CGFloat)] =
        [(0, -1), (0.87, -0.5), (0.87, 0.5), (0, 1), (-0.87, 0.5), (-0.87, -0.5)]

    var body: some View {
        ZStack {
            ForEach(dirs.indices, id: \.self) { k in
                Image(systemName: "sparkle")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.yellow)
                    .offset(x: dirs[k].0 * 18 * t, y: dirs[k].1 * 18 * t)
                    .opacity(Double(1 - t))
                    .scaleEffect(0.4 + t)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            t = 0
            withAnimation(.easeOut(duration: 0.55)) { t = 1 }
        }
    }
}
