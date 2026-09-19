import Foundation
import SwiftData

/// User theme choices — synced via CloudKit like everything else (Tim
/// confirmed sync over per-device). One record; nil/absent fields = defaults.
@Model
final class ThemeSettings {
    /// A synced identity, so two devices fold duplicate rows the same way.
    ///
    /// **This closes a real hazard rather than adding a feature.** Both
    /// singleton folds tie-broke on `createdAt`, and passed a fresh `UUID()`
    /// when those matched — so rows created in the same instant sorted at
    /// random inside the comparator. `PlayerProfile` already had an id to fix
    /// that with; this model had none, so the best available was the LOCAL
    /// identifier, which is deterministic per device and can still have two
    /// devices keep different rows and delete each other's winner. Codex found
    /// the random tie-break on 2026-09-07; this is the half of it that needed
    /// a field.
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// Global accent (hex, e.g. "#9455FA"); nil = default purple.
    ///
    /// **Legacy since build 37 — read through `accentHex(dark:)`.** One accent
    /// had to serve both appearances, and no single color can: torch is 8.74:1
    /// on the dark ground and 1.90:1 on the light one, so the shipped default
    /// was unreadable in light mode before anyone customized anything. Kept
    /// and still written so older builds and older backups keep working;
    /// treated as the DARK value, which is the appearance it was legible in.
    var accentHex: String?

    /// **The linked palette: one hue, both appearances derived.** Build 37.
    ///
    /// The user picks a hue and a saturation; the app solves brightness against
    /// each appearance's own ground, because no single value serves both —
    /// torch is 8.74:1 on dark and 1.90:1 on light. See
    /// `LSTheme.derivedAccent`, which also softens saturation in the one place
    /// brightness cannot reach the floor: saturated blues and violets on a dark
    /// ground, where blue's 0.0722 luminance coefficient means even full
    /// brightness stays dark.
    ///
    /// Only consulted when `accentHue` is set, so an existing library with a
    /// per-appearance accent is untouched until its owner opts in.
    var accentHue: Double?
    var accentSaturation: Double?
    /// One hue for both appearances, or two independent choices. Defaults true
    /// so a new library gets the simpler model; inert while `accentHue` is nil.
    var paletteLinked: Bool = true

    /// The accent for light appearance. Build 37.
    var accentHexLight: String?
    /// The accent for dark appearance. Build 37. Falls back to `accentHex`.
    var accentHexDark: String?
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
    /// **What Home is made of, in order.**
    ///
    /// Comma-joined block descriptors — `status:playing`, `systems:6`,
    /// `collections`, `collection:<uuid>`, `filter:<uuid>`. Nil means the
    /// shipped composition.
    ///
    /// **A block may carry a count**, which is how "show six consoles, the rest
    /// behind view more" is stored without a field of its own. Tim: *"you can
    /// select how many you want to show on your Home Screen (the rest stay in
    /// view more), and then you can drag the order around from there."* The
    /// count and the order are one idea — the list is your preference, and the
    /// first N of it is what fits. It generalises: `collections:4` later needs
    /// no new storage.
    ///
    /// Synced, unlike the game page's section order, and for a reason Tim gave
    /// when asked the same question twice and answered it differently: a game
    /// page's layout is a reading preference and an iPad has more room for it,
    /// but *"Home order definitely needs to sync"* — because Home is a picture
    /// of who you are, and a self-portrait that differs between your phone and
    /// your iPad is two self-portraits.
    var homeLayoutRaw: String?

    /// **Which consoles Home shows, in the order you want them.**
    ///
    /// Comma-joined platform names. Nil means "all of them, biggest first",
    /// which is what the Library shelf does today.
    ///
    /// One ordered list plus the `systems:N` count on the Home block answers
    /// the whole question: drag to set the order, set N for how many fit, and
    /// the rest are behind "view more" in that same order.
    ///
    /// Release order and acquisition order are separate asks. The app has no
    /// platform release years — `PlatformShort.rank` is a taste heuristic for
    /// deciding which platform LABELS a game, not a generation table — and no
    /// record of when anyone got a console. A manual drag is the one of Tim's
    /// three orderings that needs no data we do not have, and it is also the
    /// one he called "personal favorite".
    var homeSystemsRaw: String?

