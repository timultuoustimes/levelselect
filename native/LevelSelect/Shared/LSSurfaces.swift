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
/// good on anything I've seen behind them, including just a light grey."*
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

    /// The ground, optionally wearing a colour the user picked.
    ///
    /// **The tint supplies hue and saturation; the theme keeps luminance.**
    /// That is the whole safety property. A background is the one surface
    /// where a bad choice makes text unreadable, and letting someone drop a
    /// near-black into Light mode would do exactly that — dark ground, dark
    /// text, nothing legible, no warning. Taking only the *colour* of their
    /// choice means the app is still recognisably theirs and cannot be made
    /// unreadable by picking wrong.
    ///
    /// It also matches what the default already is. The shipped gradient is
    /// not two colours; it is one hue at two brightnesses — so deriving the
    /// second stop reproduces the look that was already tuned, rather than
    /// inventing a new one.
    static func ground(tintedBy tint: Color?) -> LinearGradient {
        let hue = tint?.lsHueSaturation
        return LinearGradient(
            colors: [
                .lsDynamic(light: shade(hue, brightness: 0.97, saturation: 0.06,
                                        fallback: Color(red: 0.97, green: 0.96, blue: 1.00)),
                           dark:  shade(hue, brightness: 0.16, saturation: 0.55,
                                        fallback: Color(red: 0.10, green: 0.07, blue: 0.18))),
                .lsDynamic(light: shade(hue, brightness: 0.88, saturation: 0.10,
                                        fallback: Color(red: 0.88, green: 0.86, blue: 0.94)),
                           dark:  shade(hue, brightness: 0.07, saturation: 0.60,
                                        fallback: Color(red: 0.05, green: 0.04, blue: 0.09))),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// One stop: the picked hue at the brightness this theme allows, or the
    /// built-in colour when nothing was picked.
    private static func shade(_ hue: (hue: Double, saturation: Double)?,
                              brightness: Double,
                              saturation: Double,
                              fallback: Color) -> Color {
        guard let hue else { return fallback }
        // A grey pick has no hue worth keeping — honour it as grey rather
        // than snapping to whatever arbitrary hue the picker reported.
        let sat = hue.saturation < 0.05 ? 0 : saturation
        return Color(hue: hue.hue, saturation: sat, brightness: brightness)
    }

    /// Hero card gradient (Continue Playing).
    static var heroGradient: LinearGradient { hero(tintedBy: nil) }

    /// The hero, wearing the same colour the ground does.
    ///
    /// It is the ground's own hue lifted off it — brighter than the ground in
    /// the dark theme, deeper in the light one, because "raised" points in
    /// opposite directions depending on which way the ground goes. Leaving it
    /// fixed while the ground moved made the most prominent card on Home the
    /// one thing that ignored your colour.
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
    // These were `.white.opacity(…)` everywhere, which is not a colour so much
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

    /// Darkening laid over artwork so text on top of it stays readable.
    ///
    /// **Stays dark in both themes, on purpose.** It is not a surface — it is
    /// a shadow cast on a photograph, and cover art is equally bright whichever
    /// theme is on. Flipping this to white in light mode would wash out the
    /// very thing it exists to make legible.
    static var artScrim: Color { .black.opacity(0.45) }
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

    /// One colour that resolves differently in each theme.
    ///
    /// Done in code rather than as asset-catalog colour sets so the *reasoning*
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
