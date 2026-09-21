import SwiftUI

/// **A badge, in three layers.**
///
/// Codex draws each badge as a plate, an emblem and a highlight, aligned on
/// one 1024 canvas (`assets/achievements/<slug>/final`). Stacking them here
/// rather than shipping one flat picture is what buys the motion: the emblem
/// can lift off the plate as the badge tilts, and the highlight can sweep
/// across the moment it is earned. Generated placeholder art — see the vault's
/// artwork spec; a commissioned set would drop into the same three slots.
///
/// A badge with no art falls back to its SF Symbol, so the catalogue can grow
/// faster than the drawing does.
struct BadgeArt: View {
    let badge: Badges.Definition
    var size: CGFloat = 96
    /// 0 at rest. Driven to 1 to sweep the highlight across — the earn moment.
    var sweep: Double = 0
    /// How far the emblem lifts off the plate, -1...1 on each axis.
    var tilt: CGSize = .zero

    /// Drawn or not. The catalogue grows faster than the art does, so a
    /// badge with no plate falls back to its symbol rather than a hole.
    private var hasArt: Bool {
        #if canImport(UIKit)
        UIImage(named: "Badges/\(badge.id)-plate") != nil
        #else
        NSImage(named: "Badges/\(badge.id)-plate") != nil
        #endif
    }

    var body: some View {
        ZStack {
            if hasArt {
                layer("plate")
                layer("emblem")
                    .offset(x: tilt.width * size * 0.02, y: tilt.height * size * 0.02)
                    .shadow(color: .black.opacity(0.35), radius: size * 0.03,
                            x: -tilt.width * size * 0.015, y: -tilt.height * size * 0.015 + size * 0.01)
                layer("highlight")
                    .offset(x: (sweep * 2 - 1) * size * 0.9)
                    .opacity(sweep > 0 ? 0.9 : 0.35)
                    .blendMode(.screen)
                    .mask(Circle().padding(size * 0.04))
            } else {
                Circle().fill(LSTheme.accent.opacity(0.16))
                Image(systemName: badge.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(LSTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func layer(_ name: String) -> some View {
        Image("Badges/\(badge.id)-\(name)")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}

/// The badge as it appears when it lands: it arrives small, settles, and the
/// highlight crosses it once.
struct EarnedBadgeArt: View {
    let badge: Badges.Definition
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: Double = 0
    @State private var scale: Double = 0.7

    var body: some View {
        BadgeArt(badge: badge, size: size, sweep: sweep)
            .scaleEffect(scale)
            .task {
                guard !reduceMotion else { scale = 1; return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { scale = 1 }
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeInOut(duration: 0.9)) { sweep = 1 }
            }
    }
}
