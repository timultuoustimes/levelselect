import SwiftUI

/// Multi-select chips for how a game is owned: Physical / Digital / Emulated.
/// Tap to toggle; a game can be more than one (double-dipped a physical +
/// digital copy). Springs + haptics to match the app's motion.
struct OwnershipControl: View {
    /// Bound to `Game.ownership` (array of raw `Ownership` values).
    @Binding var ownership: [String]

    var body: some View {
        HStack(spacing: 7) {
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
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
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
