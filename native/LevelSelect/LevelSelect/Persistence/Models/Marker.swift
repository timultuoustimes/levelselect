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
    /// When this spot was explored, found, done — nil until it is.
    ///
    /// **The field the roadmap named and never added.** Tim: *"drop location
    /// pins for items, mark areas as explored/completed."* `MarkerCategory`
    /// is all kinds and no states, so a pin could say what was here and never
    /// whether you had been. A linked marker does not use this: it shows the
    /// tracker item's state and ticking it ticks the item, so there is one
    /// record of a thing being done, not two that can disagree.
    var exploredAt: Date?

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
