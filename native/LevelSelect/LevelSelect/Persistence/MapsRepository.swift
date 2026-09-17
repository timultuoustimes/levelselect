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
/// would be the opposite of that.
///
/// **Found belongs to the playthrough.** An unlinked pin, or a pin on a counted
/// item, is found in the playthrough it was found in — a tracker state under
/// `pinStateID`, not the old game-wide `exploredAt`. Tim, 09-15: *"if I start a
/// game over completely then I have to re-find all the items again"*, while still
/// seeing what was found last time.
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
        if marker.linkedTrackerItemID != linkedTrackerItemID {
            // Relinking takes the pin's finds back from what it pointed at —
            // a counted item's +1 included — before it points somewhere else.
            if let game = marker.map?.game { clearPinFinds(marker, in: game) }
            marker.exploredAt = nil
        }
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
        // A found pin on a counted item was +1; deleting it takes that back, in
        // every playthrough it was found in. Codex, 09-15.
        if let game = marker.map?.game { clearPinFinds(marker, in: game, at: date) }
        marker.deletedAt = date
        marker.updatedAt = date
        marker.revision += 1
        persist()
    }

    /// Whether a pin reads as explored: the item's state when linked, its own
    /// found state in this playthrough otherwise (`pinStateID`).
    ///
    /// **Except for a counted item.** 900 Korok Seeds is one tracker row and
    /// hundreds of spots, so a pin on it is ONE spot, not the item: reading
    /// the item's state meant exploring one seed showed every seed explored.
    /// Those pins keep their own found state. `counted` is the set of such items,
    /// built once by the caller rather than once per pin.
    func isExplored(_ marker: Marker, states: [String: TrackerStateRecord],
                    counted: Set<String> = []) -> Bool {
        if let itemID = marker.linkedTrackerItemID, !counted.contains(itemID) {
            return states[itemID]?.completed ?? false
        }
        return states[pinStateID(marker)]?.completed ?? false
    }

    /// Tap ✓ on a pin. A linked pin ticks the item — the same act as the
    /// checkbox in the tracker, with the same journal line — and an unlinked
    /// pin stamps itself.
    func setExplored(_ marker: Marker, _ explored: Bool, in game: Game, at date: Date = .now) {
        let pt = ensureDefaultPlaythrough(for: game)
        let target = marker.linkedTrackerItemID.flatMap { countTarget(of: $0, in: game) }
        if let itemID = marker.linkedTrackerItemID, target == nil {
            setTrackerItem(pt, itemID: itemID, done: explored)
            return
        }
        // An unlinked pin, or one spot of a counted item: found in THIS
        // playthrough. Setting it to the state it already has changes nothing,
        // so a double tap can't move a count.
        let key = pinStateID(marker)
        guard (trackerState(pt, itemID: key)?.completed ?? false) != explored else { return }
        setTrackerItem(pt, itemID: key, done: explored, at: date)
        if let itemID = marker.linkedTrackerItemID, let target {
            // Forty found seed pins read 40/900 — instead of ticking the item,
            // which said all 900 were found. Never below the pins found here,
            // so a find synced from another device isn't overwritten by this
            // one's ± 1.
            let have = trackerState(pt, itemID: itemID)?.count ?? 0
            let found = foundPinCount(of: itemID, in: game, pt: pt)
            setTrackerCount(pt, itemID: itemID, count: max(have + (explored ? 1 : -1), found), target: target)
        }
    }

    // MARK: Found, per playthrough

    /// A pin's own found state is a tracker state in the playthrough under this
    /// id. No schema: it syncs, merges and backs up exactly as a tick does, and
    /// progress never counts it because it isn't a tracker item.
    static let pinStatePrefix = "pin:"

    func pinStateID(_ marker: Marker) -> String {
        Self.pinStatePrefix + marker.id.uuidString
    }

    /// Pins found in another playthrough and not in this one — Tim's Korok
    /// case, 09-15: *"see all the koroks they had found the last time, and which
    /// ones they need to look harder for."* A pin still carrying the old
    /// game-wide stamp counts as found before until `reconcile` moves it.
    func markersFoundBefore(in game: Game, counted: Set<String>) -> Set<UUID> {
        guard let active = game.activePlaythrough else { return [] }
        func completed(_ pt: Playthrough) -> Set<String> {
            Set((pt.trackerStates ?? []).filter { $0.deletedAt == nil && $0.completed }.map(\.itemID))
        }
        let here = completed(active)
        let elsewhere = game.livePlaythroughs.filter { $0.id != active.id }
            .reduce(into: Set<String>()) { $0.formUnion(completed($1)) }
        var out = Set<UUID>()
        for map in liveMaps(of: game) {
            for marker in liveMarkers(of: map) {
                let key: String
                if let itemID = marker.linkedTrackerItemID, !counted.contains(itemID) {
                    key = itemID
                } else {
                    key = pinStateID(marker)
                }
                guard !here.contains(key) else { continue }
                let legacy = key.hasPrefix(Self.pinStatePrefix) && marker.exploredAt != nil
                if elsewhere.contains(key) || legacy { out.insert(marker.id) }
            }
        }
        return out
    }

    /// Pins linked to a counted item that are found in this playthrough.
    func foundPinCount(of itemID: String, in game: Game, pt: Playthrough) -> Int {
        let done = Set((pt.trackerStates ?? [])
            .filter { $0.deletedAt == nil && $0.completed }.map(\.itemID))
        return liveMaps(of: game).flatMap { liveMarkers(of: $0) }
            .filter { $0.linkedTrackerItemID == itemID && done.contains(pinStateID($0)) }
            .count
    }

    /// Take a pin's finds back from every playthrough, and a counted item's +1
    /// with them — never below the pins still found for it.
    func clearPinFinds(_ marker: Marker, in game: Game, at date: Date = .now) {
        let key = pinStateID(marker)
        let target = marker.linkedTrackerItemID.flatMap { countTarget(of: $0, in: game) }
        for pt in game.livePlaythroughs where trackerState(pt, itemID: key)?.completed == true {
            setTrackerItem(pt, itemID: key, done: false)
            if let itemID = marker.linkedTrackerItemID, let target {
                let have = trackerState(pt, itemID: itemID)?.count ?? 0
                let found = foundPinCount(of: itemID, in: game, pt: pt)
                setTrackerCount(pt, itemID: itemID, count: max(have - 1, found), target: target)
            }
        }
    }

    /// Move pins' old game-wide found stamps into the playthrough in use, once.
    /// Before 09-15 a found pin was found for the whole game, and the playthrough
    /// someone is on is the best record of which run that was. A counted item's
    /// count already includes these, so it isn't touched.
    func migrateLegacyPinStamps(in game: Game) -> Int {
        guard let pt = game.activePlaythrough else { return 0 }
        let counted = Set(trackerCategories(for: game).flatMap(\.items)
            .filter { ($0.countTarget ?? 0) > 0 }.map(\.id))
        var moved = 0
        for map in liveMaps(of: game) {
            for marker in liveMarkers(of: map) {
                guard let stamp = marker.exploredAt else { continue }
                if let itemID = marker.linkedTrackerItemID, !counted.contains(itemID) { continue }
                let key = pinStateID(marker)
                if !game.livePlaythroughs.contains(where: { trackerState($0, itemID: key) != nil }) {
                    setTrackerItem(pt, itemID: key, done: true, at: stamp)
                }
                marker.exploredAt = nil
                marker.updatedAt = .now
                marker.revision += 1
                moved += 1
            }
        }
        if moved > 0 { persist() }
        return moved
    }

    /// Raise every counted item to at least the pins found for it, per
    /// playthrough. Two devices each finding a different seed write count 1
    /// from their own 0; both finds sync as separate states, and this is where
    /// the count catches up to them. Never lowers a count set by hand.
    func floorCountedItemsToFoundPins(in game: Game) -> Int {
        let items = trackerCategories(for: game).flatMap(\.items).filter { ($0.countTarget ?? 0) > 0 }
        guard !items.isEmpty, !liveMaps(of: game).isEmpty else { return 0 }
        var raised = 0
        for pt in game.livePlaythroughs {
            for item in items {
                let found = foundPinCount(of: item.id, in: game, pt: pt)
                guard found > (trackerState(pt, itemID: item.id)?.count ?? 0) else { continue }
                setTrackerCount(pt, itemID: item.id, count: found, target: item.countTarget)
                raised += 1
            }
        }
        return raised
    }

    /// The target of a counted item — 900 for the Korok Seeds — or nil when
    /// the item is a checkbox.
    func countTarget(of itemID: String, in game: Game) -> Int? {
        for category in trackerCategories(for: game) {
            if let item = category.items.first(where: { $0.id == itemID }) {
                return (item.countTarget ?? 0) > 0 ? item.countTarget : nil
            }
        }
        return nil
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
