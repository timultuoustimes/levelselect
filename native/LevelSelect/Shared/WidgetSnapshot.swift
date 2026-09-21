// Shared between the app and the widget extension. The app WRITES a small
// snapshot into the App Group; the widget READS it. The widget never touches
// SwiftData/CloudKit — keeping refreshes fast and offline-safe.
import Foundation

enum WidgetShared {
    static let appGroup = "group.com.timultuoustimes.levelselect"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget-snapshot.json")
    }
    static var coversDir: URL? {
        containerURL?.appendingPathComponent("covers", isDirectory: true)
    }
    /// On-disk URL for a cached cover file name (nil-safe).
    static func coverURL(_ fileName: String?) -> URL? {
        guard let fileName else { return nil }
        return coversDir?.appendingPathComponent(fileName)
    }

    /// Deep-link URL the widgets carry (handled by the app's `.onOpenURL`).
    static func gameURL(_ id: String) -> URL? {
        URL(string: "levelselect://game/\(id)")
    }
    static let homeURL = URL(string: "levelselect://home")
    static let statsURL = URL(string: "levelselect://stats")
    static let badgesURL = URL(string: "levelselect://badges")
}

/// One tracker objective, for the interactive checklist widget.
struct WidgetObjective: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var done: Bool
}

/// One game on the Now Playing shelf.
/// A wanted game that has not come out yet.
///
/// The date travels, not the countdown text. A widget can be rendered hours
/// after its snapshot was written, and a baked "in 2 days" would be wrong by
/// then — so the countdown is computed at draw time from the date, by the same
/// `ReleaseCountdown` the wishlist uses.
struct WidgetUpcomingGame: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var coverFileName: String?
    var releaseDate: Date
}

struct WidgetShelfGame: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var coverFileName: String?
    var isPlaying: Bool
    /// Additive fields for the iPad extra-large widgets. All optional so a
    /// snapshot written by an older build still decodes (missing keys are
    /// nil), and an older build reading a newer snapshot simply ignores them.
    /// Library status ("playing", "paused", "queued") for the shelf's dots.
    var statusRaw: String? = nil
    /// Tracker progress, when the game has one.
    var done: Int? = nil
    var total: Int? = nil
    /// Run record, when the game logs runs.
    var wins: Int? = nil
    var losses: Int? = nil
}

/// One game in the shuffle pool — everything "choose a game for me" needs to
/// pick and render without waking the app. Kept deliberately lean: ~150
/// entries ride every snapshot, so no per-game arrays.
struct WidgetPoolGame: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var coverFileName: String?
    var statusRaw: String
    /// Preferred platform's name as you see it ("Switch", or "Luffy").
    var platform: String
    /// The console itself ("Switch"), which the shuffler's filter matches —
    /// a name can change and a saved widget must not stop matching. Nil in a
    /// snapshot written before this existed.
    var platformKey: String? = nil

    /// The filter the shuffler applies, pure so it's testable. Statuses are
    /// raw values; completed joins the pool only when the toggle says so —
    /// short retro games are endlessly replayable, but that's an opt-in.
    static func filter(_ pool: [WidgetPoolGame],
                       statuses: Set<String>,
                       platform: String?,
                       includeCompleted: Bool) -> [WidgetPoolGame] {
        pool.filter { game in
            let statusOK = statuses.contains(game.statusRaw)
                || (includeCompleted && game.statusRaw == "completed")
            let platformOK = platform == nil || platform == (game.platformKey ?? game.platform)
                || platform == game.platform
            return statusOK && platformOK
        }
    }
}

/// Roguelike run summary for the most recently-played game that has runs.
struct WidgetRunGame: Codable, Hashable {
    var id: String
    var name: String
    var coverFileName: String?
    var inProgress: Bool
    var wins: Int
    var losses: Int
    var total: Int
    var lastOutcomeRaw: String?

    var winRate: Double {
        let decided = wins + losses
        return decided > 0 ? Double(wins) / Double(decided) : 0
    }
}

