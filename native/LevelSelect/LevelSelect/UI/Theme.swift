import SwiftUI

/// The half of `LSTheme` that reads the user's settings.
///
/// The surfaces — background, card fills, hairlines — live in
/// `Shared/LSSurfaces.swift`, because the widget target compiles `Shared` and
/// not `UI`, and a theme the widgets cannot see is a theme with two
/// implementations. This extension adds the parts that need SwiftData, which
/// a widget has no business reaching for anyway.
extension LSTheme {
    /// The live accent — user's choice (synced) or the default purple.
    @MainActor
    static var accent: Color { ThemePalette.accent }

    /// What to draw on top of a filled accent surface. See
    /// `ThemePalette.onAccent` — chosen by contrast, because the accent is the
    /// user's and can be anything from pale yellow to near-black.
    @MainActor
    static var onAccent: Color { ThemePalette.onAccent }

    /// The accent a fresh install wears.
    ///
    /// Purple until 2026-09-01, and it was the wrong purple to put on this
    /// background: the app's ground is a dark purple, so the default accent
    /// was a lighter shade of the thing behind it and every tinted control
    /// sat closer to its backdrop than it should. Tim: "The purple doesn't
    /// have enough contrast on the dark purple background."
    ///
    /// Torch orange is already the brand's own colour -- it is what the
    /// wordmark has always been lit with -- and being the ground's
    /// complement rather than its neighbour, it separates from it at every
    /// size. Anyone who has chosen an accent keeps theirs; this is only what
    /// the app reaches for when nobody has said otherwise.
    static let defaultAccent = torch

    /// Darker torch, used as the hard drop shadow under pixel type.
    static let torchShadow = Color(red: 0.54, green: 0.29, blue: 0.07)

    /// Wordmark tint: the brand torch orange by default, following the user's
    /// accent once they've chosen one.
    @MainActor
    /// Always torch orange. The wordmark is the brand, not the theme.
    ///
    /// It used to follow a custom accent, on the same rule as `working` below.
    /// That rule is right for anything reading as *the app doing something*
    /// and wrong for the logotype: an app whose name changes colour with a
    /// preference has a name that means less each time it changes. Every other
    /// piece of chrome still follows the accent — this one stopped, so that
    /// there is one fixed point.
    static var wordmark: Color { torch }

    /// Anything that reads as the app *working* — the generation card's torch,
    /// its shimmer, its warning line. Same rule as the wordmark: brand orange
    /// until you pick an accent, your accent afterwards. Hard-coding `torch`
    /// here left a yellow-accented app with an orange progress card sitting in
    /// the middle of the tracker.
    @MainActor
    static var working: Color {
        ThemePalette.accentIsCustom ? ThemePalette.accent : torch
    }

    /// Display face: Press Start 2P (bundled, registered at launch). Use for
    /// wordmarks and small display moments only — never body text.
    static func pixel(_ size: CGFloat) -> Font {
        .custom("Press Start 2P", size: size)
    }
}

extension View {
    /// Full-bleed themed background.
    func lsBackground() -> some View {
        // A picked colour tints the ground rather than replacing it — see
        // LSTheme.ground(tintedBy:). Either way it is one gradient, so nothing
        // downstream has to ask which theme is on or whether one was chosen.
        background(LSTheme.ground(tintedBy: ThemePalette.backgroundOverride).ignoresSafeArea())
    }

    /// Card surface used across Stats/Home.
    func lsCard() -> some View {
        padding(14)
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LSTheme.hairline, lineWidth: 1))
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
        // Convex specular hotspot — reads as a glossy 3D surface catching light.
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(EllipticalGradient(colors: [.white.opacity(0.22), .clear],
                                         center: .init(x: 0.3, y: 0.18),
                                         startRadiusFraction: 0, endRadiusFraction: 0.6))
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
        // Grounding: a soft dark bottom edge gives the card thickness so it
        // reads as an object sitting on the surface, not a flat sticker.
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.22)],
                           startPoint: .center, endPoint: .bottom)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .blendMode(.multiply)
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
                // Slow, ~6.6s breath — clearly off the 1s tick so the mismatch
                // reads as an intentional ambient glow, not a stuttering clock.
                withAnimation(.easeInOut(duration: 3.3).repeatForever(autoreverses: true)) { on = true }
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
