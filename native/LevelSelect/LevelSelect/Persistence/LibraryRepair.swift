import Foundation
import SwiftData

/// **Put a library back to a known-good copy, through sync.**
///
/// Built 2026-09-17, after a Production build opened a store that had been
/// on the Development container and uploaded Development's stale records
/// into Tim's real library: test games added, deleted games revived, ticks
/// and ownership rolled back, the theme and handles reverted, a console
/// folded away. A restore can't mend that — `LibraryImport` never overwrites
/// and never deletes — so this applies a plan computed off-device from a
/// copy of the store taken before the damage (Piccolo's, checked against the
/// JSON export).
///
/// The plan says, per record id, which fields to set and which records to
/// tombstone. Every write goes through `touch`, so the correction is newer
/// than the damage and wins on every device. Nothing is deleted outright;
/// hidden records land in Recently Deleted.
///
/// Plan shape:
///
///     { "hide":    { "<Entity>": ["<UUID>", …] },
///       "set":     { "<Entity>": { "<UUID>": { "<field>": value } } },
///       "theme":   { "<ZCOLUMN>": value },
///       "profile": { "<ZCOLUMN>": value } }
///
/// Dates are ISO 8601, data is base64, null clears.
@MainActor
enum LibraryRepair {
    struct Outcome: Equatable {
        var hidden = 0
        var updated = 0
        var missing: [String] = []
        var unknownFields: [String] = []

        var summary: String {
            var parts = ["Hid \(hidden) records", "restored \(updated)"]
            if !missing.isEmpty { parts.append("\(missing.count) not found") }
            if !unknownFields.isEmpty { parts.append("skipped \(unknownFields.joined(separator: ", "))") }
            return parts.joined(separator: ", ") + "."
        }
    }

    enum RepairError: LocalizedError {
        case notAPlan
        var errorDescription: String? { "This file isn't a repair plan." }
    }

