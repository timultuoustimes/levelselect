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

    /// Whether game pages show a game's logo where its name would be.
    ///
    /// Separate from `gamePageLayoutRaw` on purpose: which arrangement you
    /// like and whether you want wordmarks at all are different preferences,
    /// and folding them together would mean the quiet layout could never show
    /// a logo and the bold one could never be turned down to plain text.
    var showGameLogos: Bool = true

    /// Colors the user kept in the color editor, as a JSON array of hex
    /// strings. Synced, because a palette you built on your phone should be
    /// on your iPad — it was `@AppStorage` until this field existed.
    var savedSwatchesData: Data?

    /// Which header arrangement game pages use. Nil = `showcase`, the build
    /// 32 default. See `GamePageLayout`.
    ///
    /// Synced, for the same reason `backdropIntensityRaw` is: it is a look,
    /// not a device preference. Someone who prefers the quiet header prefers
    /// it on the iPad too.
    var gamePageLayoutRaw: String?

    /// Your own words on the five stars — JSON array of exactly five strings,
    /// index 0 = one star. Nil = plain stars. Vocabulary, not modelling: a
    /// rating that says "comfort game" instead of "3" reads like the
    /// notebook's owner wrote it. Synced, because your words for your shelf
    /// should follow you between devices.
    var starNamesData: Data?

    /// Your own word for a status: JSON `[statusRawValue: name]`. Schema V5.
    ///
    /// The same argument as `starNamesData`, and it arrived the same way — by
    /// Tim finding a status that was wrong for him. Games he played to death
    /// as a kid and will never finish are not *Abandoned*, which says the game
    /// lost him, and not *Backlog*, which says he never started. One person's
    /// "Abandoned" is another's "played it to bits", and that disagreement is
    /// not resolvable by picking a better default word.
    ///
    /// So the app states what it means (see `GameStatus.blurb`) and lets you
    /// disagree. Synced, because your words for your own shelves should follow
    /// you between devices.
    var statusNamesData: Data?

    // MARK: Build 36 — appearance (fields ahead of the feature, on purpose)

    /// `system` | `light` | `dark`; nil = system. Schema V5.
    ///
    /// **Shipped ahead of the light theme that will use it.** An unused
    /// optional costs nothing and a schema version costs a promote cycle, so a
    /// field whose feature is a build away still belongs in the batch that is
    /// deploying today. That reasoning is why V2 landed eight items at once.
    ///
    /// Synced rather than device-local: unlike the card order or a flip state,
    /// "this app is light for me" is a statement about the app rather than
    /// about the device you happen to be holding.
    var appearanceRaw: String?

    /// A custom page background (hex), overriding whatever the appearance
    /// would otherwise pick. nil = the appearance's own default.
    ///
    /// Separate from `accentHex` because they fail differently: a bad accent
    /// is ugly, a bad background makes text unreadable. Keeping them apart
    /// lets the background be validated for contrast on its own terms.
    var backgroundHex: String?

    init() {}

    var statusNames: [String: String] {
        get {
            guard let data = statusNamesData,
                  let map = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return map
        }
        set {
            statusNamesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

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
    /// gaussian, and it reads as artwork rather than a colored smear. The
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
    /// backdrop needs no lookup — it's the cover, a flat color, or nothing.
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

extension ThemeSettings {
    /// Kept colors, newest first.
    var savedSwatches: [String] {
        get {
            guard let savedSwatchesData,
                  let list = try? JSONDecoder().decode([String].self, from: savedSwatchesData)
            else { return [] }
            return list
        }
        set {
            // Capped, and empty stores nothing rather than an empty array that
            // would sync as a deliberate "I cleared my palette".
            let trimmed = Array(newValue.prefix(12))
            savedSwatchesData = trimmed.isEmpty ? nil : try? JSONEncoder().encode(trimmed)
        }
    }
}
