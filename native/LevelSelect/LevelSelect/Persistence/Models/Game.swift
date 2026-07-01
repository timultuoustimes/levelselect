import Foundation
import SwiftData

/// A game in the library. Maps from a legacy `library[]` element.
/// Cut legacy fields (NOT ported): complexity, coverColor, yearPlayed,
/// root currentSaveId, the always-empty `games` map, per-save duplicate
/// rating/review (consolidated here), playPeriods.
@Model
final class Game {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    // Identity & metadata
    var name: String
    var summary: String?
    var notes: String
    var igdbID: Int?
    var igdbSlug: String?
    var firstReleaseDate: Date?
    var franchise: String?
    var coverURLString: String?
    var coverImageID: String?

    // User state
    var status: GameStatus
    var pinned: Bool
    var rating: Int?          // consolidated game-level (1–5)
    var review: String?
    var addedAt: Date
    var currentPlaythroughID: UUID?

    // Value metadata arrays
    var platforms: [String]
    var userTags: [String]
    var genres: [String]
    var themes: [String]
    var gameModes: [String]
    var playerPerspectives: [String]
    var developers: [String]
    var publishers: [String]

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \Playthrough.game)
    var playthroughs: [Playthrough]
    @Relationship(deleteRule: .cascade, inverse: \CompletionEvent.game)
    var completionEvents: [CompletionEvent]
    @Relationship(deleteRule: .cascade, inverse: \GameMap.game)
    var maps: [GameMap]
    @Relationship(deleteRule: .cascade, inverse: \TrackerSchemaRecord.game)
    var trackerSchema: TrackerSchemaRecord?

    init(
        id: UUID = UUID(),
        name: String,
        status: GameStatus = .backlog,
        notes: String = "",
        addedAt: Date = .now,
        pinned: Bool = false
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.name = name
        self.summary = nil
        self.notes = notes
        self.igdbID = nil
        self.igdbSlug = nil
        self.firstReleaseDate = nil
        self.franchise = nil
        self.coverURLString = nil
        self.coverImageID = nil
        self.status = status
        self.pinned = pinned
        self.rating = nil
        self.review = nil
        self.addedAt = addedAt
        self.currentPlaythroughID = nil
        self.platforms = []
        self.userTags = []
        self.genres = []
        self.themes = []
        self.gameModes = []
        self.playerPerspectives = []
        self.developers = []
        self.publishers = []
        self.playthroughs = []
        self.completionEvents = []
        self.maps = []
        self.trackerSchema = nil
    }
}