    static func apply(plan data: Data, context: ModelContext, at date: Date = .now) throws -> Outcome {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["hide"] != nil || root["set"] != nil
        else { throw RepairError.notAPlan }
        var out = Outcome()
        let hide = root["hide"] as? [String: [String]] ?? [:]
        let set = root["set"] as? [String: [String: [String: Any]]] ?? [:]

        func stamp(_ m: some Syncable) { m.updatedAt = date; m.revision += 1 }

        func index<M: PersistentModel & Syncable>(_ type: M.Type) throws -> [UUID: M] {
            var byID: [UUID: M] = [:]
            for m in try context.fetch(FetchDescriptor<M>()) { byID[m.id] = m }
            return byID
        }

        func hideAll<M: PersistentModel & Syncable>(_ name: String, _ byID: [UUID: M]) {
            for raw in hide[name] ?? [] {
                guard let id = UUID(uuidString: raw), let m = byID[id] else {
                    out.missing.append("\(name) \(raw)"); continue
                }
                guard m.deletedAt == nil else { continue }
                m.deletedAt = date
                stamp(m)
                out.hidden += 1
            }
        }

        /// Walks `set[name]`, handing each record and field to `write`, which
        /// returns false for a field it doesn't know.
        func setAll<M: PersistentModel & Syncable>(
            _ name: String, _ byID: [UUID: M],
            _ write: (M, String, Any?) -> Bool
        ) {
            for (raw, fields) in set[name] ?? [:] {
                guard let id = UUID(uuidString: raw), let m = byID[id] else {
                    out.missing.append("\(name) \(raw)"); continue
                }
                for (key, value) in fields {
                    let v: Any? = value is NSNull ? nil : value
                    if !write(m, key, v) { out.unknownFields.append("\(name).\(key)") }
                }
                stamp(m)
                out.updated += 1
            }
        }

        let games = try index(Game.self)
        let pts = try index(Playthrough.self)
        let schemas = try index(TrackerSchemaRecord.self)
        let states = try index(TrackerStateRecord.self)
        let consoles = try index(Console.self)
        let videos = try index(GameVideo.self)
        let markers = try index(Marker.self)

        // Schemas first: a game's `trackerSchemaID` below points at them.
        setAll("TrackerSchemaRecord", schemas) { s, key, v in
            switch key {
            case "gameID": s.game = uuid(v).flatMap { games[$0] }
            case "jsonData": s.jsonData = bytes(v) ?? Data()
            case "deletedAt": s.deletedAt = when(v)
            default: return false
            }
            return true
        }
        setAll("Game", games) { g, key, v in
            switch key {
            case "rating": g.rating = v as? Int
            case "wikidataID": g.wikidataID = v as? String
            case "currentPlaythroughID": g.currentPlaythroughID = uuid(v)
            case "ownership": g.ownership = v as? [String] ?? []
            case "ownedPlatforms": g.ownedPlatforms = v as? [String]
            case "platforms": g.platforms = v as? [String] ?? []
            case "platformReleasesData": g.platformReleasesData = bytes(v)
            case "deletedAt": g.deletedAt = when(v)
            case "sectionStateRaw": g.sectionStateRaw = v as? String
            case "backdropURLString": g.backdropURLString = v as? String
            case "coverOverrideURLString": g.coverOverrideURLString = v as? String
            case "firstReleaseDate": g.firstReleaseDate = when(v)
            case "name": if let s = v as? String { g.name = s }
            case "notes": g.notes = v as? String ?? ""
            case "pinned": g.pinned = v as? Bool ?? false
            case "status":
                guard let s = (v as? String).flatMap(GameStatus.init(rawValue:)) else { return false }
                g.status = s
            case "trackerSchemaID":
                let schema = uuid(v).flatMap { schemas[$0] }
                g.trackerSchema = schema
            default: return false
            }
            return true
        }
        setAll("Playthrough", pts) { p, key, v in
            switch key {
            case "lastPlayedAt": p.lastPlayedAt = when(v)
            case "progressPercent": p.progressPercent = (v as? Double) ?? 0
            case "deletedAt": p.deletedAt = when(v)
            case "outcomeRaw": p.outcomeRaw = v as? String
            case "gameID": p.game = uuid(v).flatMap { games[$0] }
            default: return false
            }
            return true
        }
        setAll("TrackerStateRecord", states) { s, key, v in
            switch key {
            case "completed": s.completed = v as? Bool ?? false
            case "completedAt": s.completedAt = when(v)
            case "deletedAt": s.deletedAt = when(v)
            case "count": s.count = v as? Int
            case "rank": s.rank = v as? Int
            case "revealed": s.revealed = v as? Bool ?? false
            default: return false
            }
            return true
        }
        setAll("Console", consoles) { c, key, v in
            switch key {
            case "deletedAt": c.deletedAt = when(v)
            case "ownership": c.ownership = v as? [String] ?? []
            case "declinedOwnership": c.declinedOwnership = v as? [String] ?? []
            case "notes": c.notes = v as? String
            case "variant": c.variant = v as? String
            case "acquiredAt": c.acquiredAt = when(v)
            case "nickname": c.nickname = v as? String
            default: return false
            }
            return true
        }
        setAll("GameVideo", videos) { m, key, v in
            switch key {
            case "lastWatchedAt": m.lastWatchedAt = when(v)
            case "watchedSeconds": m.watchedSeconds = (v as? Double) ?? 0
            case "deletedAt": m.deletedAt = when(v)
            default: return false
            }
            return true
        }
        setAll("Marker", markers) { m, key, v in
            switch key {
            case "label": m.label = v as? String ?? ""
            case "linkedTrackerItemID": m.linkedTrackerItemID = v as? String
            case "deletedAt": m.deletedAt = when(v)
            default: return false
            }
            return true
        }
        for name in set.keys where ![
            "TrackerSchemaRecord", "Game", "Playthrough", "TrackerStateRecord",
            "Console", "GameVideo", "Marker",
        ].contains(name) {
            out.unknownFields.append(name)
        }

        hideAll("Game", games)
        hideAll("Playthrough", pts)
        hideAll("TrackerSchemaRecord", schemas)
        hideAll("TrackerStateRecord", states)
        hideAll("Console", consoles)
        hideAll("GameVideo", videos)
        hideAll("Marker", markers)
        hideAll("Session", try index(Session.self))
        hideAll("CompletionEvent", try index(CompletionEvent.self))
        hideAll("Memory", try index(Memory.self))
        hideAll("Run", try index(Run.self))
        hideAll("GameMap", try index(GameMap.self))
        hideAll("GameCollection", try index(GameCollection.self))
        hideAll("TrackerItemDetail", try index(TrackerItemDetail.self))
        hideAll("EarnedBadge", try index(EarnedBadge.self))
        // GameImage isn't Syncable; same fields, by hand.
        if let ids = hide["GameImage"] {
            var byID: [UUID: GameImage] = [:]
            for m in try context.fetch(FetchDescriptor<GameImage>()) { byID[m.id] = m }
            for raw in ids {
                guard let id = UUID(uuidString: raw), let m = byID[id] else {
                    out.missing.append("GameImage \(raw)"); continue
                }
                guard m.deletedAt == nil else { continue }
                m.deletedAt = date
                m.updatedAt = date
                m.revision += 1
                out.hidden += 1
            }
        }

        if let theme = root["theme"] as? [String: Any], !theme.isEmpty,
           let row = try context.fetch(FetchDescriptor<ThemeSettings>()).first {
            for (key, value) in theme {
                let v: Any? = value is NSNull ? nil : value
                if !applyTheme(row, key, v) { out.unknownFields.append("theme.\(key)") }
            }
            row.updatedAt = date
            out.updated += 1
        }
        if let profile = root["profile"] as? [String: Any], !profile.isEmpty,
           let row = try context.fetch(FetchDescriptor<PlayerProfile>()).first {
            for (key, value) in profile {
                let v: Any? = value is NSNull ? nil : value
                switch key {
                case "ZDISPLAYNAME": row.displayName = v as? String
                case "ZAVATARDATA": row.avatarData = bytes(v)
                case "ZHANDLESDATA": row.handlesData = bytes(v)
                case "ZNAMECOLORRAW": row.nameColorRaw = v as? String
                case "ZUSEHANDLEASNAME": row.useHandleAsName = (v as? Bool) ?? ((v as? Int) == 1)
                default: out.unknownFields.append("profile.\(key)")
                }
            }
            row.updatedAt = date
            out.updated += 1
        }

        try context.save()
        return out
    }

