import Foundation

/// What you can still do right now, and what you're about to lock yourself
/// out of.
///
/// Elden Ring's progression points that end questlines, a visual novel's true
/// ending gated behind the other endings, Persona deadlines — they all reduce
/// to two relationships between items: one needs another done first, and one
/// makes another impossible. Model those two and the derived view falls out,
/// and that view is the single most useful thing a tracker can show that a
/// checklist cannot.
///
/// Deliberately NOT a logic solver. Randomizer trackers solve live logic
/// against an inventory and win on it; this is the ten-percent version that
/// covers the cases actual guides describe, and it stops there.
///
/// Pure: schema in, status out. Both relationships live in the tracker JSON,
/// so none of this needs a schema version.
enum TrackerGating {

    enum Status: Equatable {
        /// Do it whenever.
        case available
        /// Something has to happen first. Carries the names, because "locked"
        /// without saying by what is just a shrug.
        case blocked(needs: [String])
        /// Something already done has closed this off. The names again — a
        /// player who sees this wants to know what cost them.
        case lost(to: [String])
    }

    /// Resolved once per render for a whole tracker: per-item lookups against
    /// a set, rather than rescanning every item for every row.
    struct Resolver {
        private let byID: [String: TrackerItemDTO]
        private let completed: Set<String>

        init(categories: [TrackerCategoryDTO], completed: Set<String>) {
            var map: [String: TrackerItemDTO] = [:]
            for item in categories.flatMap(\.items) where map[item.id] == nil {
                map[item.id] = item
            }
            self.byID = map
            self.completed = completed
        }

        private func name(_ id: String) -> String { byID[id]?.name ?? id }

        func status(of item: TrackerItemDTO) -> Status {
            // Something already finished is never blocked or lost — it
            // happened, whatever the rules say now. Reporting otherwise would
            // tell a player they can't have done a thing they did.
            if completed.contains(item.id) { return .available }

            let closedBy = byID.values
                .filter { completed.contains($0.id) && $0.locksOut.contains(item.id) }
                .map(\.name)
                .sorted()
            if !closedBy.isEmpty { return .lost(to: closedBy) }

            let missing = item.requires
                .filter { !completed.contains($0) }
                .map(name)
                .sorted()
            if !missing.isEmpty { return .blocked(needs: missing) }

            return .available
        }

        /// What completing this item would close off — the warning worth
        /// showing BEFORE the tick, since afterwards it is advice about the
        /// past. Only names things not already done or already closed.
        func wouldLoseByCompleting(_ item: TrackerItemDTO) -> [String] {
            item.locksOut
                .filter { id in
                    guard !completed.contains(id), let other = byID[id] else { return false }
                    if case .lost = status(of: other) { return false }
                    return true
                }
                .map(name)
                .sorted()
        }
    }
}
