import SwiftUI

/// **The moment a badge lands.**
///
/// Confetti over whatever you were looking at, and a toast naming what you
/// earned — not a screen that takes over, because the badge is a remark about
/// what you just did rather than an interruption of it (spec, 09-21).
///
/// Reduce Motion gets the toast without the confetti. The setting exists for
/// people who feel unwell watching things fly around, and a celebration is
/// exactly the kind of flourish it means.
struct BadgeToast: View {
    let badges: [Badges.Definition]
    var open: () -> Void
    var dismiss: () -> Void

    private var lead: Badges.Definition? { badges.first }

    var body: some View {
        HStack(spacing: 12) {
            if let lead {
                EarnedBadgeArt(badge: lead, size: 46)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(badges.count == 1 ? "Badge earned" : "\(badges.count) badges earned")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(badges.count == 1 ? (lead?.title ?? "") : badges.map(\.title).joined(separator: " · "))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("See") { open() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(LSTheme.accent)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Opaque, like the undo toast: `cardFill` is translucent, so over a
        // game page the words behind it read straight through (Tim, 09-21).
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(LSTheme.cardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(LSTheme.accent.opacity(0.35)))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// Paper, thrown once.
///
/// Drawn with `Canvas` and a single `TimelineView` rather than a stack of
/// animated views: a hundred pieces as SwiftUI views is a hundred nodes the
/// layout system walks every frame, and this is a decoration that must not
/// cost the screen underneath anything.
struct ConfettiBurst: View {
    /// Restarts the burst when it changes. Zero means nothing has happened
    /// yet, so nothing is drawn — the view can sit in an overlay all day.
    let trigger: Int
    var duration: Double = 2.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// **A box, not a `@State Date?`.**
    ///
    /// `Canvas`'s renderer closure is captured once and kept; it does not see
    /// later values of a `@State` property the way a re-evaluated `body`
    /// would. With the date in `@State`, every single frame read `nil`,
    /// elapsed time was always zero, and no paper was ever drawn even though
    /// the clock had been set (09-21). A reference the closure holds is read
    /// fresh each frame.
    ///
    /// Nil until a burst is asked for. `onAppear` used to set this, which
    /// meant the paper flew every time you opened the screen (Tim, 09-21).
    @State private var clock = Clock()

    private final class Clock { var startedAt: Date? }

    private struct Piece {
        let x: Double          // 0...1 of the width
        let drift: Double      // sideways travel
        let delay: Double      // 0...1 of the burst
        let speed: Double      // how much of the burst this piece takes
        let rise: Double       // how high it is thrown
        let spin: Double
        let size: Double
        let hue: Color
    }

    private static let pieces: [Piece] = (0..<140).map { i in
        var generator = SeededRandom(seed: UInt64(i &* 2654435761))
        return Piece(x: generator.next(),
                     drift: generator.next() * 0.7 - 0.35,
                     // **Spread, speed and height all vary.** With one shared
                     // arc and a delay of under half a second, all 140 pieces
                     // rose in lockstep and read as a solid colored band
                     // sliding up the screen rather than thrown paper (09-21).
                     delay: generator.next() * 0.35,
                     speed: 0.7 + generator.next() * 0.55,
                     rise: 0.75 + generator.next() * 0.6,
                     spin: generator.next() * 8 - 4,
                     // Paper you can see from across the room: the first pass
                     // was 5-12pt and read as dust in the middle of the screen.
                     size: 14 + generator.next() * 16,
                     hue: [LSTheme.accent, .orange, .yellow, .pink, .mint, .cyan][i % 6])
    }

    /// How long the burst really lasts, in multiples of `duration`: the last
    /// piece to start, plus the time the slowest one takes to fall.
    private static let span = pieces.map { $0.delay + $0.speed }.max() ?? 1

    var body: some View {
        if trigger == 0 {
            EmptyView()
        } else if reduceMotion {
            // **The setting means less movement, not less occasion.** Paper
            // flying across the screen is exactly the flourish Reduce Motion
            // is asking about, so it gets the accent washing over the screen
            // once instead — a moment with nothing traveling in it.
            ReduceMotionGlow(trigger: trigger)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    guard let started = clock.startedAt else { return }
                    let t = timeline.date.timeIntervalSince(started)
                    // `span`, not `duration`: a late, slow piece is still in
                    // the air well after the nominal end, and stopping at
                    // `duration` clipped the stragglers mid-flight.
                    guard t < duration * Self.span else { return }
                    for piece in Self.pieces {
                        let local = t - piece.delay * duration
                        guard local > 0 else { continue }
                        let progress = local / (duration * piece.speed)
                        guard progress <= 1 else { continue }
                        // Thrown from below the bottom edge, up over the whole
                        // screen, then down past it.
                        let rise = sin(progress * .pi) * size.height * 1.15 * piece.rise
                        let y = size.height * 1.05 - rise + progress * progress * size.height * 0.85
                        let x = size.width * (piece.x + piece.drift * progress)
                        let fade = progress > 0.75 ? (1 - progress) / 0.25 : 1
                        // `drawLayer`, not a copied context: mutating a copy of
                        // `GraphicsContext` and filling into it draws nothing.
                        context.drawLayer { layer in
                            layer.opacity = fade
                            layer.translateBy(x: x, y: y)
                            layer.rotate(by: .radians(piece.spin * local))
                            layer.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 2,
                                                   width: piece.size, height: piece.size * 0.6)),
                                       with: .color(piece.hue))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            // **Keyed on the trigger.** This view is built while the trigger
            // is still zero, so a start time set at creation was already in
            // the past by the time the burst appeared — every frame counted as
            // "after the end" and no paper was ever drawn (09-21).
            .task(id: trigger) { clock.startedAt = .now }
        }
    }
}

/// What a celebration looks like with Reduce Motion on: the accent gathers at
/// the edges, holds for a moment, and goes. It fades rather than moves, which
/// is the distinction the setting actually draws.
private struct ReduceMotionGlow: View {
    let trigger: Int
    @State private var lit = false

    var body: some View {
        RadialGradient(colors: [.clear, LSTheme.accent.opacity(0.42)],
                       center: .center, startRadius: 90, endRadius: 520)
            .ignoresSafeArea()
            .opacity(lit ? 1 : 0)
            .allowsHitTesting(false)
            .task(id: trigger) {
                withAnimation(.easeOut(duration: 0.45)) { lit = true }
                try? await Task.sleep(for: .seconds(1.1))
                withAnimation(.easeIn(duration: 0.7)) { lit = false }
            }
    }
}

/// Deterministic, so the confetti falls the same way every time and a test
/// of the layout is not a test of luck.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B9 : seed }
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}
