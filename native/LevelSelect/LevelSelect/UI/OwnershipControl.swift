import SwiftUI

/// Multi-select chips for how a game is owned: Physical / Digital / Emulated.
/// Tap to toggle; a game can be more than one (double-dipped a physical +
/// digital copy). Springs + haptics to match the app's motion.
struct OwnershipControl: View {
    /// Bound to `Game.ownership` (array of raw `Ownership` values).
    @Binding var ownership: [String]
    /// Centred on the game page, where the header above it is centred too.
    /// Left-aligned everywhere else — in the Add Game form these are one field
    /// among many, and a centred row of chips in a column of left-aligned
    /// labels reads as a mistake.
    var centered = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        content
            // Outside `ViewThatFits`, deliberately. Inside, a
            // `maxWidth: .infinity` frame would make every candidate row
            // "fit" and the measurement below would always pick the first.
            .frame(maxWidth: .infinity,
                   alignment: centered ? .center : .leading)
    }

    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            // Wrapping is right here and shrinking is not: someone who asked
            // for larger text should get larger text, on a second row.
            FlowLayout(spacing: 6) { chips(font: .caption, hPad: 8) }
        } else {
            // `ViewThatFits` measures instead of guessing. Four labelled chips
            // fit one line on a 430pt Max and don't on a 393pt phone, so this
            // row broke on some hardware and not others — and the previous fix
            // (a minimum scale factor) couldn't help, because the layout
            // decides whether to WRAP before any text is scaled. Each rung is
            // tried in order and the first that genuinely fits wins, so the
            // comfortable size still gets used wherever there's room and no
            // screen width is hardcoded anywhere.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips(font: .caption,  hPad: 8) }
                HStack(spacing: 5) { chips(font: .caption2, hPad: 7) }
                HStack(spacing: 4) { chips(font: .caption2, hPad: 5) }
                FlowLayout(spacing: 6) { chips(font: .caption, hPad: 8) }
            }
        }
    }

    @ViewBuilder
    private func chips(font: Font, hPad: CGFloat) -> some View {
        ForEach(Ownership.allCases, id: \.self) { kind in
            chip(kind, font: font, hPad: hPad)
        }
    }

    private func chip(_ kind: Ownership, font: Font, hPad: CGFloat) -> some View {
        let on = ownership.contains(kind.rawValue)
        return Button {
            toggle(kind)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .symbolVariant(on ? .fill : .none)
                Text(kind.label)
            }
            // No `minimumScaleFactor`: it would let a candidate row claim it
            // fits by silently shrinking its own text, which is exactly the
            // measurement `ViewThatFits` exists to make honestly.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .font(font.weight(.medium))
            .padding(.horizontal, hPad)
            .padding(.vertical, 5)
            .background(on ? AnyShapeStyle(LSTheme.accent.opacity(0.20))
                           : AnyShapeStyle(.white.opacity(0.06)),
                        in: .capsule)
            .overlay {
                Capsule().strokeBorder(on ? LSTheme.accent.opacity(0.55) : .clear, lineWidth: 1)
            }
            .foregroundStyle(on ? AnyShapeStyle(LSTheme.accent) : AnyShapeStyle(.secondary))
            .scaleEffect(on ? 1 : 0.98)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }

    private func toggle(_ kind: Ownership) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) {
            if let idx = ownership.firstIndex(of: kind.rawValue) {
                ownership.remove(at: idx)
            } else {
                ownership.append(kind.rawValue)
            }
        }
    }
}

/// Tiny read-only ownership icons for library rows and cover cards.
struct OwnershipBadges: View {
    let ownership: [String]
    var size: CGFloat = 10
    var tint: Color = .secondary

    private var kinds: [Ownership] {
        Ownership.allCases.filter { ownership.contains($0.rawValue) }
    }

    var body: some View {
        if !kinds.isEmpty {
            HStack(spacing: 4) {
                ForEach(kinds, id: \.self) { k in
                    Image(systemName: k.systemImage)
                        .symbolVariant(.fill)
                        .font(.system(size: size))
                }
            }
            .foregroundStyle(tint)
        }
    }
}
