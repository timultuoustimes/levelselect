import SwiftUI

/// How the profile name on Home is coloured.
///
/// Three states in one string, because the interesting one isn't a colour at
/// all: **following the accent** means the name keeps changing with the theme
/// rather than being pinned to whatever the accent happened to be the day it
/// was set.
///
/// **Device-local for now.** Storing this per-profile means a new field on
/// `PlayerProfile`, which is a CloudKit schema deploy. Queued with the two
/// others waiting on the same dance — a live-linked "use my handle as my name"
/// toggle, and syncing kept swatches — so one deploy covers all three rather
/// than three deploys covering one each.
enum ProfileNameColor {
    static let key = "levelselect.profileNameColor"

    /// Follow the accent, whatever it becomes later.
    static let accent = "accent"
    /// The plain default: ordinary primary text.
    static let plain = ""

    @MainActor
    static func resolve(_ raw: String) -> Color {
        switch raw {
        case plain:  .primary
        case accent: LSTheme.accent
        default:     Color(hex: raw) ?? .primary
        }
    }

    /// The swatch to show for a setting, so the row previews the real thing.
    @MainActor
    static func swatch(_ raw: String) -> Color { resolve(raw) }

    enum Mode: String, CaseIterable, Identifiable {
        case plain, accent, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .plain:  "Default"
            case .accent: "Accent"
            case .custom: "Custom"
            }
        }
    }

    static func mode(of raw: String) -> Mode {
        switch raw {
        case plain:  .plain
        case accent: .accent
        default:     .custom
        }
    }
}
