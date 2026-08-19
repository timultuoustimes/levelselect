import Foundation
import SwiftData
import os

/// The mutation layer over SwiftData. Every write bumps sync metadata
/// (`updatedAt`/`revision`) for UI + ordering. Cross-device sync is handled by
/// CloudKit automatically — there is no outbox to maintain. Views read via
/// `@Query`; all writes go through here.
@MainActor
struct Repository {
    static let log = Logger(subsystem: "com.timultuoustimes.levelselect", category: "repository")

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
        // Stop every RUNNING session of the GAME, not just this playthrough's.
        // One game is one activity — two of its playthroughs can't be played
        // at once. The two-device test caught the per-playthrough version:
        // after a sync race the open twin can sit on a DIFFERENT playthrough
        // (each device minted its own default earlier), and stopping only
        // this playthrough's left the other timer silently accruing forever.
        //
        // Deliberately leave paused sessions alone. A real two-device run
        // proved that auto-stopping a synced pause while its origin device
        // resumes it offline makes both devices write the same Session record
        // divergently. CloudKit then detached that record from its playthrough,
        // hiding irreplaceable playtime from every game total. A grace period
        // would only postpone the same race; paused sessions accrue nothing,
        // so preserving them is the safe ambiguity-preserving rule.
        let unstopped = pt.game.map { $0.livePlaythroughs.flatMap { liveUnstoppedSessions(of: $0) } }
            ?? liveUnstoppedSessions(of: pt)
        let thisDevice = DeviceIdentity.name
        let policy = overlappingTimerPolicy
        for active in unstopped where active.state == .running {
            // THIS device's own timer is replaced without ceremony — nobody
            // means to run two timers on one device, and there is nothing
            // ambiguous to ask about. (A session with no recorded origin
            // predates Schema V2; treated as ours, which keeps the old
            // behaviour for legacy records rather than prompting about a
            // device we can't name.)
            let isOurs = (active.originDevice ?? thisDevice) == thisDevice
            if isOurs || policy == .keepNewest {
                stopSession(active, at: date)
            }
            // Another device's running timer under `.ask` is left alone on
            // purpose: starting here creates a visible overlap, and
            // OverlappingTimerGuard asks which one to keep. That covers the
            // watch, the widget and Live Activity intents too — none of which
            // can put a question on screen themselves.
        }
        let session = Session(startDate: date, state: .running)
        // Stamped once, here, because sessions are also started from the
        // watch, the widget and Live Activity intents — a view is the wrong
        // place for an invariant every entry point needs.
        session.originDevice = DeviceIdentity.name
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
        attachIfDetached(session, to: pt)
        return session
    }

    /// A session must never exist without its playthrough.
    ///
    /// Sessions have been appearing with a nil playthrough on the device that
    /// created them — invisible in the game, absent from totals and export,
    /// their time accruing into nothing. The mechanism is not yet understood,
    /// so this is a guard rather than a fix: it checks the relationship
    /// AFTER the save that should have written it, repairs it if it is
    /// missing, and records that it had to, so the next occurrence leaves
    /// evidence instead of just damage. If it never fires on device, the
    /// detachment happens later than the save and the hunt moves to the
    /// import side.
    private func attachIfDetached(_ session: Session, to pt: Playthrough) {
        // Written down at creation, while the answer is still known for
        // certain — this is what makes a later repair a record rather than a
        // guess.
        SessionParentLedger.record(sessionID: session.id, playthroughID: pt.id)
        guard session.playthrough == nil else { return }
        session.playthrough = pt
        persist()
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: "detachedSessionRepairs") + 1,
                     forKey: "detachedSessionRepairs")
        defaults.set(Date.now, forKey: "detachedSessionRepairAt")
        Self.log.error("Session \(session.id.uuidString, privacy: .public) saved with no playthrough; reattached.")
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
        // returns its accumulated total unchanged — and its anchor is the
        // PAUSE, not the original start: the pause proves activity until that
        // moment, so the recorded stop (and "last played") may never predate
        // it. Anchoring a paused session at startDate let the sheet's default
        // write a stop timestamp hours before the user actually stopped.
        let anchor = session.state == .running
            ? (session.resumedAt ?? session.startDate)
            : (session.pausedAt ?? session.startDate)
        // Clamp both ways: never earlier than the anchor (activity is proven
        // until then), never in the future (a synced anchor can be ahead of
        // this device's clock, and history must not record a stop that
        // hasn't happened).
        let clamped = min(.now, max(anchor, stop))
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
        session.originDevice = DeviceIdentity.name
        session.accumulatedDuration = duration
        session.endDate = date.addingTimeInterval(duration)
        session.notes = notes
        context.insert(session)
        session.playthrough = pt
        pt.lastPlayedAt = date
        touch(pt, at: date)
        persist()
        attachIfDetached(session, to: pt)
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
        TrackerStateRecord.winner(of: (pt.trackerStates ?? [])
            .filter { $0.itemID == itemID && $0.deletedAt == nil })
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

    /// Set how many of a counted thing you have — 37 of 900 koroks.
    ///
    /// Completion is derived, exactly as it is for ranks: reaching the target
    /// ticks the item, dropping below it unticks it. That keeps one rule for
    /// "done" across checkboxes, ranks and counts instead of three.
    func setTrackerCount(_ pt: Playthrough, itemID: String, count: Int, target: Int?) {
        let record = ensureTrackerState(pt, itemID: itemID)
        let clamped = max(0, target.map { min(count, $0) } ?? count)
        record.count = clamped
        if let target, target > 0 { record.completed = clamped >= target }
        touch(record)
        touch(pt)
        recomputeProgress(pt)
        persist()
    }

    /// Turn an item into a counter, or back into a checkbox (`nil`/0).
    @discardableResult
    func setTrackerCountTarget(_ game: Game, categoryID: String, itemID: String,
                               target: Int?) -> Bool {
        guard let schema = game.trackerSchema,
              let data = TrackerSchemaJSON.editingItem(
                categoryID: categoryID, itemID: itemID,
                countTarget: target ?? 0, in: schema.jsonData)
        else { return false }
        schema.jsonData = data
        touch(schema)
        touch(game)
        recomputeProgress(game)
        persist()
        return true
    }

    /// Choose which form of a two-form item this playthrough is running —
    /// Hades' Mirror of Night talents, a route choice, a loadout slot.
    ///
    /// Per playthrough rather than per game, because that is what it is: a
    /// configuration of THIS run. Starting a new run and finding the last
    /// one's choices already made would be wrong.
    func setTrackerVariant(_ pt: Playthrough, itemID: String, variant: String?) {
        let record = ensureTrackerState(pt, itemID: itemID)
        record.selectedVariant = variant
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
            // A new goal changes every playthrough's denominator — round 3
            // caught this path saving without recomputing, so a 1/1 tracker
            // stayed cached at 100% after becoming 1/2.
            recomputeAllPlaythroughs(of: game)
            persist()
        }
    }

    /// Add a planned, empty category — the unit stepped generation works in.
    ///
    /// Useful on its own before any of that exists: sketching "Bosses,
    /// Charms, Grubs" by hand and filling them one at a time is a better way
    /// to build a tracker than asking for everything and pruning, and it is
    /// the same structure a generated plan will write.
    @discardableResult
    func addPlannedCategory(to game: Game, named name: String,
                            plannedCount: Int? = nil, counted: Bool = false) -> Bool {
        let schema: TrackerSchemaRecord
        if let existing = game.trackerSchema {
            schema = existing
        } else {
            schema = TrackerSchemaRecord(
                source: .builtIn, engine: .objective,
                jsonData: TrackerSchemaJSON.emptySchema())
            context.insert(schema)
            schema.game = game
        }
        // Two categories called "Bosses" is never what anyone meant, and the
        // pair is genuinely hard to untangle afterwards — both look identical
        // in the list and only one of them is the one you generated into.
        // Refused at the point of typing instead. (Name is identity for a
        // *typed* category only; the merge engine still folds by id alone,
        // because a generator reusing a name is not a claim of sameness.)
        let key = TrackerMerge.matchKey(name)
        guard !TrackerSchemaJSON.categories(from: schema.jsonData)
            .contains(where: { TrackerMerge.matchKey($0.name) == key })
        else { return false }
        guard let updated = TrackerSchemaJSON.addingCategory(
            named: name, plannedCount: plannedCount, counted: counted, to: schema.jsonData)
        else { return false }
        schema.jsonData = updated
        touch(schema)
        touch(game)
        persist()
        return true
    }

    /// Drop a planned category that was never filled.
    ///
    /// Only ever a PENDING one: an empty planned heading is scaffolding, but
    /// a category with content is the user's, and removing that belongs to
    /// the merge review rather than a stray tap.
    @discardableResult
    func removePlannedCategory(from game: Game, categoryID: String) -> Bool {
        guard let schema = game.trackerSchema,
              let root = (try? JSONSerialization.jsonObject(with: schema.jsonData)) as? [String: Any],
              var cats = root["categories"] as? [[String: Any]],
              let idx = cats.firstIndex(where: { ($0["id"] as? String) == categoryID }),
              (cats[idx]["pending"] as? Bool) == true,
              ((cats[idx]["items"] as? [[String: Any]]) ?? []).isEmpty
        else { return false }
        cats.remove(at: idx)
        var next = root
        next["categories"] = cats
        guard let data = try? JSONSerialization.data(withJSONObject: next) else { return false }
        schema.jsonData = data
        touch(schema)
        touch(game)
        persist()
        return true
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
        guard let schema = game.trackerSchema else { return false }
        // Read the name it had BEFORE the blob is rewritten — editingItem
        // renames in place, so capturing afterwards would anchor `sourceName`
        // to the new name and break the merge engine's ability to match this
        // item against a future generation.
        let priorName = schemaItemName(game, itemID: itemID)
        guard let data = TrackerSchemaJSON.editingItem(
                categoryID: categoryID, itemID: itemID,
                name: name, location: location, note: note, in: schema.jsonData)
        else { return false }
        schema.jsonData = data
        // Written to BOTH the blob and the per-item record, deliberately.
        //
        // The record is what makes two devices' notes survive each other — it
        // syncs on its own, so editing item A here and item B there merges
        // instead of one whole blob winning. The blob copy stays because a
        // build that predates Schema V2 can only read notes from there, and
        // silently blanking a tester's notes to win an architecture argument
        // is not a trade worth making. Reads prefer the record, so a stale
        // blob copy is harmless; when every client is V2 this write can stop.
        writeItemDetail(game, itemID: itemID, name: name, note: note, priorName: priorName)
        touch(schema)
        touch(game)
        persist()
        return true
    }

    // MARK: Tracker item detail (user-authored content, Schema V2)

    /// The record holding this game's user-authored content for one item.
    func trackerItemDetail(_ game: Game, itemID: String) -> TrackerItemDetail? {
        // Newest wins under the same total order as every other duplicate
        // read, so a sync race resolves identically everywhere.
        (game.trackerItemDetails ?? [])
            .filter { $0.itemID == itemID && $0.deletedAt == nil }
            .max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    /// Create-or-update the record for one item. `nil` leaves a field alone;
    /// an empty string clears it — same contract as `editingItem`.
    private func writeItemDetail(_ game: Game, itemID: String,
                                 name: String?, note: String?,
                                 priorName: String? = nil) {
        let existing = trackerItemDetail(game, itemID: itemID)
        let detail: TrackerItemDetail
        if let existing {
            detail = existing
        } else {
            detail = TrackerItemDetail(itemID: itemID)
            context.insert(detail)
            detail.game = game
        }
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespaces)
            detail.note = trimmed.isEmpty ? nil : trimmed
        }
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed != detail.chosenName {
                // Keep the name it arrived with, so the merge engine can still
                // match this item after a rename.
                if detail.sourceName == nil {
                    detail.sourceName = priorName ?? schemaItemName(game, itemID: itemID)
                }
                detail.chosenName = trimmed
            }
        }
        touch(detail)
    }

    private func schemaItemName(_ game: Game, itemID: String) -> String? {
        guard let schema = game.trackerSchema else { return nil }
        return TrackerSchemaJSON.categories(from: schema.jsonData)
            .flatMap(\.items)
            .first { $0.id == itemID }?
            .name
    }

    /// Parsed categories with the user's own content overlaid from records.
    ///
    /// One read path for every surface that shows tracker content, so a note
    /// that lives in a record and a note that still lives only in the blob
    /// look identical to the UI. The record wins where both exist: it is the
    /// one that merges per item, so it is the one that can be trusted after
    /// two devices have both been edited.
    func trackerCategories(for game: Game) -> [TrackerCategoryDTO] {
        guard let schema = game.trackerSchema else { return [] }
        let parsed = TrackerSchemaJSON.categories(from: schema.jsonData)
        let details = (game.trackerItemDetails ?? []).filter { $0.deletedAt == nil }
        guard !details.isEmpty else { return parsed }

        var byItem: [String: TrackerItemDetail] = [:]
        for detail in details {
            if let held = byItem[detail.itemID],
               (held.updatedAt, held.id.uuidString) >= (detail.updatedAt, detail.id.uuidString) {
                continue
            }
            byItem[detail.itemID] = detail
        }

        return parsed.map { category in
            var next = category
            next.items = category.items.map { item in
                guard let detail = byItem[item.id] else { return item }
                var merged = item
                if let note = detail.note, !note.isEmpty { merged.note = note }
                if let chosen = detail.chosenName, !chosen.isEmpty {
                    merged.name = chosen
                    merged.sourceName = detail.sourceName ?? item.sourceName
                }
                return merged
            }
            return next
        }
    }

    /// Copy user-authored content out of the schema blob into per-item
    /// records, once, idempotently.
    ///
    /// Runs on game open rather than as a Core Data migration stage: a custom
    /// stage on a CloudKit-backed store is a far worse place to discover a
    /// mistake than a repository pass that can be re-run, skipped, and tested.
    /// Only fills gaps — a record that already exists is left exactly as it
    /// is, because it may hold a newer edit than the blob it came from.
    @discardableResult
    func liftTrackerItemDetails(for game: Game) -> Int {
        guard let schema = game.trackerSchema else { return 0 }
        let parsed = TrackerSchemaJSON.categories(from: schema.jsonData)
        guard !parsed.isEmpty else { return 0 }
        var lifted = 0
        for item in parsed.flatMap(\.items) {
            let hasNote = !(item.note ?? "").isEmpty
            let hasRename = !(item.sourceName ?? "").isEmpty
            guard hasNote || hasRename else { continue }
            if trackerItemDetail(game, itemID: item.id) != nil { continue }
            let detail = TrackerItemDetail(
                itemID: item.id,
                note: hasNote ? item.note : nil,
                chosenName: hasRename ? item.name : nil,
                sourceName: hasRename ? item.sourceName : nil)
            context.insert(detail)
            detail.game = game
            lifted += 1
        }
        if lifted > 0 { persist() }
        return lifted
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

        var outcome: TrackerMergeOutcome
        if case .replaceCategories(let ids) = mode {
            // Summarise only what this step changed — a stepped run does one
            // category at a time, and "removed 240 items" about categories it
            // never looked at would be alarming and false.
            let scoped = diff.categories.filter { ids.contains($0.id) }
            outcome = TrackerMergeOutcome(
                added: scoped.flatMap(\.added).count,
                removed: scoped.flatMap(\.removed).count,
                renamed: scoped.flatMap(\.renamed).count)
        } else {
            outcome = TrackerMergeOutcome(
                added: diff.added.count, removed: diff.removed.count, renamed: diff.renamed.count)
        }

        // Only the replacing modes adopt incoming ids, so only they need the
        // migration — the additive modes leave existing items exactly where
        // they are, which is why they can't lose progress at all.
        //
        // A CATEGORY-scoped replace migrates and reports only within the
        // categories it actually touched. Counting a rename in an untouched
        // category would claim work that never happened, and listing its
        // items as lost would offer to rescue things that are still sitting
        // there.
        let replacingScope: Set<String>?
        switch mode {
        case .replace: replacingScope = nil                       // everything
        case .replaceCategories(let ids): replacingScope = ids
        case .addAll, .add: replacingScope = Set()                 // nothing
        }
        if replacingScope == nil || !(replacingScope?.isEmpty ?? true) {
            let scoped = diff.categories.filter { category in
                guard let replacingScope else { return true }
                return replacingScope.contains(category.id)
            }
            // Grouped, not a dictionary keyed by item id: the same item has a
            // SEPARATE state record in each playthrough, so keeping only the
            // first would migrate one and strand the rest.
            let byID = Dictionary(grouping: states, by: \.itemID)
            for match in scoped.flatMap(\.renamed) where match.current.id != match.incoming.id {
                for record in byID[match.current.id] ?? [] {
                    record.itemID = match.incoming.id
                    touch(record)
                    outcome.migrated += 1
                }
            }
            outcome.lostProgress = scoped.flatMap(\.removed).filter { progressIDs.contains($0.id) }
        }

        // A category that now has content is no longer a plan.
        var filledSchema = merged
        if case .replaceCategories(let ids) = mode {
            for id in ids {
                let hasContent = TrackerSchemaJSON.categories(from: filledSchema)
                    .first { $0.id == id }?.items.isEmpty == false
                if hasContent,
                   let cleared = TrackerSchemaJSON.markingFilled(categoryID: id, in: filledSchema) {
                    filledSchema = cleared
                }
            }
        }
        existing.jsonData = filledSchema
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
        // Same sanitizer as every other schema ingress.
        let schemaData = TrackerMerge.deduplicated(builtin.schemaData)
        let schema: TrackerSchemaRecord
        if let existing = game.trackerSchema {
            schema = existing
            schema.jsonData = TrackerSchemaJSON.mergingPersonalGoals(
                from: existing.jsonData, into: schemaData)
        } else {
            schema = TrackerSchemaRecord(source: .builtIn, engine: builtin.engine, jsonData: schemaData)
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
        recomputeAllPlaythroughs(of: game)
        persist()
    }

    private func recomputeAllPlaythroughs(of game: Game) {
        for pt in game.livePlaythroughs { recompute(pt, allItems: trackerItems(of: game)) }
    }

    /// Recompute the cache of the playthrough that CHANGED — the setters take
    /// an explicit playthrough, and recomputing `game.activePlaythrough`
    /// instead meant a write to a non-active playthrough updated its row but
    /// refreshed a different playthrough's percentage.
    private func recomputeProgress(_ pt: Playthrough) {
        guard let game = pt.game else { return }
        recompute(pt, allItems: trackerItems(of: game))
    }

    private func trackerItems(of game: Game) -> [TrackerItemDTO] {
        trackerCategories(for: game).flatMap(\.items)
    }

    private func recompute(_ pt: Playthrough, allItems: [TrackerItemDTO]) {
        // Winner rule, not "any twin completed": OR-ing across duplicates let
        // a stale completed twin keep the ring full after the user's latest
        // action was an untick.
        //
        // An EMPTY (or removed) schema recomputes to zero rather than being
        // skipped — the old early-return left whatever percentage was cached
        // before, so replacing a completed tracker with an empty one kept
        // every ring full forever.
        let percent: Double
        if allItems.isEmpty {
            percent = 0
        } else {
            let byItem = Dictionary(grouping: (pt.trackerStates ?? [])
                .filter { $0.deletedAt == nil }, by: \.itemID)
            let done = allItems.filter {
                byItem[$0.id].flatMap(TrackerStateRecord.winner)?.completed == true
            }.count
            percent = Double(done) / Double(allItems.count) * 100
        }
        guard pt.progressPercent != percent else { return }
        pt.progressPercent = percent
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
        }
        outcome.closedSessions = reconcileSessions(in: game, at: date)
        if outcome.mergedStates > 0 { recomputeProgress(game) }
        if !outcome.isNoOp { persist() }
        return outcome
    }

    /// Sessions currently unstopped anywhere in the live library. One small
    /// indexed fetch — the set is bounded by how many timers are actually
    /// running, not by library size.
    func unstoppedSessions() -> [Session] {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.endDate == nil && $0.deletedAt == nil })
        return ((try? context.fetch(descriptor)) ?? []).filter {
            $0.state != .stopped
                && $0.playthrough?.deletedAt == nil
                && $0.playthrough?.game?.deletedAt == nil
        }
    }

    /// Reattach detached sessions this device created, using the note it took
    /// at the time.
    ///
    /// Runs wherever repair already runs, because that is when the damage
    /// appears. Only ever acts on a recorded fact: a session whose parent
    /// this device wrote down at creation, whose playthrough still exists and
    /// is live. Anything else is left for the user to place by hand.
    @discardableResult
    func repairDetachedSessionsFromLedger() -> Int {
        let orphans = orphanedSessions()
        guard !orphans.isEmpty else { return 0 }
        var repaired = 0
        for session in orphans {
            guard let ptID = SessionParentLedger.playthroughID(for: session.id) else { continue }
            let descriptor = FetchDescriptor<Playthrough>(
                predicate: #Predicate { $0.id == ptID && $0.deletedAt == nil })
            guard let pt = try? context.fetch(descriptor).first else { continue }
            session.playthrough = pt
            touch(session)
            repaired += 1
            Self.log.notice("Reattached detached session \(session.id.uuidString, privacy: .public) from ledger.")
        }
        if repaired > 0 {
            let defaults = UserDefaults.standard
            defaults.set(defaults.integer(forKey: "detachedSessionRepairs") + repaired,
                         forKey: "detachedSessionRepairs")
            defaults.set(Date.now, forKey: "detachedSessionRepairAt")
            persist()
        }
        return repaired
    }

    /// Sessions whose CloudKit relationship was lost. Their playtime is real
    /// user data, but there is no supported, trustworthy way to infer which
    /// playthrough owned it. Preserve and surface them; never adopt, delete, or
    /// tombstone them by guesswork.
    func orphanedSessions() -> [Session] {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.playthrough == nil && $0.deletedAt == nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Foreground sweep, bounded. It walks only the games that currently
    /// have an open timer (found by one small fetch, not a whole-library
    /// relationship walk — round 2's performance flag) and runs the full
    /// per-game reconcile on each: those are exactly the games being played
    /// right now, where doubled clocks corrupt totals and duplicate state
    /// rows are actively being read. Everything else waits for its page to
    /// open or a schema merge. Known blind spot, by construction: a game
    /// whose ONLY open sessions are contradictory merged records (state
    /// running but endDate set — invisible to the endDate==nil fetch) isn't
    /// found here; page-open reconcile normalizes those.
    func reconcileLibrary(at date: Date = .now) {
        repairDetachedSessionsFromLedger()
        var seen = Set<UUID>()
        for session in unstoppedSessions() {
            guard let game = session.playthrough?.game,
                  seen.insert(game.id).inserted else { continue }
            reconcile(game, at: date)
        }
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
            let winner = TrackerStateRecord.winner(of: records)!
            // Losers in TOTAL order too, newest first. Round 3 showed that
            // with three or more rows, "first loser encountered" filled the
            // winner's missing rank/count from whichever row the relationship
            // happened to list first — so two devices folding the same rows
            // could write different surviving content. Every derived value
            // below depends only on the rows, never on iteration order.
            let losers = records.filter { $0 !== winner }
                .sorted { $0.outranks($1) }

            if winner.rank == nil { winner.rank = losers.compactMap(\.rank).first }
            if winner.count == nil { winner.count = losers.compactMap(\.count).first }
            winner.revealed = winner.revealed || losers.contains { $0.revealed }

            // Notes: winner's first, then each loser's in the same total
            // order, skipping any text an earlier part already contains —
            // that containment check is what makes the fold idempotent under
            // partial delivery (the already-merged winner note "A\nB" can
            // arrive before loser B's tombstone; B must not be appended
            // again).
            var noteParts: [String] = []
            for record in [winner] + losers {
                let note = record.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !note.isEmpty, !noteParts.contains(where: { $0.contains(note) })
                else { continue }
                noteParts.append(note)
            }
            if !noteParts.isEmpty { winner.notes = noteParts.joined(separator: "\n") }

            for loser in losers {
                loser.deletedAt = date
                touch(loser, at: date)
                merged += 1
            }
            touch(winner)
            touch(pt)
        }
        return merged
    }

    // MARK: Overlapping timers

    /// The user's answer to "two devices are timing the same game". Read from
    /// the synced settings record, so choosing on one device answers for all
    /// of them.
    var overlappingTimerPolicy: OverlappingTimerPolicy {
        let settings = (try? context.fetch(FetchDescriptor<ThemeSettings>(
            sortBy: [SortDescriptor(\.createdAt)])))?.first
        return OverlappingTimerPolicy(raw: settings?.overlappingTimerPolicyRaw)
    }

    func setOverlappingTimerPolicy(_ policy: OverlappingTimerPolicy) {
        let all = (try? context.fetch(FetchDescriptor<ThemeSettings>(
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        let settings: ThemeSettings
        if let first = all.first {
            settings = first
        } else {
            settings = ThemeSettings()
            context.insert(settings)
        }
        settings.overlappingTimerPolicyRaw = policy.rawValue
        settings.updatedAt = .now
        persist()
    }

    /// Every running session for a game, across all of its playthroughs —
    /// more than one means two devices are timing at once.
    func runningSessions(in game: Game) -> [Session] {
        game.livePlaythroughs
            .flatMap { liveUnstoppedSessions(of: $0) }
            .filter { $0.state == .running }
            .sorted { ($0.lastUserAction, $0.id.uuidString) > ($1.lastUserAction, $1.id.uuidString) }
    }

    /// Resolve an overlap the way the USER asked: keep `keeper`, close every
    /// other running session on the game. Same crediting as the automatic
    /// path — a loser keeps the time it genuinely earned, cut at the moment
    /// the survivor's current segment began, so the overlap isn't counted
    /// twice.
    @discardableResult
    func keepOnlyRunningSession(_ keeper: Session, in game: Game,
                                at date: Date = .now) -> Int {
        // The keeper must still be running. If the conflict was resolved
        // elsewhere first — the other device answered, and this device is
        // acting on a sheet describing a conflict that has already gone —
        // then honouring the choice would stop whichever timer survived
        // instead, leaving the game with none. Do nothing; the surviving
        // state is already an answer.
        guard keeper.state == .running else { return 0 }
        let others = runningSessions(in: game).filter { $0 !== keeper }
        guard !others.isEmpty else { return 0 }
        let anchor = min(date, keeper.resumedAt ?? keeper.startDate)
        for loser in others {
            let cut = min(date, max(loser.resumedAt ?? loser.startDate, anchor))
            loser.accumulatedDuration = loser.elapsed(asOf: cut)
            loser.endDate = cut
            loser.pausedAt = nil
            loser.resumedAt = nil
            loser.state = .stopped
            touch(loser)
            if let pt = loser.playthrough { touch(pt, at: date) }
            NotificationManager.cancelStaleReminder(sessionID: loser.id)
            LiveActivityManager.sessionResolved(loser.id)
        }
        persist()
        return others.count
    }

    /// Give a detached session back to a game, on the USER's say-so.
    ///
    /// The app can't infer where these belong — that was true when they were
    /// first surfaced and it is still true. But the person who played them
    /// usually knows exactly, and refusing to let them say so means the time
    /// stays lost for a reason that is really just the app's ignorance.
    /// Attaches to the game's active playthrough, since that is the one every
    /// per-playthrough surface reads.
    func reattachSession(_ session: Session, to game: Game) {
        let pt = ensureDefaultPlaythrough(for: game)
        session.playthrough = pt
        touch(session)
        if let end = session.endDate, pt.lastPlayedAt.map({ $0 < end }) ?? true {
            pt.lastPlayedAt = end
        }
        touch(pt)
        persist()
    }

    /// Two finished sessions that claim overlapping wall-clock time.
    ///
    /// Detection is deliberately narrow, because acting on it means deleting
    /// recorded playtime and a false positive costs someone real data:
    ///
    /// - both must name a DIFFERENT origin device. Two overlapping sessions
    ///   from one device are ordinary (a hand-logged block covering a period
    ///   you also timed); two devices claiming the same minutes is the shape
    ///   that actually double-counts a library total.
    /// - neither may be hand-logged. `isManual` entries are typed after the
    ///   fact and routinely span a period that a timer also covered — that is
    ///   the user's own bookkeeping, not a conflict.
    /// - the intersection must be more than a minute, so sessions that merely
    ///   touch at their edges are left alone.
    ///
    /// Even then this only ever ASKS. A session's interval says nothing about
    /// its pauses — `accumulatedDuration` is a scalar, so a session paused
    /// through the middle can overlap another without a single minute being
    /// counted twice — which is exactly why the app must not resolve this on
    /// its own.
    struct SessionOverlap: Identifiable {
        let game: Game
        let first: Session
        let second: Session
        /// Stable across launches and devices, so a dismissal sticks.
        var id: String {
            [first.id.uuidString, second.id.uuidString].sorted().joined(separator: "+")
        }
        var seconds: TimeInterval {
            let start = max(first.startDate, second.startDate)
            let end = min(first.endDate ?? first.startDate, second.endDate ?? second.startDate)
            return max(0, end.timeIntervalSince(start))
        }
    }

    /// Overlapping finished sessions across the live library.
    ///
    /// Bounded to sessions that ended in the last 90 days: the work is then
    /// proportional to recent play rather than to a lifetime of history, and
    /// an overlap old enough to fall outside that window is one the user has
    /// long since lived with. Stated rather than silent — an older pair will
    /// not be reported.
    func overlappingFinishedSessions(asOf now: Date = .now,
                                     within: TimeInterval = 90 * 24 * 3600) -> [SessionOverlap] {
        let cutoff = now.addingTimeInterval(-within)
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isManual == false })
        let candidates = ((try? context.fetch(descriptor)) ?? []).filter {
            $0.state == .stopped
                && ($0.endDate ?? $0.startDate) >= cutoff
                && $0.originDevice != nil
                && $0.playthrough?.deletedAt == nil
                && $0.playthrough?.game?.deletedAt == nil
        }

        var found: [SessionOverlap] = []
        for (_, sessions) in Dictionary(grouping: candidates, by: { $0.playthrough?.game?.id }) {
            let ordered = sessions.sorted { $0.startDate < $1.startDate }
            for (index, earlier) in ordered.enumerated() {
                for later in ordered.dropFirst(index + 1) {
                    // Sorted by start, so once a later session begins after
                    // this one ended, no further pair can intersect it.
                    let earlierEnd = earlier.endDate ?? earlier.startDate
                    if later.startDate >= earlierEnd { break }
                    guard earlier.originDevice != later.originDevice,
                          let game = earlier.playthrough?.game
                    else { continue }
                    let overlap = SessionOverlap(game: game, first: earlier, second: later)
                    if overlap.seconds > 60 { found.append(overlap) }
                }
            }
        }
        return found.sorted { $0.seconds > $1.seconds }
    }

    /// Repair a game's sessions in two passes: normalize running records
    /// CloudKit's field-level merge left contradictory, then make sure the
    /// GAME has at most one RUNNING session. Paused sessions are intentionally
    /// preserved: they accrue no time, and an automatic write to one can race
    /// the origin device resuming that same record and lose its relationship.
    ///
    /// GAME-scoped, not per-playthrough — the two-device test caught the
    /// per-playthrough version failing its own scenario: each device's
    /// session can land on a DIFFERENT playthrough of the same game (each
    /// device minted its own default in an earlier race), a per-playthrough
    /// sweep then sees one open session on each side and closes nothing, and
    /// both timers run forever while the game's playtime double-counts. One
    /// game is one activity; two of its playthroughs cannot be played at
    /// once.
    ///
    /// Among RUNNING sessions, the survivor is the one the user ACTED on last
    /// — started or resumed, with the id as a total tie-break — not the one
    /// with the newest original start date: an old session deliberately
    /// resumed at 17:00 is a later user action than a fresh one started at
    /// 16:00. Paused sessions are outside this contest and remain untouched.
    ///
    /// Losers are closed, never deleted — their recorded time is user data.
    /// A running loser's CURRENT segment is credited only up to the moment
    /// the survivor's current segment began; past that point the same
    /// wall-clock minutes are already being counted by the survivor. Honest
    /// limit (round 3): `accumulatedDuration` is a scalar, so overlap already
    /// banked inside BOTH sessions' earlier segments is invisible here and
    /// stays double-counted — removing it would need per-segment history the
    /// model doesn't keep. Every written timestamp is clamped to now: synced
    /// clocks can be ahead of this device, and history must never record a
    /// stop in the future.
    private func reconcileSessions(in game: Game, at date: Date = .now) -> Int {
        var repaired = 0

        // CloudKit merges per FIELD, not per record: one device stops a
        // session (state=stopped, endDate set) while another resumes it
        // (state=running, resumedAt set), and the merged record can carry
        // BOTH a live state and an endDate. That contradictory shape also
        // hides from the foreground sweep's endDate==nil fetch while its
        // timer keeps running. Resolve by the later intent: if the last
        // start/pause/resume is after the recorded stop, the stop lost —
        // clear it; otherwise the stop stands and the record closes properly.
        for pt in game.livePlaythroughs {
            for session in liveUnstoppedSessions(of: pt) {
                // Never automatically write a paused record. Even resolving a
                // contradictory stop here can collide with an offline resume
                // of the same CloudKit record. It is harmless while paused and
                // will be resolved after an explicit resume/stop.
                guard session.state == .running else { continue }
                guard let end = session.endDate else { continue }
                if session.lastUserAction > end {
                    session.endDate = nil
                } else {
                    session.pausedAt = nil
                    session.resumedAt = nil
                    session.state = .stopped
                    NotificationManager.cancelStaleReminder(sessionID: session.id)
                    LiveActivityManager.sessionResolved(session.id)
                }
                touch(session, at: date)
                repaired += 1
            }
        }

        let running = game.livePlaythroughs
            .flatMap { liveUnstoppedSessions(of: $0) }
            .filter { $0.state == .running }
        // Whose decision this is, is now the user's. Under `.ask` the overlap
        // is LEFT INTACT for the prompt to surface — closing it here first is
        // exactly the silent decision this replaced. `.keepNewest` is the old
        // automatic behaviour, still available, now chosen. `.keepBoth` leaves
        // them alone permanently.
        guard running.count > 1, overlappingTimerPolicy == .keepNewest
        else { return repaired }
        let winner = running.max {
            ($0.lastUserAction, $0.id.uuidString) < ($1.lastUserAction, $1.id.uuidString)
        }!
        // When the survivor's current segment started counting — clamped to
        // now, so a future clock can't credit a loser for time that hasn't
        // happened yet.
        let winnerAnchor = min(date, winner.resumedAt ?? winner.startDate)
        for older in running where older !== winner {
            // Below the loser's own running anchor elapsed() clamps to its
            // banked time, so an early cut can't go negative; the min(date, …)
            // keeps a future-dated loser anchor from becoming a future endDate.
            let cut = min(date, max(older.resumedAt ?? older.startDate, winnerAnchor))
            older.accumulatedDuration = older.elapsed(asOf: cut)
            older.endDate = cut
            older.pausedAt = nil
            older.resumedAt = nil
            older.state = .stopped
            touch(older)
            if let loserPT = older.playthrough { touch(loserPT, at: date) }
            NotificationManager.cancelStaleReminder(sessionID: older.id)
            // A Live Activity may be showing this loser's timer — a session
            // closed by repair, not by the user, still has to take its
            // Lock Screen timer down with it.
            LiveActivityManager.sessionResolved(older.id)
            repaired += 1
        }
        return repaired
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

    /// Live (non-deleted) playthroughs, oldest first — with the id as a
    /// total tie-break, because `activePlaythrough` falls back to `.first`:
    /// equal creation timestamps otherwise let two devices resolve different
    /// fallback playthroughs and write sessions into different histories.
    var livePlaythroughs: [Playthrough] {
        (playthroughs ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
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
    /// Live runs, newest first — id as a total tie-break so `activeRun`
    /// (which takes the first in-progress row) resolves the same run on
    /// every device even at equal start timestamps.
    var liveRuns: [Run] {
        (runs ?? [])
            .filter { $0.deletedAt == nil }
            .sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
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
