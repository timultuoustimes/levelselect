import Foundation
import SwiftData

/// Versioned JSON export of the user's library content.
///
/// Beta P0: soft-delete plus iCloud is not a backup. Asking testers to invest
/// hours of tracking with no way to get their data out is how a beta loses
/// people's trust permanently — so this exists before the first external
/// tester, not after.
///
/// The format is deliberately plain and self-describing: a `manifest` with
/// counts, then the records themselves. Every record type carries its stable
/// UUID so a future importer can round-trip without duplicating. Honest
/// scope, kept in sync with the in-app footer and site copy: this is the
/// library's CONTENT as the user sees it, not a byte-for-byte store clone —
/// tombstoned records, internal sync metadata (revisions, timestamps on
/// nested records, legacy ids), profile/migration bookkeeping, and map image
/// bytes (referenced by their remote path, not embedded) are not included.
/// The manifest counts only what the exporter visited; it cannot prove
/// nothing was omitted.
@MainActor
enum LibraryExport {
    /// Bump when the shape changes; importers should refuse unknown majors.
    /// **2 — memories, and the pictures on them.**
    ///
    /// Bumped rather than added quietly. The importer gates strictly on this
    /// number, so a build that predates memories now refuses the file and says
    /// why, instead of restoring a library with every memory silently missing
    /// — which is the failure this version exists to fix.
    static let formatVersion = 3

    struct Manifest: Codable {
        var formatVersion: Int
        var exportedAt: Date
        var appVersion: String
        var games: Int
        var playthroughs: Int
        var sessions: Int
        var runs: Int
        var trackerStates: Int
        var trackerSchemas: Int
        var completions: Int
        var videos: Int
        var maps: Int
        var markers: Int
        var collections: Int
        var memories: Int
        /// The user's own notes and renames on tracker items. Absent from the
        /// file until v3, which is the whole reason v3 exists.
        var trackerItemDetails: Int
        /// User-added images, and what they weigh. The byte figure is
        /// reported so someone reading the manifest can see why the file is
        /// the size it is, without decoding anything.
        var images: Int
        var imageBytes: Int
        /// Sum of every record count above — a cheap integrity check that an
        /// importer (or a person) can verify without parsing the whole file.
        var totalRecords: Int
    }

    // MARK: Building

