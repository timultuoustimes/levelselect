import Foundation

/// THE progress calculator. One, on purpose.
///
/// Three copies of this arithmetic used to exist — the tracker header,
/// `Repository.recompute`, and the widget bridge — identical today and one
/// refactor away from disagreeing, which is exactly how a ring ends up
/// contradicting the header above it. Every consumer now calls this; if the
/// semantics ever change, they change everywhere in the same commit.
///
/// The semantics, pinned:
/// - An item counts when its state's `completed` is true, full stop.
/// - Counted items (countTarget > 0) are ALREADY binary by the time they get
///   here — `setTrackerCount` flips `completed` at the target — so a 0/900
///   counter is one undone item, not nine hundred. Partial-credit for
///   counters would be a deliberate future change made HERE, not a bug fix
///   made in one of three places.
/// - Hidden-until-discovered items count toward the total whether or not
///   they've been revealed: the game has that many things, discovery doesn't
///   change the denominator, and a total that grows as you reveal spoilers
///   would leak how many are left.
/// - Winner resolution across sync twins is the CALLER's job (each site
///   already holds its states in a winner-resolved form); this takes the
///   resolved answer, not the raw records.
enum TrackerProgress {
    struct Tally: Equatable {
        var done: Int
        var total: Int

        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
        var percent: Double { fraction * 100 }
    }

    static func tally(items: [TrackerItemDTO],
                      isCompleted: (String) -> Bool) -> Tally {
        Tally(done: items.filter { isCompleted($0.id) }.count,
              total: items.count)
    }
}
