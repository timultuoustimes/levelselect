import Foundation
import SwiftData

/// A playthrough (legacy `saves[]`). CloudKit-compatible.
@Model
final class Playthrough {
    var id: UUID = UUID()
    var userID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var revision: Int = 0
    var deletedAt: Date?
    var legacyID: String?

    var name: String = "Playthrough"
    var notes: String?
    var progressPercent: Double = 0
    var startedAt: Date?
    /// How this run ended, when it did — see `PlaythroughOutcome`. Nil means
    /// it's still going, which is what most runs are.
    ///
    /// Distinct from the game's status: a game can be Playing because a second
    /// save is alive while the first was abandoned twenty hours in. Only the
    /// run knows that, and until now nothing recorded it.
    var outcomeRaw: String?
    /// Why it ended that way, in your words. The whole point of recording a
    /// dropped run is the sentence explaining it — "combat never clicked",
    /// "lost the save" — which a status alone can't carry.
    var outcomeNote: String?
    var lastPlayedAt: Date?

    var game: Game?

    /// Beaten and no longer the run you're actively working: true when a
    /// live completion event points here. Derived, so deleting the event
    /// un-finishes the run with no cleanup and no flags to reconcile.
    /// How this run ended, if it has.
    var outcome: PlaythroughOutcome? {
        get { outcomeRaw.flatMap(PlaythroughOutcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    var isFinished: Bool {
        (completionEvents ?? []).contains { $0.deletedAt == nil }
    }

    @Relationship(deleteRule: .cascade, inverse: \Session.playthrough)
    var sessions: [Session]?
    @Relationship(deleteRule: .cascade, inverse: \TrackerStateRecord.playthrough)
    var trackerStates: [TrackerStateRecord]?
    @Relationship(deleteRule: .cascade, inverse: \Run.playthrough)
    var runs: [Run]?
    /// Nullify, not cascade: deleting a playthrough must not erase the fact
    /// you beat the game — the event survives, pointed at the game alone.
    @Relationship(deleteRule: .nullify, inverse: \CompletionEvent.playthrough)
    var completionEvents: [CompletionEvent]?

    /// Active session = the running session, or a paused one when nothing is
    /// running (no separate stored flag).
    ///
    /// When sync leaves more than one running session, the winner is the one
    /// the user ACTED on last (started or resumed — not the newest original
    /// start date, which loses to a deliberately resumed old session), with
    /// the id as a total tie-break. The total order matters:
    /// with timestamps alone, equal stamps let each device resolve a
    /// different winner from its own relationship order, and cross-device
    /// repair passes then need not converge. Running takes priority over paused
    /// because paused records are now deliberately preserved when a new timer
    /// starts: they accrue nothing, while hiding the running record would keep
    /// real time accruing behind a paused UI.
    var activeSession: Session? {
        let live = (sessions ?? [])
            .filter { $0.state != .stopped && $0.deletedAt == nil }
        let candidates = live.contains { $0.state == .running }
            ? live.filter { $0.state == .running }
            : live
        return candidates.max {
            ($0.lastUserAction, $0.id.uuidString) < ($1.lastUserAction, $1.id.uuidString)
        }
    }

    init(
        id: UUID = UUID(),
        name: String = "Playthrough",
        progressPercent: Double = 0,
        startedAt: Date? = .now
    ) {
        self.id = id
        self.createdAt = .now
        self.updatedAt = .now
        self.name = name
        self.progressPercent = progressPercent
        self.startedAt = startedAt
    }
}
