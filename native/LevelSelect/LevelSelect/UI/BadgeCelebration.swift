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
            ZStack {
                Circle().fill(LSTheme.accent.opacity(0.18)).frame(width: 42, height: 42)
                Image(systemName: lead?.symbol ?? "rosette")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(LSTheme.accent)
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
        .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LSTheme.accent.opacity(0.35)))
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
    /// Restarts the burst when it changes.
    let trigger: Int
    var duration: Double = 1.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now

    private struct Piece {
        let x: Double          // 0...1 of the width
        let drift: Double      // sideways travel
        let delay: Double
        let spin: Double
        let size: Double
        let hue: Color
    }

    private static let pieces: [Piece] = (0..<90).map { i in
        var generator = SeededRandom(seed: UInt64(i &* 2654435761))
        return Piece(x: generator.next(),
                     drift: generator.next() * 0.5 - 0.25,
                     delay: generator.next() * 0.35,
                     spin: generator.next() * 8 - 4,
                     size: 5 + generator.next() * 7,
                     hue: [LSTheme.accent, .orange, .yellow, .pink, .mint, .cyan][i % 6])
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSince(startedAt)
                    guard t < duration else { return }
                    for piece in Self.pieces {
                        let local = t - piece.delay
                        guard local > 0 else { continue }
                        let progress = local / (duration - piece.delay)
                        guard progress <= 1 else { continue }
                        // Up, then down — a throw, not a fall.
                        let rise = sin(min(progress, 1) * .pi) * size.height * 0.45
                        let y = size.height * 0.62 - rise + progress * progress * size.height * 0.5
                        let x = size.width * (piece.x + piece.drift * progress)
                        let fade = progress > 0.75 ? (1 - progress) / 0.25 : 1
                        var rect = context
                        rect.translateBy(x: x, y: y)
                        rect.rotate(by: .radians(piece.spin * local))
                        rect.opacity = fade
                        rect.fill(Path(CGRect(x: -piece.size / 2, y: -piece.size / 2,
                                              width: piece.size, height: piece.size * 0.6)),
                                  with: .color(piece.hue))
                    }
                }
                .allowsHitTesting(false)
            }
            .onChange(of: trigger) { startedAt = .now }
            .onAppear { startedAt = .now }
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
