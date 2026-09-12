import SwiftUI
import SwiftData

/// Resolved theme values, cached on the main actor so `GameStatus.color` and
/// `LSTheme.accent` stay cheap to read from any view. Refreshed from the
/// synced ThemeSettings record on launch and whenever it changes.
@MainActor
enum ThemePalette {
    private(set) static var accent: Color = LSTheme.defaultAccent
    /// The accent as DISPLAY ink: **the color as picked, uncorrected**.
    ///
    /// `accent` is held to 4.5:1, which is right for the 59 places it is used
    /// as ordinary foreground text and wrong for pixel type with a hard step
    /// under it. Flat fill-versus-ground contrast assumes solid text on a
    /// solid ground; outlined type carries its own edge, and the step is what
    /// makes it read. The wordmark is the proof and has been all along — it is
    /// `torch` on both grounds at 1.90:1 on light, and nobody has ever had
    /// trouble reading it.
    ///
    /// Correcting the name instead of trusting the step cost two things.
    /// Custom took `Color(hex:)` with no correction at all, so the same color
    /// came out two different ways depending on which button was pressed —
    /// Tim, 2026-09-07: *"Tapping default, and having it be accent make it
    /// basically black, but choosing custom color and the current accent
    /// color shows the right color."* And the light default fell to
    /// `torchInk`, which is what he lost: *"I honestly think we went too dark
    /// on some color choices in light mode. Loosing torch, which I thought
    /// read fine on the profile name, especially with the secondary dark
    /// orange as it's hard edge drop shadow, worked well."*
    ///
    /// So this is the wordmark's own ink rule: torch until you pick an accent,
    /// exactly what you picked afterwards, on both grounds. Accent and Custom
    /// now agree because they are the same color by construction.
    private(set) static var displayAccent: Color = LSTheme.defaultAccent
    /// True once the user has picked their own accent. The wordmark keeps its
    /// brand torch-orange until then, so the default look is unchanged.
    private(set) static var accentIsCustom = false
    private(set) static var pageBackground: ThemePageBackground = .cover
    private(set) static var defaultTrackerDisplay: TrackerDisplay = .inline
    private static var statusOverrides: [GameStatus: Color] = [:]
    /// Custom words on the five stars ([] = the built-in labels).
    private(set) static var starNames: [String] = []
    /// Custom words for statuses ([:] = the built-in ones).
    private static var statusNameOverrides: [String: String] = [:]
    /// Light, dark, or the system's choice. Schema V5.
    private(set) static var appearance: LSAppearance = .dark
    /// A custom page background, overriding the appearance's own. Schema V5.
    /// The chosen ground tint per appearance (nil = the built-in ground).
    private(set) static var backgroundOverrideLight: Color?
    private(set) static var backgroundOverrideDark: Color?
    /// The dark value, for the single-tint paths that cannot express two —
    /// the widget snapshot and the hero gradient.
    static var backgroundOverride: Color? { backgroundOverrideDark }
    /// How hard the game-page backdrop reads.
    private(set) static var backdropIntensity: BackdropIntensity = .standard
    /// How game pages arrange their header.
    private(set) static var gamePageLayout: GamePageLayout = .showcase
    /// Whether a game's logo stands in for its name.
    private(set) static var showGameLogos = true
    /// Which ownership chips a game page offers. Never empty — an empty set
    /// would be a game page with no way to say you own the game at all, so a
    /// stored value that decodes to nothing falls back to the default five.
    private(set) static var ownershipChips: [Ownership] = Ownership.shownByDefault

    /// The label a rating wears: the user's word if set, the built-in if not.
    static func starLabel(for rating: Int) -> String {
        if rating >= 1, rating <= starNames.count,
           !starNames[rating - 1].isEmpty {
            return starNames[rating - 1]
        }
        return RatingControl.labels[max(1, min(rating, 5)) - 1]
    }

