import Foundation
import SwiftData

/// A completion moment (legacy `clears[]` + status transitions).
@Model
final class CompletionEvent {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var date: Date
    var label: CompletionLabel
    var customLabel: String?   // used when label == .custom
    var platform: String?
    var notes: String?

    var game: Game?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        label: CompletionLabel = .cleared,
        customLabel: String? = nil
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.date = date
        self.label = label
        self.customLabel = customLabel
        self.platform = nil
        self.notes = nil
    }
}