    private static func applyTheme(_ t: ThemeSettings, _ key: String, _ v: Any?) -> Bool {
        let flag = (v as? Bool) ?? ((v as? Int) == 1)
        switch key {
        case "ZACCENTHEX": t.accentHex = v as? String
        case "ZACCENTHEXDARK": t.accentHexDark = v as? String
        case "ZACCENTHEXLIGHT": t.accentHexLight = v as? String
        case "ZACCENTHUE": t.accentHue = v as? Double
        case "ZACCENTSATURATION": t.accentSaturation = v as? Double
        case "ZAPPEARANCERAW": t.appearanceRaw = v as? String
        case "ZBACKGROUNDHEX": t.backgroundHex = v as? String
        case "ZBACKGROUNDHEXLIGHT": t.backgroundHexLight = v as? String
        case "ZBACKGROUNDHEXDARK": t.backgroundHexDark = v as? String
        case "ZDISMISSEDCONSOLESRAW": t.dismissedConsolesRaw = v as? String
        case "ZHOMELAYOUTRAW": t.homeLayoutRaw = v as? String
        case "ZHOMESYSTEMSRAW": t.homeSystemsRaw = v as? String
        case "ZOWNERSHIPCHIPSRAW": t.ownershipChipsRaw = v as? String
        case "ZPAGEBACKGROUNDRAW": if let s = v as? String { t.pageBackgroundRaw = s }
        case "ZDEFAULTTRACKERDISPLAYRAW": if let s = v as? String { t.defaultTrackerDisplayRaw = s }
        case "ZPALETTELINKED": t.paletteLinked = flag
        case "ZSHOWITEMHINTS": t.showItemHints = flag
        case "ZSHOWGAMELOGOS": t.showGameLogos = flag
        case "ZPLATFORMNAMESDATA": t.platformNamesData = bytes(v)
        case "ZSAVEDSWATCHESDATA": t.savedSwatchesData = bytes(v)
        case "ZSTATUSCOLORSDATA": t.statusColorsData = bytes(v)
        case "ZSTATUSNAMESDATA": t.statusNamesData = bytes(v)
        case "ZSTARNAMESDATA": t.starNamesData = bytes(v)
        case "ZPLATFORMICONVARIANTSDATA": t.platformIconVariantsData = bytes(v)
        case "ZGAMEPAGELAYOUTRAW": t.gamePageLayoutRaw = v as? String
        case "ZEXPANDEDSECTIONSRAW": t.expandedSectionsRaw = v as? String
        case "ZDEFAULTMERGEMODERAW": t.defaultMergeModeRaw = v as? String
        case "ZOVERLAPPINGTIMERPOLICYRAW": t.overlappingTimerPolicyRaw = v as? String
        case "ZBACKDROPINTENSITYRAW": t.backdropIntensityRaw = v as? String
        case "ZDEKUWISHLISTURLSTRING": t.dekuWishlistURLString = v as? String
        default: return false
        }
        return true
    }

    private static func uuid(_ v: Any?) -> UUID? { (v as? String).flatMap(UUID.init(uuidString:)) }
    private static func bytes(_ v: Any?) -> Data? { (v as? String).flatMap { Data(base64Encoded: $0) } }

    private static func when(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
