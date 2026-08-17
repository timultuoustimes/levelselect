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

    /// Route a direct model edit through the repository's invariants.
    ///
    /// The header above says every write goes through here; the review found
    /// a dozen view call sites mutating models directly — pin, status,
    /// rating, ownership, tags — leaving `updatedAt`/`revision` stale (which
    /// corrupts cross-device ordering) and deferring the save to autosave,
    /// where a failure surfaces nowhere and a crash can silently lose the
    /// edit. One generic wrapper beats a bespoke method per field: the call
    /// site keeps its one-line mutation and the invariant stops depending on
    /// anyone remembering it.
    func edit<T: Syncable>(_ model: T, _ mutate: (T) -> Void) {
        mutate(model)
        touch(model)
        persist()
    }

    /// Stamp-and-commit for the screen that edits through SwiftUI bindings
    /// (Game Detail's rating, ownership, notes, metadata and review editors).
    ///
    /// Text fields write straight into the model on every keystroke; wrapping
    /// each keystroke in an explicit commit would trade one bug for a worse
    /// one, so the natural boundary — leaving the page — stamps sync metadata
    /// once. The change test is EDIT-SCOPED: the view captures the game's
    /// `bindingEditFingerprint` when the page appears and this compares
    /// against it on the way out. The old gate asked `context.hasChanges` — a
    /// question about the whole context, not this game — so any unrelated
    /// pending model made leaving an untouched page bump this game's
    /// revision, and an autosave that committed the keystrokes first left a
    /// real edit persisted with NO stamp at all. Either way, CloudKit's
    /// conflict ordering then judged the wrong side newer.
    func finalizeEdits(_ game: Game, ifChangedFrom fingerprint: Int) {
        guard game.bindingEditFingerprint != fingerprint else { return }
        touch(game)
        persist()
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
        // ALL of them, not `pt.activeSession` — after a sync race there can be
        // more than one unstopped session, and stopping only the arbitrary
        // first left another timer silently accruing forever.
        for active in liveUnstoppedSessions(of: pt) { stopSession(active, at: date) }
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
        // Reuse Session.elapsed rather than restating the arithmetic.
        //
        // This used to write `stop - startDate`, throwing away both
        // accumulatedDuration and the resume anchor — so every pause between
        // the original start and the chosen stop was recorded as PLAYTIME.
        // Start at 1pm, play an hour, pause for four, resume, forget to stop:
        // the app banked five hours. The inflated figure then synced, appeared
        // in Stats and went into exports, and nothing on screen suggested it
        // was wrong.
        //
        // A paused session has no running segment, so elapsed() correctly
        // returns its accumulated total unchanged.
        let anchor = session.state == .running
            ? (session.resumedAt ?? session.startDate)
            : session.startDate
        let clamped = max(anchor, stop)
        session.accumulatedDuration = session.elapsed(asOf: clamped)
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
    ///
    /// Deterministic when duplicates exist: two devices can each create a row
    /// for the same item before sync, and both survive it (ids are random
    /// UUIDs; logical identity is only a convention). The winner is the row
    /// most recently touched, under a TOTAL order — (updatedAt, id) — so
    /// equal timestamps still resolve to the same row on every device. A
    /// "prefer the ticked twin" rule looks kinder but reads the wrong state
    /// when the user's LATEST action was an untick; latest action is the only
    /// rule that never overrides the user. `reconcile` merges the duplicates
    /// away with the same order; this keeps reads stable until it has.
    func trackerState(_ pt: Playthrough, itemID: String) -> TrackerStateRecord? {
        (pt.trackerStates ?? [])
            .filter { $0.itemID == itemID && $0.deletedAt == nil }
            .max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    @discardableResult
    private func ensureTrackerState(_ pt: Playthrough, itemID: String) -> TrackerStateRecord {
        if let existing = trackerState(pt, itemID: itemID) { return existing }
        let record = TrackerStateRecord(itemID: itemID)
        context.insert(record)
        record.playthrough = pt
        return record
    }

    /// Tick or untick an item, and keep the cached percentage true.
    ///
    /// `recomputeProgress` used to be the CALLER's job, which held only for as
    /// long as every caller remembered. The widget/Live Activity toggle didn't,
    /// so checking something off there saved the tick and left the progress
    /// ring showing the old number until an in-app action happened to fix it.
    /// A second caller forgetting is evidence the invariant belongs here — and
    /// callers must NOT also recompute; that doubled the parse/touch/save per
    /// tap. It recomputes `pt`, the playthrough actually written, and commits
    /// exactly once.
    func setTrackerItem(_ pt: Playthrough, itemID: String, done: Bool) {
        let record = ensureTrackerState(pt, itemID: itemID)
        record.completed = done
        touch(record)
        touch(pt)
        recomputeProgress(pt)
        persist()
    }

    /// Rank items auto-complete at max rank.
    func setTrackerRank(_ pt: Playthrough, itemID: String, rank: Int, maxRank: Int?) {
        let record = ensureTrackerState(pt, itemID: itemID)
        record.rank = max(0, rank)
        if let maxRank { record.completed = rank >= maxRank }
        touch(record)
        touch(pt)
        recomputeProgress(pt)
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
        // Generated ids are untrusted input, not a valid key set — duplicate
        // item ids share one state record (ticking either row ticks both).
        // Sanitize at the boundary so no install path accepts them raw.
        let jsonData = TrackerMerge.deduplicated(jsonData)
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

    /// What actually happened when a generated schema was folded in — the
    /// material for the summary the user sees afterwards.
    struct TrackerMergeOutcome: Sendable {
        var added: Int = 0
        var removed: Int = 0
        var renamed: Int = 0
        /// Progress records whose item id was rewritten to follow a rename, so
        /// the tick survived. The whole point of the exercise.
        var migrated: Int = 0
        /// Items the user had progress on that the new tracker no longer
        /// contains at all. These can't be re-ticked — there's nothing left to
        /// tick — so they're what `rescueAsPersonalGoals` exists for.
        var lostProgress: [TrackerItemDTO] = []

        var isNoOp: Bool { added == 0 && removed == 0 && renamed == 0 }
    }

    /// Rename a tracker category, or one item inside it.
    ///
    /// Works on generated content as much as imported or hand-written — a
    /// generator's naming is a suggestion, not a fact. "Stages" becoming
    /// "Achievements" shouldn't require regenerating anything.
    @discardableResult
    func renameTracker(_ game: Game, categoryID: String,
                       itemID: String? = nil, to newName: String) -> Bool {
        guard let schema = game.trackerSchema,
              let data = TrackerSchemaJSON.renaming(categoryID: categoryID, itemID: itemID,
                                                   to: newName, in: schema.jsonData)
        else { return false }
        schema.jsonData = data
        touch(schema)
        touch(game)
        persist()
        return true
    }

    /// Edit an item's name, location and the user's own note.
    @discardableResult
    func editTrackerItem(_ game: Game, categoryID: String, itemID: String,
                         name: String?, location: String?, note: String?) -> Bool {
        guard let schema = game.trackerSchema,
              let data = TrackerSchemaJSON.editingItem(
                categoryID: categoryID, itemID: itemID,
                name: name, location: location, note: note, in: schema.jsonData)
        else { return false }
        schema.jsonData = data
        touch(schema)
        touch(game)
        persist()
        return true
    }

    /// Every tracker-state record across ALL live playthroughs of a game.
    ///
    /// The schema belongs to the *game*, not to one playthrough, so anything
    /// that rewrites it affects every playthrough at once. Looking only at the
    /// active one — which this did — meant a regeneration silently orphaned the
    /// progress of every other playthrough, with no warning and no rescue.
    private func allTrackerStates(for game: Game) -> [TrackerStateRecord] {
        game.livePlaythroughs.flatMap { ($0.trackerStates ?? []).filter { $0.deletedAt == nil } }
    }

    /// Items the user has put work into, across every playthrough.
    ///
    /// Deliberately broader than "completed" — a part-filled rank or count is
    /// just as much their work, and rank rides on the same record, so a
    /// half-upgraded Mirror of Night talent has to count as progress worth
    /// protecting. A written note and a revealed secret count too: a removal
    /// that takes a note with it used to sail through the review screen
    /// unlisted, because "work" was defined as only the checkable kinds.
    func progressItemIDs(for game: Game) -> Set<String> {
        Set(allTrackerStates(for: game)
            .filter {
                $0.completed || ($0.rank ?? 0) > 0 || ($0.count ?? 0) > 0
                    || $0.revealed || !($0.notes ?? "").isEmpty
            }
            .map(\.itemID))
    }

    /// What a generated schema *would* do, without touching anything. Feeds the
    /// review screen so the choice is made against real numbers.
    func previewGeneratedSchema(for game: Game, jsonData: Data) -> TrackerDiff {
        // Same sanitation as the apply path, so the preview describes exactly
        // what an apply would install.
        let jsonData = TrackerMerge.deduplicated(jsonData)
        guard let existing = game.trackerSchema else {
            return TrackerMerge.diff(current: TrackerSchemaJSON.emptySchema(), incoming: jsonData)
        }
        return TrackerMerge.diff(current: existing.jsonData, incoming: jsonData,
                                 progressIDs: progressItemIDs(for: game))
    }

    /// Fold a generated schema into the game's existing one on the user's
    /// terms, carrying progress across items that came back under a new id.
    ///
    /// Replaces the all-or-nothing `setGeneratedSchema` path for anything
    /// user-initiated. The migration step is the reason this exists: progress
    /// is keyed by item id, generation is nondeterministic about ids, so a
    /// regeneration that returns the same content re-slugged used to silently
    /// zero the user's ticks. Renames are followed; only genuine removals
    /// lose anything.
    @discardableResult
    func applyGeneratedSchema(for game: Game, jsonData: Data,
                              mode: TrackerMergeMode) -> TrackerMergeOutcome {
        // The ONE ingest boundary: first generation, Replace, Add-to-existing
        // and Add-new-category all pass through here, so sanitizing the
        // payload once covers every mode — the previous seen-set fix deduped
        // only the append-into-matched-category branch and left the other
        // three accepting duplicate ids/names raw.
        let jsonData = TrackerMerge.deduplicated(jsonData)
        // Migration rewrites state-record ids; running it over sync-duplicated
        // rows would migrate one twin and strand the other under the old id.
        reconcile(game)
        guard let existing = game.trackerSchema else {
            // Nothing to merge into — first generation is just an install.
            setGeneratedSchema(for: game, jsonData: jsonData)
            let cats = TrackerSchemaJSON.categories(from: jsonData)
            return TrackerMergeOutcome(added: cats.flatMap(\.items).count)
        }

        let states = allTrackerStates(for: game)
        let progressIDs = progressItemIDs(for: game)

        let diff = TrackerMerge.diff(current: existing.jsonData,
                                     incoming: jsonData, progressIDs: progressIDs)
        let merged = TrackerMerge.merged(current: existing.jsonData,
                                         incoming: jsonData, mode: mode)

        var outcome = TrackerMergeOutcome(
            added: diff.added.count, removed: diff.removed.count, renamed: diff.renamed.count)

        // Only Replace adopts the incoming ids, so only Replace needs the
        // migration — the additive modes leave existing items exactly where
        // they are, which is why they can't lose progress at all.
        if mode == .replace {
            // Grouped, not a dictionary keyed by item id: the same item has a
            // SEPARATE state record in each playthrough, so keeping only the
            // first would migrate one and strand the rest.
            let byID = Dictionary(grouping: states, by: \.itemID)
            for match in diff.renamed where match.current.id != match.incoming.id {
                for record in byID[match.current.id] ?? [] {
                    record.itemID = match.incoming.id
                    touch(record)
                    outcome.migrated += 1
                }
            }
            outcome.lostProgress = diff.removed.filter { progressIDs.contains($0.id) }
        }

        existing.jsonData = merged
        existing.source = .aiGenerated
        existing.generatedAt = .now
        existing.generatedBy = "claude"
        touch(existing)
        touch(game)
        recomputeProgress(game)
        persist()
        return outcome
    }

    /// Keep items a regenerated tracker dropped, as Personal Goals.
    ///
    /// A removed item can't be re-ticked because it no longer exists in the
    /// schema, so the only way not to silently lose someone's completed work
    /// is to move it somewhere every merge mode preserves. Completion moves
    /// with it — the goal arrives already ticked if the item was.
    @discardableResult
    func rescueAsPersonalGoals(_ items: [TrackerItemDTO], for game: Game) -> Int {
        guard let schema = game.trackerSchema, !items.isEmpty else { return 0 }
        // Across every playthrough, and grouped — a rescued item can have a
        // record in each, and all of them need pointing at the new goal.
        let byID = Dictionary(grouping: allTrackerStates(for: game), by: \.itemID)

        var data = schema.jsonData
        var rescued = 0
        // Id is derived from the original rather than random, so a second
        // rescue of the same item is recognisable — but `addingGoal` appends
        // unconditionally, so the skip has to happen here.
        var present = Set(TrackerSchemaJSON.categories(from: data).flatMap(\.items).map(\.id))
        for item in items {
            let goalID = "goal-rescued-\(item.id)"
            guard !present.contains(goalID) else { continue }
            guard let next = TrackerSchemaJSON.addingGoal(named: item.name, id: goalID, to: data)
            else { continue }
            present.insert(goalID)
            data = next
            for record in byID[item.id] ?? [] {
                record.itemID = goalID
                touch(record)
            }
            rescued += 1
        }
        guard rescued > 0 else { return 0 }
        schema.jsonData = data
        touch(schema)
        touch(game)
        recomputeProgress(game)
        persist()
        return rescued
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

    /// Recompute cached progress for EVERY live playthrough of a game.
    ///
    /// The schema belongs to the game, so anything that rewrites it — a
    /// Replace, a rescue, a builtin swap — changes the denominator for all
    /// playthroughs at once. Recomputing only the active one left every
    /// inactive playthrough's cached percentage stale indefinitely: switching
    /// to it later showed a ring that disagreed with its own migrated
    /// checkmarks, and nothing ever corrected it.
    func recomputeProgress(_ game: Game) {
        guard let schema = game.trackerSchema else { return }
        let allItems = TrackerSchemaJSON.categories(from: schema.jsonData).flatMap(\.items)
        guard !allItems.isEmpty else { return }
        for pt in game.livePlaythroughs { recompute(pt, allItems: allItems) }
        persist()
    }

    /// Recompute the cache of the playthrough that CHANGED — the setters take
    /// an explicit playthrough, and recomputing `game.activePlaythrough`
    /// instead meant a write to a non-active playthrough updated its row but
    /// refreshed a different playthrough's percentage.
    private func recomputeProgress(_ pt: Playthrough) {
        guard let schema = pt.game?.trackerSchema else { return }
        let allItems = TrackerSchemaJSON.categories(from: schema.jsonData).flatMap(\.items)
        guard !allItems.isEmpty else { return }
        recompute(pt, allItems: allItems)
    }

    private func recompute(_ pt: Playthrough, allItems: [TrackerItemDTO]) {
        let doneIDs = Set((pt.trackerStates ?? [])
            .filter { $0.completed && $0.deletedAt == nil }
            .map(\.itemID))
        let done = allItems.filter { doneIDs.contains($0.id) }.count
        pt.progressPercent = Double(done) / Double(allItems.count) * 100
        touch(pt)
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
        // Carry existing per-part positions across a re-cache — the parts list
        // is refetched whenever the player reports it, and dropping the
        // positions here would quietly reset the playlist every time.
        let existing = Dictionary(video.parts.map { ($0.id, $0.seconds) },
                                  uniquingKeysWith: { a, _ in a })
        let payload: [[Any]] = ids.map { [$0, titles[$0] ?? "Part", existing[$0] ?? 0] }
        video.partsData = try? JSONSerialization.data(withJSONObject: payload)
        touch(video)
        persist()
    }

    /// Persist the synced resume position (called by the player bridge,
    /// debounced upstream).
    func updateVideoProgress(_ video: GameVideo, seconds: Double, partIndex: Int?) {
        video.watchedSeconds = max(0, seconds)
        if let partIndex, partIndex >= 0 {
            video.watchedPartIndex = partIndex
            // Each part keeps its own position, so moving between parts doesn't
            // overwrite where you were in the last one.
            setPartSeconds(video, index: partIndex, seconds: max(0, seconds))
        }
        video.lastWatchedAt = .now
        touch(video)
        persist()
    }

    /// Select a playlist part WITHOUT disturbing its saved position.
    ///
    /// Jumping to a part used to write `seconds: 0`, which wiped that part's
    /// resume point at the exact moment you asked to go there — so a playlist
    /// could never resume a part you returned to.
    func setVideoPart(_ video: GameVideo, index: Int) {
        guard index >= 0 else { return }
        video.watchedPartIndex = index
        if video.parts.indices.contains(index) {
            video.watchedSeconds = video.parts[index].seconds
        }
        video.lastWatchedAt = .now
        touch(video)
        persist()
    }

    private func setPartSeconds(_ video: GameVideo, index: Int, seconds: Double) {
        guard let data = video.partsData,
              var raw = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]],
              raw.indices.contains(index)
        else { return }
        var row = raw[index]
        if row.count >= 3 { row[2] = seconds } else { row.append(seconds) }
        raw[index] = row
        video.partsData = try? JSONSerialization.data(withJSONObject: raw)
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

    // MARK: CloudKit reconciliation

    /// CloudKit syncs records; it does not enforce this app's logical
    /// invariants. Ids are random UUIDs and logical identity — one state row
    /// per (playthrough, item), one unstopped session per playthrough, one
    /// default playthrough per game — is only a convention each device upholds
    /// locally. Two devices editing before sync can therefore both be right,
    /// and after sync the store holds both versions of the truth.
    ///
    /// This is the repair pass. It resolves only what it can resolve without
    /// guessing: duplicate rows for the same logical record. It never infers
    /// intent from absence — a record that merely LOOKS disposable (empty,
    /// default-named) may be mid-sync from another device, so nothing is
    /// deleted on that basis. It runs before a schema merge, whose migration
    /// must not operate on duplicated rows, and when a game's page opens.
    struct ReconcileOutcome {
        var mergedStates = 0
        var closedSessions = 0
        var isNoOp: Bool { mergedStates == 0 && closedSessions == 0 }
    }

    /// Duplicate playthroughs are deliberately NOT auto-deleted. An "empty
    /// duplicate default" is indistinguishable from a playthrough another
    /// device just created and is still filling — its tracker state and
    /// session may simply not have synced yet. Emptiness at one instant is
    /// not proof of duplicate intent, and a wrong guess here tombstones a
    /// real playthrough plus everything later written into it, silently.
    /// Duplicates stay visible for the user to resolve; deletion requires
    /// their hand.
    @discardableResult
    func reconcile(_ game: Game, at date: Date = .now) -> ReconcileOutcome {
        var outcome = ReconcileOutcome()
        for pt in game.livePlaythroughs {
            outcome.mergedStates += mergeDuplicateStates(in: pt, at: date)
            outcome.closedSessions += closeDuplicateSessions(in: pt, at: date)
        }
        if outcome.mergedStates > 0 { recomputeProgress(game) }
        if !outcome.isNoOp { persist() }
        return outcome
    }

    /// Foreground sweep, bounded. The previous version walked every live
    /// game's playthrough/state/session relationships on the main actor at
    /// every activation — O(whole library) faulting at the worst possible
    /// moment, flagged by the round-2 review. The only duplicate that does
    /// cross-game damage while merely sitting there is two clocks running at
    /// once (playtime double-counts in Stats and totals), and unstopped
    /// sessions are a tiny, directly fetchable set — so foregrounding now
    /// repairs exactly that and nothing else. Duplicate state rows are
    /// benign at rest (reads are deterministic and pick the same row
    /// everywhere); the full per-game reconcile handles them when a game's
    /// page opens and before every schema merge, where ids get rewritten.
    func reconcileLibrary(at date: Date = .now) {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.endDate == nil && $0.deletedAt == nil })
        let open = ((try? context.fetch(descriptor)) ?? []).filter { $0.state != .stopped }
        var closed = 0
        for (_, sessions) in Dictionary(grouping: open, by: { $0.playthrough?.id }) {
            guard sessions.count > 1, let pt = sessions.first?.playthrough,
                  pt.deletedAt == nil, pt.game?.deletedAt == nil
            else { continue }
            closed += closeDuplicateSessions(in: pt, at: date)
        }
        if closed > 0 { persist() }
    }

    private func liveUnstoppedSessions(of pt: Playthrough) -> [Session] {
        (pt.sessions ?? []).filter { $0.state != .stopped && $0.deletedAt == nil }
    }

    /// Fold duplicate state rows for the same item into one and tombstone the
    /// rest, so the removal itself syncs.
    ///
    /// The winner is the row the user touched last, under the same total
    /// order as the `trackerState` read — (updatedAt, id) — so the surviving
    /// row is the row the UI was already showing, and every device picks the
    /// SAME survivor. (Without the id tie-break, equal timestamps let each
    /// device tombstone the row the other kept; after those tombstones
    /// synced, both copies of the user's progress could be gone.)
    ///
    /// The winner's checked/rank/count stand exactly as last set: no OR, no
    /// max. Folding "the strongest claim from each side" resurrected
    /// deliberate reductions — untick an item on one device and a stale twin
    /// re-ticked it — and could manufacture rank/completion combinations no
    /// one ever set. A loser's value fills in only where the winner has no
    /// claim at all (a never-set rank or count), a reveal survives from
    /// either side (revealing has no undo, so it can't contradict anything),
    /// and a note is never dropped: when both rows carry different notes the
    /// loser's is appended, so the user resolves the conflict instead of the
    /// code silently picking one.
    private func mergeDuplicateStates(in pt: Playthrough, at date: Date = .now) -> Int {
        let live = (pt.trackerStates ?? []).filter { $0.deletedAt == nil }
        let groups = Dictionary(grouping: live, by: \.itemID).filter { $0.value.count > 1 }
        guard !groups.isEmpty else { return 0 }
        var merged = 0
        for (_, records) in groups {
            let winner = records.max {
                ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString)
            }!
            for loser in records where loser !== winner {
                if winner.rank == nil { winner.rank = loser.rank }
                if winner.count == nil { winner.count = loser.count }
                winner.revealed = winner.revealed || loser.revealed
                let winnerNote = winner.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let loserNote = loser.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !loserNote.isEmpty, winnerNote.isEmpty {
                    winner.notes = loser.notes
                } else if !loserNote.isEmpty, winnerNote != loserNote {
                    winner.notes = winnerNote + "\n" + loserNote
                }
                loser.deletedAt = date
                touch(loser, at: date)
                merged += 1
            }
            touch(winner)
            touch(pt)
        }
        return merged
    }

    /// More than one unstopped session means two devices were both timing.
    /// The survivor is the session the user ACTED on last — started, paused,
    /// or resumed, with the id as a total tie-break — not the one with the
    /// newest original start date. Keying on `startDate` stopped the wrong
    /// session for exactly the case that matters: an old session deliberately
    /// resumed at 17:00 is a later user action than a fresh one started at
    /// 16:00, yet lost to it and was silently stopped while the user watched
    /// its timer run.
    ///
    /// Losers are closed, never deleted — their recorded time is user data.
    /// A running loser is credited only up to the moment the survivor's
    /// current segment began; past that point the same wall-clock minutes are
    /// already being counted by the survivor, and summing both is exactly the
    /// double-counted playtime this exists to prevent. A paused loser keeps
    /// its banked time unchanged and closes at its own pause time, not an
    /// invented one.
    private func closeDuplicateSessions(in pt: Playthrough, at date: Date = .now) -> Int {
        let open = liveUnstoppedSessions(of: pt)
        guard open.count > 1 else { return 0 }
        let winner = open.max {
            ($0.lastUserAction, $0.id.uuidString) < ($1.lastUserAction, $1.id.uuidString)
        }!
        // When the survivor's current segment started counting (or, if it is
        // paused, the last moment it was known to be counting) — clamped to
        // now, so a survivor whose anchor sits in this device's future (clock
        // skew) can't credit a loser for time that hasn't happened yet.
        let winnerAnchor = min(date, winner.state == .running
            ? (winner.resumedAt ?? winner.startDate)
            : (winner.pausedAt ?? winner.startDate))
        var closed = 0
        for older in open where older !== winner {
            if older.state == .running {
                // Clamp to the loser's own running anchor so a survivor whose
                // segment began earlier can never produce a negative segment.
                let cut = max(older.resumedAt ?? older.startDate, winnerAnchor)
                older.accumulatedDuration = older.elapsed(asOf: cut)
                older.endDate = cut
            } else {
                older.endDate = older.pausedAt ?? older.startDate
            }
            older.pausedAt = nil
            older.resumedAt = nil
            older.state = .stopped
            touch(older)
            NotificationManager.cancelStaleReminder(sessionID: older.id)
            closed += 1
        }
        touch(pt)
        return closed
    }

}

// MARK: - Derived helpers

extension Game {
    /// Digest of every field Game Detail edits through SwiftUI bindings —
    /// rating, ownership, notes, review, and the metadata edit form. Captured
    /// when the page appears and compared when it leaves, so the stamp
    /// decision is about THIS game's edited fields — not about whatever else
    /// the context has pending, and not about whether autosave already
    /// committed the keystrokes. (Fields edited through `repo.edit`, like
    /// tags and status, stamp themselves and are deliberately absent.)
    var bindingEditFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(rating)
        hasher.combine(ownership)
        hasher.combine(notes)
        hasher.combine(review)
        hasher.combine(firstReleaseDate)
        hasher.combine(franchise)
        hasher.combine(developers)
        hasher.combine(publishers)
        hasher.combine(platforms)
        hasher.combine(genres)
        hasher.combine(themes)
        hasher.combine(gameModes)
        hasher.combine(playerPerspectives)
        return hasher.finalize()
    }

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
