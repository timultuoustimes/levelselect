import Foundation

/// A cover for a game IGDB has never heard of.
///
/// The logo already had this: `LogoArt` falls back to SteamGridDB **by name**,
/// which was built for exactly this shape of game. Covers had no equivalent,
/// so a hand-added game stayed a grey rectangle in every grid it appeared in —
/// and a library is mostly covers, so one blank tile in a wall of art reads as
/// a mistake rather than as missing data.
///
/// This is the itch.io case in particular. Those games frequently have no IGDB
/// entry at all, which is what makes the manual-add path a first-class flow
/// rather than a fallback — but it improves every hand-added game, not just
/// itch ones.
///
/// Writes `coverURLString` once rather than resolving per view. A cover is
/// drawn in the library grid, the shelves, the widgets and the watch; fetching
/// it at each site would be the same lookup many times over, and none of those
/// surfaces can await anything.
@MainActor
enum CoverArt {
    /// Games worth asking about: no cover, and no IGDB id to get one from.
    ///
    /// A game WITH an id and no cover is IGDB's problem and the fill pass
    /// already reports it; asking SteamGridDB for those would paper over a
    /// wrong match with a plausible-looking picture.
    static func needsCover(_ game: Game) -> Bool {
        game.igdbID == nil
            && (game.coverURLString ?? "").isEmpty
            && (game.coverImageID ?? "").isEmpty
            && game.liveImages(role: .cover).isEmpty
    }

    /// Resolve and store covers for games that have none. Returns how many
    /// were found.
    ///
    /// Sequential on purpose: this runs inside the same user-initiated pass
    /// that fills metadata, against a service with no published rate limit,
    /// for a set that is normally a handful of games. Speed here would be
    /// bought with a burst of requests nobody asked for.
    @discardableResult
    static func fill(_ games: [Game], repository: Repository) async -> Int {
        var found = 0
        for game in games where needsCover(game) {
            guard let art = await SteamGridDBService.artwork(for: game, role: .cover),
                  let first = art.first else { continue }
            repository.edit(game) { $0.coverURLString = first.full }
            found += 1
        }
        return found
    }
}
