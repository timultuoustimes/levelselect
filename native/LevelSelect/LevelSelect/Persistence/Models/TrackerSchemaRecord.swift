import Foundation
import SwiftData

/// Immutable tracker definition (legacy `structuredData`). Stored as versioned
/// JSON; decoded into typed Codable DTOs before display. Separate from progress.
@Model
final class TrackerSchemaRecord {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var schemaVersion: Int
    var source: TrackerSource
    var engine: TrackerEngine
    var generatedAt: Date?
    var generatedBy: String?
    var jsonData: Data          // encoded schema tree (sections→items and/or runTemplate)
    var sourcesJSON: Data?      // reference URLs/notes

    var game: Game?

    init(
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        source: TrackerSource = .builtIn,
        engine: TrackerEngine = .objective,
        jsonData: Data = Data()
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.schemaVersion = schemaVersion
        self.source = source
        self.engine = engine
        self.generatedAt = nil
        self.generatedBy = nil
        self.jsonData = jsonData
        self.sourcesJSON = nil
    }
}
