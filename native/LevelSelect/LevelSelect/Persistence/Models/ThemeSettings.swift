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
}

enum ThemePageBackground: String, CaseIterable {
    case cover, status

    var label: String {
        switch self {
        case .cover: "Cover art"
        case .status: "Status color"
        }
    }
}
