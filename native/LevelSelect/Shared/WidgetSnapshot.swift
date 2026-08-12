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

    /// Deep-link URL the widgets carry (handled by the app's `.onOpenURL`).
    static func gameURL(_ id: String) -> URL? {
        URL(string: "levelselect://game/\(id)")
    }
    static let homeURL = URL(string: "levelselect://home")
}

/// Everything the Phase 1 widgets need, in a few KB of JSON.
struct WidgetSnapshot: Codable, Hashable {
    var gameID: String
    var gameName: String
    var statusRaw: String
    var isPlaying: Bool
    var isPaused: Bool
    var playtimeSeconds: Double
    var lastPlayedAt: Date?
    var nextObjective: String?
    var completionDone: Int
    var completionTotal: Int
    var coverFileName: String?
    var activeSessionID: String?
    var generatedAt: Date

    var hasActiveSession: Bool { isPlaying || isPaused }

    func coverImageURL() -> URL? {
        guard let name = coverFileName else { return nil }
        return WidgetShared.coversDir?.appendingPathComponent(name)
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
}