/// Everything the widgets need, in a few KB of JSON.
struct WidgetSnapshot: Codable, Hashable {
    // Continue Playing (current game)
    var gameID: String
    var gameName: String
    var statusRaw: String
    var isPlaying: Bool
    var isPaused: Bool
    var playtimeSeconds: Double
    var lastPlayedAt: Date?
    var nextObjective: String?
    var nextObjectiveID: String?
    /// The last thing ticked — what you were *doing*, as opposed to what's
    /// next. Additive and optional, so an older snapshot still decodes.
    var lastTicked: String? = nil
    var completionDone: Int
    var completionTotal: Int
    var coverFileName: String?
    var activeSessionID: String?
    var generatedAt: Date

    // Phase 2
    var objectives: [WidgetObjective]
    var nowPlaying: [WidgetShelfGame]
    var weeklySeconds: [Double]         // 7 entries, oldest → newest (today last)
    var gamesPlayedThisWeek: Int
    var runGame: WidgetRunGame?
    /// The shuffle pool and the platform list its config picker offers.
    ///
    /// `libraryPlatforms` is derived from the pool, so it is the systems you
    /// have GAMES on — which is what the shuffler needs, since a system with
    /// nothing on it has nothing to shuffle.
    var shufflePool: [WidgetPoolGame] = []
    var libraryPlatforms: [String] = []
    /// **The systems on your shelf**, which is not the same list.
    ///
    /// Since build 39 a console is a record you can own without a game on it,
    /// and Home shows those. The launcher widget's picker was still built
    /// from `libraryPlatforms` and so offered nothing at all to a library of
    /// four consoles and no games. Tim, 2026-09-08: *"In the Open To widget,
    /// I can't do consoles anymore?"* This is Home's own list — games'
    /// platforms unioned with the consoles you hold a record for.
    var systemShelves: [String] = []
    /// Console key → the name you gave it. `libraryPlatforms`,
    /// `systemShelves` and `platformIcons` are keyed by console; this is how
    /// a widget shows them. Absent keys show as themselves.
    var platformNames: [String: String] = [:]
    /// Minutes played per day, oldest → newest, today last (16 weeks' worth).
    /// Feeds the heatmap widget, the streak, and the week gauge.
    var dailyMinutes: [Double] = []
    /// The accent the user chose, as "#RRGGBB", or nil when they have not
    /// chosen one. Widgets cannot read ThemeSettings — it is SwiftData in the
    /// app's own store — so the accent travels here with everything else the
    /// app already tells them.
    var accentHex: String? = nil
    /// **The accent's two halves, because a widget cannot resolve a dynamic
    /// color the app froze.**
    ///
    /// `accentHex` was written by asking `ThemePalette.accent` for a hex,
    /// which resolves against whatever trait collection the app happened to
    /// be in when the snapshot was written. Once light and dark could hold
    /// different pairs (build 38), a Torch-light / Pink-dark library could put
    /// a pink widget on a light Home Screen. These carry both and let the
    /// widget pick, the way `LSWidget.accent` now does.
    ///
    /// Nil still means "no choice" — the widget falls back to the same
    /// default pair the app does, rather than to a copy of today's color.
    var accentHexLight: String? = nil
    var accentHexDark: String? = nil
    /// Light / dark / system, and a chosen background, traveling the same
    /// road as the accent and for the same reason: a widget cannot read
    /// ThemeSettings.
    ///
    /// A widget cannot use `.preferredColorScheme` — WidgetKit hands it the
    /// system's scheme and ignores that modifier — so it applies the choice as
    /// an environment override on its own content instead. Without this, an
    /// app pinned to dark would sit beside light widgets on the same screen.
    var appearanceRaw: String? = nil
    var backgroundHex: String? = nil
    /// The ground's tint per appearance, for the same reason as the accent —
    /// and this one was single-valued from the start: `backgroundOverride`
    /// hands back the DARK tint only, so a light Home Screen has been drawing
    /// the dark choice's ground since build 37.
    var backgroundHexLight: String? = nil
    var backgroundHexDark: String? = nil
    /// Status colors the user has actually changed, `GameStatus.rawValue` →
    /// "#RRGGBB". Absent keys mean "never touched it", NOT "use this default":
    /// the widgets keep their own built-in colors for those, so nobody's Home
    /// Screen changes because this field arrived. A4.
    var statusColors: [String: String] = [:]
    /// Wishlist games with a real date still ahead, soonest first.
    var upcoming: [WidgetUpcomingGame] = []
    /// Average seconds per week over the four *finished* weeks before this
    /// one — the gauge's "my own pace" reference.
    var weeklyAverageSeconds: Double = 0
    /// Library-wide finished share, for the stats tile.
    var completedCount: Int = 0
    var libraryCount: Int = 0
    /// Collections, for the launcher widget's picker.
    var collections: [WidgetCollectionRef] = []
    /// Short platform name → console icon asset name, for launcher portals.
    var platformIcons: [String: String] = [:]

