import Foundation
import SwiftData

/// User theme choices — synced via CloudKit like everything else (Tim
/// confirmed sync over per-device). One record; nil/absent fields = defaults.
@Model
final class ThemeSettings {
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// Global accent (hex, e.g. "#9455FA"); nil = default purple.
    var accentHex: String?
    /// Per-status overrides: JSON [statusRawValue: hex].
    var statusColorsData: Data?
    /// Game-page backdrop: "cover" (ambient art) or "status" (status color).
    var pageBackgroundRaw: String = ThemePageBackground.cover.rawValue
    /// Library-wide default tracker display ("inline"/"compact"). Per-game
    /// overrides (Game.trackerDisplayRaw) always win over this.
    var defaultTrackerDisplayRaw: String = TrackerDisplay.inline.rawValue

    // MARK: Schema V2
    //
    // These live here, beside the accent and status colors, because settings
    // that don't sync are a bug with a long fuse: the Deku wishlist URL was
    // kept in per-device UserDefaults, so connecting it on the phone could
    // never reach the iPad, and it looked like broken sync for weeks.

    /// Remembered default for what the generate button does — add-only,
    /// review, or replace ("addNew"/"review"/"replace"). Nil = the safe
    /// built-in default (add-only), which can never cost progress.
    var defaultMergeModeRaw: String?
    /// Remembered answer for overlapping timers across devices
    /// ("ask"/"keepNewest"/"keepBoth"). Nil = ask. This is what turns today's
    /// automatic resolution from something the app does silently into
    /// something the user chose.
    var overlappingTimerPolicyRaw: String?
    /// Whether generated item descriptions/hints show by default. Distinct
    /// from the spoiler mechanic (`hideUntilDiscovered`/`revealed`): spoilers
    /// are about not seeing content yet, this is about clutter.
    var showItemHints: Bool = true
    /// Per-platform console art choice ({platform key: variant slug}), JSON
    /// like `statusColorsData` — the hardware you owned is part of the memory.
    var platformIconVariantsData: Data?
    /// The Deku Deals wishlist URL. Was device-local UserDefaults, which is
    /// why it never synced.
    var dekuWishlistURLString: String?

    // MARK: Build 31 (promote with the batch)

    /// How strongly the game-page backdrop reads: nil = the built-in default.
    /// See `BackdropIntensity`. Schema V3, and synced with the rest of the
    /// appearance choices because it's a look, not a device preference.
    var backdropIntensityRaw: String?

    /// Your own words on the five stars — JSON array of exactly five strings,
    /// index 0 = one star. Nil = plain stars. Vocabulary, not modelling: a
    /// rating that says "comfort game" instead of "3" reads like the
    /// notebook's owner wrote it. Synced, because your words for your shelf
    /// should follow you between devices.
    var starNamesData: Data?

    init() {}

    var statusColors: [String: String] {
        get {
            guard let data = statusColorsData,
                  let map = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return map
        }
        set {
            statusColorsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Star names as an array; empty = unset. Reads tolerate any stored
    /// count but the editor always writes five.
    var starNames: [String] {
        get {
            guard let data = starNamesData,
                  let names = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return names
        }
        set {
            let trimmed = newValue.map { $0.trimmingCharacters(in: .whitespaces) }
            starNamesData = trimmed.allSatisfy(\.isEmpty)
                ? nil : try? JSONEncoder().encode(trimmed)
        }
    }

    /// The word for a given rating (1...5), if one is set and non-empty.
    func starName(for rating: Int) -> String? {
        let names = starNames
        guard rating >= 1, rating <= names.count else { return nil }
        let name = names[rating - 1]
        return name.isEmpty ? nil : name
    }
}

/// New cases are free (String-raw, stored in `pageBackgroundRaw`); an old
/// build reading an unknown value falls back to `.cover` via the
/// `ThemePalette.refresh` nil-coalesce.
/// How hard the backdrop pushes.
///
/// The old single setting was a 60pt blur at 0.55 opacity over a near-black
/// background — which, on the dark cover most games have, was very nearly
/// invisible. Tim: "it's very subtle. Can we make it more obvious, or let
/// users choose the blur level?" Both: `standard` is stronger than what
/// shipped, and the choice exists.
enum BackdropIntensity: String, CaseIterable, Identifiable {
    case off, subtle, standard, bold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off:      "Off"
        case .subtle:   "Subtle"
        case .standard: "Standard"
        case .bold:     "Bold"
        }
    }

    var opacity: Double {
        switch self {
        case .off:      0
        case .subtle:   0.40
        case .standard: 0.70
        case .bold:     0.92
        }
    }

    /// Bold blurs LESS, not more — at full strength the point is to see the
    /// art, not a smear of its average colour.
    var blurRadius: CGFloat {
        switch self {
        case .off:      0
        case .subtle:   60
        case .standard: 44
        case .bold:     22
        }
    }

    /// The saturation boost fights the opacity, so it eases off as opacity
    /// rises; a bold backdrop is already vivid enough.
    var saturation: Double {
        switch self {
        case .off:      1
        case .subtle:   1.5
        case .standard: 1.3
        case .bold:     1.1
        }
    }
}

enum ThemePageBackground: String, CaseIterable {
    case cover, status, accent, plain

    var label: String {
        switch self {
        case .cover:  "Cover art"
        case .status: "Status color"
        case .accent: "Accent color"
        case .plain:  "Plain"
        }
    }
}
