import Foundation
import SwiftData

/// A game map (legacy `maps[]`). Image bytes stay in Supabase Storage;
/// only metadata + path are stored/synced. `localCacheURL` holds cached bytes.
@Model
final class GameMap {
    // Sync metadata
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deletedAt: Date?
    var legacyID: String?

    var name: String
    var kind: MapKind
    var storageType: String
    var remoteStoragePath: String    // canonical reference (NOT a public URL)
    var remoteURLString: String?
    var localCacheURL: URL?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var addedAt: Date

    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Marker.map)
    var markers: [Marker]

    init(
        id: UUID = UUID(),
        name: String,
        kind: MapKind = .other,
        storageType: String = "upload",
        remoteStoragePath: String = "",
        addedAt: Date = .now
    ) {
        self.id = id
        self.userID = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.revision = 0
        self.deletedAt = nil
        self.legacyID = nil
        self.name = name
        self.kind = kind
        self.storageType = storageType
        self.remoteStoragePath = remoteStoragePath
        self.remoteURLString = nil
        self.localCacheURL = nil
        self.pixelWidth = nil
        self.pixelHeight = nil
        self.addedAt = addedAt
        self.markers = []
    }
}