    /// Badges earned, newest first, and how many there are to earn.
    ///
    /// Defaulted, like everything added after the first snapshot shipped: a
    /// widget must be able to decode a file written by the previous build,
    /// or it shows nothing until the app next happens to open.
    var badges: [WidgetBadge] = []
    var badgesTotal: Int = 0
    /// How many are earned in the ledger. Separate from `badges.count`, which
    /// is capped so the file stays small.
    var badgesEarnedCount: Int = 0

    var hasActiveSession: Bool { isPlaying || isPaused }

    var weeklyTotalSeconds: Double { weeklySeconds.reduce(0, +) }

    func coverImageURL() -> URL? { WidgetShared.coverURL(coverFileName) }

    // MARK: Persistence

    /// **The snapshot, but only when there is a game to show.**
    ///
    /// Since build 39 a library can hold consoles and collections and no
    /// games at all, and the snapshot is written for those — the launcher
    /// widget's picker is built from it, and a library of four consoles used
    /// to offer nothing to open. Every widget that leads with a game asks
    /// through here instead, so it keeps the empty state it had when a
    /// game-free library meant no snapshot at all.
    static func loadWithGame() -> WidgetSnapshot? {
        guard let s = load(), !s.gameID.isEmpty else { return nil }
        return s
    }

    static func load() -> WidgetSnapshot? {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = WidgetShared.snapshotURL,
              let data = try? Self.encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url = WidgetShared.snapshotURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // MARK: Inits

    init(
        gameID: String, gameName: String, statusRaw: String,
        isPlaying: Bool, isPaused: Bool, playtimeSeconds: Double,
        lastPlayedAt: Date?, nextObjective: String?, nextObjectiveID: String?,
        completionDone: Int, completionTotal: Int, coverFileName: String?,
        activeSessionID: String?, generatedAt: Date,
        objectives: [WidgetObjective], nowPlaying: [WidgetShelfGame],
        weeklySeconds: [Double], gamesPlayedThisWeek: Int, runGame: WidgetRunGame?,
        shufflePool: [WidgetPoolGame] = [], libraryPlatforms: [String] = [],
        systemShelves: [String] = [],
        platformNames: [String: String] = [:],
        dailyMinutes: [Double] = [], weeklyAverageSeconds: Double = 0,
        completedCount: Int = 0, libraryCount: Int = 0,
        collections: [WidgetCollectionRef] = [],
        platformIcons: [String: String] = [:],
        lastTicked: String? = nil,
        accentHex: String? = nil,
        accentHexLight: String? = nil,
        accentHexDark: String? = nil,
        appearanceRaw: String? = nil,
        backgroundHex: String? = nil,
        backgroundHexLight: String? = nil,
        backgroundHexDark: String? = nil,
        statusColors: [String: String] = [:],
        upcoming: [WidgetUpcomingGame] = []
    ) {
        self.accentHex = accentHex
        self.accentHexLight = accentHexLight
        self.accentHexDark = accentHexDark
        self.statusColors = statusColors
        self.appearanceRaw = appearanceRaw
        self.backgroundHex = backgroundHex
        self.backgroundHexLight = backgroundHexLight
        self.backgroundHexDark = backgroundHexDark
        self.upcoming = upcoming
        self.lastTicked = lastTicked
        self.gameID = gameID; self.gameName = gameName; self.statusRaw = statusRaw
        self.isPlaying = isPlaying; self.isPaused = isPaused
        self.playtimeSeconds = playtimeSeconds; self.lastPlayedAt = lastPlayedAt
        self.nextObjective = nextObjective; self.nextObjectiveID = nextObjectiveID
        self.completionDone = completionDone; self.completionTotal = completionTotal
        self.coverFileName = coverFileName; self.activeSessionID = activeSessionID
        self.generatedAt = generatedAt
        self.objectives = objectives; self.nowPlaying = nowPlaying
        self.shufflePool = shufflePool; self.libraryPlatforms = libraryPlatforms
        self.systemShelves = systemShelves
        self.platformNames = platformNames
        self.dailyMinutes = dailyMinutes; self.weeklyAverageSeconds = weeklyAverageSeconds
        self.completedCount = completedCount; self.libraryCount = libraryCount
        self.collections = collections
        self.platformIcons = platformIcons
        self.weeklySeconds = weeklySeconds; self.gamesPlayedThisWeek = gamesPlayedThisWeek
        self.runGame = runGame
    }

    /// Tolerant decoder: older snapshots (pre-Phase 2) still power the Phase 1
    /// widgets — missing fields fall back to sensible empties.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameID = try c.decode(String.self, forKey: .gameID)
        gameName = try c.decode(String.self, forKey: .gameName)
        statusRaw = try c.decodeIfPresent(String.self, forKey: .statusRaw) ?? ""
        lastTicked = try c.decodeIfPresent(String.self, forKey: .lastTicked)
        isPlaying = try c.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false
        isPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        playtimeSeconds = try c.decodeIfPresent(Double.self, forKey: .playtimeSeconds) ?? 0
        lastPlayedAt = try c.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        nextObjective = try c.decodeIfPresent(String.self, forKey: .nextObjective)
        nextObjectiveID = try c.decodeIfPresent(String.self, forKey: .nextObjectiveID)
        completionDone = try c.decodeIfPresent(Int.self, forKey: .completionDone) ?? 0
        completionTotal = try c.decodeIfPresent(Int.self, forKey: .completionTotal) ?? 0
        coverFileName = try c.decodeIfPresent(String.self, forKey: .coverFileName)
        activeSessionID = try c.decodeIfPresent(String.self, forKey: .activeSessionID)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .init(timeIntervalSince1970: 0)
        objectives = try c.decodeIfPresent([WidgetObjective].self, forKey: .objectives) ?? []
        nowPlaying = try c.decodeIfPresent([WidgetShelfGame].self, forKey: .nowPlaying) ?? []
        weeklySeconds = try c.decodeIfPresent([Double].self, forKey: .weeklySeconds) ?? []
        gamesPlayedThisWeek = try c.decodeIfPresent(Int.self, forKey: .gamesPlayedThisWeek) ?? 0
        runGame = try c.decodeIfPresent(WidgetRunGame.self, forKey: .runGame)
        shufflePool = try c.decodeIfPresent([WidgetPoolGame].self, forKey: .shufflePool) ?? []
        libraryPlatforms = try c.decodeIfPresent([String].self, forKey: .libraryPlatforms) ?? []
        // An older snapshot has no key here, and a widget reading one must
        // still offer the systems it can see — so it falls back to the list
        // that used to be the only one.
        systemShelves = try c.decodeIfPresent([String].self, forKey: .systemShelves) ?? libraryPlatforms
        platformNames = try c.decodeIfPresent([String: String].self, forKey: .platformNames) ?? [:]
        dailyMinutes = try c.decodeIfPresent([Double].self, forKey: .dailyMinutes) ?? []
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex)
        // A snapshot written before build 38 carries only the single hex, and
        // that hex IS what both appearances were showing — so falling back to
        // it reproduces the old behavior exactly rather than dropping the
        // user's accent until the app next writes.
        //
        // Safe in a way the GROUND's fallback below was not: the bridge writes
        // both accent halves together or neither (they are gated on the same
        // `accentIsCustom`), so a missing key here always means an old file,
        // never "this appearance has no choice". A nil optional is omitted
        // rather than encoded as null, so those two cases are otherwise
        // indistinguishable — see the note on the ground.
        accentHexLight = try c.decodeIfPresent(String.self, forKey: .accentHexLight) ?? accentHex
        accentHexDark = try c.decodeIfPresent(String.self, forKey: .accentHexDark) ?? accentHex
        // decodeIfPresent, like every field added after v1: an older snapshot
        // on disk simply has no key, and must still decode.
        appearanceRaw = try c.decodeIfPresent(String.self, forKey: .appearanceRaw)
        backgroundHex = try c.decodeIfPresent(String.self, forKey: .backgroundHex)
        // **The legacy ground hex was the DARK tint, and only that.**
        //
        // `ThemePalette.backgroundOverride` hands back `backgroundOverrideDark`
        // — that is the whole reason a light Home Screen was drawing the dark
        // choice's ground. So it can stand in for dark, and must NEVER stand
        // in for light.
        //
        // Falling back on both is what broke Tim's widget the first time:
        // Swift's synthesized encoder OMITS a nil optional rather than writing
        // null, so `backgroundHexLight` is missing from a NEW snapshot whenever
        // no light ground has been chosen — indistinguishable from an old
        // snapshot that never had the key. `decodeIfPresent ?? backgroundHex`
        // then handed the light side the dark tint again, and the fix looked
        // like it had done nothing. Tim: *"the widget isn't changing from the
        // dark mode background selection when I go back to light mode."*
        //
        // No fallback here means an unchosen light ground is the DEFAULT
        // ground, which is what the app itself draws.
        backgroundHexLight = try c.decodeIfPresent(String.self, forKey: .backgroundHexLight)
        backgroundHexDark = try c.decodeIfPresent(String.self, forKey: .backgroundHexDark)
            ?? backgroundHex
        statusColors = try c.decodeIfPresent([String: String].self, forKey: .statusColors) ?? [:]
        upcoming = try c.decodeIfPresent([WidgetUpcomingGame].self, forKey: .upcoming) ?? []
        weeklyAverageSeconds = try c.decodeIfPresent(Double.self, forKey: .weeklyAverageSeconds) ?? 0
        completedCount = try c.decodeIfPresent(Int.self, forKey: .completedCount) ?? 0
        libraryCount = try c.decodeIfPresent(Int.self, forKey: .libraryCount) ?? 0
        collections = try c.decodeIfPresent([WidgetCollectionRef].self, forKey: .collections) ?? []
        platformIcons = try c.decodeIfPresent([String: String].self, forKey: .platformIcons) ?? [:]
    }
}


