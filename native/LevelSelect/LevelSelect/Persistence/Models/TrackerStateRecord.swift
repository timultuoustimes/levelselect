import Foundation
import SwiftData

/// Mutable per-playthrough progress for one schema item (sparse — only items
/// with non-default state get a row). "Personal Goals" items live here too.
@Model
final class TrackerStateRecord {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var itemID: String          // stable id of the schema item
    var completed: Bool
    var count: Int?
    var rank: Int?
    var revealed: Bool
    var notes: String?

    var playthrough: Playthrough?

    init(
        id: UUID = UUID(),
        itemID: String,
        completed: Bool = false,
        count: Int? = nil,
        rank: Int? = nil,
        revealed: Bool = false
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.itemID = itemID
        self.completed = completed
        self.count = count
        self.rank = rank
        self.revealed = revealed
        self.notes = nil
    }
}
