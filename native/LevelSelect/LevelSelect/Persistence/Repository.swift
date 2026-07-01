import Foundation
import SwiftData

/// The mutation layer over SwiftData. Every write bumps sync metadata and
/// enqueues an outbox op, so the (future) sync engine has a complete change
/// log. Views read via `@Query`; all writes go through here.
@MainActor
struct Repository {
    let context: ModelContext

    init(_ context: ModelContext) { self.context = context }

    // MARK: Sync bookkeeping

    private func touch<T: Syncable>(_ model: T, at date: Date = .now) {
        model.updatedAt = date
        model.revision += 1
    }

    private func enqueue(_ entityType: String, _ id: UUID, _ op: SyncOpType) {
        context.insert(SyncOperation(entityType: entityType, entityID: id, opType: op))
    }

    // MARK: Games

    @discardableResult
    func addGame(name: String, status: GameStatus = .backlog) -> Game {
        let game = Game(name: name, status: status)
        context.insert(game)
        enqueue("Game", game.id, .upsert)
        return game
    }

    /// Soft delete — sets a tombstone so the deletion can propagate.
    func softDelete(_ game: Game, at date: Date = .now) {
        game.deletedAt = date
        touch(game, at: date)
        enqueue("Game", game.id, .delete)
    }

    // MARK: Playthroughs

    /// Returns the game's active playthrough, creating a default one on first use.
    @discardableResult
    func ensureDefaultPlaythrough(for game: Game) -> Playthrough {
        if let existing = game.playthroughs.first(where: { $0.deletedAt == nil }) {
            return existing
        }
        let pt = Playthrough()
        context.insert(pt)
        game.playthroughs.append(pt)   // sets inverse
        game.currentPlaythroughID = pt.id
        touch(game)
        enqueue("Playthrough", pt.id, .upsert)
        return pt
    }

    // MARK: Sessions (timer is derived from timestamps — no ticking writes)

    @discardableResult
    func startSession(on pt: Playthrough, at date: Date = .now) -> Session {
        if let active = pt.activeSession { stopSession(active, at: date) }
        let session = Session(startDate: date, state: .running)
        context.insert(session)
        pt.sessions.append(session)
        pt.lastPlayedAt = date
        touch(pt, at: date)
        enqueue("Session", session.id, .upsert)
        return session
    }

    func pauseSession(_ session: Session, at date: Date = .now) {
        guard session.state == .running else { return }
        session.accumulatedDuration = session.elapsed(asOf: date)
        session.pausedAt = date
        session.resumedAt = nil
        session.state = .paused
        touch(session, at: date)
        enqueue("Session", session.id, .upsert)
    }

    func resumeSession(_ session: Session, at date: Date = .now) {
        guard session.state == .paused else { return }
        session.resumedAt = date
        session.pausedAt = nil
        session.state = .running
        touch(session, at: date)
        enqueue("Session", session.id, .upsert)
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
        enqueue("Session", session.id, .upsert)
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
        pt.sessions.append(session)
        pt.lastPlayedAt = date
        touch(pt, at: date)
        enqueue("Session", session.id, .upsert)
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
        game.completionEvents.append(event)
        if label == .completed, game.status != .completed {
            game.status = .completed
        }
        touch(game, at: date)
        enqueue("CompletionEvent", event.id, .upsert)
        return event
    }
}

// MARK: - Derived helpers

extension Playthrough {
    /// Total time across all sessions (accumulated; active session counted live via `asOf`).
    func totalPlaytime(asOf now: Date = .now) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.elapsed(asOf: now) }
    }
}