/// One earned badge, flattened for the widget.
///
/// The symbol name travels rather than the drawing: the widget renders it in
/// the accent exactly as the Journal does, and when there is real art the
/// file name joins it here without anything else changing.
struct WidgetBadge: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    var earnedAt: Date
}

/// A collection the launcher widget can point at.
struct WidgetCollectionRef: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var count: Int
    /// Top members (most active first) for the portal launcher's art wall.
    /// Parallel arrays over a struct to keep the synthesized Codable simple.
    var memberIDs: [String] = []
    var memberCovers: [String?] = []

    /// Tolerant on purpose: this morning's snapshots already carry
    /// collections WITHOUT the member arrays, and a widget that can't decode
    /// yesterday's file shows nothing until the app happens to open.
    init(id: String, name: String, count: Int,
         memberIDs: [String] = [], memberCovers: [String?] = []) {
        self.id = id; self.name = name; self.count = count
        self.memberIDs = memberIDs; self.memberCovers = memberCovers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        memberIDs = try c.decodeIfPresent([String].self, forKey: .memberIDs) ?? []
        memberCovers = try c.decodeIfPresent([String?].self, forKey: .memberCovers) ?? []
    }
}

/// Pure math shared by the streak, gauge, and heatmap surfaces — pure so the
/// tests need no store and the widgets and app can't drift apart.
enum WidgetMath {
    /// Consecutive play days counting back from today. A zero TODAY doesn't
    /// break the streak — the day isn't over — but a zero before that does.
    static func streak(dailyMinutes: [Double]) -> Int {
        guard !dailyMinutes.isEmpty else { return 0 }
        var days = dailyMinutes
        let today = days.removeLast()
        var run = today > 0 ? 1 : 0
        for minutes in days.reversed() {
            guard minutes > 0 else { break }
            run += 1
        }
        return run
    }

    /// Gauge position: this week against your own four-week pace, clamped so
    /// a monster week pins the needle rather than wrapping it.
    static func gaugeValue(thisWeekSeconds: Double, averageSeconds: Double) -> Double {
        guard averageSeconds > 0 else { return thisWeekSeconds > 0 ? 1 : 0 }
        return min(thisWeekSeconds / averageSeconds, 1.0)
    }
}
