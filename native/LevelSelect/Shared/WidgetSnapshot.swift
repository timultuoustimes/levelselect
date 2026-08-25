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
        weeklySeconds: [Double], gamesPlayedThisWeek: Int, runGame: WidgetRunGame?
    ) {
        self.gameID = gameID; self.gameName = gameName; self.statusRaw = statusRaw
        self.isPlaying = isPlaying; self.isPaused = isPaused
        self.playtimeSeconds = playtimeSeconds; self.lastPlayedAt = lastPlayedAt
        self.nextObjective = nextObjective; self.nextObjectiveID = nextObjectiveID
        self.completionDone = completionDone; self.completionTotal = completionTotal
        self.coverFileName = coverFileName; self.activeSessionID = activeSessionID
        self.generatedAt = generatedAt
        self.objectives = objectives; self.nowPlaying = nowPlaying
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
    }
}
