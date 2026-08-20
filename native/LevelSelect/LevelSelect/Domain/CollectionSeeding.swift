import Foundation

/// First drafts for the templates that can answer their own question.
///
/// This app times sessions and records how you own things, so for some of
/// these prompts it already knows a decent starting point — "where has your
/// time really gone" is a query, not an opinion. That is the part a list app
/// with no timer cannot do.
///
/// Everything here is a DRAFT. Each returns at most the template's slot count,
/// pre-filled so there is something to react to rather than an empty list, and
/// the user edits freely afterwards. Nothing here decides anything: a wrong
/// guess costs one swipe, an empty list costs the whole feature.
///
/// Pure and store-free — games in, games out — so the picking rules are
/// testable without SwiftData or a view.
enum CollectionSeeding {

    static func games(for seed: CollectionTemplate.Seed,
                      from games: [Game], limit: Int,
                      now: Date = .now) -> [Game] {
        let picked: [Game]
        switch seed {
        case .mostPlayed:
            picked = games
                .map { ($0, played($0, now: now)) }
                .filter { $0.1 > 0 }
                .sorted { ($0.1, $0.0.name) > ($1.1, $1.0.name) }
                .map(\.0)

        case .singleSitting:
            // One session, and it finished the game. Two sessions means you
            // got up, which is the whole claim the prompt makes.
            picked = games
                .filter { game in
                    !liveCompletions(game).isEmpty && sessions(game).count == 1
                }
                .sorted { played($0, now: now) > played($1, now: now) }

        case .physicalRetro:
            // Retro is doing real work here: "physical" alone would return a
            // shelf of last year's Switch games.
            picked = games
                .filter { $0.ownership.contains(Ownership.physical.rawValue) && isRetro($0) }
                .sorted { releaseYear($0) < releaseYear($1) }

        case .emulatedOnly:
            // Emulated AND nothing else — a game you also own on a cartridge
            // is not one you'll never hold a copy of.
            picked = games
                .filter { $0.ownership == [Ownership.emulated.rawValue] }
                .sorted { $0.name < $1.name }

        case .backlog:
            // Most recently added first: the ones you meant to play are the
            // ones you added while meaning to play them.
            picked = games
                .filter { $0.status == .backlog }
                .sorted { ($0.addedAt, $0.name) > ($1.addedAt, $1.name) }

        case .unreleasedWishlist:
            picked = games
                .filter { game in
                    guard game.status == .wishlist else { return false }
                    guard let date = game.firstReleaseDate else { return true }
                    return date > now
                }
                .sorted { ($0.firstReleaseDate ?? .distantFuture) < ($1.firstReleaseDate ?? .distantFuture) }
        }
        return Array(picked.prefix(limit))
    }

    // MARK: Helpers

    private static func sessions(_ game: Game) -> [Session] {
        game.livePlaythroughs.flatMap { ($0.sessions ?? []).filter { $0.deletedAt == nil } }
    }

    private static func liveCompletions(_ game: Game) -> [CompletionEvent] {
        (game.completionEvents ?? []).filter { $0.deletedAt == nil }
    }

    static func played(_ game: Game, now: Date = .now) -> TimeInterval {
        sessions(game).reduce(0) { $0 + $1.elapsed(asOf: now) }
    }

    private static func releaseYear(_ game: Game) -> Int {
        guard let date = game.firstReleaseDate else { return 9_999 }
        return Calendar.current.component(.year, from: date)
    }

    /// Before 2001. A line has to go somewhere, and this one puts the sixth
    /// generation's start just outside — a PS2 game is not what anyone means
    /// by a cartridge shelf.
    private static func isRetro(_ game: Game) -> Bool { releaseYear(game) < 2001 }
}
