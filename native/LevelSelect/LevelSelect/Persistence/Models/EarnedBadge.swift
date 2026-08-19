import Foundation
import SwiftData

/// A milestone the user has earned, recorded permanently.
///
/// Deliberately a ledger entry rather than a live-recomputed threshold check:
/// a badge earned once must not vanish because the qualifying data later
/// changed (un-marking a completed game, editing a session's time, clearing
/// progress). Recomputed "achievements" quietly un-earn themselves, which is
/// worse than not having them.
///
/// Ships in Schema V2 ahead of the feature that awards them — an empty table
/// costs nothing, and defining it now is what keeps the badge work from
/// needing a Schema V3.
@Model
final class EarnedBadge {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    /// Stable identifier of the badge kind (e.g. "first-completion").
    /// A string, not an enum, so a build that doesn't know a badge yet can
    /// still carry and sync it rather than dropping the record.
    var badgeID: String = ""
    /// When it was earned — the fact being recorded.
    var earnedAt: Date = Date.now
    /// The game that earned it, when it was game-specific. A plain id rather
    /// than a relationship: the badge outlives the game record and must not
    /// be cascade-deleted with it.
    var gameID: UUID?
    /// Free-form context (the number hit, the streak length…) so a later
    /// badge kind can carry its own detail without another schema change.
    var detailJSON: Data?

    init(badgeID: String, earnedAt: Date = .now,
         gameID: UUID? = nil, detailJSON: Data? = nil) {
        self.id = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.badgeID = badgeID
        self.earnedAt = earnedAt
        self.gameID = gameID
        self.detailJSON = detailJSON
    }
}