    /// **Which game-page sections open by default, library-wide.**
    ///
    /// Comma-joined `GamePageSection` raw values; nil means the built-in set.
    /// Synced, unlike section ORDER and HIDING, which stay device-local — Tim
    /// asked for this one specifically to follow him: *"I think we let people
    /// set their own default expanded sections that syncs across devices."*
    ///
    /// It replaced a rule that opened a section when it had content. That was
    /// clever and wrong twice: on a generated tracker it opened Joule Boxes
    /// over Story Progression, and on a game page it would have opened a wall
    /// of IGDB prose identically on every game. What you want open is a
    /// preference, not something to infer.
    var expandedSectionsRaw: String?

    /// Which ownership chips a game page offers, in the app's own order —
    /// comma-separated raw values, nil = the default five.
    ///
    /// Ownership is the one vocabulary in the app that is genuinely
    /// person-specific. A PC-only library has no use for Physical; somebody
    /// cataloguing a childhood has every use for Rented and none for
    /// Subscription. Tim, arriving at it from a Halo 2 memory of a game he
    /// never owned: *"maybe we let them choose what ownership options they
    /// want displayed?"*
    ///
    /// **Hiding a chip never changes a game.** A game already marked Rented
    /// keeps that mark, and it reappears the moment the chip comes back —
    /// same contract as hiding a game-page section. Nothing here deletes.
    ///
    /// Synced, because it is vocabulary rather than a display preference:
    /// choosing not to think about subscriptions is a decision about your
    /// library, and it should not have to be made twice.
    var ownershipChipsRaw: String?

    var gamePageLayoutRaw: String?

    /// Your own words on the five stars — JSON array of exactly five strings,
    /// index 0 = one star. Nil = plain stars. Vocabulary, not modeling: a
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

    /// Which name a console goes by, for the ones that have more than one.
    ///
    /// `PlatformShort` collapses IGDB's spellings to one short name per
    /// machine, and for most consoles there is nothing to argue about. For
    /// some there is: "Sega Mega Drive/Genesis" is one machine with two names
    /// depending on where you grew up, and the app picked Genesis for
    /// everybody. Tim: *"the user should be able to choose which one they want
    /// displayed, not forced to see Genesis if they don't call it that."* The
    /// same goes for the ones that are a matter of habit rather than region —
    /// he calls the NES "Nintendo" and the SNES "Super Nintendo".
    ///
    /// Keyed by the app's own default short name, valued with the chosen
    /// alternative. Absent means the default, so this stays empty for anyone
    /// who never opens the screen. See `PlatformNaming` for the choices and
    /// why it is a fixed pair rather than a free field.
    ///
    /// Synced, like `statusNames`, for the same reason: your words for your
    /// own shelves should follow you between devices.
    var platformNamesData: Data?

    // MARK: Build 36 — appearance (fields ahead of the feature, on purpose)

    /// `system` | `light` | `dark`. Schema V5.
    ///
    /// **nil means DARK, not system** — see `LSAppearance.init(raw:)`, which
    /// falls back deliberately: every library from before this shipped has nil
    /// here, and reading that as "follow the system" would have turned the app
    /// light overnight for everyone whose phone is in light mode. This said
    /// "nil = system", which is the opposite of what the code does.
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
    /// **Legacy since build 37 — read through `backgroundHex(dark:)`**, for
    /// the same reason as `accentHex`. Treated as the dark value.
    var backgroundHex: String?

    /// The ground tint for light appearance. Build 37.
    var backgroundHexLight: String?
    /// The ground tint for dark appearance. Build 37. Falls back to `backgroundHex`.
    var backgroundHexDark: String?

    /// The accent for the appearance actually on screen.
    ///
    /// Resolution is explicit rather than derived at render time on purpose:
    /// both values are the user's own choice, so switching appearance shows a
    /// palette they picked rather than a fallback the app computed. Nothing
    /// changes color on its own.
    func accentHex(dark: Bool) -> String? {
        dark ? (accentHexDark ?? accentHex) : accentHexLight
    }

    /// The ground tint for the appearance actually on screen.
    func backgroundHex(dark: Bool) -> String? {
        dark ? (backgroundHexDark ?? backgroundHex) : backgroundHexLight
    }

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

    var platformNames: [String: String] {
        get {
            guard let data = platformNamesData,
                  let map = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return map
        }
        set {
            platformNamesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
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
