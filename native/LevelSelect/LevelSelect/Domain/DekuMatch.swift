import Foundation

/// Which Deku Deals rows the app already knows about.
///
/// The two lists sat side by side as strangers. On Tim's Mac, 2026-08-31,
/// "Future Knight", "Promise Mascot Agency" and "Resident Evil Requiem" were
/// visible in BOTH panes on one screen, and "Cities: Skylines" sat on the Deku
/// list as something to buy when he already owns it. A wishlist that does not
/// know what you own is a shopping list you have to check by memory.
///
/// **Display only, and deliberately strict.** `WishlistTab` already reasons
/// that promoting a Deku row into the library is manual "for now… automatic
/// matching can come later, when a wrong match costs less than it would
/// today." That still holds for CREATING a game — a wrong match there writes
/// bad data. Drawing a label costs nothing if it is wrong, so this is the half
/// that is safe to ship: exact name equality after normalisation, never
/// substrings, never fuzzy distance.
enum DekuMatch {
    /// What the library already knows about a name.
    enum Known: Equatable {
        /// Already on your wishlist here — the duplicate case.
        case wishlisted
        /// You own it, or owned it. On a list of things to buy, this is the
        /// one worth noticing.
        case inLibrary
    }

    /// Case, spacing and punctuation are noise; everything else is signal.
    ///
    /// Deliberately does NOT strip edition or platform suffixes. "Resident
    /// Evil 4" and "Resident Evil 4: Separate Ways" are different purchases,
    /// and collapsing them would mark a game bought that is not.
    static func normalize(_ name: String) -> String {
        name.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    static func index(_ library: [Game]) -> [String: Known] {
        var out: [String: Known] = [:]
        for game in library where game.deletedAt == nil {
            let key = normalize(game.name)
            let known: Known = game.status == .wishlist ? .wishlisted : .inLibrary
            // Owning beats wanting: if a name is somehow both, the fact worth
            // showing on a list of things to buy is that you already have it.
            if out[key] == .inLibrary { continue }
            out[key] = known
        }
        return out
    }
}
