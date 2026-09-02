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

    /// App background. Near-black with a purple cast; in light, the same cast
    /// at the other end of the range rather than plain white — the purple is
    /// the brand and it should survive the switch.
    static var background: LinearGradient {
        LinearGradient(
            colors: [
                .lsDynamic(light: Color(red: 0.96, green: 0.95, blue: 0.99),
                           dark:  Color(red: 0.10, green: 0.07, blue: 0.18)),
                .lsDynamic(light: Color(red: 0.91, green: 0.90, blue: 0.96),
                           dark:  Color(red: 0.05, green: 0.04, blue: 0.09)),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Hero card gradient (Continue Playing).
    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                .lsDynamic(light: purple.opacity(0.20), dark: purpleDeep.opacity(0.85)),
                .lsDynamic(light: purple.opacity(0.08),
                           dark:  Color(red: 0.12, green: 0.08, blue: 0.22)),
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
