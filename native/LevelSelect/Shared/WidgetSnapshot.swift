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
}

/// One tracker objective, for the interactive checklist widget.
struct WidgetObjective: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var done: Bool
}

/// One game on the Now Playing shelf.
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
    /// Preferred platform's short display name ("Switch", "SNES") — doubles
    /// as the value the shuffler's console filter matches against.
    var platform: String

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
            let platformOK = platform == nil || platform == game.platform
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
    var shufflePool: [WidgetPoolGame] = []
    var libraryPlatforms: [String] = []
    /// Minutes played per day, oldest → newest, today last (16 weeks' worth).
    /// Feeds the heatmap widget, the streak, and the week gauge.
    var dailyMinutes: [Double] = []
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

    var hasActiveSession: Bool { isPlaying || isPaused }

    var weeklyTotalSeconds: Double { weeklySeconds.reduce(0, +) }

    func coverImageURL() -> URL? { WidgetShared.coverURL(coverFileName) }

    // MARK: Persistence

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
        dailyMinutes: [Double] = [], weeklyAverageSeconds: Double = 0,
        completedCount: Int = 0, libraryCount: Int = 0,
        collections: [WidgetCollectionRef] = [],
        platformIcons: [String: String] = [:]
    ) {
        self.gameID = gameID; self.gameName = gameName; self.statusRaw = statusRaw
        self.isPlaying = isPlaying; self.isPaused = isPaused
        self.playtimeSeconds = playtimeSeconds; self.lastPlayedAt = lastPlayedAt
        self.nextObjective = nextObjective; self.nextObjectiveID = nextObjectiveID
        self.completionDone = completionDone; self.completionTotal = completionTotal
        self.coverFileName = coverFileName; self.activeSessionID = activeSessionID
        self.generatedAt = generatedAt
        self.objectives = objectives; self.nowPlaying = nowPlaying
        self.shufflePool = shufflePool; self.libraryPlatforms = libraryPlatforms
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
        dailyMinutes = try c.decodeIfPresent([Double].self, forKey: .dailyMinutes) ?? []
        weeklyAverageSeconds = try c.decodeIfPresent(Double.self, forKey: .weeklyAverageSeconds) ?? 0
        completedCount = try c.decodeIfPresent(Int.self, forKey: .completedCount) ?? 0
        libraryCount = try c.decodeIfPresent(Int.self, forKey: .libraryCount) ?? 0
        collections = try c.decodeIfPresent([WidgetCollectionRef].self, forKey: .collections) ?? []
        platformIcons = try c.decodeIfPresent([String: String].self, forKey: .platformIcons) ?? [:]
    }
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
