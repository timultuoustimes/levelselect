import Foundation

/// Finds a game's wordmark, so the header can use one without being asked.
///
/// The gap this closes: build 32 shipped a logo *picker* and a header built
/// around logos, but nothing ever fetched one — so a logo only appeared on
/// games where someone had gone in and chosen it by hand, one at a time. The
/// cover and the backdrop have never worked that way, and a header feature
/// that needs manual setup per game across a four-hundred-game library is a
/// feature almost nobody sees.
///
/// Resolution order, highest priority first:
///   1. The game's own `logoURLString` — an explicit per-game choice always wins.
///   2. IGDB, in its own preference order: color, then white, then black.
///   3. SteamGridDB, which has logos for a great many games IGDB doesn't.
///   4. Nothing, and the header draws the game's name as text.
///
/// **PNG, never JPEG.** A logo is a transparent image and the extension is
/// what decides whether that survives — `.jpg` flattens alpha onto black,
/// which is exactly how these looked before anyone noticed they were being
/// requested as the wrong format.
///
/// Caches to `UserDefaults` like `BackdropArt` — by IGDB id where there is
/// one, by name otherwise — including
/// **misses** — a game with no logo anywhere is the case most worth
/// remembering, or every visit re-asks two services to learn the same
/// nothing. Deliberately not a stored model field: a cache of derived URLs is
/// not user data and would cost a CloudKit promote to sync something every
/// device can work out for itself.
@MainActor
enum LogoArt {
    private static let defaultsKey = "logoArtCache"
    /// Cache key → URL string, or "" for a known miss.
    ///
    /// Keyed by IGDB id where there is one and by name otherwise, because a
    /// game added by hand has no IGDB id — and those are precisely the games
    /// IGDB won't have a logo for, so they are the ones that most need the
    /// SteamGridDB fallback to be reachable.
    private static var memory: [String: String] = [:]

    /// The wordmark a game page should draw, if one can be found.
    ///
    /// Returns immediately from cache when possible. Callers await this from a
    /// `.task` and render the text name until it returns, so the header is
    /// never empty while a lookup is in flight.
    static func url(for game: Game) async -> URL? {
        // An explicit choice wins outright, and a locally-stored image is the
        // view's job (it holds bytes, not a URL) — `Game.resolvedArtwork(.logo)`
        // covers both, so this only runs when neither applies.
        if game.logoURLString != nil { return nil }

        let key = game.igdbID.map { "igdb:\($0)" }
            ?? "name:\(game.name.lowercased())"
        if let cached = memory[key] { return cached.isEmpty ? nil : URL(string: cached) }
        if let stored = diskCache()[key] {
            memory[key] = stored
            return stored.isEmpty ? nil : URL(string: stored)
        }

        var found = ""
        // IGDB first, when the game is matched to it: that art is the
        // publisher's, and it costs a request the artwork picker often makes
        // anyway. A game added by hand simply skips this and goes straight to
        // the search-by-name source below.
        if let igdbID = game.igdbID {
            let rows = await IGDBService.raw(
                endpoint: "artworks",
                query: "fields image_id,image_type; where game = \(igdbID); limit 50;")
            for type in IGDBImageType.logos {
                if let hit = rows.first(where: { $0["image_type"] as? Int == type }),
                   let imageID = hit["image_id"] as? String {
                    found = "https://images.igdb.com/igdb/image/upload/t_720p/\(imageID).png"
                    break
                }
            }
        }
        // Then SteamGridDB, which is why it was integrated — IGDB's logo
        // coverage is partial and the gap is the newer, smaller games.
        if found.isEmpty {
            let art = await SteamGridDBService.artwork(for: game, role: .logo)
            if let first = art?.first { found = first.full }
        }

        memory[key] = found
        var disk = diskCache()
        disk[key] = found
        UserDefaults.standard.set(disk, forKey: defaultsKey)
        return found.isEmpty ? nil : URL(string: found)
    }

    private static func diskCache() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    /// For the artwork picker, after someone chooses or clears a logo by hand:
    /// the cached automatic answer is no longer what the page should draw.
    static func forget(_ game: Game) {
        let key = game.igdbID.map { "igdb:\($0)" }
            ?? "name:\(game.name.lowercased())"
        memory[key] = nil
        var disk = diskCache()
        disk[key] = nil
        UserDefaults.standard.set(disk, forKey: defaultsKey)
    }
}
