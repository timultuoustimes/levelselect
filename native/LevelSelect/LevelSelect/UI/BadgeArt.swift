import SwiftUI

/// **A badge, as a symbol for now.**
///
/// The first pass was generated art in layers — a plate and an emblem stacked
/// so the emblem could lift off. The drawing was decent; the motion was not,
/// and a placeholder you don't want to keep is worse than an honest symbol
/// (Tim, 09-21). So this is the SF Symbol in the accent, and the art slot
/// waits for something worth keeping.
///
/// `CoverShine` still crosses it, because that is the light the box art
/// catches and a badge should live in the same room.
struct BadgeArt: View {
    let badge: Badges.Definition
    var size: CGFloat = 96
    /// Sweep the light across when this changes — the earn moment.
    var shineTrigger: Int = 0
    /// Repeat the sweep slowly, for a badge sitting on screen.
    var shimmers: Bool = false
    /// Staggers the loop so a list doesn't flash in unison.
    var phase: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loop = 0

    var body: some View {
        ZStack {
            Circle().fill(LSTheme.accent.opacity(0.16))
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(LSTheme.accent)
        }
        .frame(width: size, height: size)
        .overlay {
            CoverShine(delay: 0)
                .id(shineTrigger + loop)
                .mask(Circle())
        }
        .task(id: shimmers) {
            guard shimmers, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(phase))
            while !Task.isCancelled {
                loop += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The badge as it appears when it lands: it arrives small, settles, and the
/// light crosses it once.
struct EarnedBadgeArt: View {
    let badge: Badges.Definition
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shine = 0
    @State private var scale: Double = 0.7

    var body: some View {
        BadgeArt(badge: badge, size: size, shineTrigger: shine)
            .scaleEffect(scale)
            .task {
                guard !reduceMotion else { scale = 1; return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { scale = 1 }
                try? await Task.sleep(for: .milliseconds(180))
                shine += 1
            }
    }
}
