import Foundation
import SwiftData

/// A completion moment (legacy `clears[]` + status transitions). CloudKit-compatible.
@Model
final class CompletionEvent {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var date: Date = Date.now
    var label: CompletionLabel = CompletionLabel.cleared
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
        self.createdAt = .now
        self.updatedAt = .now
        self.date = date
        self.label = label
        self.customLabel = customLabel
    }
}
