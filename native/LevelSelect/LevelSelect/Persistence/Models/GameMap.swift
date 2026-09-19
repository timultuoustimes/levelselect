import Foundation
import SwiftData

/// A game map (legacy `maps[]`). CloudKit-compatible. Image bytes live in
/// CloudKit assets / Supabase Storage (Phase 3); this stores metadata + path.
@Model
final class GameMap {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var name: String = ""
    var kind: MapKind = MapKind.other
    var storageType: String = "upload"
    var remoteStoragePath: String = ""    // canonical reference (NOT a public URL)
    var remoteURLString: String?
    var localCacheURL: URL?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var addedAt: Date = Date.now

    var game: Game?

    @Relationship(deleteRule: .cascade, inverse: \Marker.map)
    var markers: [Marker]?

    init(
        id: UUID = UUID(),
        name: String,
        kind: MapKind = .other,
        storageType: String = "upload",
        remoteStoragePath: String = "",
        addedAt: Date = .now
    ) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name
        self.kind = kind
        self.storageType = storageType
        self.remoteStoragePath = remoteStoragePath
        self.addedAt = addedAt
    }
}