    /// The word a status wears: the user's if set, the built-in if not.
    ///
    /// Blank counts as unset, so clearing the field restores the default
    /// rather than leaving a shelf with no heading at all.
    static func statusName(for status: GameStatus) -> String {
        if let custom = statusNameOverrides[status.rawValue],
           !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }
        return status.defaultTitle
    }

    /// Built-in defaults (the palette shipped before theming existed).
    static func defaultColor(for status: GameStatus) -> Color {
        switch status {
        case .playing:   .green
        case .paused:    .orange
        case .completed: .blue
        case .queued:    .purple
        case .backlog:   .gray
        // Warm, and deliberately not near .abandoned's color: the whole
        // point of the status is that it is not a failure.
        case .oldFavorite: .pink
        case .shelved:   .brown
        case .abandoned: .red
        case .wishlist:  .pink
        case .ongoing:   .teal
        }
    }

    static func color(for status: GameStatus) -> Color {
        statusOverrides[status] ?? defaultColor(for: status)
    }

    /// Only the statuses whose color the user actually changed, as hex.
    ///
    /// This is what rides to the widgets and, through them, to the Lock Screen
    /// and Live Activity (A4). Deliberately the OVERRIDES rather than every
    /// status's resolved color: an untouched status sends nothing, so the
    /// widget keeps its own built-in color rather than being handed a frozen
    /// copy of whatever the default happened to be today.
    static var statusColorHexes: [String: String] {
        statusOverrides.reduce(into: [:]) { out, pair in
            out[pair.key.rawValue] = pair.value.hexString()
        }
    }

    /// Text and glyphs drawn ON the accent, black or white by contrast.
    ///
    /// The accent is the user's to choose, and a pale yellow one makes white
    /// lettering unreadable while a deep indigo does the same to black. Any
    /// filled accent control has to ask rather than assume — this is the one
    /// place that decides.
    private(set) static var onAccent: Color = .white

    /// Relative luminance, sRGB, per WCAG, against the crossover where black
    /// and white contrast EQUALLY: 0.179, not 0.5.
    ///
    /// The number is derived, not chosen. Black on a color scores
    /// `(L + 0.05) / 0.05`; white scores `1.05 / (L + 0.05)`. Setting those
    /// equal gives `L = sqrt(0.0525) - 0.05 ~= 0.179`. Above it black wins,
    /// below it white does, and picking the other is measurably worse rather
    /// than a matter of taste.
    ///
    /// A sensible-looking 0.5 threshold puts WHITE on torch orange at about
    /// 2:1 — under half the 4.5:1 AA floor, on the most important control on
    /// Home. Black on that same orange is 10:1.
    /// Internal so the color editor can preview a candidate before it is
    /// stored — the preview has to answer the same question the button will.
    static func onColor(for color: Color) -> Color {
        #if canImport(UIKit)
        let native = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard native.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        #else
        guard let native = NSColor(color).usingColorSpace(.sRGB) else { return .white }
        let r = native.redComponent, g = native.greenComponent, b = native.blueComponent
        #endif
        func lin(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return luminance > 0.179 ? .black : .white
    }

    /// Relative luminance, sRGB, per WCAG. Shared by `onColor` and the
    /// knockout test below rather than computed twice.
    static func luminance(of color: Color) -> Double { LSContrast.luminance(of: color) }

    static func contrast(_ a: Color, _ b: Color) -> Double { LSContrast.ratio(a, b) }

    /// What to draw *inside* a filled accent surface, so the glyph reads as a
    /// hole punched through it rather than ink sitting on top.
    ///
    /// Tim, on a dark green accent in the light theme: *"that play text/icon
    /// should maybe be the color of the background… so it looks like it's cut
    /// out of the button."* The ground is the right answer because a knockout
    /// is literally the shape of the thing behind showing through — which is
    /// also why it has to be the ground and not white: white is a color, the
    /// ground is an absence.
    ///
    /// **Falls back to plain contrast when the ground is too close to the
    /// accent.** A pale accent on the light theme would knock out to pale on
    /// pale — an invisible Play button, which is worse than an unfashionable
    /// one. 3:1 is the WCAG floor for large text and graphical objects, which
    /// is exactly what this is.
    static func knockout(on accent: Color) -> Color {
        knockoutPreview(on: accent, ground: groundBase)
    }

    /// The same rule against a ground you name, so the color editor can show
    /// a candidate pair before either is stored. The preview has to answer the
    /// question the button will, and the button's answer depends on both.
    static func knockoutPreview(on accent: Color, ground rawGround: Color) -> Color {
        let ground = rawGround
        if contrast(ground, accent) >= 3 { return ground }

        // **Not black.** Torch orange on the light ground knocks out at
        // 1.90:1 — genuinely unreadable — but flat black throws away the
        // effect entirely, and the point was that the glyph looks cut from
        // the material behind it. So the ground is *darkened* until it is
        // legible instead of abandoned: same hue, same family, enough
        // contrast. On torch that lands around 5.6:1 against black's 10:1,
        // which is well clear of the 4.5:1 floor and looks like it belongs.
        //
        // Note the knockout is already live in dark mode for the same accent
        // — torch on the dark ground is 8.77:1. This is only the light-theme,
        // light-accent corner.
        guard let hs = ground.lsHueSaturation else { return onColor(for: accent) }
        for brightness in stride(from: 0.45, through: 0.10, by: -0.05) {
            // A much lower gray threshold than `groundBase` uses. The
            // default light ground is (0.97, 0.96, 1.00) — saturation 0.04,
            // deliberately barely purple — and treating that as gray threw
            // away the exact hue that makes this read as the ground rather
            // than as ink. Only a genuinely neutral pick stays neutral.
            let candidate = Color(hue: hs.hue,
                                  saturation: hs.saturation < 0.01 ? 0 : 0.35,
                                  brightness: brightness)
            if contrast(candidate, accent) >= 4.5 { return candidate }
        }
        // A mid-toned accent that nothing in the ground's hue can beat —
        // rare, and black or white is the honest last resort.
        return onColor(for: accent)
    }

    /// A solid stand-in for the background gradient — its top stop, which is
    /// what sits behind the controls that use a knockout.
    /// The ground a piece of ink will actually sit on, resolved concretely.
    ///
    /// Concrete, not dynamic, on purpose: every contrast decision below is
    /// arithmetic on color components, and a dynamic color resolves against
    /// whatever trait happens to be current when it is sampled — which is how
    /// you get a light-mode answer applied to a dark-mode screen.
    static func groundBase(dark: Bool) -> Color {
        let tint = dark ? backgroundOverrideDark : backgroundOverrideLight
        if let tint {
            let hs = tint.lsHueSaturation
            return Color(hue: hs?.hue ?? 0,
                         saturation: (hs?.saturation ?? 0) < 0.05 ? 0 : 0.06,
                         brightness: dark ? 0.16 : 0.97)
        }
        return dark ? Color(red: 0.10, green: 0.07, blue: 0.18)
                    : Color(red: 0.97, green: 0.96, blue: 1.00)
    }

    static var groundBase: Color {
        backgroundOverride.map { tint in
            let hs = tint.lsHueSaturation
            return Color(hue: hs?.hue ?? 0,
                         saturation: (hs?.saturation ?? 0) < 0.05 ? 0 : 0.06,
                         brightness: 0.97)
        } ?? .lsDynamic(light: Color(red: 0.97, green: 0.96, blue: 1.00),
                        dark:  Color(red: 0.10, green: 0.07, blue: 0.18))
    }

    static func refresh(from settings: ThemeSettings?) {
        // **One accent per appearance, both chosen by the user.**
        //
        // No single color serves both grounds: torch is 8.74:1 on dark and
        // 1.90:1 on light. Deriving a fallback at render time was the other
        // option and was worse — the same label would be orange in dark and
        // near-black in light, changing character at sunset with "Follow
        // system" on. Two chosen values mean nothing shifts on its own.
        // Linked wins when a hue has been picked; otherwise the per-appearance
        // values, then the legacy single value, then the default. Gated on the
        // hue being set so switching the flag alone can never silently discard
        // an accent someone already chose.

        // The ground is assigned BEFORE anything is measured against it.
        //
        // `groundBase(dark:)` reads these statics, and both the legibility
        // correction below and the knockout further down call it — so with the
        // assignment last, a change of accent AND background in one save
        // measured the new accent against the OLD ground. It usually stayed
        // safe, because the fallback ink is conservative, but it made the
        // committed colors disagree with the editor's own preview, which
        // computes against the candidate ground. Codex K1.
        backgroundOverrideLight = settings?.backgroundHex(dark: false).flatMap(Color.init(hex:))
        backgroundOverrideDark = settings?.backgroundHex(dark: true).flatMap(Color.init(hex:))
        var linkedLight: Color?
        var linkedDark: Color?
        if let s = settings, s.paletteLinked, let hue = s.accentHue {
            let saturation = s.accentSaturation ?? 0.7
            linkedLight = LSTheme.derivedAccent(hue: hue, saturation: saturation,
                                                dark: false,
                                                ground: groundBase(dark: false)).color
            linkedDark = LSTheme.derivedAccent(hue: hue, saturation: saturation,
                                               dark: true,
                                               ground: groundBase(dark: true)).color
        }
        let lightCustom = linkedLight
            ?? settings?.accentHex(dark: false).flatMap { Color(hex: $0) }
        let darkCustom = linkedDark
            ?? settings?.accentHex(dark: true).flatMap { Color(hex: $0) }
        // Corrected only if it fails. A color picked through the build 37
        // picker already clears the floor; this catches the ones stored before
        // it existed, which were never checked against anything.
        let lightAccent = LSTheme.legible(lightCustom ?? LSTheme.torchInk,
                                          on: groundBase(dark: false))
        let darkAccent = LSTheme.legible(darkCustom ?? LSTheme.torch,
                                         on: groundBase(dark: true))
        accent = .lsDynamic(light: lightAccent, dark: darkAccent)
        // No `legible()` here, and torch on BOTH grounds by default — the
        // hard step is the legibility mechanism. See `displayAccent`.
        displayAccent = .lsDynamic(light: lightCustom ?? LSTheme.torch,
                                   dark: darkCustom ?? LSTheme.torch)
        accentIsCustom = lightCustom != nil || darkCustom != nil
        // A knockout, not simply a contrasting ink — see `knockout(on:)`.
        //
        // Computed per appearance against that appearance's ACTUAL ground,
        // rather than letting a dynamic color resolve itself: the arithmetic
        // needs real components, and sampling a dynamic color picks whichever
        // trait is current when it is read.
        onAccent = .lsDynamic(
            light: knockoutPreview(on: lightAccent, ground: groundBase(dark: false)),
            dark: knockoutPreview(on: darkAccent, ground: groundBase(dark: true)))
        pageBackground = settings.flatMap { ThemePageBackground(rawValue: $0.pageBackgroundRaw) } ?? .cover
        defaultTrackerDisplay = settings.flatMap { TrackerDisplay(rawValue: $0.defaultTrackerDisplayRaw) } ?? .inline
        var overrides: [GameStatus: Color] = [:]
        for (raw, hex) in settings?.statusColors ?? [:] {
            if let status = GameStatus(rawValue: raw), let color = Color(hex: hex) {
                overrides[status] = color
            }
        }
        statusOverrides = overrides
        starNames = settings?.starNames ?? []
        statusNameOverrides = settings?.statusNames ?? [:]
        // Pushed into `PlatformShort` rather than held here, because that is
        // where every caller already asks. Sanitized on the way in: the value
        // arrives from CloudKit and a name this build does not offer must not
        // reach a shelf heading.
        PlatformShort.displayOverrides =
            PlatformNaming.sanitized(settings?.platformNames ?? [:])
        appearance = LSAppearance(raw: settings?.appearanceRaw)
        backdropIntensity = settings?.backdropIntensityRaw
            .flatMap(BackdropIntensity.init(rawValue:)) ?? .standard
        gamePageLayout = settings?.gamePageLayoutRaw
            .flatMap(GamePageLayout.init(rawValue:)) ?? .showcase
        showGameLogos = settings?.showGameLogos ?? true
        Self.chipsRawCache = settings?.ownershipChipsRaw
        ownershipChips = Self.chips(from: settings?.ownershipChipsRaw)
    }

    /// Stored order is ignored: the app's own `allCases` order is what keeps
    /// the chips in the same places on every game page, whatever order they
    /// were toggled in.
    static func chips(from raw: String?) -> [Ownership] {
        guard let raw else { return Ownership.shownByDefault }
        let parts = raw.split(separator: ",").map(String.init)
        let names = parts.filter { !$0.hasPrefix(OwnershipChipOrder.token) }
        let chosen = Set(names)
        let present = Ownership.allCases.filter { chosen.contains($0.rawValue) }
        guard !present.isEmpty else { return Ownership.shownByDefault }

        switch chipOrder(from: raw) {
        case .standard:
            return present
        case .mostUsed:
            // Ties fall back to the app's order, so a library where nothing is
            // used twice still looks like the default rather than like noise.
            let rank = Dictionary(uniqueKeysWithValues:
                Ownership.allCases.enumerated().map { ($1, $0) })
            return present.sorted {
                let a = ownershipUsage[$0.rawValue] ?? 0
                let b = ownershipUsage[$1.rawValue] ?? 0
                return a == b ? rank[$0]! < rank[$1]! : a > b
            }
        case .custom:
            // Stored order first, then anything the string does not mention —
            // a chip turned on by an older build, or a case added since.
            var seen: Set<Ownership> = []
            var ordered: [Ownership] = []
            for name in names {
                guard let kind = Ownership(rawValue: name), !seen.contains(kind) else { continue }
                ordered.append(kind); seen.insert(kind)
            }
            return ordered + present.filter { !seen.contains($0) }
        }
    }

    static func chipOrder(from raw: String?) -> OwnershipChipOrder {
        OwnershipChipOrder(token: raw?.split(separator: ",").map(String.init)
            .first { $0.hasPrefix(OwnershipChipOrder.token) })
    }

    /// How many games carry each ownership kind, for `OwnershipChipOrder.mostUsed`.
    ///
    /// Pushed in from Home, which already holds every game, rather than
    /// fetched here — the same shape as `PlatformShort.displayOverrides`. An
    /// empty map is not a failure state: `mostUsed` simply falls back to the
    /// app's own order until the library has been seen once.
    private(set) static var ownershipUsage: [String: Int] = [:]

    static func refreshOwnershipUsage(from games: [Game]) {
        var counts: [String: Int] = [:]
        for game in games where game.deletedAt == nil {
            for raw in game.ownership { counts[raw, default: 0] += 1 }
        }
        ownershipUsage = counts
        // `mostUsed` is the one order that depends on something outside the
        // settings record, so the resolved list has to be rebuilt when the
        // counts move — otherwise it is fixed at whatever launch saw.
        if chipOrder(from: chipsRawCache) == .mostUsed {
            ownershipChips = chips(from: chipsRawCache)
        }
    }

    /// The stored string, kept so `mostUsed` can be re-resolved without a
    /// second trip to the settings record.
    private static var chipsRawCache: String?

    /// The single settings record (created on first use). Duplicates from a
    /// sync race resolve to the oldest.
    static func fetchOrCreate(in context: ModelContext) -> ThemeSettings {
        let all = (try? context.fetch(FetchDescriptor<ThemeSettings>(
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        if let first = all.first { return first }
        let settings = ThemeSettings()
        context.insert(settings)
        return settings
    }
}
