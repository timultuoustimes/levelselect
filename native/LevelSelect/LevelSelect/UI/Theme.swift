import SwiftUI

/// LevelSelect visual identity: purple primary + dark gradient surfaces,
/// matching the web app's look (Tim: "purple as the main color, and I like
/// the gradients").
enum LSTheme {
    static let purple = Color(red: 0.58, green: 0.36, blue: 0.98)   // brand default accent
    static let purpleDeep = Color(red: 0.30, green: 0.16, blue: 0.55)

    /// The live accent — user's choice (synced) or the default purple.
    @MainActor
    static var accent: Color { ThemePalette.accent }

    /// App background: near-black with a purple cast at the top.
    static var background: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.07, blue: 0.18),
                Color(red: 0.05, green: 0.04, blue: 0.09),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Hero card gradient (Continue Playing).
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [purpleDeep.opacity(0.85), Color(red: 0.12, green: 0.08, blue: 0.22)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// Subtle card surface on the dark background.
    static var cardFill: Color { .white.opacity(0.06) }

    /// Torch orange from the dungeon-door icon/wordmark artwork.
    static let torch = Color(red: 0.96, green: 0.64, blue: 0.30)

    /// Display face: Press Start 2P (bundled, registered at launch). Use for
    /// wordmarks and small display moments only — never body text.
    static func pixel(_ size: CGFloat) -> Font {
        .custom("Press Start 2P", size: size)
    }
}

extension View {
    /// Full-bleed themed background.
    func lsBackground() -> some View {
        background(LSTheme.background.ignoresSafeArea())
    }

    /// Card surface used across Stats/Home.
    func lsCard() -> some View {
        padding(14)
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }

    /// Glassy sheen for box art — a soft top-left highlight + a bright top
    /// hairline, giving covers the soft-3D "diamorphic" look. Cheap (static),
    /// so it's safe to apply to every cover.
    func coverGloss(cornerRadius: CGFloat = 6) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.32), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.30),
                        .init(color: .clear, location: 0.58),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.45), .white.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

/// A one-shot diagonal "shine" that sweeps across a cover when it appears —
/// the little bit of life Tim wanted on the box art. Respects Reduce Motion.
struct CoverShine: View {
    var delay: Double = 0.35
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.35), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: w * 0.45)
                .rotationEffect(.degrees(22))
                .offset(x: phase * w)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).delay(delay)) { phase = 1.4 }
        }
    }
}

/// A soft breathing glow behind the live session timer — signals "recording"
/// without a distracting blink. Respects Reduce Motion (holds a steady glow).
struct LivePulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .fill(LSTheme.accent)
            .frame(width: 130, height: 130)
            .blur(radius: 42)
            .opacity(on ? 0.34 : 0.14)
            .scaleEffect(on ? 1.08 : 0.9)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Springy pressed state for tappable cards ("fluid buttons" — everything
/// moves, nothing snaps). Honors Reduce Motion by keeping the scale subtle.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Tap wrapper that ALWAYS bounces — even on a quick tap inside a scroll view
/// (where the system delays touch-down, so ButtonStyle press states never
/// show). Plays a light haptic, dips with a spring, then fires the action.
struct BouncyTap<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { pressed = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { pressed = false }
                action()
            }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.92 : 1)
        .sensoryFeedback(.impact(weight: .light), trigger: pressed) { _, new in new }
    }
}
