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
        Pair(name: "Torch",  accent: "#F2A24B", step: "#A55410"),
        Pair(name: "Purple", accent: "#976EF5", step: "#4324BA"),
        Pair(name: "Yellow", accent: "#FBDB15", step: "#8F6B00"),
        Pair(name: "Blue",   accent: "#2573DD", step: "#1B2E7A"),
        Pair(name: "Pink",   accent: "#FF74D9", step: "#B139B1"),
        Pair(name: "Green",  accent: "#44CC77", step: "#25701F"),
        Pair(name: "Red",    accent: "#EE2C4C", step: "#7E3047"),
    ]

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

    /// The tinted pill's fill: the accent at five percent, both grounds.
    /// Tim's spec from the palette sheet.
    static let tintFillOpacity: Double = 0.05
}
