import SwiftUI
import SwiftData

/// Resolved theme values, cached on the main actor so `GameStatus.color` and
/// `LSTheme.accent` stay cheap to read from any view. Refreshed from the
/// synced ThemeSettings record on launch and whenever it changes.
@MainActor
enum ThemePalette {
    private(set) static var accent: Color = LSTheme.purple
    /// True once the user has picked their own accent. The wordmark keeps its
    /// brand torch-orange until then, so the default look is unchanged.
    private(set) static var accentIsCustom = false
    private(set) static var pageBackground: ThemePageBackground = .cover
    private(set) static var defaultTrackerDisplay: TrackerDisplay = .inline
    private static var statusOverrides: [GameStatus: Color] = [:]
    /// Custom words on the five stars ([] = the built-in labels).
    private(set) static var starNames: [String] = []
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

    /// Built-in defaults (the palette shipped before theming existed).
    static func defaultColor(for status: GameStatus) -> Color {
        switch status {
        case .playing:   .green
        case .paused:    .orange
        case .completed: .blue
        case .queued:    .purple
        case .backlog:   .gray
        case .shelved:   .brown
        case .abandoned: .red
        case .wishlist:  .pink
        case .ongoing:   .teal
        }
    }

    static func color(for status: GameStatus) -> Color {
        statusOverrides[status] ?? defaultColor(for: status)
    }

    static func refresh(from settings: ThemeSettings?) {
        let custom = settings?.accentHex.flatMap { Color(hex: $0) }
        accent = custom ?? LSTheme.purple
        accentIsCustom = custom != nil
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

// MARK: - Color ↔ hex

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    func hexString() -> String? {
        #if os(macOS)
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = converted.redComponent, g = converted.greenComponent, b = converted.blueComponent
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}
