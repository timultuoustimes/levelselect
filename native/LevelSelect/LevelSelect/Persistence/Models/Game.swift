import Foundation
import SwiftData

/// A game in the library (legacy `library[]`).
/// CloudKit-compatible: no unique constraints, every property optional or
/// inline-defaulted, relationships optional/defaulted.
@Model
final class Game {
    // Sync metadata
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    // Identity & metadata
    var name: String = ""
    var summary: String?
    var notes: String = ""
    var igdbID: Int?
    var igdbSlug: String?
    var firstReleaseDate: Date?
    var franchise: String?
    var coverURLString: String?
    var coverImageID: String?
    /// A cover the user chose in place of the fetched one (their own image, a
    /// different official release, community art). Schema V2 — the art the
    /// box had when THEY owned it is part of the memory. Wins over
    /// `coverURLString` wherever a cover is drawn.
    var coverOverrideURLString: String?

    // User state
    var status: GameStatus = GameStatus.backlog
    var pinned: Bool = false
    var rating: Int?          // consolidated game-level (1–5)
    var review: String?
    var addedAt: Date = Date.now
    var currentPlaythroughID: UUID?
    /// Per-game tracker display override; nil = follow the library default.
    var trackerDisplayRaw: String?

    // Value metadata arrays
    var platforms: [String] = []
    /// How the game is owned (raw `Ownership` values; multi-select).
    var ownership: [String] = []
    var userTags: [String] = []
    var genres: [String] = []
    var themes: [String] = []
    var gameModes: [String] = []
    var playerPerspectives: [String] = []
    var developers: [String] = []
    var publishers: [String] = []

    // Relationships — all optional (CloudKit requires optional relationships).
    @Relationship(deleteRule: .cascade, inverse: \Playthrough.game)
    var playthroughs: [Playthrough]?
    @Relationship(deleteRule: .cascade, inverse: \CompletionEvent.game)
    var completionEvents: [CompletionEvent]?
    @Relationship(deleteRule: .cascade, inverse: \GameMap.game)
    var maps: [GameMap]?
    @Relationship(deleteRule: .cascade, inverse: \TrackerSchemaRecord.game)
    var trackerSchema: TrackerSchemaRecord?
    @Relationship(deleteRule: .cascade, inverse: \GameVideo.game)
    var videos: [GameVideo]?
    /// The user's own notes and renames for this game's tracker items, kept
    /// OUT of the schema blob so they merge per item instead of whole. See
    /// TrackerItemDetail. Schema V2.
    @Relationship(deleteRule: .cascade, inverse: \TrackerItemDetail.game)
    var trackerItemDetails: [TrackerItemDetail]?

    init(
        id: UUID = UUID(),
        name: String,
        status: GameStatus = .backlog,
        notes: String = "",
        addedAt: Date = .now,
        pinned: Bool = false
    ) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name
        self.notes = notes
        self.status = status
        self.pinned = pinned
        self.addedAt = addedAt
    }
}
