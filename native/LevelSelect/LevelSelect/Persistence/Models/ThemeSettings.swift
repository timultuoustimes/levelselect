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
        case .subtle:   0.55
        case .standard: 0.80
        case .bold:     1.0
        }
    }

    /// SMALL numbers. The first pass at this used 60/44/22pt, which destroys
    /// the image before opacity ever matters — Tim's own mockup uses a 3pt
    /// gaussian, and it reads as artwork rather than a coloured smear. The
    /// job of the blur is to stop the art competing with the text on top of
    /// it, not to hide what the art is.
    var blurRadius: CGFloat {
        switch self {
        case .off:      0
        case .subtle:   8
        case .standard: 3
        case .bold:     0
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
    /// Key art first, because it's authored to BE art — but a screenshot is
    /// often the better header, since in-engine shots are natively wide where
    /// key art is composed for a poster crop. Hence the choice.
    case keyArt, screenshot, cover, status, accent, plain

    var label: String {
        switch self {
        case .keyArt:     "Key art"
        case .screenshot: "Screenshot"
        case .cover:      "Cover art"
        case .status:     "Status color"
        case .accent:     "Accent color"
        case .plain:      "Plain"
        }
    }

    /// Which IGDB art this background wants fetched, if any. Nil means the
    /// backdrop needs no lookup — it's the cover, a flat colour, or nothing.
    var igdbEndpoint: String? {
        switch self {
        case .keyArt:     "artworks"
        case .screenshot: "screenshots"
        default:          nil
        }
    }

    /// The size slug for that endpoint's images.
    var igdbSize: String {
        self == .screenshot ? "t_screenshot_huge" : "t_1080p"
    }

    /// Whether this background draws a game's own artwork at all.
    var usesArtwork: Bool { igdbEndpoint != nil || self == .cover }
}
