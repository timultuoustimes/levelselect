import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Writes the shared widget snapshot from the live store and pokes WidgetKit
/// to reload. Called on launch, on scene changes, and after session mutations.
@MainActor
enum WidgetBridge {
    static func refresh() {
        let ctx = LevelSelectStore.shared.mainContext
        guard let (snapshot, coverURL) = build(context: ctx) else {
            WidgetSnapshot.clear()
            reload()
            return
        }
        snapshot.save()
        reload()

        // Cache the cover out-of-band; reload again once it lands so the tile
        // swaps its themed placeholder for real box art.
        if let coverURL, let name = snapshot.coverFileName, !coverExists(name) {
            Task.detached(priority: .utility) {
                await cacheCover(from: coverURL, fileName: name)
                await MainActor.run { reload() }
            }
        }
    }

    private static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: Snapshot

    /// Returns the snapshot plus the cover URL to cache (if any).
    private static func build(context: ModelContext) -> (WidgetSnapshot, URL?)? {
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        guard let games = try? context.fetch(descriptor), !games.isEmpty else { return nil }

        // Continue Playing: playing/paused first (most recent activity), else
        // the most recently played game so the tile is never empty.
        let active = games
            .filter { $0.status == .playing || $0.status == .paused }
            .max { activityKey($0) < activityKey($1) }
        guard let game = active ?? mostRecentlyPlayed(games) else { return nil }

        let pt = game.activePlaythrough
        let session = pt?.activeSession
        let (objective, done, total) = trackerProgress(game: game, pt: pt)

        let coverName = game.coverURLString.map(coverFileName(for:))

        let snapshot = WidgetSnapshot(
            gameID: game.id.uuidString,
            gameName: game.name,
            statusRaw: game.status.rawValue,
            isPlaying: session?.state == .running,
            isPaused: session?.state == .paused,
            playtimeSeconds: pt?.totalPlaytime() ?? 0,
            lastPlayedAt: pt?.lastPlayedAt,
            nextObjective: objective,
            completionDone: done,
            completionTotal: total,
            coverFileName: coverName,
            activeSessionID: session?.id.uuidString,
            generatedAt: .now
        )
        let coverURL = game.coverURLString.flatMap(URL.init(string:))
        return (snapshot, coverURL)
    }

    private static func activityKey(_ g: Game) -> (Bool, Date) {
        (g.pinned, g.livePlaythroughs.compactMap(\.lastPlayedAt).max() ?? g.addedAt)
    }

    private static func mostRecentlyPlayed(_ games: [Game]) -> Game? {
        games
            .filter { $0.livePlaythroughs.contains { $0.lastPlayedAt != nil } }
            .max { activityKey($0) < activityKey($1) }
    }

    /// First uncompleted, non-spoiler objective + overall done/total.
    private static func trackerProgress(game: Game, pt: Playthrough?) -> (String?, Int, Int) {
        guard let schema = game.trackerSchema else { return (nil, 0, 0) }
        let cats = TrackerSchemaJSON.categories(from: schema.jsonData)
        let states = (pt?.trackerStates ?? []).filter { $0.deletedAt == nil }
        let byItem = Dictionary(states.map { ($0.itemID, $0) }, uniquingKeysWith: { a, _ in a })

        let allItems = cats.flatMap(\.items)
        let done = allItems.filter { byItem[$0.id]?.completed == true }.count

        // Skip hidden-until-discovered items that haven't been revealed (no spoilers).
        let next = allItems.first { item in
            byItem[item.id]?.completed != true &&
            !(item.hideUntilDiscovered && byItem[item.id]?.revealed != true)
        }
        return (next?.name, done, allItems.count)
    }

    // MARK: Cover cache

    private static func coverFileName(for urlString: String) -> String {
        // Stable, filesystem-safe name derived from the URL.
        let hash = UInt64(bitPattern: Int64(urlString.hashValue))
        return "cover-\(hash).jpg"
    }

    private static func coverExists(_ name: String) -> Bool {
        guard let url = WidgetShared.coversDir?.appendingPathComponent(name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func cacheCover(from url: URL, fileName: String) async {
        #if canImport(UIKit)
        guard let dir = WidgetShared.coversDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        let target = downscale(image, maxWidth: 320)
        guard let jpeg = target.jpegData(compressionQuality: 0.85) else { return }
        try? jpeg.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        #endif
    }

    #if canImport(UIKit)
    private static func downscale(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        guard image.size.width > maxWidth else { return image }
        let scale = maxWidth / image.size.width
        let size = CGSize(width: maxWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    #endif
}
