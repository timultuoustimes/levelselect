import Foundation
import SwiftData

/// The mutation layer over SwiftData. Every write bumps sync metadata
/// (`updatedAt`/`revision`) for UI + ordering. Cross-device sync is handled by
/// CloudKit automatically — there is no outbox to maintain. Views read via
/// `@Query`; all writes go through here.
@MainActor
struct Repository {
    let context: ModelContext

    init(_ context: ModelContext) { self.context = context }

    private func touch<T: Syncable>(_ model: T, at date: Date = .now) {
        model.updatedAt = date
        model.revision += 1
    }

    /// Explicit commit after every mutation (beta P0). Failures surface in
    /// the retry banner via PersistenceMonitor instead of vanishing.
    private func persist() {
        PersistenceMonitor.shared.commit(context)
    }

    // MARK: Games

    @discardableResult
    func addGame(name: String, status: GameStatus = .backlog) -> Game {
        let game = Game(name: name, status: status)
        context.insert(game)
        persist()
        return game
    }

    /// Add a game from an IGDB search result with full metadata. The chosen
    /// platform is placed first in `platforms`; the rest are preserved.
    @discardableResult
    func addGame(from igdb: IGDBGame, platform: String?, status: GameStatus) -> Game {
        let game = Game(name: igdb.name, status: status)
        game.igdbID = igdb.id
        game.igdbSlug = igdb.slug
        game.coverImageID = igdb.coverImageID
        game.coverURLString = igdb.coverURLString
        game.franchise = igdb.franchise
        game.firstReleaseDate = igdb.releaseDate
        game.summary = igdb.summary
        game.genres = igdb.genres
        game.themes = igdb.themes
        game.gameModes = igdb.gameModes
        game.playerPerspectives = igdb.playerPerspectives
        game.developers = igdb.developers
        game.publishers = igdb.publishers
        if let platform, !platform.isEmpty {
            game.platforms = [platform] + igdb.platforms.filter { $0 != platform }
        } else {
            game.platforms = igdb.platforms
        }
        context.insert(game)
        persist()
        return game
    }

    /// Re-pull metadata from IGDB by id — fixes legacy data (summaries the web
    /// app capped at 200 chars, bad release dates) and refreshes dev/genre/etc.
    /// Never touches user data (status, rating, ownership, notes) or the user's
    /// chosen `platforms`.
    func refreshFromIGDB(_ game: Game) async {
        guard let id = game.igdbID, let igdb = try? await IGDBService.lookup(id: id) else { return }
        if let s = igdb.summary, !s.isEmpty { game.summary = s }
        if let date = igdb.releaseDate { game.firstReleaseDate = date }
        if let f = igdb.franchise { game.franchise = f }
        if let cover = igdb.coverImageID { game.coverImageID = cover; game.coverURLString = igdb.coverURLString }
        if !igdb.developers.isEmpty { game.developers = igdb.developers }
        if !igdb.publishers.isEmpty { game.publishers = igdb.publishers }
        if !igdb.genres.isEmpty { game.genres = igdb.genres }
        if !igdb.themes.isEmpty { game.themes = igdb.themes }
        if !igdb.gameModes.isEmpty { game.gameModes = igdb.gameModes }
        if !igdb.playerPerspectives.isEmpty { game.playerPerspectives = igdb.playerPerspectives }
        touch(game)
        persist()
    }

    // MARK: - Collections

    @discardableResult
    func createCollection(name: String, isBundle: Bool = false) -> GameCollection {
        let collection = GameCollection(name: name, isBundle: isBundle)
        context.insert(collection)
        touch(collection)
        persist()
        return collection
    }

    func renameCollection(_ collection: GameCollection, to name: String) {
        collection.name = name
        touch(collection)
        persist()
    }

    func setBundle(_ collection: GameCollection, isBundle: Bool) {
        collection.isBundle = isBundle
        touch(collection)
        persist()
    }

    func deleteCollection(_ collection: GameCollection, at date: Date = .now) {
        collection.deletedAt = date
        touch(collection, at: date)
        persist()
    }

    func setMembership(_ collection: GameCollection, game: Game, member: Bool) {
        let key = game.id.uuidString
        var ids = collection.gameIDs
        if member {
            guard !ids.contains(key) else { return }
            ids.append(key)
        } else {
            ids.removeAll { $0 == key }
        }
        collection.gameIDs = ids   // reassign so SwiftData tracks the change
        touch(collection)
        persist()
    }

