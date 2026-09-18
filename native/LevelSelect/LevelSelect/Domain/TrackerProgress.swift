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
///
/// Since 2026-09-17 a list can opt out or ask for partial credit
/// (`TrackerCategoryDTO.progress`), and a playthrough can focus on some lists
/// (`focus`), which then are the only ones counted. Both are the category's
/// or the playthrough's choice; with neither, the rules above are unchanged.
enum TrackerProgress {
    struct Tally: Equatable {
        var done: Int
        var total: Int
        /// `done` plus partial credit. Equal to `done` unless a list asked.
        var credit: Double

        init(done: Int, total: Int, credit: Double? = nil) {
            self.done = done
            self.total = total
            self.credit = credit ?? Double(done)
        }

        var fraction: Double { total == 0 ? 0 : min(1, credit / Double(total)) }
        var percent: Double { fraction * 100 }
    }

    /// What progress needs from an item's state.
    struct ItemState: Equatable {
        var completed: Bool
        var count: Int? = nil
        var rank: Int? = nil

        init(completed: Bool, count: Int? = nil, rank: Int? = nil) {
            self.completed = completed
            self.count = count
            self.rank = rank
        }

        init(_ record: TrackerStateRecord) {
            self.init(completed: record.completed, count: record.count, rank: record.rank)
        }
    }

    static func tally(items: [TrackerItemDTO],
                      isCompleted: (String) -> Bool) -> Tally {
        Tally(done: items.filter { isCompleted($0.id) }.count,
              total: items.count)
    }

    /// The lists that count: not opted out, and inside the focus when there is one.
    static func counted(_ categories: [TrackerCategoryDTO], focus: Set<String>?) -> [TrackerCategoryDTO] {
        categories.filter { category in
            guard category.progress != .excluded else { return false }
            guard let focus, !focus.isEmpty else { return true }
            return focus.contains(category.id)
        }
    }

    static func tally(categories: [TrackerCategoryDTO], focus: Set<String>? = nil,
                      state: (String) -> ItemState?) -> Tally {
        var done = 0, total = 0
        var credit = 0.0
        for category in counted(categories, focus: focus) {
            for item in category.items {
                total += 1
                let s = state(item.id)
                if s?.completed == true {
                    done += 1
                    credit += 1
                } else if category.progress == .partial, let s {
                    if let target = item.countTarget, target > 0 {
                        credit += Double(min(max(s.count ?? 0, 0), target)) / Double(target)
                    } else if let maxRank = item.maxRank, maxRank > 0 {
                        credit += Double(min(max(s.rank ?? 0, 0), maxRank)) / Double(maxRank)
                    }
                }
            }
        }
        return Tally(done: done, total: total, credit: credit)
    }
}
