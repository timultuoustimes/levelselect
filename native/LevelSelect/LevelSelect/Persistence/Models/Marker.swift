import Foundation
import SwiftData

/// A map marker (legacy `maps[].markers[]`). CloudKit-compatible.
/// Coordinates normalized to 0…1 (legacy x/y are 0–100 → divide by 100 on import).
@Model
final class Marker {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var normalizedX: Double = 0     // 0…1
    var normalizedY: Double = 0     // 0…1
    var category: MarkerCategory = MarkerCategory.note
    var label: String = ""
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
        self.createdAt = .now
        self.updatedAt = .now
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.category = category
        self.label = label
    }
}
