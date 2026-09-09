import SwiftUI

/// The seven accents, each with its own step — Tim's palette, 2026-09-08.
///
/// **Why seven authored pairs and not a wheel.** The build-37 picker offered
/// twenty-three hexes and a hue plane, and most of the hexes were struck
/// through on one ground or the other — Tim: *"giant blocks of 'doesn't work
/// here' all crossed out and then just a few colors to choose from."* A
/// palette you cannot pick from is not a palette. These seven were chosen
/// to work on both grounds as **fills**, with a dark knockout ink on every
/// one (every pair clears 4.5:1 for black text on the accent), and each
/// carries the step that sits under pixel type and serves as its ink on the
/// light ground — authored, not derived, so the shadow under the wordmark can
/// never drift the way a computed one did.
///
/// The accent is the same hex on both grounds; what changes is which of the
/// pair is the ink: **the step on light, the accent on dark.**
enum LSPalette {
    struct Pair: Identifiable, Hashable, Sendable {
        let name: String
        /// The fill — buttons, chips, the name in the header.
        let accent: String
        /// The hard step under pixel type, and the ink on the light ground.
        let step: String
        var id: String { accent }
        var accentColor: Color { Color(hex: accent) ?? .orange }
        var stepColor: Color { Color(hex: step) ?? .brown }
    }

    static let pairs: [Pair] = [
        // Steps re-authored by Tim, 2026-09-09, against the accent as a
        // surface (the ink on a Play button), not only against the light
        // ground. Every step now clears 3:1 on its own accent — the old red
        // (#7E3047) sat at 2.12:1 and read as maroon-on-red — and the two
        // weakest, blue and red, were tuned last to the same 3.6 margin.
        // Torch keeps its own step: on light the default pair paints its
        // fills in the step, so this is the brand orange itself, not an ink.
        Pair(name: "Torch",  accent: "#F5A34D", step: "#A55410"),
        Pair(name: "Purple", accent: "#976EF5", step: "#331C72"),
        Pair(name: "Yellow", accent: "#FBDB15", step: "#765302"),
        Pair(name: "Blue",   accent: "#2573DD", step: "#0C1A4E"),
        Pair(name: "Pink",   accent: "#FF74D9", step: "#6B1B6D"),
        Pair(name: "Green",  accent: "#44CC77", step: "#134C0E"),
        Pair(name: "Red",    accent: "#EE2C4C", step: "#530916"),
        // **The high-contrast one.** Tim, 2026-09-09: *"the dark mode
        // background is nearly black charcoal, and text and icons are very
        // light grey. Light mode background is very light grey, text and icons
        // are nearly black charcoal."*
        //
        // It needs no new concept: the accent is already the ink on dark and
        // the step is already the ink on light, so a light-grey accent over a
        // charcoal step IS that description. What it needs is a neutral
        // GROUND — see `ground(tint:dark:bottom:)`, where the shared bases
        // carry a deliberate cast that a grey tint would turn faintly purple.
        //
        // Named for the scheme rather than a color, because it has none. NOT
        // "Ink": that word already means the foreground in this codebase
        // (`hardStep(under ink:)`, "accent-as-ink"), and a pair by that name
        // would collide with it in every comment that follows.
        Pair(name: "Mono",   accent: "#E8E8EA", step: "#1C1C1E"),
    ]

    /// **The pair whose ground is not a tint of anything.**
    ///
    /// Every other pair paints its ground by laying the accent over a base
    /// that leans slightly blue on dark and slightly lavender on light — a
    /// cast that is right when a hue is going over it and wrong when the whole
    /// point is that there is no hue. Kept as a name rather than a flag on
    /// `Pair` so the seven authored pairs are untouched by it.
    static let neutralPairName = "Mono"

    /// The pair an accent hex belongs to, if it is one of the seven.
    static func pair(matching hex: String?) -> Pair? {
        guard let hex else { return nil }
        let key = normalized(hex)
        return pairs.first { normalized($0.accent) == key }
    }

    static func normalized(_ hex: String) -> String {
        var s = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if !s.hasPrefix("#") { s = "#" + s }
        return s
    }

    /// The tinted pill's fill: the accent at half strength over the ground,
    /// both grounds — measured off Tim's "Palette Look" sheet (2026-09-08),
    /// where the pill reads #EDBFA4 on the light ground and #875A46 on the
    /// dark one, both the accent at ~0.5 over what is behind it.
    static let tintFillOpacity: Double = 0.5

    /// The pair a stored ground tint belongs to, and the one used when none
    /// is stored: Purple, which is what the app's own indigo ground has
    /// always been.
    static var defaultGround: Pair { pairs[1] }

    /// The ground a pair makes: the pair's accent laid over the base gray
    /// (light) or base charcoal (dark) with the *overlay* blend at full
    /// strength — Tim's own construction in the palette sheet: *"it's 100%
    /// overlay on top of the base light grey and base charcoal."* The bases
    /// were solved from his renders (purple → #F0E5FE / #2E214F, green →
    /// #E5F6F6 / #153D26), and the bottom stops keep the gradient the app
    /// already had.
    static func ground(tint: Color?, dark: Bool, bottom: Bool = false) -> Color {
        // Mono's ground is authored, not derived. Same lightness as the bases
        // below, with the cast taken out: #272727 → #131313 on dark, #EDEDED →
        // #E0E0E0 on light. Matched by the accent it was authored with rather
        // than by a flag, so a library that stored the hex before this pair
        // existed still resolves to it.
        if let tint, pair(matching: tint.hexString())?.name == neutralPairName {
            let v = dark ? (bottom ? 0.075 : 0.152) : (bottom ? 0.880 : 0.930)
            return Color(red: v, green: v, blue: v)
        }
        let base: (Double, Double, Double) = dark
            ? (bottom ? (0.075, 0.070, 0.085) : (0.152, 0.150, 0.160))
            : (bottom ? (0.880, 0.860, 0.910) : (0.930, 0.910, 0.960))
        let tint = (tint ?? defaultGround.accentColor).lsRGB ?? defaultGround.accentColor.lsRGB ?? (0.59, 0.43, 0.96)
        func overlay(_ b: Double, _ c: Double) -> Double {
            b < 0.5 ? 2 * b * c : 1 - 2 * (1 - b) * (1 - c)
        }
        return Color(red: overlay(base.0, tint.r), green: overlay(base.1, tint.g), blue: overlay(base.2, tint.b))
    }
}

extension Color {
    /// sRGB components, or nil for a color that has none to give.
    var lsRGB: (r: Double, g: Double, b: Double)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b))
        #elseif canImport(AppKit)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        #else
        return nil
        #endif
    }
}
