import SwiftUI

/// The app's surfaces, and the only place that knows what "light" means.
///
/// **Why this lives in `Shared/` rather than `UI/`.** The widget target
/// compiles `Widgets` + `Shared` and *not* `LevelSelect/UI`, so `LSTheme` was
/// invisible to widgets — which is why roughly sixty hardcoded colors grew
/// there independently. A light theme built only in `UI/` would have left the
/// widgets dark, so the surfaces move to where both targets can see them.
///
/// `LSTheme` is declared here and *extended* in `UI/Theme.swift` with the
/// parts that read the user's settings out of SwiftData. Within the app both
/// halves compile into one type; a widget gets only this half, which is
/// exactly what it can support.
///
/// **What is deliberately NOT here:** cover art, console icons and
/// `coverGloss`. Tim, looking at the TurboGrafx render on white: *"Game art
/// carries across theme… Consoles are the colors of the consoles, and look
/// good on anything I've seen behind them, including just a light gray."*
/// Artwork is artwork on any ground.
enum LSTheme {
    static let purple = Color(red: 0.58, green: 0.36, blue: 0.98)
    static let purpleDeep = Color(red: 0.30, green: 0.16, blue: 0.55)

    /// Torch orange from the dungeon-door icon/wordmark artwork.
    static let torch = Color(red: 0.96, green: 0.64, blue: 0.30)

    // MARK: The ground

    /// App background: a wash from a lighter top to a darker bottom.
    ///
    /// The light range is deliberately wider than the first attempt at it,
    /// which read as flat. Tim: *"Light mode should carry over the same
    /// gradient style that dark mode had. It's slight, but there."* Dark can
    /// halve its luminance across the drop and stay handsome; light has less
    /// room before it goes muddy, so it travels less — but it has to travel.
    static var background: LinearGradient { ground(tintedBy: nil) }

    /// The ground, optionally wearing a color the user picked.
    ///
    /// **The tint supplies hue and saturation; the theme keeps luminance.**
    /// That is the whole safety property. A background is the one surface
    /// where a bad choice makes text unreadable, and letting someone drop a
    /// near-black into Light mode would do exactly that — dark ground, dark
    /// text, nothing legible, no warning. Taking only the *color* of their
    /// choice means the app is still recognizably theirs and cannot be made
    /// unreadable by picking wrong.
    ///
    /// It also matches what the default already is. The shipped gradient is
    /// not two colors; it is one hue at two brightnesses — so deriving the
    /// second stop reproduces the look that was already tuned, rather than
    /// inventing a new one.
    /// - Parameter scheme: nil resolves per the environment. **A widget must
    ///   pass one explicitly**: WidgetKit hoists `containerBackground` out of
    ///   the view's environment, so a dynamic color there never sees a
    ///   `.environment(\.colorScheme,)` override and resolves against the
    ///   system instead. That produced the exact bug it looks like — a Light
    ///   app on a Dark phone drawing dark-mode ground under light-mode text.
    /// One tint for both appearances — the widget and preview path, where only
    /// a single stored color is available.
    static func ground(tintedBy tint: Color?, scheme: ColorScheme? = nil) -> LinearGradient {
        ground(lightTint: tint, darkTint: tint, scheme: scheme)
    }