    /// Member games of a collection (non-deleted), fetched by id.
    func games(in collection: GameCollection) -> [Game] {
        let ids = collection.gameIDs.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { ids.contains($0.id) && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Soft delete — sets a tombstone so trash/undo is possible and the deletion
    /// propagates via CloudKit.
    func softDelete(_ game: Game, at date: Date = .now) {
        game.deletedAt = date
        touch(game, at: date)
        persist()
    }

    // MARK: Playthroughs

    /// Returns the game's ACTIVE playthrough, creating a default one on first use.
    @discardableResult
    func ensureDefaultPlaythrough(for game: Game) -> Playthrough {
        if let active = game.activePlaythrough {
            if game.currentPlaythroughID != active.id {
                game.currentPlaythroughID = active.id
            }
            return active
        }
        let pt = Playthrough()
        context.insert(pt)
        pt.game = game                 // set to-one; SwiftData maintains the inverse
        game.currentPlaythroughID = pt.id
        touch(game)
        persist()
        return pt
    }

    /// Create a new playthrough and switch to it immediately (per Tim).
    @discardableResult
    func addPlaythrough(to game: Game, named name: String) -> Playthrough {
        let pt = Playthrough(name: name.isEmpty ? "Playthrough" : name)
        context.insert(pt)
        pt.game = game
        game.currentPlaythroughID = pt.id
        touch(game)
        persist()
        return pt
    }

    func setActivePlaythrough(_ pt: Playthrough, for game: Game) {
        game.currentPlaythroughID = pt.id
        touch(game)
        persist()
    }

    func renamePlaythrough(_ pt: Playthrough, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        pt.name = trimmed
        touch(pt)
        persist()
    }

    /// Soft-delete a playthrough. A running session is stopped first (records
    /// its time); if it was active, the newest remaining playthrough takes over.
    func deletePlaythrough(_ pt: Playthrough, from game: Game, at date: Date = .now) {
        if let active = pt.activeSession { stopSession(active, at: date) }
        pt.deletedAt = date
        touch(pt, at: date)
        if game.currentPlaythroughID == pt.id {
            game.currentPlaythroughID = game.livePlaythroughs.last?.id
        }
        touch(game, at: date)
        persist()
    }

    // MARK: Sessions (timer derived from timestamps — no ticking writes)

    @discardableResult
    func startSession(on pt: Playthrough, at date: Date = .now) -> Session {
        if let active = pt.activeSession { stopSession(active, at: date) }
        let session = Session(startDate: date, state: .running)
        context.insert(session)
        session.playthrough = pt
        pt.lastPlayedAt = date
        touch(pt, at: date)
        NotificationManager.requestAuthorizationIfNeeded()
        NotificationManager.scheduleStaleReminder(
            sessionID: session.id,
            gameName: pt.game?.name ?? "A game",
            sessionStart: date,
            threshold: StaleSessionGuard.threshold
        )
        LiveActivityManager.sessionChanged(session, gameName: pt.game?.name ?? "A game")
        persist()
        return session
    }

    func pauseSession(_ session: Session, at date: Date = .now) {
        guard session.state == .running else { return }
        session.accumulatedDuration = session.elapsed(asOf: date)
        session.pausedAt = date
        session.resumedAt = nil
        session.state = .paused
        touch(session, at: date)
        // Paused time doesn't accrue — no alarm while paused.
        NotificationManager.cancelStaleReminder(sessionID: session.id)
        LiveActivityManager.sessionChanged(session, gameName: session.playthrough?.game?.name ?? "A game")
        persist()
    }

    func resumeSession(_ session: Session, at date: Date = .now) {
        guard session.state == .paused else { return }
        session.resumedAt = date
        session.pausedAt = nil
        session.state = .running
        touch(session, at: date)
        // Re-arm for the REMAINING time: backdating the start by the already-
        // accumulated play makes (threshold - elapsed-since-start) = remaining.
        NotificationManager.scheduleStaleReminder(
            sessionID: session.id,
            gameName: session.playthrough?.game?.name ?? "A game",
            sessionStart: date.addingTimeInterval(-session.accumulatedDuration),
            threshold: StaleSessionGuard.threshold
        )
        LiveActivityManager.sessionChanged(session, gameName: session.playthrough?.game?.name ?? "A game")
        persist()
    }

    func stopSession(_ session: Session, at date: Date = .now) {
        guard session.state != .stopped else { return }
        session.accumulatedDuration = session.elapsed(asOf: date)
        session.endDate = date
        session.pausedAt = nil
        session.resumedAt = nil
        session.state = .stopped
        touch(session, at: date)
        if let pt = session.playthrough {
            pt.lastPlayedAt = date
            touch(pt, at: date)
        }
        NotificationManager.cancelStaleReminder(sessionID: session.id)
        LiveActivityManager.sessionChanged(session, gameName: session.playthrough?.game?.name ?? "A game")
        persist()
    }

    /// End a forgotten/runaway session at a user-chosen stop time (the timer
    /// was left running, so the user tells us when they actually stopped).
    func endStaleSession(_ session: Session, stoppedAt stop: Date) {
        guard session.state != .stopped else { return }
        let clamped = max(session.startDate, stop)
        session.accumulatedDuration = clamped.timeIntervalSince(session.startDate)
        session.endDate = clamped
        session.pausedAt = nil
        session.resumedAt = nil
        session.state = .stopped
        touch(session)
        if let pt = session.playthrough {
            pt.lastPlayedAt = clamped
            touch(pt)
        }
        NotificationManager.cancelStaleReminder(sessionID: session.id)
        LiveActivityManager.sessionChanged(session, gameName: session.playthrough?.game?.name ?? "A game")
        persist()
    }

    /// Edit a completed session's times and notes.
    func updateSession(_ session: Session, start: Date, end: Date, notes: String?) {
        let clampedEnd = max(start, end)
        session.startDate = start
        session.endDate = clampedEnd
        session.accumulatedDuration = clampedEnd.timeIntervalSince(start)
        session.notes = (notes?.isEmpty == true) ? nil : notes
        touch(session)
        if let pt = session.playthrough { touch(pt) }
        persist()
    }

    /// Remove a session from history (tombstoned so the removal syncs).
    func deleteSession(_ session: Session, at date: Date = .now) {
        session.deletedAt = date
        if session.state != .stopped {
            session.state = .stopped
            session.endDate = session.startDate
        }
        touch(session, at: date)
        NotificationManager.cancelStaleReminder(sessionID: session.id)
        persist()
    }

    /// Discard a session entirely (records no time; tombstoned so the removal syncs).
    func discardSession(_ session: Session, at date: Date = .now) {
        session.accumulatedDuration = 0
        session.endDate = session.startDate
        session.pausedAt = nil
        session.resumedAt = nil
        session.state = .stopped
        session.deletedAt = date
        touch(session, at: date)
        NotificationManager.cancelStaleReminder(sessionID: session.id)
        LiveActivityManager.sessionChanged(session, gameName: session.playthrough?.game?.name ?? "A game")
        persist()
    }

    /// Hand-logged session (already-known duration, no live timer).
    @discardableResult
    func logManualSession(
        on pt: Playthrough,
        duration: TimeInterval,
        date: Date = .now,
        notes: String? = nil
    ) -> Session {
        let session = Session(startDate: date, state: .stopped, isManual: true)
        session.accumulatedDuration = duration
        session.endDate = date.addingTimeInterval(duration)
        session.notes = notes
        context.insert(session)
        session.playthrough = pt
        pt.lastPlayedAt = date
        touch(pt, at: date)
        persist()
        return session
    }

    // MARK: Tracker

    /// Existing state row for one schema item, if any.
    func trackerState(_ pt: Playthrough, itemID: String) -> TrackerStateRecord? {
        (pt.trackerStates ?? []).first { $0.itemID == itemID && $0.deletedAt == nil }
    }

    @discardableResult
    private func ensureTrackerState(_ pt: Playthrough, itemID: String) -> TrackerStateRecord {
        if let existing = trackerState(pt, itemID: itemID) { return existing }
        let record = TrackerStateRecord(itemID: itemID)
        context.insert(record)
        record.playthrough = pt
        return record
    }

    func setTrackerItem(_ pt: Playthrough, itemID: String, done: Bool) {
        let record = ensureTrackerState(pt, itemID: itemID)
        record.completed = done
        touch(record)
        touch(pt)
        persist()
    }

    /// Rank items auto-complete at max rank.
    func setTrackerRank(_ pt: Playthrough, itemID: String, rank: Int, maxRank: Int?) {
        let record = ensureTrackerState(pt, itemID: itemID)
        record.rank = max(0, rank)
        if let maxRank { record.completed = rank >= maxRank }
        touch(record)
        touch(pt)
        persist()
    }

    func revealTrackerItem(_ pt: Playthrough, itemID: String) {
        let record = ensureTrackerState(pt, itemID: itemID)
        record.revealed = true
        touch(record)
        persist()
    }

    /// Ensure the game has a tracker schema record (creating an empty one for
    /// Personal Goals on first use) and append a user goal to it.
    func addPersonalGoal(to game: Game, named name: String) {
        let schema: TrackerSchemaRecord
        if let existing = game.trackerSchema {
            schema = existing
        } else {
            schema = TrackerSchemaRecord(
                source: .builtIn, engine: .objective,
                jsonData: TrackerSchemaJSON.emptySchema()
            )
            context.insert(schema)
            schema.game = game
        }
        if let updated = TrackerSchemaJSON.addingGoal(named: name, to: schema.jsonData) {
            schema.jsonData = updated
            touch(schema)
            touch(game)
            persist()
        }
    }

    /// Apply an AI-generated schema to a game (create or replace), keeping
    /// the user's Personal Goals across regeneration.
    func setGeneratedSchema(for game: Game, jsonData: Data) {
        let schema: TrackerSchemaRecord
        if let existing = game.trackerSchema {
            schema = existing
            schema.jsonData = TrackerSchemaJSON.mergingPersonalGoals(
                from: existing.jsonData, into: jsonData)
        } else {
            schema = TrackerSchemaRecord(source: .aiGenerated, engine: .objective, jsonData: jsonData)
            context.insert(schema)
            schema.game = game
        }
        schema.source = .aiGenerated
        schema.generatedAt = .now
        schema.generatedBy = "claude"
        touch(schema)
        touch(game)
        recomputeProgress(game)
        persist()
    }

    /// Swap the current schema for the game's curated built-in one, if it
    /// ships one. `installMissing` only fills a gap and never overwrites an
    /// existing schema, so once someone generates an AI tracker over a game
    /// that actually has real built-in content, there was previously no way
    /// back — this is that deliberate, user-initiated undo. Personal Goals
    /// carry over the same way regeneration preserves them. Returns whether
    /// a built-in schema existed for this game.
    @discardableResult
    func useBuiltinSchema(for game: Game) -> Bool {
        guard let builtin = BuiltinTrackers.match(for: game) else { return false }
        let schema: TrackerSchemaRecord
        if let existing = game.trackerSchema {
            schema = existing
            schema.jsonData = TrackerSchemaJSON.mergingPersonalGoals(
                from: existing.jsonData, into: builtin.schemaData)
        } else {
            schema = TrackerSchemaRecord(source: .builtIn, engine: builtin.engine, jsonData: builtin.schemaData)
            context.insert(schema)
            schema.game = game
        }
        schema.source = .builtIn
        schema.engine = builtin.engine
        schema.generatedAt = nil
        schema.generatedBy = nil
        touch(schema)
        touch(game)
        recomputeProgress(game)
        persist()
        return true
    }

    /// Turn per-game run logging on or off.
    ///
    /// Runs are a capability of a tracker, not a property of a genre — Dead
    /// Cells and Ball x Pit want trackers without a run log, and someone may
    /// want to log attempts for a game whose generated schema never offered
    /// it. Creates an empty schema first if the game has none, so enabling
    /// runs doesn't require generating a tracker first.
    func setRunTracking(_ enabled: Bool, for game: Game) {
        let schema: TrackerSchemaRecord
        if let existing = game.trackerSchema {
            schema = existing
        } else {
            guard enabled else { return }
            schema = TrackerSchemaRecord(
                source: .builtIn, engine: .run,
                jsonData: TrackerSchemaJSON.emptySchema()
            )
            context.insert(schema)
            schema.game = game
        }
        let updated = enabled
            ? TrackerSchemaJSON.addingDefaultRunTemplate(to: schema.jsonData)
            : TrackerSchemaJSON.removingRunTemplate(from: schema.jsonData)
        guard let updated else { return }
        schema.jsonData = updated
        schema.engine = enabled ? .run : .objective
        touch(schema)
        touch(game)
        persist()
    }

    /// Whether this game currently logs runs.
    func runTrackingEnabled(for game: Game) -> Bool {
        guard let schema = game.trackerSchema else { return false }
        return TrackerSchemaJSON.runTemplate(from: schema.jsonData) != nil
    }

    /// Recompute the active playthrough's progress % from schema + state.
    func recomputeProgress(_ game: Game) {
        guard let schema = game.trackerSchema else { return }
        let categories = TrackerSchemaJSON.categories(from: schema.jsonData)
        let allItems = categories.flatMap(\.items)
        guard !allItems.isEmpty,
              let pt = game.activePlaythrough
        else { return }
        let doneIDs = Set((pt.trackerStates ?? [])
            .filter { $0.completed && $0.deletedAt == nil }
            .map(\.itemID))
        let done = allItems.filter { doneIDs.contains($0.id) }.count
        pt.progressPercent = Double(done) / Double(allItems.count) * 100
        touch(pt)
        persist()
    }

    // MARK: Runs (roguelikes / Hades)

    /// Start a live run with the loadout chosen up front.
    @discardableResult
    func startRun(on pt: Playthrough, fields: [String: String], at date: Date = .now) -> Run {
        let run = Run(
            templateID: "default",
            startedAt: date,
            outcome: .inProgress,
            fieldsJSON: (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
        )
        context.insert(run)
        run.playthrough = pt
        pt.lastPlayedAt = date
        touch(pt, at: date)
        persist()
        return run
    }

    func endRun(_ run: Run, outcome: RunOutcome, notes: String?, at date: Date = .now) {
        run.endedAt = date
        run.outcome = outcome
        run.notes = (notes?.isEmpty == true) ? nil : notes
        touch(run, at: date)
        if let pt = run.playthrough {
            pt.lastPlayedAt = date
            touch(pt, at: date)
        }
        persist()
    }

    /// Log a finished run after the fact.
    @discardableResult
    func logRun(
        on pt: Playthrough,
        fields: [String: String],
        outcome: RunOutcome,
        started: Date,
        duration: TimeInterval,
        notes: String?
    ) -> Run {
        let run = Run(
            templateID: "default",
            startedAt: started,
            outcome: outcome,
            fieldsJSON: (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
        )
        run.endedAt = started.addingTimeInterval(max(0, duration))
        run.notes = (notes?.isEmpty == true) ? nil : notes
        context.insert(run)
        run.playthrough = pt
        pt.lastPlayedAt = started
        touch(pt)
        persist()
        return run
    }

    func deleteRun(_ run: Run, at date: Date = .now) {
        run.deletedAt = date
        if run.outcome == .inProgress { run.outcome = .neutral; run.endedAt = date }
        touch(run, at: date)
        persist()
    }

    // MARK: Videos

    /// Add a video/playlist from a URL. Playlists auto-group under their
    /// title; loose videos land in "Videos". Metadata is filled from oEmbed
    /// by the caller (async) — this just persists.
    @discardableResult
    func addVideo(
        to game: Game,
        parsed: YouTubeService.Parsed,
        urlString: String,
        metadata: YouTubeService.Metadata?
    ) -> GameVideo {
        let title = metadata?.title
            ?? (parsed.kind == .playlist ? "YouTube Playlist" : "YouTube Video")
        let video = GameVideo(kind: parsed.kind, urlString: urlString,
                              youtubeID: parsed.id, title: title)
        video.channel = metadata?.channel
        video.thumbnailURL = metadata?.thumbnailURL
        video.groupName = parsed.kind == .playlist ? title : "Videos"
        video.orderIndex = ((game.videos ?? []).map(\.orderIndex).max() ?? -1) + 1
        context.insert(video)
        video.game = game
        touch(game)
        persist()
        return video
    }

    func deleteVideo(_ video: GameVideo, at date: Date = .now) {
        video.deletedAt = date
        touch(video, at: date)
        persist()
    }

    func moveVideo(_ video: GameVideo, toGroup group: String) {
        let trimmed = group.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        video.groupName = trimmed
        touch(video)
        persist()
    }

    /// Cache a playlist's parts (id + title, playlist order) on the record.
    func cachePlaylistParts(_ video: GameVideo, ids: [String], titles: [String: String]) {
        let payload = ids.map { [$0, titles[$0] ?? "Part"] }
        video.partsData = try? JSONSerialization.data(withJSONObject: payload)
        touch(video)
        persist()
    }

    /// Persist the synced resume position (called by the player bridge,
    /// debounced upstream).
    func updateVideoProgress(_ video: GameVideo, seconds: Double, partIndex: Int?) {
        video.watchedSeconds = max(0, seconds)
        if let partIndex, partIndex >= 0 { video.watchedPartIndex = partIndex }
        video.lastWatchedAt = .now
        touch(video)
        persist()
    }

    // MARK: Bulk clears (Settings → Your data)

    /// Tombstone every session across the library. Games, trackers, and
    /// collections are untouched — this only removes logged time.
    @discardableResult
    func clearAllSessions(at date: Date = .now) -> Int {
        let sessions = (try? context.fetch(
            FetchDescriptor<Session>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []
        for session in sessions {
            NotificationManager.cancelStaleReminder(sessionID: session.id)
            session.deletedAt = date
            if session.state != .stopped {
                session.state = .stopped
                session.endDate = session.startDate
            }
            touch(session, at: date)
        }
        for pt in ((try? context.fetch(FetchDescriptor<Playthrough>())) ?? []) {
            pt.lastPlayedAt = nil
            touch(pt, at: date)
        }
        LiveActivityManager.endCurrent()
        persist()
        return sessions.count
    }

    /// Tombstone every tracker state row and run, so trackers read as untouched
    /// while their structure (the schema) stays in place.
    @discardableResult
    func clearAllTrackerProgress(at date: Date = .now) -> Int {
        let states = (try? context.fetch(
            FetchDescriptor<TrackerStateRecord>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []
        for state in states {
            state.deletedAt = date
            touch(state, at: date)
        }
        let runs = (try? context.fetch(
            FetchDescriptor<Run>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []
        for run in runs {
            run.deletedAt = date
            touch(run, at: date)
        }
        for pt in ((try? context.fetch(FetchDescriptor<Playthrough>())) ?? []) {
            pt.progressPercent = 0
            touch(pt, at: date)
        }
        persist()
        return states.count + runs.count
    }

    // MARK: Completion

    @discardableResult
    func addCompletion(
        to game: Game,
        label: CompletionLabel = .cleared,
        date: Date = .now
    ) -> CompletionEvent {
        let event = CompletionEvent(date: date, label: label)
        context.insert(event)
        event.game = game
        if label == .completed, game.status != .completed {
            game.status = .completed
        }
        touch(game, at: date)
        persist()
        return event
    }
}

// MARK: - Derived helpers

extension Game {
    #if os(iOS) || os(macOS)
    /// Effective tracker display: explicit per-game choice wins; otherwise
    /// the library default (which can never override an explicit choice).
    /// (iOS/macOS only — `ThemePalette` is UI; the watch never reads this.)
    @MainActor
    var resolvedTrackerDisplay: TrackerDisplay {
        trackerDisplayRaw.flatMap { TrackerDisplay(rawValue: $0) }
            ?? ThemePalette.defaultTrackerDisplay
    }
    #endif

    /// Live (non-deleted) playthroughs, oldest first (stable ordering).
    var livePlaythroughs: [Playthrough] {
        (playthroughs ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The playthrough all per-playthrough UI reads: the current selection,
    /// falling back to the oldest live one.
    var activePlaythrough: Playthrough? {
        let live = livePlaythroughs
        if let id = currentPlaythroughID, let match = live.first(where: { $0.id == id }) {
            return match
        }
        return live.first
    }
}

extension Run {
    /// Decoded loadout/field values.
    var fieldsDict: [String: String] {
        guard let obj = try? JSONSerialization.jsonObject(with: fieldsJSON) as? [String: Any]
        else { return [:] }
        return obj.compactMapValues {
            if let s = $0 as? String { return s }
            if let n = $0 as? NSNumber { return n.stringValue }
            return nil
        }
    }

    var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }
}

extension Playthrough {
    /// Live runs, newest first.
    var liveRuns: [Run] {
        (runs ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var activeRun: Run? {
        liveRuns.first { $0.outcome == .inProgress }
    }
}

extension Playthrough {
    /// Total time across all sessions (active session counted live via `asOf`;
    /// discarded/tombstoned sessions excluded).
    func totalPlaytime(asOf now: Date = .now) -> TimeInterval {
        (sessions ?? [])
            .filter { $0.deletedAt == nil }
            .reduce(0) { $0 + $1.elapsed(asOf: now) }
    }
}
