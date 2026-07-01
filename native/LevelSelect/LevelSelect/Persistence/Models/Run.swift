import Foundation
import SwiftData

/// A roguelike run (legacy `structuredData.runs[]`). Persisted immediately —
/// fixes the web bug where runs lived only in component state.
@Model
final class Run {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var templateID: String      // which run template within the schema jsonData
    var startedAt: Date
    var endedAt: Date?
    var outcome: RunOutcome
    var fieldsJSON: Data        // setup + in-run field values
    var notes: String?

    var playthrough: Playthrough?

    init(
        id: UUID = UUID(),
        templateID: String,
        startedAt: Date = .now,
        outcome: RunOutcome = .inProgress,
        fieldsJSON: Data = Data()
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.templateID = templateID
        self.startedAt = startedAt
        self.endedAt = nil
        self.outcome = outcome
        self.fieldsJSON = fieldsJSON
        self.notes = nil
    }
}