    /// Produce the export as pretty-printed JSON data.
    static func makeJSON(context: ModelContext) throws -> Data {
        let games = try context.fetch(
            FetchDescriptor<Game>(
                predicate: #Predicate { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.name)]
            )
        )
        let collections = try context.fetch(
            FetchDescriptor<GameCollection>(predicate: #Predicate { $0.deletedAt == nil })
        )

        var counts = (playthroughs: 0, sessions: 0, runs: 0,
                      states: 0, schemas: 0, completions: 0, videos: 0,
                      maps: 0, markers: 0, images: 0, imageBytes: 0,
                      trackerItemDetails: 0)

        var gameObjects: [[String: Any]] = []
        for game in games {
            var dict: [String: Any] = [
                "id": game.id.uuidString,
                "name": game.name,
                "status": game.status.rawValue,
                "addedAt": iso(game.addedAt),
                "createdAt": iso(game.createdAt),
                "updatedAt": iso(game.updatedAt),
                "pinned": game.pinned,
                "notes": game.notes,
                "platforms": game.platforms,
                "ownership": game.ownership,
                "userTags": game.userTags,
            ]
            dict["summary"] = game.summary
            dict["rating"] = game.rating
            dict["review"] = game.review
            dict["igdbID"] = game.igdbID
            dict["igdbSlug"] = game.igdbSlug
            dict["wikidataID"] = game.wikidataID
            dict["coverImageID"] = game.coverImageID
            dict["coverURL"] = game.coverURLString
            // The artwork the USER chose, which the fetched fields above
            // cannot reconstruct. `coverOverrideURL` shipped in build 31 and
            // was missing from this file until V3 — a chosen cover did not
            // survive a round trip, which for an export that calls itself the
            // backup is a data-loss bug rather than an omission.
            dict["coverOverrideURL"] = game.coverOverrideURLString
            dict["logoURL"] = game.logoURLString
            dict["backdropURL"] = game.backdropURLString
            dict["franchise"] = game.franchise
            dict["firstReleaseDate"] = game.firstReleaseDate.map(iso)
            dict["developers"] = game.developers
            dict["publishers"] = game.publishers
            dict["genres"] = game.genres
            dict["themes"] = game.themes
            dict["gameModes"] = game.gameModes
            dict["playerPerspectives"] = game.playerPerspectives
            dict["trackerDisplay"] = game.trackerDisplayRaw
            // The systems the user OWNS it on, which `platforms` (availability)
            // cannot reconstruct. Absent until v3: after a restore,
            // `ownedPlatformNames` read nil as pre-V3 data and fell back to
            // `platforms.first`, so a Switch+PC purchase came back as one
            // arbitrary platform.
            dict["ownedPlatforms"] = game.ownedPlatforms
            dict["platformReleases"] = game.platformReleasesData?.base64EncodedString()
            dict["showItemHintsOverride"] = game.showItemHintsOverride

            // The user's own notes and renames on tracker items.
            //
            // `TrackerItemDetail` exists precisely because a typed sentence
            // must not be lost to a whole-blob overwrite — and then the backup
            // omitted the model entirely. Game-scoped, so it rides with its
            // game rather than in a root array.
            let details = (game.trackerItemDetails ?? []).filter { $0.deletedAt == nil }
            if !details.isEmpty {
                counts.trackerItemDetails += details.count
                dict["trackerItemDetails"] = details
                    .sorted { $0.itemID < $1.itemID }
                    .map { d -> [String: Any] in
                        var t: [String: Any] = [
                            "id": d.id.uuidString,
                            "itemID": d.itemID,
                            "createdAt": iso(d.createdAt),
                            "updatedAt": iso(d.updatedAt),
                        ]
                        t["note"] = d.note
                        t["chosenName"] = d.chosenName
                        t["sourceName"] = d.sourceName
                        return t
                    }
            }

            // Tracker schema (the structure), separate from progress.
            if let schema = game.trackerSchema, schema.deletedAt == nil {
                counts.schemas += 1
                dict["trackerSchema"] = [
                    "id": schema.id.uuidString,
                    "schemaVersion": schema.schemaVersion,
                    "source": schema.source.rawValue,
                    "engine": schema.engine.rawValue,
                    "generatedAt": schema.generatedAt.map(iso) as Any,
                    "generatedBy": schema.generatedBy as Any,
                    // Embedded as parsed JSON, not an opaque blob, so the file
                    // stays readable and diffable.
                    "data": (try? JSONSerialization.jsonObject(with: schema.jsonData)) ?? [:],
                    "sources": schema.sourcesJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as Any,
                ]
            }

            var playthroughObjects: [[String: Any]] = []
            for pt in game.livePlaythroughs {
                counts.playthroughs += 1

                let sessions = (pt.sessions ?? []).filter { $0.deletedAt == nil }
                counts.sessions += sessions.count
                let sessionObjects = sessions
                    .sorted { $0.startDate < $1.startDate }
                    .map { session -> [String: Any] in
                        var s: [String: Any] = [
                            "id": session.id.uuidString,
                            "startDate": iso(session.startDate),
                            "durationSeconds": session.accumulatedDuration,
                            "state": session.state.rawValue,
                            "isManual": session.isManual,
                        ]
                        s["endDate"] = session.endDate.map(iso)
                        s["notes"] = session.notes
                        // Anchors for a session that was live at export time —
                        // without them "running" is unreconstructable.
                        s["resumedAt"] = session.resumedAt.map(iso)
                        s["pausedAt"] = session.pausedAt.map(iso)
                        s["playedWith"] = session.companions.map { ["name": $0.name, "handle": $0.handle] }
                        return s
                    }

                let runs = pt.liveRuns
                counts.runs += runs.count
                let runObjects = runs.map { run -> [String: Any] in
                    var r: [String: Any] = [
                        "id": run.id.uuidString,
                        "templateID": run.templateID,
                        "startedAt": iso(run.startedAt),
                        "outcome": run.outcome.rawValue,
                        "fields": run.fieldsDict,
                    ]
                    r["endedAt"] = run.endedAt.map(iso)
                    r["notes"] = run.notes
                    r["playedWith"] = run.companions.map { ["name": $0.name, "handle": $0.handle] }
                    return r
                }

                let states = (pt.trackerStates ?? []).filter { $0.deletedAt == nil }
                counts.states += states.count
                let stateObjects = states
                    .sorted { $0.itemID < $1.itemID }
                    .map { state -> [String: Any] in
                        var t: [String: Any] = [
                            // The record's own UUID, not just the schema item
                            // it points at — without it an importer can't
                            // round-trip without duplicating rows.
                            "id": state.id.uuidString,
                            "itemID": state.itemID,
                            "completed": state.completed,
                            "revealed": state.revealed,
                        ]
                        t["count"] = state.count
                        t["rank"] = state.rank
                        t["notes"] = state.notes
                        // The chosen form is a user decision, and `completedAt`
                        // is what "where you left off" reads — `updatedAt` is
                        // only a legacy fallback. Both were dropped before v3,
                        // so a restored tracker showed the wrong variant and
                        // the wrong last-ticked item.
                        t["completedAt"] = state.completedAt.map(iso)
                        t["selectedVariant"] = state.selectedVariant
                        t["selectedVariantUpdatedAt"] = state.selectedVariantUpdatedAt.map(iso)
                        return t
                    }

                var p: [String: Any] = [
                    "id": pt.id.uuidString,
                    "name": pt.name,
                    "progressPercent": pt.progressPercent,
                    "isActive": pt.id == game.activePlaythrough?.id,
                    "createdAt": iso(pt.createdAt),
                    "sessions": sessionObjects,
                    "runs": runObjects,
                    "trackerProgress": stateObjects,
                ]
                p["notes"] = pt.notes
                p["startedAt"] = pt.startedAt.map(iso)
                p["lastPlayedAt"] = pt.lastPlayedAt.map(iso)
                p["outcome"] = pt.outcomeRaw
                p["outcomeNote"] = pt.outcomeNote
                // Zero is every library that never set one, so it is omitted
                // rather than written into every playthrough in the file.
                if pt.carriedOverSeconds > 0 {
                    p["carriedOverSeconds"] = pt.carriedOverSeconds
                }
                playthroughObjects.append(p)
            }
            dict["playthroughs"] = playthroughObjects

            let completions = (game.completionEvents ?? []).filter { $0.deletedAt == nil }
            counts.completions += completions.count
            dict["completions"] = completions.map { event -> [String: Any] in
                var c: [String: Any] = ["id": event.id.uuidString,
                                        "date": iso(event.date), "label": event.label.rawValue]
                c["customLabel"] = event.customLabel
                c["platform"] = event.platform
                c["notes"] = event.notes
                c["datePrecision"] = event.datePrecision
                c["startedDate"] = event.startedDate.map(iso)
                c["startedPrecision"] = event.startedPrecision
                c["playthroughID"] = event.playthrough?.id.uuidString
                c["playedWith"] = event.companions.map { ["name": $0.name, "handle": $0.handle] }
                return c
            }

            // Images the user added, bytes and all.
            //
            // Base64 inside the JSON rather than a sidecar or a zip, because
            // "your library exports to a readable file you can keep anywhere"
            // is a promise on the site and in the beta notes, and a single
            // file is what makes it true. It costs size — roughly a third
            // more than the bytes themselves — which is precisely why ingest
            // downscales before anything is stored (`ImageIngest`).
            //
            // Maps remain links rather than bytes. That gap stays documented
            // and is a different thing: map images are FETCHED, and a photo
            // the user took exists nowhere else.
            let images = (game.images ?? []).filter { $0.deletedAt == nil }
            counts.images += images.count
            counts.imageBytes += images.reduce(0) { $0 + $1.byteCount }
            dict["images"] = images.sorted { $0.addedAt < $1.addedAt }.map { image -> [String: Any] in
                var i: [String: Any] = [
                    "id": image.id.uuidString,
                    "role": image.roleRaw,
                    "addedAt": iso(image.addedAt),
                    "pixelWidth": image.pixelWidth,
                    "pixelHeight": image.pixelHeight,
                    "byteCount": image.byteCount,
                ]
                i["caption"] = image.caption
                i["data"] = image.data?.base64EncodedString()
                return i
            }

            let videos = (game.videos ?? []).filter { $0.deletedAt == nil }
            counts.videos += videos.count
            dict["videos"] = videos.sorted { $0.orderIndex < $1.orderIndex }.map { video -> [String: Any] in
                var v: [String: Any] = [
                    "id": video.id.uuidString,
                    "url": video.urlString,
                    "kind": video.kindRaw,
                    "title": video.title,
                    "group": video.groupName,
                    "orderIndex": video.orderIndex,
                    "watchedSeconds": video.watchedSeconds,
                    "watchedPartIndex": video.watchedPartIndex,
                ]
                v["channel"] = video.channel
                v["youtubeID"] = video.youtubeID.isEmpty ? nil : video.youtubeID
                v["thumbnailURL"] = video.thumbnailURL
                v["notes"] = video.notes
                v["lastWatchedAt"] = video.lastWatchedAt.map(iso)
                // Each playlist part's own resume position — hours of "where
                // was I in part 7" that used to be dropped.
                if !video.parts.isEmpty {
                    v["parts"] = video.parts.map {
                        ["id": $0.id, "title": $0.title, "watchedSeconds": $0.seconds]
                    }
                }
                return v
            }

            let maps = (game.maps ?? []).filter { $0.deletedAt == nil }
            counts.maps += maps.count
            dict["maps"] = maps.sorted { $0.addedAt < $1.addedAt }.map { map -> [String: Any] in
                var m: [String: Any] = [
                    "id": map.id.uuidString,
                    "name": map.name,
                    "kind": map.kind.rawValue,
                    "storageType": map.storageType,
                    // The canonical reference. The local cache URL is a path on
                    // THIS device and meaningless anywhere else, so it is
                    // deliberately not exported.
                    "remoteStoragePath": map.remoteStoragePath,
                    "addedAt": iso(map.addedAt),
                ]
                m["remoteURL"] = map.remoteURLString
                m["pixelWidth"] = map.pixelWidth
                m["pixelHeight"] = map.pixelHeight
                let live = (map.markers ?? []).filter { $0.deletedAt == nil }
                counts.markers += live.count
                m["markers"] = live.map { marker -> [String: Any] in
                    var mk: [String: Any] = [
                        "id": marker.id.uuidString,
                        "x": marker.normalizedX,
                        "y": marker.normalizedY,
                        "category": marker.category.rawValue,
                        "label": marker.label,
                    ]
                    mk["notes"] = marker.notes
                    mk["linkedTrackerItemID"] = marker.linkedTrackerItemID
                    return mk.compactMapValues { $0 }
                }
                return m.compactMapValues { $0 }
            }

            gameObjects.append(dict.compactMapValues { $0 })
        }

        // **Memories are top-level, not nested under their game.** A memory
        // can stand alone — "first LAN party" belongs to no game — so nesting
        // would have exported only the ones that happened to be attached.
        let memories = try context.fetch(
            FetchDescriptor<Memory>(predicate: #Predicate { $0.deletedAt == nil })
        )
        let memoryObjects = memories
            // `id` after the date: two memories with the same interval —
            // easy, since a year-grain memory's interval is the whole year —
            // would otherwise export in whichever order the store happened to
            // hand them over. Codex data #11.
            .sorted { $0.earliest == $1.earliest ? $0.id < $1.id : $0.earliest < $1.earliest }
            .map { memory -> [String: Any] in
                var m: [String: Any] = [
                    "id": memory.id.uuidString,
                    "title": memory.title,
                    // The interval, both ends. Re-deriving it from `precision`
                    // on the way back in would rebuild a guess; these are the
                    // stored truth.
                    "earliest": iso(memory.earliest),
                    "latest": iso(memory.latest),
                    "kind": memory.kind,
                    "createdAt": iso(memory.createdAt),
                ]
                m["body"] = memory.body
                // The user's own words for the date, which the app never
                // re-renders from the interval. Losing this loses the memory's
                // actual answer to "when".
                m["whenText"] = memory.whenText
                m["precision"] = memory.precision
                m["place"] = memory.place
                m["platform"] = memory.platform
                m["gameID"] = memory.game?.id.uuidString
                if !memory.companions.isEmpty {
                    m["playedWith"] = memory.companions.map {
                        ["name": $0.name, "handle": $0.handle]
                    }
                }
                let pictures = (memory.images ?? []).filter { $0.deletedAt == nil }
                counts.images += pictures.count
                counts.imageBytes += pictures.reduce(0) { $0 + $1.byteCount }
                if !pictures.isEmpty {
                    m["images"] = pictures.sorted { $0.addedAt < $1.addedAt }
                        .map { image -> [String: Any] in
                            var i: [String: Any] = [
                                "id": image.id.uuidString,
                                "role": image.roleRaw,
                                "addedAt": iso(image.addedAt),
                                "pixelWidth": image.pixelWidth,
                                "pixelHeight": image.pixelHeight,
                                "byteCount": image.byteCount,
                            ]
                            i["caption"] = image.caption
                            i["data"] = image.data?.base64EncodedString()
                            return i
                        }
                }
                return m.compactMapValues { $0 }
            }

        let collectionObjects = collections
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { collection -> [String: Any] in
                [
                    "id": collection.id.uuidString,
                    "name": collection.name,
                    "isBundle": collection.isBundle,
                    "sortIndex": collection.sortIndex,
                    "notes": collection.notes,
                    "gameIDs": collection.gameIDs,
                ]
            }

        let total = games.count + counts.playthroughs + counts.sessions + counts.runs
            + counts.states + counts.schemas + counts.completions + counts.videos
            + counts.maps + counts.markers + counts.images + collectionObjects.count
            + memoryObjects.count + counts.trackerItemDetails

        let manifest = Manifest(
            formatVersion: formatVersion,
            exportedAt: .now,
            appVersion: appVersionString,
            games: games.count,
            playthroughs: counts.playthroughs,
            sessions: counts.sessions,
            runs: counts.runs,
            trackerStates: counts.states,
            trackerSchemas: counts.schemas,
            completions: counts.completions,
            videos: counts.videos,
            maps: counts.maps,
            markers: counts.markers,
            collections: collectionObjects.count,
            memories: memoryObjects.count,
            trackerItemDetails: counts.trackerItemDetails,
            images: counts.images,
            imageBytes: counts.imageBytes,
            totalRecords: total
        )

        var root: [String: Any] = [
            "manifest": try manifestDictionary(manifest),
            "games": gameObjects,
            "collections": collectionObjects,
            "memories": memoryObjects,
        ]
        // The player's own identity. NOT the obsolete `Profile` bookkeeping
        // row this file's comment excludes — this is the name, the handles and
        // the avatar, and the avatar is the one thing here that cannot be
        // retyped from memory. Added in v3.
        // **Sorted, because `.first` of an unsorted fetch is not a choice.**
        //
        // Before foreground reconciliation folds them, two profile rows can
        // both be present, and an unsorted fetch could put either one in the
        // backup — so the file that exists to rescue an identity could capture
        // the wrong one. Same order the fold itself uses.
        let profiles = ((try? context.fetch(FetchDescriptor<PlayerProfile>())) ?? [])
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        if let profile = profiles.first {
            root["profile"] = ([
                "id": profile.id.uuidString,
                "createdAt": iso(profile.createdAt),
                "updatedAt": iso(profile.updatedAt),
                "displayName": profile.displayName as Any,
                "avatar": profile.avatarData?.base64EncodedString() as Any,
                "nameColor": profile.nameColorRaw as Any,
                "useHandleAsName": profile.useHandleAsName,
                "handles": profile.handles.isEmpty ? nil : profile.handles as Any,
            ] as [String: Any?]).compactMapValues { $0 }
        }
        // Synced appearance choices are user data too — a custom accent and
        // per-status colors are exactly the kind of thing that's annoying to
        // rebuild by memory after a reinstall.
        //
        // Through v2 this wrote six of eighteen fields and the importer never
        // read the block at all, so it was decorative JSON rather than a
        // restore point. Every stored choice is written now, and
        // `LibraryImport.applyAppearance` reads it.
        // Sorted, like every other reader: an unsorted `.first` on a model
        // that can legitimately have two rows exports whichever one the store
        // happened to hand over. See `Repository.reconcileSingletons`.
        if let theme = try? context.fetch(FetchDescriptor<ThemeSettings>(
            sortBy: [SortDescriptor(\.createdAt)])).first {
            root["appearance"] = ([
                "accentHex": theme.accentHex as Any,
                "backgroundHex": theme.backgroundHex as Any,
                // build 37: a palette per appearance. The legacy pair above is
                // still written so an older build can still read this file.
                "accentHue": theme.accentHue as Any,
                "accentSaturation": theme.accentSaturation as Any,
                "paletteLinked": theme.paletteLinked,
                "accentHexLight": theme.accentHexLight as Any,
                "accentHexDark": theme.accentHexDark as Any,
                "backgroundHexLight": theme.backgroundHexLight as Any,
                "backgroundHexDark": theme.backgroundHexDark as Any,
                "appearance": theme.appearanceRaw as Any,
                "statusColors": theme.statusColors,
                "statusNames": theme.statusNames.isEmpty ? nil : theme.statusNames as Any,
                "platformNames": theme.platformNames.isEmpty ? nil : theme.platformNames as Any,
                "pageBackground": theme.pageBackgroundRaw,
                "gamePageLayout": theme.gamePageLayoutRaw as Any,
                "defaultTrackerDisplay": theme.defaultTrackerDisplayRaw,
                "defaultMergeMode": theme.defaultMergeModeRaw as Any,
                "overlappingTimerPolicy": theme.overlappingTimerPolicyRaw as Any,
                "starNames": theme.starNames.isEmpty ? nil : theme.starNames as Any,
                "backdropIntensity": theme.backdropIntensityRaw as Any,
                "showItemHints": theme.showItemHints,
                "showGameLogos": theme.showGameLogos,
                "dekuWishlistURL": theme.dekuWishlistURLString as Any,
                "platformIconVariants": theme.platformIconVariantsData?.base64EncodedString() as Any,
                "savedSwatches": theme.savedSwatchesData?.base64EncodedString() as Any,
            ] as [String: Any?]).compactMapValues { $0 }
        }
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    /// Write the export to a temporary file and return its URL, ready to hand
    /// to a share sheet. Named with the date so a user's Files folder stays
    /// legible when they export more than once.
    static func writeToTemporaryFile(context: ModelContext) throws -> URL {
        try writeToTemporaryFile(data: makeJSON(context: context))
    }

    /// Write already-built export bytes. The settings screen builds the JSON
    /// once for its summary; serialising the whole graph a second time on the
    /// main actor just to write the same bytes doubled the freeze on a big
    /// library.
    static func writeToTemporaryFile(data: Data) throws -> URL {
        let stamp = ExportFormatters.dateOnly.string(from: .now)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LevelSelect-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Short human summary for the UI after an export.
    static func summary(for data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let manifest = root["manifest"] as? [String: Any],
            let games = manifest["games"] as? Int,
            let sessions = manifest["sessions"] as? Int,
            let total = manifest["totalRecords"] as? Int
        else { return nil }
        return "\(games) games · \(sessions) sessions · \(total) records total"
    }

    // MARK: Helpers

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private static func iso(_ date: Date) -> String {
        ExportFormatters.timestamp.string(from: date)
    }

    private static func manifestDictionary(_ manifest: Manifest) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// Formatters are not Sendable, so they live on the main actor alongside the
/// export itself rather than as free-floating statics.
@MainActor
private enum ExportFormatters {
    static let timestamp = ISO8601DateFormatter()
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
