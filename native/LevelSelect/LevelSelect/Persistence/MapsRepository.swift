import Foundation
import SwiftData

/// Maps and markers — the web app's largest surviving feature, native.
///
/// **A map is a picture** (`GameImage`, role `.map`) **plus a record of what
/// is on it** (`GameMap` and its `Marker`s). The picture goes through the
/// same ingest, sync, Recently Deleted and export as every other picture; the
/// map record points at it with `storageType == "image"` and the picture's
/// id in `remoteStoragePath`. That reuses two deployed CloudKit asset fields
/// instead of adding a storage bucket, and it is why a map is offline by
/// nature: it is in the store.
///
/// **A linked marker has no state of its own.** Link a pin to a tracker item
/// and the pin shows the item's checkbox; tapping ✓ on the pin ticks the item
/// through the one write path a tick has, with the same completion event and
/// journal line. Tim's reason for pins on items was so that finding the thing
/// on the map and ticking it are one motion — two states that could disagree
/// would be the opposite of that. Unlinked pins use `exploredAt`.
extension Repository {

    static let mapImageStorageType = "image"

    // MARK: Maps

    /// A map from picked bytes: ingested as a picture, then recorded.
    @discardableResult
    func addMap(to game: Game, data: Data, name: String, kind: MapKind,
                sourceURL: String? = nil) throws -> GameMap {
        let image = try addImage(to: game, data: data, role: .map)
        let map = GameMap(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                          kind: kind,
                          storageType: Self.mapImageStorageType,
                          remoteStoragePath: image.id.uuidString)
        // Where it came from, if the web did. Provenance, the way credits
        // say Wikidata and the studio says IGDB.
        map.remoteURLString = sourceURL
        map.pixelWidth = image.pixelWidth
        map.pixelHeight = image.pixelHeight
        context.insert(map)
        map.game = game
        touch(game)
        persist()
        return map
    }

    /// The map a picture is the image of, if any — including a tombstoned
    /// map, which is what Recently Deleted needs to know.
    func map(backedBy image: GameImage) -> GameMap? {
        (image.game?.maps ?? []).first {
            $0.storageType == Self.mapImageStorageType && $0.remoteStoragePath == image.id.uuidString
        }
    }

    /// The picture behind a map, if this build stores maps as pictures.
    /// A web-era map (`storageType == "upload"`) has none here, and shows as
    /// a map without an image rather than crashing the section.
    func image(for map: GameMap) -> GameImage? {
        guard map.storageType == Self.mapImageStorageType,
              let id = UUID(uuidString: map.remoteStoragePath) else { return nil }
        return (map.game?.images ?? []).first { $0.id == id && $0.deletedAt == nil }
    }

    func liveMaps(of game: Game) -> [GameMap] {
        (game.maps ?? []).filter { $0.deletedAt == nil }
            .sorted { ($0.kind.sortRank, $0.addedAt) < ($1.kind.sortRank, $1.addedAt) }
    }

    func rename(_ map: GameMap, to name: String, kind: MapKind) {
        map.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        map.kind = kind
        map.updatedAt = .now
        map.revision += 1
        persist()
    }

    /// Soft, like everything: the map's picture goes to Recently Deleted with
    /// the same stamp, and the markers stay on the tombstoned map so a
    /// restore of the picture can bring the whole thing back.
    func deleteMap(_ map: GameMap, at date: Date = .now) {
        map.deletedAt = date
        map.updatedAt = date
        map.revision += 1
        if let image = image(for: map) { softDelete(image, at: date) }
        if let game = map.game { touch(game, at: date) }
        persist()
    }

    func liveMarkers(of map: GameMap) -> [Marker] {
        (map.markers ?? []).filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Markers

    @discardableResult
    func addMarker(to map: GameMap, x: Double, y: Double,
                   category: MarkerCategory = .note, label: String = "",
                   linkedTrackerItemID: String? = nil) -> Marker {
        let marker = Marker(normalizedX: min(max(x, 0), 1), normalizedY: min(max(y, 0), 1),
                            category: category, label: label)
        marker.linkedTrackerItemID = linkedTrackerItemID
        context.insert(marker)
        marker.map = map
        map.updatedAt = .now
        persist()
        return marker
    }

    func updateMarker(_ marker: Marker, label: String, category: MarkerCategory,
                      notes: String?, linkedTrackerItemID: String?) {
        marker.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        marker.category = category
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        marker.notes = trimmed.isEmpty ? nil : trimmed
        // Linking hands the state to the item; the pin's own stamp is
        // cleared so unlinking later starts from "not explored" rather than
        // from whatever was true before the link.
        if marker.linkedTrackerItemID != linkedTrackerItemID { marker.exploredAt = nil }
        marker.linkedTrackerItemID = linkedTrackerItemID
        marker.updatedAt = .now
        marker.revision += 1
        persist()
    }

    func moveMarker(_ marker: Marker, x: Double, y: Double) {
        marker.normalizedX = min(max(x, 0), 1)
        marker.normalizedY = min(max(y, 0), 1)
        marker.updatedAt = .now
        marker.revision += 1
        persist()
    }

    func deleteMarker(_ marker: Marker, at date: Date = .now) {
        marker.deletedAt = date
        marker.updatedAt = date
        marker.revision += 1
        persist()
    }

    /// Whether a pin reads as explored: the item's state when linked, its
    /// own stamp otherwise.
    func isExplored(_ marker: Marker, states: [String: TrackerStateRecord]) -> Bool {
        if let itemID = marker.linkedTrackerItemID {
            return states[itemID]?.completed ?? false
        }
        return marker.exploredAt != nil
    }

    /// Tap ✓ on a pin. A linked pin ticks the item — the same act as the
    /// checkbox in the tracker, with the same journal line — and an unlinked
    /// pin stamps itself.
    func setExplored(_ marker: Marker, _ explored: Bool, in game: Game, at date: Date = .now) {
        if let itemID = marker.linkedTrackerItemID {
            let pt = ensureDefaultPlaythrough(for: game)
            setTrackerItem(pt, itemID: itemID, done: explored)
            return
        }
        marker.exploredAt = explored ? date : nil
        marker.updatedAt = date
        marker.revision += 1
        persist()
    }

    /// Every live marker on this game, keyed by the tracker item it points
    /// at — what the tracker reads to draw a pin beside an item.
    func linkedMarkers(in game: Game) -> [String: Marker] {
        var result: [String: Marker] = [:]
        for map in liveMaps(of: game) {
            for marker in liveMarkers(of: map) {
                if let id = marker.linkedTrackerItemID, result[id] == nil { result[id] = marker }
            }
        }
        return result
    }
}

extension MapKind {
    /// World first, then areas, then the rest — the order a wiki lists them.
    var sortRank: Int {
        switch self {
        case .world: 0
        case .area:  1
        case .other: 2
        }
    }

    var label: String {
        switch self {
        case .world: "World"
        case .area:  "Area"
        case .other: "Other"
        }
    }
}

extension MarkerCategory {
    var label: String {
        switch self {
        case .collectible: "Collectible"
        case .note:        "Note"
        case .warning:     "Warning"
        case .secret:      "Secret"
        }
    }

    var systemImage: String {
        switch self {
        case .collectible: "star.fill"
        case .note:        "note.text"
        case .warning:     "exclamationmark.triangle.fill"
        case .secret:      "eye.slash.fill"
        }
    }
}