    /// A tint per appearance. Build 37.
    ///
    /// The app stores light and dark grounds separately, because a color that
    /// reads on one is rarely the color you want on the other — the same
    /// reason the accent is now a pair. Each branch shades from its OWN hue,
    /// so a warm light ground and a cool dark one do not have to compromise.
    static func ground(lightTint: Color?, darkTint: Color?,
                       scheme: ColorScheme? = nil) -> LinearGradient {
        let lightHue = lightTint?.lsHueSaturation
        let darkHue = darkTint?.lsHueSaturation
        func pick(_ light: Color, _ dark: Color) -> Color {
            switch scheme {
            case .light: light
            case .dark:  dark
            default:     .lsDynamic(light: light, dark: dark)
            }
        }
        return LinearGradient(
            colors: [
                pick(shade(lightHue, brightness: 0.97, saturation: 0.06,
                           fallback: Color(red: 0.97, green: 0.96, blue: 1.00)),
                     shade(darkHue, brightness: 0.16, saturation: 0.55,
                           fallback: Color(red: 0.10, green: 0.07, blue: 0.18))),
                pick(shade(lightHue, brightness: 0.88, saturation: 0.10,
                           fallback: Color(red: 0.88, green: 0.86, blue: 0.94)),
                     shade(darkHue, brightness: 0.07, saturation: 0.60,
                           fallback: Color(red: 0.05, green: 0.04, blue: 0.09))),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// One stop: the picked hue at the brightness this theme allows, or the
    /// built-in color when nothing was picked.
    private static func shade(_ hue: (hue: Double, saturation: Double)?,
                              brightness: Double,
                              saturation: Double,
                              fallback: Color) -> Color {
        guard let hue else { return fallback }
        // A gray pick has no hue worth keeping — honor it as gray rather
        // than snapping to whatever arbitrary hue the picker reported.
        let sat = hue.saturation < 0.05 ? 0 : saturation
        return Color(hue: hue.hue, saturation: sat, brightness: brightness)
    }

    // MARK: Derived accent

    /// Where each appearance starts looking, before contrast is considered.
    ///
    /// These are the brightnesses the shipped defaults already use — torch is
    /// 0.96 on dark and torch ink is 0.60 on light — so a hue that behaves
    /// like torch lands exactly where it does today and nothing moves.
    static let preferredAccentBrightness = (light: 0.60, dark: 0.96)

    /// A stored color, made legible on the ground it will be read on.
    ///
    /// **This is what makes accent-as-ink safe everywhere**, and it is why the
    /// 59 sites that use the accent as a foreground did not have to be swept
    /// to semantic colors. A color chosen through the picker already clears
    /// the floor — the picker refuses anything that does not. What this catches
    /// is the LEGACY value: an accent stored before build 37 was never checked
    /// against anything, and the developer's own `#8A5CF6` sits at 4.22:1 on
    /// the dark ground.
    ///
    /// A passing color is returned untouched, so nothing moves for anyone
    /// whose accent was already fine. A failing one is re-derived from its own
    /// hue and saturation, which keeps the color recognizably theirs rather
    /// than replacing it with a default.
    static func legible(_ color: Color, on ground: Color, floor: Double = 4.5) -> Color {
        if LSContrast.ratio(color, ground) >= floor { return color }
        guard let hs = color.lsHueSaturation else { return color }
        return derivedAccent(hue: hs.hue, saturation: hs.saturation,
                             dark: LSContrast.luminance(of: ground) < 0.18,
                             ground: ground, floor: floor).color
    }

    /// A derived accent, and whether the app had to compromise to get there.
    struct DerivedAccent {
        let color: Color
        /// The saturation actually used.
        let saturation: Double
        /// What the user asked for.
        let requested: Double
        /// True when brightness alone could not reach the floor and saturation
        /// had to come down. The picker says so when this is set — a silent
        /// compromise is the thing this whole model exists to avoid.
        var softened: Bool { saturation < requested - 0.005 }
    }

    /// The accent for one appearance, derived from a hue the user picked.
    ///
    /// **The user sets hue and saturation; the app derives brightness.** Tim,
    /// 2026-09-04 — one fewer thing moving on its own.
    ///
    /// Brightness alone cannot always get there, and the failure is not
    /// uniform. Testing every hue found that **light solves everywhere, and
    /// dark cannot solve saturated blues and violets** — hue 0.61–0.78 at
    /// saturation ≥ 0.75. Blue contributes 0.0722 to relative luminance
    /// against green's 0.7152, so a saturated blue at FULL brightness is still
    /// luminance-dark and nothing reaches 4.5:1 on a dark ground.
    ///
    /// So saturation is a last resort, not a second dial: it is honored
    /// whenever brightness can do the job, and softened only where physics
    /// forbids otherwise — with `softened` set so the UI can say it happened.
    /// Tim chose this over hard-restricting the region: *"Go with softening
    /// saturation and telling me when it happens."*
    static func derivedAccent(hue: Double,
                              saturation: Double,
                              dark: Bool,
                              ground: Color,
                              floor: Double = 4.5) -> DerivedAccent {
        // Honor the chosen saturation if any brightness works at it.
        if let color = solveBrightness(hue: hue, saturation: saturation,
                                       dark: dark, ground: ground, floor: floor) {
            return DerivedAccent(color: color, saturation: saturation, requested: saturation)
        }
        // Otherwise walk saturation down until the hue can be seen at all.
        var candidate = saturation
        while candidate > 0 {
            candidate = max(0, candidate - 0.02)
            if let color = solveBrightness(hue: hue, saturation: candidate,
                                           dark: dark, ground: ground, floor: floor) {
                return DerivedAccent(color: color, saturation: candidate, requested: saturation)
            }
        }
        // Gray at this brightness always clears a themed ground, so this is
        // unreachable in practice; returning the honest last try beats a crash.
        let fallback = Color(hue: hue, saturation: 0,
                             brightness: dark ? 1 : preferredAccentBrightness.light)
        return DerivedAccent(color: fallback, saturation: 0, requested: saturation)
    }

    /// The brightness search, at a fixed saturation. Nil when none passes.
    ///
    /// Starts at the brightness each appearance prefers — the values the
    /// shipped defaults already use — and walks toward more contrast only if
    /// it has to. Contrast rises as a color brightens on a dark ground and
    /// darkens on a light one, so the walk goes opposite ways; this is not a
    /// symmetric formula and should not be "simplified" into one.
    private static func solveBrightness(hue: Double, saturation: Double,
                                        dark: Bool, ground: Color,
                                        floor: Double) -> Color? {
        let start = dark ? preferredAccentBrightness.dark : preferredAccentBrightness.light
        let step = dark ? 0.01 : -0.01
        var brightness = start
        // From the preferred value toward more contrast.
        while brightness >= 0, brightness <= 1 {
            let candidate = Color(hue: hue, saturation: saturation, brightness: brightness)
            if LSContrast.ratio(candidate, ground) >= floor { return candidate }
            brightness += step
        }
        // Then the other way, for a preferred value that overshot.
        brightness = start
        while brightness >= 0, brightness <= 1 {
            let candidate = Color(hue: hue, saturation: saturation, brightness: brightness)
            if LSContrast.ratio(candidate, ground) >= floor { return candidate }
            brightness -= step
        }
        return nil
    }

    /// Hero card gradient (Continue Playing).
    static var heroGradient: LinearGradient { hero(tintedBy: nil) }

    /// The hero, wearing the same color the ground does.
    ///
    /// It is the ground's own hue lifted off it — brighter than the ground in
    /// the dark theme, deeper in the light one, because "raised" points in
    /// opposite directions depending on which way the ground goes. Leaving it
    /// fixed while the ground moved made the most prominent card on Home the
    /// one thing that ignored your color.
    static func hero(tintedBy tint: Color?) -> LinearGradient {
        let hue = tint?.lsHueSaturation
        return LinearGradient(
            colors: [
                .lsDynamic(light: shade(hue, brightness: 0.93, saturation: 0.20,
                                        fallback: purple.opacity(0.20)),
                           dark:  shade(hue, brightness: 0.24, saturation: 0.55,
                                        fallback: purpleDeep.opacity(0.85))),
                .lsDynamic(light: shade(hue, brightness: 0.89, saturation: 0.26,
                                        fallback: purple.opacity(0.08)),
                           dark:  shade(hue, brightness: 0.15, saturation: 0.60,
                                        fallback: Color(red: 0.12, green: 0.08, blue: 0.22))),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: Surfaces raised off the ground
    //
    // These were `.white.opacity(…)` everywhere, which is not a color so much
    // as an instruction: *lighten whatever is behind you*. On a light ground
    // that instruction is backwards — a card lifted off white has to go
    // darker — so each one becomes a token that knows which way "up" is.

    /// A card sitting on the ground.
    static var cardFill: Color {
        .lsDynamic(light: .black.opacity(0.04), dark: .white.opacity(0.06))
    }

    /// A card sitting on another card.
    static var elevatedFill: Color {
        .lsDynamic(light: .black.opacity(0.07), dark: .white.opacity(0.10))
    }

    /// The one-pixel edge that gives a card its shape.
    static var hairline: Color {
        .lsDynamic(light: .black.opacity(0.10), dark: .white.opacity(0.07))
    }

    /// A divider between rows.
    static var separator: Color {
        .lsDynamic(light: .black.opacity(0.08), dark: .white.opacity(0.09))
    }

    /// The hard step under a pixel-art glyph or object.
    ///
    /// **The amount has to change with the ground, because darkening has no
    /// headroom on a dark one.** A step 55% toward black measures 10.9:1
    /// against the light ground and 1.5:1 against the dark one — the same
    /// color, disappearing into the exact background it exists to stand out
    /// from. Going *darker* makes it worse, not better: at 70% it is 1.2:1 and
    /// at 85% it is 1.0:1, because the ground is already near black and there
    /// is nowhere below it to go.
    ///
    /// So on dark the step is a *lighter* shade than on light. It stays much
    /// darker than the object and ends up lighter than the ground behind it,
    /// which is how pixel art has always shaded a sprite: the shadow belongs
    /// to the object, not to the surface it is standing on. At 40% the two
    /// separations come out even — 2.1:1 from the ground, 2.1:1 from the ink —
    /// so the step reads the same weight in both themes.
    ///
    /// Radius is always 0 where this is used. A gaussian blur is the one thing
    /// pixel art never has.
    /// **One block of Press Start 2P, in points.** The offset a hard shadow
    /// under pixel type is allowed to take.
    ///
    /// Measured out of the font, not guessed: `unitsPerEm` is 1000, the GCD of
    /// every outline coordinate in the face is 125, and the cap height and the
    /// advance width are both exactly 8 of those. So the grid is 8x8 and one
    /// block is `size / 8`, precisely.
    ///
    /// **Floored, never rounded.** A zero-blur shadow offset by MORE than one
    /// block leaves a lit sliver between the glyph and its shadow, because
    /// nothing is drawn in the gap; offset by less, the shadow simply tucks
    /// under the glyph and still reads as a solid step. So overshooting is
    /// visible and undershooting is not, and the safe direction is down.
    ///
    /// This is what `ProfileHeader` found by eye at 22pt — *"y:2, not 3... an
    /// offset larger than one of its blocks leaves a lit gap"* — and 22/8 is
    /// 2.75, which floors to 2 and rounds to 3. `Wordmark` rounded, and was
    /// wrong at exactly that size.
    static func pixelStep(for size: CGFloat) -> CGFloat {
        max(1, (size / 8).rounded(.down))
    }

    static func hardStep(under ink: Color) -> Color {
        .lsDynamic(light: ink.mix(with: .black, by: 0.55),
                   dark: ink.mix(with: .black, by: 0.40))
    }

    /// Darkening laid over artwork so text on top of it stays readable.
    ///
    /// **Stays dark in both themes, on purpose.** It is not a surface — it is
    /// a shadow cast on a photograph, and cover art is equally bright whichever
    /// theme is on. Flipping this to white in light mode would wash out the
    /// very thing it exists to make legible.
    static var artScrim: Color { .black.opacity(0.45) }

    /// `artScrim`, carrying a hint of a tint — same weight, different hue.
    ///
    /// The Journal's month page uses this with the accent, so the year strip's
    /// pill fill and the month grid's day cells share a color and the zoom
    /// between them reads as one idea (Fable 5.4).
    ///
    /// **The mix happens before the alpha, not after.** `Color.mix` interpolates
    /// opacity along with everything else, so mixing the already-translucent
    /// `artScrim` toward an opaque tint would have taken it from 45% to 59%
    /// — a heavier scrim, which is the opposite of a hue change and would
    /// quietly undo the legibility work this token exists for.
    static func artScrim(tintedBy tint: Color, amount: Double = 0.25) -> Color {
        .black.mix(with: tint, by: amount).opacity(0.45)
    }
}

extension Color {
    /// Hue and saturation, dropped of brightness — what a tint contributes to
    /// the ground. nil when the platform will not give up components.
    var lsHueSaturation: (hue: Double, saturation: Double)? {
        #if canImport(UIKit)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        else { return nil }
        return (Double(h), Double(s))
        #elseif canImport(AppKit)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return (Double(c.hueComponent), Double(c.saturationComponent))
        #else
        return nil
        #endif
    }

    /// One color that resolves differently in each theme.
    ///
    /// Done in code rather than as asset-catalog color sets so the *reasoning*
    /// can sit beside the values — an `.xcassets` entry has nowhere to say why
    /// a scrim stays dark while a card fill flips.
    static func lsDynamic(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        return dark
        #endif
    }
}

/// Light, dark, or whatever the system is doing.
///
/// Stored on `ThemeSettings.appearanceRaw` (Schema V5, in Production since
/// 2026-09-02) and carried to widgets on the snapshot, the same route the
/// accent already takes.
enum LSAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    /// nil means "follow the system", which is what `.preferredColorScheme`
    /// wants for that case.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    /// **Falls back to `.dark`, not `.system`.**
    ///
    /// `appearanceRaw` is nil for every library that existed before this
    /// shipped. Reading nil as "follow the system" would have turned the app
    /// light overnight for everyone whose phone is in light mode — a change
    /// nobody asked for, delivered by an update about something else. The app
    /// has always been dark; light is a thing you choose.
    init(raw: String?) {
        self = LSAppearance(rawValue: raw ?? "") ?? .dark
    }
}

/// WCAG relative luminance and contrast, in Shared so the widgets and the
/// Watch can reason about legibility too.
///
/// Moved out of `ThemePalette` (app target only) when `LSTheme.derivedAccent`
/// needed it: the derivation lives beside the grounds it solves against, and
/// two copies of this arithmetic is exactly how the two sides drift apart.
/// `ThemePalette.contrast` and `.luminance` now delegate here.
enum LSContrast {
    static func luminance(of color: Color) -> Double {
        #if canImport(UIKit)
        let native = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard native.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        #else
        guard let native = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        let r = native.redComponent, g = native.greenComponent, b = native.blueComponent
        #endif
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func ratio(_ a: Color, _ b: Color) -> Double {
        let la = luminance(of: a), lb = luminance(of: b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
