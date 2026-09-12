import Foundation
import SwiftData

/// Immutable tracker definition (legacy `structuredData`). CloudKit-compatible.
/// Stored as versioned JSON; decoded into typed Codable DTOs before display.
@Model
final class TrackerSchemaRecord {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var schemaVersion: Int = 1
    var source: TrackerSource = TrackerSource.builtIn
    var engine: TrackerEngine = TrackerEngine.objective
    var generatedAt: Date?
    var generatedBy: String?
    var jsonData: Data = Data()      // encoded schema tree (sections→items and/or runTemplate)
    var sourcesJSON: Data?           // reference URLs/notes

    var game: Game?

    init(
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        source: TrackerSource = .builtIn,
        engine: TrackerEngine = .objective,
        jsonData: Data = Data()
    ) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.schemaVersion = schemaVersion
        self.source = source
        self.engine = engine
        self.jsonData = jsonData
    }
}
