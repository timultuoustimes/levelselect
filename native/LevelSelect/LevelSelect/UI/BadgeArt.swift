import SwiftUI

/// **A badge, drawn in layers, lit the way the covers are.**
///
/// Codex draws each badge as a plate and an emblem on one 1024 canvas
/// (`assets/achievements/<slug>/final`). Stacking them rather than shipping
/// one flat picture is what lets the emblem lift off the plate as the badge
/// tilts. Generated placeholder art — the vault's artwork spec has the brief
/// for a commissioned set, which would drop into the same slots.
///
/// **The light is `CoverShine`, not a drawn layer.** The highlight PNG was
/// slid back and forth across the plate, which read as a scrubbed slider
/// rather than a catch of light (Tim, 09-21: *"weirdly moves back and
/// forth"*). Box art already has the right answer: one tilted band sweeping
/// across once. Badges use the same one, so a badge and a cover are lit by
/// the same room.
///
/// A badge with no art falls back to its SF Symbol, so the catalogue can grow
/// faster than the drawing does.
struct BadgeArt: View {
    let badge: Badges.Definition
    var size: CGFloat = 96
    /// Sweep the light across when this changes — the earn moment, or a tap.
    var shineTrigger: Int = 0
    /// Repeat the sweep on a slow loop, for a badge sitting on screen.
    var shimmers: Bool = false
    /// Staggers the loop so a list doesn't flash in unison.
    var phase: Double = 0
    /// How far the emblem lifts off the plate, -1...1 on each axis.
    var tilt: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loop = 0

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
                            x: -tilt.width * size * 0.015,
                            y: -tilt.height * size * 0.015 + size * 0.01)
            } else {
                Circle().fill(LSTheme.accent.opacity(0.16))
                Image(systemName: badge.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(LSTheme.accent)
            }
        }
        .frame(width: size, height: size)
        // The same shine the box art gets, clipped to the badge's own disc.
        .overlay {
            CoverShine(delay: 0)
                .id(shineTrigger + loop)
                .mask(Circle().padding(size * 0.03))
        }
        .task(id: shimmers) {
            guard shimmers, !reduceMotion else { return }
            // Staggered, so a list of badges catches the light in turn rather
            // than all at once.
            try? await Task.sleep(for: .seconds(phase))
            while !Task.isCancelled {
                loop += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
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
