import Foundation
import SwiftData

/// Mutable per-playthrough progress for one schema item (sparse). CloudKit-compatible.
@Model
final class TrackerStateRecord {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var itemID: String = ""          // stable id of the schema item
    var completed: Bool = false
    var count: Int?
    var rank: Int?
    var revealed: Bool = false
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
        self.createdAt = .now
        self.updatedAt = .now
        self.itemID = itemID
        self.completed = completed
        self.count = count
        self.rank = rank
        self.revealed = revealed
    }
}
