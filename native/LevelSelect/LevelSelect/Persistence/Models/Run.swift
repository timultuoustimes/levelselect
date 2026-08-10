import Foundation
import SwiftData

/// A roguelike run (legacy `structuredData.runs[]`). CloudKit-compatible.
/// Persisted immediately — fixes the web bug where runs lived only in component state.
@Model
final class Run {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var templateID: String = ""      // which run template within the schema jsonData
    var startedAt: Date = Date.now
    var endedAt: Date?
    var outcome: RunOutcome = RunOutcome.inProgress
    var fieldsJSON: Data = Data()    // setup + in-run field values
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
        self.createdAt = .now
        self.updatedAt = .now
        self.templateID = templateID
        self.startedAt = startedAt
        self.outcome = outcome
        self.fieldsJSON = fieldsJSON
    }
}
