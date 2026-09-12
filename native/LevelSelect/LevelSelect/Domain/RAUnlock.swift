import Foundation

/// One RetroAchievements achievement the user has actually unlocked.
///
/// Lives in Domain rather than beside the service because `Repository` folds
/// these into tracker state, and the watch target compiles Repository without
/// any of the networking. A plain value type keeps that boundary honest —
/// the store layer never needs to know an HTTP call exists.
struct RAUnlock: Sendable, Hashable {
    /// The tracker item id, already prefixed (`ra-1234`).
    let itemID: String
    /// Earned without savestates or rewind. Recorded, never used to filter:
    /// an unlock is an unlock, and refusing to tick a softcore one would be
    /// telling someone they didn't do a thing they did.
    let hardcore: Bool
    let earnedAt: Date?
    let points: Int
}
