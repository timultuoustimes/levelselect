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

extension TrackerStateRecord {
    /// The ONE duplicate-winner rule, shared by every reader — repository
    /// reads, the tracker view's state map, the widget bridge, progress
    /// recomputation, and the reconciler's fold. Total order: latest
    /// `updatedAt`, ties broken by id, so every device (and every reader on
    /// one device) resolves the same row. Round 3 found three readers each
    /// using a different arbitrary rule ("first in relationship order",
    /// "any twin completed"), which let a widget or a cached percentage
    /// contradict the repository's declared winner until reconciliation
    /// happened to run.
    func outranks(_ other: TrackerStateRecord) -> Bool {
        (updatedAt, id.uuidString) > (other.updatedAt, other.id.uuidString)
    }

    /// The winning row among duplicates for one item, under that total order.
    static func winner(of records: [TrackerStateRecord]) -> TrackerStateRecord? {
        records.max { $1.outranks($0) }
    }
}
