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
    /// **The accent as a fill**, with `knockout(on:)` as its ink — the raw
    /// chosen color, never legibility-corrected, because a filled control
    /// does not read against the ground the way text does. `accent` stays
    /// the corrected value for the places that draw it as ink.
    @MainActor static var accentFill: Color { ThemePalette.displayAccent }
    /// The hard step under pixel type in the accent; the accent's ink on the
    /// light ground. See `LSPalette`.
    @MainActor static var accentStep: Color { ThemePalette.accentStep }

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

extension LSTheme {
    /// The ground as chosen — the tinted gradient every page stands on.
    /// `background` (Shared) is the untinted default the widgets use; a page
    /// in the app should stand on THIS, or a chosen ground stops at Home.
    @MainActor
    static var liveGround: LinearGradient {
        ground(lightTint: ThemePalette.backgroundOverrideLight,
               darkTint: ThemePalette.backgroundOverrideDark)
    }

    /// The chosen ground, for a surface whose height changes — see
    /// `sheetGround`. Every settings page and picker stands on this.
    @MainActor
    static var liveSheetGround: LinearGradient {
        sheetGround(lightTint: ThemePalette.backgroundOverrideLight,
                    darkTint: ThemePalette.backgroundOverrideDark)
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

    /// A text field that belongs to this app rather than to the system.
    ///
    /// `.roundedBorder` draws a near-black filled rectangle in dark mode. On a
    /// white sheet that is a bordered field; on LevelSelect's purple it is a
    /// hole. Tim caught it on the video paste box first (iPad, 09-18) and
    /// again on the game page's Notes (09-21), and it was still on eight
    /// fields besides — every one of them standing on a themed pane.
    ///
    /// Use it wherever a field sits on `lsBackground()`. Inside a `Form`,
    /// leave the system style alone: there the field is a row, not a box.
    func lsField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(LSTheme.cardFill, in: .rect(cornerRadius: 10))
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
            // A glow is a fill, so it wears the accent as picked rather than
            // the ink the light ground darkens it to.
            .fill(LSTheme.accentFill)
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

// MARK: - Play controls

/// **The weight a play control presses with.**
///
/// Tim, 2026-09-09: *"can there be a big haptic and pressing animation when
/// you press play, and a bit less when you hit pause and stop. I can't tell
/// when I'm hitting them."* — and there was nothing to tell him. Every one of
/// these controls is a `.plain` button with a background painted behind it,
/// so pressing one dimmed it a little and that was all; Start Session had the
/// app's own press-onto-its-step and still said nothing to the hand.
///
/// Two weights, because they are two kinds of act. Sitting down to play is
/// the event the app exists for and gets the heavy thump; pausing and
/// stopping are housekeeping and get a light one, so a thumb can tell them
/// apart without looking. Logging a session by hand is neither — nothing
/// starts, a record is filed — so it gets the success notification.
enum LSPlayFeedback: Equatable {
    case play, housekeeping, logged

    var sensory: SensoryFeedback {
        switch self {
        case .play:         .impact(weight: .heavy, intensity: 1)
        case .housekeeping: .impact(weight: .light, intensity: 0.7)
        case .logged:       .success
        }
    }
}

/// A press you can feel and see, over whatever the control already wears.
///
/// Every play control in the app is a `.plain` button with its own
/// `.background` — a filled square on the hero, a tinted rounded rect in the
/// timers strip, a circle on the stage — so a style that DREW something would
/// have to re-create four looks that are already right. This one draws
/// nothing and only moves, and it fires on touch-DOWN rather than on the
/// action, because that is the moment the finger is asking whether it landed.
struct LSPlayButtonStyle: ButtonStyle {
    var feedback: LSPlayFeedback = .play
    /// How the control moves under a finger.
    ///
    /// **`key` is `LSPrimaryButtonStyle`'s motion, exactly**: down 2pt over
    /// 0.08s while the hard step beneath shrinks, so the cap sinks into its
    /// own shadow like a keyboard key. It is for the controls that HAVE a
    /// step to sink into — the hero's Play, which sits on one.
    ///
    /// `lift` is the scale dip, for the small round pause and stop controls.
    /// They carry no step, and 2pt of travel on a 30pt circle with nothing
    /// under it reads as a glitch rather than a press.
    var press: Press = .lift

    enum Press { case lift, key }

    /// Play dips further than the housekeeping — the same "bigger for play"
    /// the haptic says, in the other sense.
    private var dip: CGFloat { feedback == .play ? 0.88 : 0.93 }

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        return configuration.label
            // The decoration draws the step, so it is the only thing that can
            // collapse it. See `EnvironmentValues.lsKeyPressed`.
            .environment(\.lsKeyPressed, press == .key && down)
            .scaleEffect(press == .lift && down ? dip : 1)
            .opacity(press == .lift && down ? 0.85 : 1)
            .offset(y: press == .key && down ? 2 : 0)
            .animation(press == .key ? .easeOut(duration: 0.08)
                                     : .spring(response: 0.22, dampingFraction: 0.55),
                       value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, isDown in
                isDown ? feedback.sensory : nil
            }
    }
}

/// A play control's press, as something `.sensoryFeedback` can watch.
///
/// The controls that keep a SYSTEM button style — `.bordered` already draws a
/// press, it just never said anything — cannot take `LSPlayButtonStyle`, and
/// a haptic needs a value that changes to fire on. So the tap bumps this and
/// names its weight in the same move.
struct LSPlayPulse: Equatable {
    private(set) var count = 0
    private(set) var feedback: LSPlayFeedback = .play

    mutating func fire(_ feedback: LSPlayFeedback) {
        self.feedback = feedback
        count += 1
    }
}

extension View {
    /// Plays whatever the pulse last named, every time it is bumped.
    func lsPlayFeedback(_ pulse: LSPlayPulse) -> some View {
        sensoryFeedback(trigger: pulse) { _, now in now.feedback.sensory }
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
        modifier(LSToolbarScrim(hasArt: hasArt))
    }
}

/// The scrim, weighed per appearance. In dark mode a 0.5 shadow under the
/// glyph vanishes into the art; in light mode the same shadow sat under the
/// glass ring as a gray smear — Tim, 09-08: *"shadow under the ellipses menu
/// is currently very weird looking on light mode."* Light gets a quarter
/// of it, which still separates the ring from bright art.
private struct LSToolbarScrim: ViewModifier {
    let hasArt: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .shadow(color: .black.opacity(hasArt ? (dark ? 0.5 : 0.12) : 0),
                    radius: dark ? 3 : 1.5, y: 1)
            .background {
                if hasArt {
                    Circle()
                        .fill(RadialGradient(
                            colors: [.black.opacity(dark ? 0.34 : 0.14), .black.opacity(0)],
                            center: .center, startRadius: 1, endRadius: 20))
                        .frame(width: 40, height: 40)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// **The primary button, as Tim drew it.** The accent as the fill, the
/// pair's step as the ink AND as a hard edge along the bottom — a pixel-art
/// object standing on its own shadow, not a glass pill. Tim, 09-08: *"I also
/// prefer how my buttons look, and they should be like that throughout the
/// app. I think to start, at the very least, change the Play button to match.
/// right now it's still white text when in light mode."*
///
/// Bold, not semibold: SF Pro is the app's face for everything but the
/// wordmark, and the sheet was set in SF Pro Display Bold.
struct LSPrimaryButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(LSTheme.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LSTheme.accentFill)
                    .shadow(color: LSTheme.accentStep, radius: 0, y: configuration.isPressed ? 1 : 3)
            }
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
