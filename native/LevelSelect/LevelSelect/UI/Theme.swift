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
    /// The accent for large display type — see `ThemePalette.displayAccent`.
    @MainActor
    static var displayAccent: Color { ThemePalette.displayAccent }

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
    /// Torch orange is already the brand's own color -- it is what the
    /// wordmark has always been lit with -- and being the ground's
    /// complement rather than its neighbor, it separates from it at every
    /// size. Anyone who has chosen an accent keeps theirs; this is only what
    /// the app reaches for when nobody has said otherwise.
    /// Torch, dropped in value until it clears 4.5:1 on the light ground.
    ///
    /// Same hue and saturation, so light mode still reads as LevelSelect
    /// rather than a different product. Bright torch is 1.90:1 there — it
    /// misses even the 3:1 floor for glyphs — while this is 4.53:1.
    static let torchInk = Color(red: 0.60, green: 0.40, blue: 0.188)   // #996630

    /// The default accent, per appearance. Bright torch on dark, torch ink on
    /// light. There is no single value that works on both.
    static let defaultAccent: Color = .lsDynamic(light: torchInk, dark: torch)

    /// Darker torch, used as the hard drop shadow under pixel type.
    static let torchShadow = Color(red: 0.54, green: 0.29, blue: 0.07)

    /// Wordmark tint: the brand torch orange by default, following the user's
    /// accent once they've chosen one.
    @MainActor
    /// Always torch orange. The wordmark is the brand, not the theme.
    ///
    /// It used to follow a custom accent, on the same rule as `working` below.
    /// That rule is right for anything reading as *the app doing something*
    /// and wrong for the logotype: an app whose name changes color with a
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
        // A picked color tints the ground rather than replacing it — see
        // LSTheme.ground(tintedBy:). Either way it is one gradient, so nothing
        // downstream has to ask which theme is on or whether one was chosen.
        background(LSTheme.ground(lightTint: ThemePalette.backgroundOverrideLight,
                                  darkTint: ThemePalette.backgroundOverrideDark)
            .ignoresSafeArea())
    }

    /// A 44-point tap target, for a control with room to be one.
    ///
    /// **The glyph is not the target.** `PlatformEditor` said exactly that —
    /// "An 8pt glyph is a caption, not a target" — and then gave it a 22×22
    /// frame on the next line. The build 37 audit found at least 17 component
    /// families under 44 points.
    ///
    /// This grows the LAYOUT, which is right for a standalone control: a close
    /// button or a chevron should occupy 44 points. Use `lsTapTargetInline`
    /// where neighbors are close enough that growing would overlap them.
    func lsTapTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side).contentShape(.rect)
    }

    /// A bigger hit area that does NOT change layout, for a control in a
    /// crowded row.
    ///
    /// Padding out and back in leaves the frame where it was. Kept modest on
    /// purpose: `grow` is added on every side, so a 22-point control reaches
    /// 44 and a 30-point one reaches 52. Going further would make adjacent
    /// targets overlap, and a tap landing on the wrong control is worse than a
    /// small one — which is what a naive `side / 2` would have produced here.
    func lsTapTargetInline(_ grow: CGFloat = 11) -> some View {
        padding(grow).contentShape(.rect).padding(-grow)
    }

    /// Taller hit area only, for a control in a horizontal row.
    ///
    /// `lsTapTargetInline` grows on every side, which is right for a lone
    /// glyph and wrong for a row of chips: at 8 points of spacing, 11 points
    /// each side means neighbours overlap and the chip you did not aim at
    /// wins the tap. `RatingControl` reached the same conclusion about five
    /// stars in a row and solved it the same way — a tap landing on the wrong
    /// control is worse than a small one.
    ///
    /// Vertical is free in these rows, because nothing sits directly above or
    /// below a chip except the row's own padding. 8 points each side takes a
    /// 28-point chip to 44 without moving anything.
    /// `horizontal` grows sideways too, for a row whose gaps have room to
    /// spare. It must stay at or under HALF the spacing between neighbours or
    /// their targets overlap and the wrong one wins — the failure this whole
    /// family exists to avoid.
    func lsTapTargetTall(_ grow: CGFloat = 8, horizontal: CGFloat = 0) -> some View {
        padding(.vertical, grow)
            .padding(.horizontal, horizontal)
            .contentShape(.rect)
            .padding(.vertical, -grow)
            .padding(.horizontal, -horizontal)
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

extension View {
    /// A dark wash behind a toolbar glyph that has artwork under it.
    ///
    /// Liquid Glass takes its contrast from what is behind it, so over bright
    /// key art a toolbar button becomes a faint ring — present, and not
    /// findable. This puts something dark between the glyph and the picture so
    /// the ring has an edge to read against, and fades at its rim so it reads
    /// as part of the art treatment rather than as a plate bolted to the bar.
    ///
    /// Deliberately soft: strong enough to rescue a control on white key art,
    /// weak enough to be invisible on the dark art that never needed it.
    func lsToolbarScrim(over hasArt: Bool) -> some View {
        shadow(color: .black.opacity(hasArt ? 0.5 : 0), radius: 3, y: 1)
            .background {
                if hasArt {
                    Circle()
                        .fill(RadialGradient(
                            colors: [.black.opacity(0.34), .black.opacity(0)],
                            center: .center, startRadius: 1, endRadius: 20))
                        .frame(width: 40, height: 40)
                        .allowsHitTesting(false)
                }
            }
    }
}
