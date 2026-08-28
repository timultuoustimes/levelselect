import SwiftUI

/// Multi-select chips for how a game is owned: Physical / Digital / Emulated.
/// Tap to toggle; a game can be more than one (double-dipped a physical +
/// digital copy). Springs + haptics to match the app's motion.
struct OwnershipControl: View {
    /// Bound to `Game.ownership` (array of raw `Ownership` values).
    @Binding var ownership: [String]

    var body: some View {
        // Wraps rather than squeezing: three labelled chips do not fit one
        // line at accessibility text sizes, and a chip that hyphenates
        // "Emu-lated" is worse than one on a second row.
        FlowLayout(spacing: 6) {
            ForEach(Ownership.allCases, id: \.self) { kind in
                chip(kind)
            }
        }
    }

    private func chip(_ kind: Ownership) -> some View {
        let on = ownership.contains(kind.rawValue)
        return Button {
            toggle(kind)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .symbolVariant(on ? .fill : .none)
                Text(kind.label)
            }
            // Compress before wrapping. A fourth chip arrived in build 31
            // ("Previously Owned") and four labelled chips no longer fit one
            // line on a 393pt phone, though they do on a 430pt one — so the
            // row broke on some devices and not others. Shrinking slightly is
            // less disruptive than a second row appearing on half the
            // hardware. It still wraps at accessibility sizes, which is
            // correct and deliberate.
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
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
