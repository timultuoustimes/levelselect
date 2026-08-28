import Foundation

/// Finds the wide image that sits behind a game page header.
///
/// This is the piece that was missing: build 32 shipped a backdrop *picker*
/// and an intensity control, but nothing ever fetched artwork, so the
/// backdrop silently fell back to the cover — a 3:4 image cropped into a wide
/// band, which is the least characteristic slice of it. No blur setting can
/// rescue the wrong picture.
///
/// Resolution order, highest priority first:
///   1. The game's own `backdropURLString` — an explicit per-game choice always wins.
///   2. The library preference (`ThemePageBackground`): key art or a screenshot.
///   3. The other one of those two, if the preferred kind doesn't exist.
///   4. The cover, blurred, as a genuine last resort.
///
/// Caches to `UserDefaults` keyed by IGDB id, so a game is looked up once per
/// device and never again. Deliberately NOT a stored model field: a cache of
/// derived URLs is not user data, it would cost a CloudKit promote, and it
/// would sync a value every device can compute for itself.
@MainActor
enum BackdropArt {
    private static let defaultsKey = "backdropArtCache"
    /// igdbID → [endpoint: image id]. Two endpoints per game, so a switch
    /// between key art and screenshots costs no second fetch.
    private static var memory: [Int: [String: String]] = [:]

    /// What a game page should draw behind its header, if anything.
    ///
    /// Returns immediately from cache when possible; otherwise performs at
    /// most one lookup per endpoint per game. Callers await this from a
    /// `.task`, and should show the cover fallback until it returns.
    static func url(for game: Game, preference: ThemePageBackground) async -> URL? {
        // 1. An explicit per-game choice wins over everything.
        if let pointer = game.backdropURLString,
           let explicit = ArtworkPointer.remoteURL(pointer) {
            return explicit
        }
        // A local per-game image is handled by the view (it holds bytes, not
        // a URL) — `Game.resolvedArtwork(.backdrop)` covers that path.
        if ArtworkPointer.localID(game.backdropURLString) != nil { return nil }

        guard preference.igdbEndpoint != nil, let igdbID = game.igdbID else { return nil }

        let ids = await imageIDs(for: igdbID)
        // Preferred kind, then the other — a game with only screenshots
        // shouldn't fall all the way back to its cover just because the
        // library is set to key art.
        let order: [ThemePageBackground] = preference == .screenshot
            ? [.screenshot, .keyArt]
            : [.keyArt, .screenshot]
        for kind in order {
            guard let endpoint = kind.igdbEndpoint, let imageID = ids[endpoint] else { continue }
            return URL(string:
                "https://images.igdb.com/igdb/image/upload/\(kind.igdbSize)/\(imageID).jpg")
        }
        return nil
    }

    // MARK: Lookup + cache

    private static func imageIDs(for igdbID: Int) async -> [String: String] {
        if let hit = memory[igdbID] { return hit }
        if let stored = diskCache()[String(igdbID)] {
            memory[igdbID] = stored
            return stored
        }

        // One request per endpoint, both in flight together. `limit 1` because
        // only the first is ever drawn — picking a different one is what the
        // artwork picker is for.
        async let art = IGDBService.raw(
            endpoint: "artworks", query: "fields image_id; where game = \(igdbID); limit 1;")
        async let shots = IGDBService.raw(
            endpoint: "screenshots", query: "fields image_id; where game = \(igdbID); limit 1;")

        var found: [String: String] = [:]
        if let id = (await art).first?["image_id"] as? String { found["artworks"] = id }
        if let id = (await shots).first?["image_id"] as? String { found["screenshots"] = id }

        // Cached even when EMPTY. A game with no art on IGDB is the case most
        // worth remembering — otherwise every visit re-asks and re-spends
        // proxy quota to learn the same nothing.
        memory[igdbID] = found
        var disk = diskCache()
        disk[String(igdbID)] = found
        UserDefaults.standard.set(disk, forKey: defaultsKey)
        return found
    }

    private static func diskCache() -> [String: [String: String]] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String: String]] ?? [:]
    }

    /// Forget everything — for the Fix Match path, where the game the ids
    /// belonged to is no longer the game on screen.
    static func forget(igdbID: Int) {
        memory[igdbID] = nil
        var disk = diskCache()
        disk.removeValue(forKey: String(igdbID))
        UserDefaults.standard.set(disk, forKey: defaultsKey)
    }
}
