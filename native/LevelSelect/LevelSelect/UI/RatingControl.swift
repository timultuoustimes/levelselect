import SwiftUI

/// Netflix-style enjoyment rating: 1–5 stars named Hated it … Loved it, with a
/// springy, haptic pick and a little sparkle when you hit "Loved it" (5 = a de
/// facto favorite). Tap the current rating again to clear it.
struct RatingControl: View {
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
            // One adjustable control rather than five unlabelled images.
            // VoiceOver previously found "star, image" five times with no way
            // to learn the current value or change it — the stars carry
            // `onTapGesture`, which has no button trait and no accessible
            // action. Swiping up and down now sets the rating directly.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rating")
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(min(5, value + 1) == value ? value : min(5, value + 1))
                case .decrement:
                    // Down from one star clears it, which is what tapping the
                    // filled first star already does.
                    if value <= 1 { rating = nil } else { set(value - 1) }
                @unknown default: break
                }
            }
            if showLabel {
                labelView
                    // Scales rather than pinned: 15pt fits "Loved it" at the
                    // default text size and clips it at accessibility sizes.
                    // The fixed height exists to stop the row jumping as the
                    // label changes, which a scaled height still does.
                    .frame(height: labelHeight, alignment: .leading)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: rating)
            }
        }
    }

    @ScaledMetric(relativeTo: .caption) private var labelHeight: CGFloat = 15

    @ViewBuilder
    private var labelView: some View {
        if let r = rating {
            Text(Self.labels[r - 1])
                .font(.caption.weight(.semibold))
                .foregroundStyle(labelColor(r))
                .id(r)   // new identity per rating → the transition re-fires
                .transition(.asymmetric(
                    insertion: .push(from: .bottom).combined(with: .opacity),
                    removal: .opacity))
        } else {
            Text("Rate it")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityValue: String {
        guard value > 0 else { return "Not rated" }
        return "\(value) of 5, \(Self.labels[value - 1])"
    }

    private func star(_ i: Int) -> some View {
        let filled = value >= i
        return Image(systemName: filled ? "star.fill" : "star")
            .font(.title3)
            .foregroundStyle(filled ? Color.yellow : Color.secondary.opacity(0.5))
            .symbolEffect(.bounce, value: filled)      // pops as it fills
            .scaleEffect(filled ? 1 : 0.9)
            .overlay { if i == 5 && value == 5 { SparkleBurst(trigger: burst) } }
            .contentShape(.rect)
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
