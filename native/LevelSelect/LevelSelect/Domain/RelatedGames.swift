import Foundation

/// What else in your library connects to this game.
///
/// Four different relationships, in descending order of how certain they are:
/// a collection you put it in yourself, a series it belongs to, a studio that
/// made it, and — last and weakest — games that merely resemble it.
///
/// The resemblance rule is the one worth being careful about. The web app
/// counted a single shared tag as similar, so The Messenger (Platform,
/// Adventure, Indie, Arcade, Action, Comedy) matched Hogwarts Legacy on
/// "Adventure" and Bulletstorm on "Action". Sharing one word out of six is not
/// resemblance, and a section full of obviously-wrong suggestions teaches
/// people to ignore the section.
enum RelatedGames {

    /// Everything that describes what a game is *like*.
    ///
    /// Perspective is in here deliberately, and does real work: The Messenger
    /// is Side view and Mario Odyssey is Third person, which is most of why
    /// they don't feel alike despite both being platformers.
    static func traits(_ game: Game) -> Set<String> {
        Set(game.genres + game.themes + game.playerPerspectives)
    }

    /// How alike two games are, 0…1 — shared traits over combined traits.
    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }

    /// Games that genuinely resemble this one, best first.
    ///
    /// Two thresholds, because either alone lets nonsense through. A minimum
    /// of two shared traits kills the single-word match. A minimum ratio kills
    /// the case where a game tagged with everything overlaps everything —
    /// twelve tags against three, sharing two, is not similarity, it's one of
    /// them being vague.
    ///
    /// Same-franchise games are excluded: they're shown above under their own
    /// heading, and repeating them here would make the section look padded.
    static func similar(to game: Game, in library: [Game],
                        minimumShared: Int = 2, minimumScore: Double = 0.3,
                        limit: Int = 10) -> [Game] {
        let mine = traits(game)
        guard mine.count >= 2 else { return [] }
        let franchise = game.franchise

        return library
            .filter { $0.id != game.id && $0.deletedAt == nil }
            .filter { other in
                guard let franchise, let theirs = other.franchise else { return true }
                return theirs != franchise
            }
            .map { other -> (game: Game, score: Double, shared: Int) in
                let theirs = traits(other)
                return (other, similarity(mine, theirs), mine.intersection(theirs).count)
            }
            .filter { $0.shared >= minimumShared && $0.score >= minimumScore }
            .sorted { ($0.score, $1.game.name) > ($1.score, $0.game.name) }
            .prefix(limit)
            .map(\.game)
    }

    /// Other games in the same series.
    static func sameFranchise(as game: Game, in library: [Game], limit: Int = 10) -> [Game] {
        guard let franchise = game.franchise, !franchise.isEmpty else { return [] }
        return library
            .filter { $0.id != game.id && $0.deletedAt == nil && $0.franchise == franchise }
            .sorted { ($0.firstReleaseDate ?? .distantPast, $0.name)
                    < ($1.firstReleaseDate ?? .distantPast, $1.name) }
            .prefix(limit)
            .map { $0 }
    }

    /// Other games by the same studio, excluding the series (shown already).
    static func sameDeveloper(as game: Game, in library: [Game], limit: Int = 10)
        -> (developer: String, games: [Game])? {
        let mine = Set(game.developers)
        guard !mine.isEmpty else { return nil }
        let franchise = game.franchise
        let matches = library
            .filter { $0.id != game.id && $0.deletedAt == nil }
            .filter { other in
                guard let franchise, let theirs = other.franchise else { return true }
                return theirs != franchise
            }
            .filter { !mine.isDisjoint(with: Set($0.developers)) }
            .sorted { ($0.firstReleaseDate ?? .distantPast, $0.name)
                    < ($1.firstReleaseDate ?? .distantPast, $1.name) }
        guard !matches.isEmpty, let name = game.developers.first else { return nil }
        return (name, Array(matches.prefix(limit)))
    }
}
