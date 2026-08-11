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

    // MARK: Games

    @discardableResult
    func addGame(name: String, status: GameStatus = .backlog) -> Game {
        let game = Game(name: name, status: status)
        context.insert(game)
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
        return game
    }

    /// Soft delete — sets a tombstone so trash/undo is possible and the deletion
    /// propagates via CloudKit.
    func softDelete(_ game: Game, at date: Date = .now) {
        game.deletedAt = date
        touch(game, at: date)
    }

    // MARK: Playthroughs

    /// Returns the game's active playthrough, creating a default one on first use.
    @discardableResult
    func ensureDefaultPlaythrough(for game: Game) -> Playthrough {
        if let existing = (game.playthroughs ?? []).first(where: { $0.deletedAt == nil }) {
            return existing
        }
        let pt = Playthrough()
        context.insert(pt)
        pt.game = game                 // set to-one; SwiftData maintains the inverse
        game.currentPlaythroughID = pt.id
        touch(game)
        return pt
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
        return session
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
        return event
    }
}

// MARK: - Derived helpers

extension Playthrough {
    /// Total time across all sessions (active session counted live via `asOf`;
    /// discarded/tombstoned sessions excluded).
    func totalPlaytime(asOf now: Date = .now) -> TimeInterval {
        (sessions ?? [])
            .filter { $0.deletedAt == nil }
            .reduce(0) { $0 + $1.elapsed(asOf: now) }
    }
}
