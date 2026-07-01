import Foundation
import SwiftData

/// Reconciliation report for a one-time legacy import (roadmap §Phase 1.8).
struct ImportReport: Equatable, Sendable {
    var games = 0
    var playthroughs = 0
    var sessions = 0
    var completionEvents = 0
    var maps = 0
    var markers = 0
    var trackerSchemas = 0
    var skipped: [String] = []      // "game name — reason"
    var alreadyImported = false
}

/// Imports a legacy `game_data.data` JSON blob into SwiftData. Tolerant by
/// design: a malformed game is skipped and reported rather than aborting the
/// whole import. Idempotent per source device via `MigrationReceipt`.
@MainActor
struct LegacyImporter {
    let context: ModelContext

    init(_ context: ModelContext) { self.context = context }

    @discardableResult
    func `import`(
        data: Data,
        sourceDeviceID: String,
        appVersion: String = "0.1.0"
    ) throws -> ImportReport {
        var report = ImportReport()

        // Idempotency: already imported this device?
        let receipts = try context.fetch(
            FetchDescriptor<MigrationReceipt>(
                predicate: #Predicate { $0.sourceDeviceID == sourceDeviceID }
            )
        )
        if !receipts.isEmpty {
            report.alreadyImported = true
            return report
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let library = root["library"] as? [Any]
        else {
            throw ImportError.malformedRoot
        }

        // Dedupe against any games already present by legacyID.
        let existingLegacyIDs = Set(
            try context.fetch(FetchDescriptor<Game>()).compactMap(\.legacyID)
        )

        for entry in library {
            guard let g = entry as? [String: Any] else { continue }
            let legacyID = str(g, "id") ?? UUID().uuidString
            let name = str(g, "name") ?? "Untitled"
            if existingLegacyIDs.contains(legacyID) {
                report.skipped.append("\(name) — duplicate legacyID")
                continue
            }
            importGame(g, legacyID: legacyID, name: name, into: &report)
        }

        // Receipt (idempotency + reconciliation).
        let counts = try? JSONSerialization.data(withJSONObject: [
            "games": report.games, "playthroughs": report.playthroughs,
            "sessions": report.sessions, "completionEvents": report.completionEvents,
            "maps": report.maps, "markers": report.markers,
            "trackerSchemas": report.trackerSchemas,
        ])
        context.insert(MigrationReceipt(
            sourceDeviceID: sourceDeviceID,
            appVersion: appVersion,
            countsJSON: counts ?? Data()
        ))
        return report
    }

    // MARK: - Per-game

    private func importGame(_ g: [String: Any], legacyID: String, name: String, into report: inout ImportReport) {
        let game = Game(name: name, status: parseStatus(str(g, "status")))
        game.legacyID = legacyID
        game.notes = str(g, "notes") ?? ""
        game.summary = str(g, "summary")
        game.igdbID = int(g, "igdbId")
        game.igdbSlug = str(g, "igdbSlug")
        game.firstReleaseDate = date(g["firstReleaseDate"])
        game.franchise = str(g, "franchise")
        game.coverURLString = str(g, "coverUrl")
        game.coverImageID = str(g, "coverImageId")
        game.addedAt = date(g["addedAt"]) ?? .now
        game.platforms = arrStr(g, "platforms")
        game.userTags = arrStr(g, "userTags")
        game.genres = arrStr(g, "genres")
        game.themes = arrStr(g, "themes")
        game.gameModes = arrStr(g, "gameModes")
        game.playerPerspectives = arrStr(g, "playerPerspectives")
        game.developers = arrStr(g, "developers")
        game.publishers = arrStr(g, "publishers")
        game.review = str(g, "review")   // rare game-level review

        context.insert(game)
        report.games += 1

        // Playthroughs (+ sessions). Consolidate rating: userRating ?? first save rating.
        var consolidatedRating: Int? = int(g, "userRating")
        let saves = arr(g, "saves")
        for s in saves {
            let pt = importPlaythrough(s, into: &report)
            pt.game = game
            game.playthroughs.append(pt)
            if consolidatedRating == nil, let r = int(s, "rating"), r > 0 {
                consolidatedRating = r
            }
        }
        game.rating = consolidatedRating
        game.currentPlaythroughID = game.playthroughs.first?.id

        // Completion events (legacy clears[]).
        for c in arr(g, "clears") {
            let ev = CompletionEvent(date: date(c["clearedAt"]) ?? .now, label: .cleared)
            ev.legacyID = str(c, "id")
            ev.game = game
            game.completionEvents.append(ev)
            context.insert(ev)
            report.completionEvents += 1
        }

        // Tracker schema (only when structuredData present).
        if let sd = g["structuredData"] as? [String: Any] {
            let rec = TrackerSchemaRecord(
                schemaVersion: int(sd, "schemaVersion") ?? 1,
                source: parseSource(str(sd, "generatedBy")),
                engine: engine(forTrackerType: str(g, "trackerType") ?? "None"),
                jsonData: (try? JSONSerialization.data(withJSONObject: sd)) ?? Data()
            )
            rec.generatedAt = date(sd["generatedAt"])
            rec.generatedBy = str(sd, "generatedBy")
            rec.game = game
            game.trackerSchema = rec
            context.insert(rec)
            report.trackerSchemas += 1
        }

        // Maps + markers.
        for m in arr(g, "maps") {
            let map = GameMap(
                name: str(m, "name") ?? "Map",
                kind: parseMapKind(str(m, "type")),
                storageType: str(m, "storageType") ?? "upload",
                remoteStoragePath: str(m, "storagePath") ?? "",
                addedAt: date(m["addedAt"]) ?? .now
            )
            map.legacyID = str(m, "id")
            map.remoteURLString = str(m, "imageUrl")
            map.game = game
            game.maps.append(map)
            context.insert(map)
            report.maps += 1

            for mk in arr(m, "markers") {
                let marker = Marker(
                    normalizedX: clamp01((dbl(mk, "x") ?? 0) / 100),
                    normalizedY: clamp01((dbl(mk, "y") ?? 0) / 100),
                    category: parseMarkerCategory(str(mk, "category")),
                    label: str(mk, "label") ?? ""
                )
                marker.legacyID = str(mk, "id")
                marker.notes = str(mk, "notes")
                marker.createdAt = date(mk["createdAt"]) ?? .now
                marker.map = map
                map.markers.append(marker)
                context.insert(marker)
                report.markers += 1
            }
        }
    }

    private func importPlaythrough(_ s: [String: Any], into report: inout ImportReport) -> Playthrough {
        let pt = Playthrough(
            name: str(s, "name") ?? "Playthrough",
            progressPercent: dbl(s, "progressPercent") ?? 0,
            startedAt: date(s["createdAt"])
        )
        pt.legacyID = str(s, "id")
        pt.notes = str(s, "notes")
        pt.lastPlayedAt = date(s["lastPlayedAt"])
        context.insert(pt)
        report.playthroughs += 1

        // Sessions: sessions[] is authoritative; append activeSession if not listed.
        var seen = Set<String>()
        var rawSessions = arr(s, "sessions")
        if let active = s["activeSession"] as? [String: Any] {
            let aid = str(active, "id")
            if aid == nil || !rawSessions.contains(where: { str($0, "id") == aid }) {
                rawSessions.append(active)
            }
        }
        for raw in rawSessions {
            if let sid = str(raw, "id") {
                if seen.contains(sid) { continue }
                seen.insert(sid)
            }
            let session = importSession(raw)
            session.playthrough = pt
            pt.sessions.append(session)
            context.insert(session)
            report.sessions += 1
        }
        return pt
    }

    private func importSession(_ raw: [String: Any]) -> Session {
        let start = date(raw["startTime"]) ?? .now
        let end = date(raw["endTime"])
        let paused = date(raw["pausedAt"])
        let accumulated = dbl(raw, "accumulatedTime")
            ?? dbl(raw, "duration")
            ?? end.map { $0.timeIntervalSince(start) }
            ?? 0

        let state: SessionState
        if end != nil { state = .stopped }
        else if paused != nil { state = .paused }
        else { state = .running }

        let session = Session(startDate: start, state: state, isManual: (raw["manual"] as? Bool) ?? false)
        session.endDate = end
        session.accumulatedDuration = accumulated
        session.pausedAt = (state == .paused) ? paused : nil
        session.notes = str(raw, "notes")
        session.legacyID = str(raw, "id")
        return session
    }

    // MARK: - Mapping helpers

    private func engine(forTrackerType t: String) -> TrackerEngine {
        switch t {
        case "gonner", "lone-ruin", "cursed-to-golf": return .run
        default: return .objective
        }
    }
    private func parseStatus(_ s: String?) -> GameStatus {
        guard let s, let v = GameStatus(rawValue: s) else { return .backlog }
        return v
    }
    private func parseSource(_ generatedBy: String?) -> TrackerSource {
        guard let g = generatedBy?.lowercased() else { return .builtIn }
        return (g.contains("claude") || g.contains("ai") || g.contains("gpt")) ? .aiGenerated : .builtIn
    }
    private func parseMapKind(_ s: String?) -> MapKind { MapKind(rawValue: s ?? "") ?? .other }
    private func parseMarkerCategory(_ s: String?) -> MarkerCategory { MarkerCategory(rawValue: s ?? "") ?? .note }
    private func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

    // MARK: - Tolerant field accessors

    private func str(_ d: [String: Any], _ k: String) -> String? {
        if let s = d[k] as? String { return s.isEmpty ? nil : s }
        return nil
    }
    private func int(_ d: [String: Any], _ k: String) -> Int? {
        if let n = d[k] as? NSNumber { return n.intValue }
        if let s = d[k] as? String { return Int(s) }
        return nil
    }
    private func dbl(_ d: [String: Any], _ k: String) -> Double? {
        if let n = d[k] as? NSNumber { return n.doubleValue }
        if let s = d[k] as? String { return Double(s) }
        return nil
    }
    private func arrStr(_ d: [String: Any], _ k: String) -> [String] {
        (d[k] as? [Any])?.compactMap { $0 as? String } ?? []
    }
    private func arr(_ d: [String: Any], _ k: String) -> [[String: Any]] {
        (d[k] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }
    /// Parse a date from an ISO8601 string or an epoch number (seconds or ms).
    private func date(_ any: Any?) -> Date? {
        if let s = any as? String {
            if let d = Self.isoFractional.date(from: s) { return d }
            if let d = Self.iso.date(from: s) { return d }
            return nil
        }
        if let n = any as? NSNumber {
            let v = n.doubleValue
            return Date(timeIntervalSince1970: v > 1_000_000_000_000 ? v / 1000 : v)
        }
        return nil
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    enum ImportError: Error { case malformedRoot }
}
