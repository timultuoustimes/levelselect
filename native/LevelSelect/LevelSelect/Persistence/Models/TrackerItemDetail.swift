import Foundation
import SwiftData

/// The user's own content for one tracker item, stored as its own synced
/// record instead of inside the tracker's JSON blob.
///
/// Why this exists (Schema V2): a tracker's structure AND everything the user
/// wrote about it lived in one `TrackerSchemaRecord.jsonData` value. CloudKit
/// syncs that value whole, so two devices editing different items meant one
/// device's entire blob won — and the note you wrote on your phone vanished
/// because your iPad happened to rename something else. Structure is rewritten
/// wholesale by generation anyway and can tolerate last-writer-wins; the
/// sentence you typed cannot. Splitting the authored content into per-item
/// records makes those edits merge independently, which is the failure that
/// actually costs people something.
///
/// Scoped to the GAME, not a playthrough: a note about where a collectible is
/// hidden is true on every playthrough. (`TrackerStateRecord.notes` is
/// per-playthrough and remains the right home for run-specific scribbles.)
///
/// Growth path, deliberately left open: if the tracker is ever decomposed into
/// real models, the structure fields (name, location, category, rank) are
/// ADDED to this record rather than introducing another one — so that change
/// stays additive instead of a second decomposition.
@Model
final class TrackerItemDetail {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    /// The schema item this annotates — same id space as
    /// `TrackerStateRecord.itemID`.
    var itemID: String = ""
    /// The user's own note. Distinct from the generated `description`, which
    /// belongs to whatever produced the item and may be replaced freely.
    var note: String?
    /// A name the user chose in place of the generated one.
    var chosenName: String?
    /// The name the item arrived with, kept so name-based merge matching still
    /// works after a rename.
    var sourceName: String?

    var game: Game?

    init(itemID: String, note: String? = nil,
         chosenName: String? = nil, sourceName: String? = nil) {
        self.id = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.itemID = itemID
        self.note = note
        self.chosenName = chosenName
        self.sourceName = sourceName
    }
}
