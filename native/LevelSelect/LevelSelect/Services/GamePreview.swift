import Foundation

/// Enough of a game to tell whether it is the one you meant.
///
/// Search returns a name, a cover and a year, which is enough to disambiguate
/// a sequel and not enough for anything else. Tim: *"I should be able to see
/// the game trailer, screenshots, about, and other game info before confirming
/// that it's the right game I want."*
///
/// Fetched only when a result is opened, never for the list — a search of ten
/// results would otherwise be eleven requests, ten of them for games nobody
/// chose.
struct GamePreview: Sendable {
    var screenshotIDs: [String] = []
    /// YouTube ids, trailer first — IGDB names its trailer rows, and a
    /// gameplay video is a better preview than a teaser when both exist.
    var videoIDs: [String] = []

    var isEmpty: Bool { screenshotIDs.isEmpty && videoIDs.isEmpty }
}

@MainActor
enum GamePreviewService {
    /// Kept for the life of the sheet: going back to the results and forward
    /// into the same game again is a normal thing to do while deciding, and it
    /// should not cost another round trip each time.
    private static var cache: [Int: GamePreview] = [:]

    static func load(igdbID: Int) async -> GamePreview {
        if let hit = cache[igdbID] { return hit }

        async let shots = IGDBService.raw(
            endpoint: "screenshots",
            query: "fields image_id; where game = \(igdbID); limit 6;")
        // `name` comes along so a trailer can be preferred over a teaser.
        async let clips = IGDBService.raw(
            endpoint: "game_videos",
            query: "fields video_id, name; where game = \(igdbID); limit 6;")

        var preview = GamePreview()
        preview.screenshotIDs = (await shots).compactMap { $0["image_id"] as? String }
        let rows = await clips
        let trailers = rows.filter {
            (($0["name"] as? String) ?? "").localizedCaseInsensitiveContains("trailer")
        }
        preview.videoIDs = (trailers + rows.filter { row in
            !trailers.contains { ($0["video_id"] as? String) == (row["video_id"] as? String) }
        }).compactMap { $0["video_id"] as? String }

        cache[igdbID] = preview
        return preview
    }
}
