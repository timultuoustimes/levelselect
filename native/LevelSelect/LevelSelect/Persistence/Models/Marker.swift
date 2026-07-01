import Foundation
import SwiftData

/// A map marker (legacy `maps[].markers[]`). Coordinates normalized to 0…1
/// (legacy x/y are 0–100 → divide by 100 on import).
@Model
final class Marker {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var normalizedX: Double     // 0…1
    var normalizedY: Double     // 0…1
    var category: MarkerCategory
    var label: String
    var notes: String?
    var linkedTrackerItemID: String?

    var map: GameMap?

    init(
        id: UUID = UUID(),
        normalizedX: Double,
        normalizedY: Double,
        category: MarkerCategory = .note,
        label: String = ""
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.category = category
        self.label = label
        self.notes = nil
        self.linkedTrackerItemID = nil
    }
}
