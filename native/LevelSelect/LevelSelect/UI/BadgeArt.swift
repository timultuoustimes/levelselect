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
    /// Keep the light moving, the way a cover catches it as you scroll past.
    /// Every badge on a list does this; one badge, alone and still, reads as
    /// a sticker (Tim, 09-21).
    var shimmers: Bool = false
    /// Staggers the loop so a list doesn't flash in unison.
    var phase: Double = 0
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
        Group {
            if shimmers && !reduceMotion {
                TimelineView(.animation) { timeline in
                    // One pass every six seconds, most of it spent off the
                    // plate: a slow catch of light, not a strobe.
                    let t = timeline.date.timeIntervalSinceReferenceDate / 6 + phase
                    stack(sweep: max(sweep, t - floor(t)))
                }
            } else {
                stack(sweep: sweep)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    private func stack(sweep: Double) -> some View {
        ZStack {
            if hasArt {
                layer("plate")
                layer("emblem")
                    .offset(x: tilt.width * size * 0.02, y: tilt.height * size * 0.02)
                    .shadow(color: .black.opacity(0.35), radius: size * 0.03,
                            x: -tilt.width * size * 0.015, y: -tilt.height * size * 0.015 + size * 0.01)
                // At rest the highlight sits where it was drawn — it is part
                // of the badge's own shading. A sweep drives it across and
                // back; it never parks off the plate (Tim, 09-21: "no
                // highlight animation on it").
                layer("highlight")
                    .offset(x: sweepOffset(sweep))
                    .opacity(sweep > 0 && sweep < 1 ? 1 : 0.55)
                    .blendMode(.screen)
                    .mask(Circle().padding(size * 0.04))
            } else {
                Circle().fill(LSTheme.accent.opacity(0.16))
                Image(systemName: badge.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(LSTheme.accent)
            }
        }
    }

    /// 0 and 1 both mean "at rest, where it was drawn"; the middle of the
    /// animation is what carries it across the face.
    private func sweepOffset(_ sweep: Double) -> CGFloat {
        guard sweep > 0, sweep < 1 else { return 0 }
        return CGFloat(sin(sweep * .pi * 2)) * size * 0.75
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
