import SwiftUI
import SwiftData

/// Resolved theme values, cached on the main actor so `GameStatus.color` and
/// `LSTheme.accent` stay cheap to read from any view. Refreshed from the
/// synced ThemeSettings record on launch and whenever it changes.
@MainActor
enum ThemePalette {
    private(set) static var accent: Color = LSTheme.defaultAccent
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
    private(set) static var backgroundOverride: Color?
    /// How hard the game-page backdrop reads.
    private(set) static var backdropIntensity: BackdropIntensity = .standard
    /// How game pages arrange their header.
    private(set) static var gamePageLayout: GamePageLayout = .showcase
    /// Whether a game's logo stands in for its name.
    private(set) static var showGameLogos = true

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
        // Warm, and deliberately not near .abandoned's colour: the whole
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
    static func luminance(of color: Color) -> Double {
        #if canImport(UIKit)
        let native = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard native.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
        #else
        guard let native = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        let r = native.redComponent, g = native.greenComponent, b = native.blueComponent
        #endif
        func lin(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    static func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(of: a), lb = luminance(of: b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// What to draw *inside* a filled accent surface, so the glyph reads as a
    /// hole punched through it rather than ink sitting on top.
    ///
    /// Tim, on a dark green accent in the light theme: *"that play text/icon
    /// should maybe be the color of the background… so it looks like it's cut
    /// out of the button."* The ground is the right answer because a knockout
    /// is literally the shape of the thing behind showing through — which is
    /// also why it has to be the ground and not white: white is a colour, the
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

    /// The same rule against a ground you name, so the colour editor can show
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
            // A much lower grey threshold than `groundBase` uses. The
            // default light ground is (0.97, 0.96, 1.00) — saturation 0.04,
            // deliberately barely purple — and treating that as grey threw
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
        let custom = settings?.accentHex.flatMap { Color(hex: $0) }
        accent = custom ?? LSTheme.defaultAccent
        accentIsCustom = custom != nil
        // A knockout, not simply a contrasting ink — see `knockout(on:)`.
        // Falls back to black/white on its own when the ground is too close
        // to the accent to be seen through it.
        onAccent = knockout(on: accent)
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
        appearance = LSAppearance(raw: settings?.appearanceRaw)
        backgroundOverride = settings?.backgroundHex.flatMap(Color.init(hex:))
        backdropIntensity = settings?.backdropIntensityRaw
            .flatMap(BackdropIntensity.init(rawValue:)) ?? .standard
        gamePageLayout = settings?.gamePageLayoutRaw
            .flatMap(GamePageLayout.init(rawValue:)) ?? .showcase
        showGameLogos = settings?.showGameLogos ?? true
    }

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
