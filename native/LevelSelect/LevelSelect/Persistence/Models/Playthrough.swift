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
    /// **On a playthrough carrying imported hours, the year those hours
    /// belong to** — see `Repository.setCarriedOverYear`. Written as the
    /// first instant of a year and only ever read back as a year, because a
    /// day is exactly what nobody knows about time a storefront reported as
    /// one lifetime total.
    var startedAt: Date?

    /// The year `startedAt` names, when it is standing in for one.
    func carriedOverYear(_ calendar: Calendar = .current) -> Int? {
        guard carriedOverSeconds > 0, let startedAt else { return nil }
        return calendar.component(.year, from: startedAt)
    }

    /// **Which years the imported hours belong to** — see `CarriedOverSpan`.
    ///
    /// Schema V8. Attribution only: `carriedOverSeconds` remains the total,
    /// so every existing reading of it is correct whether this is set or not.
    var carriedOverSpansData: Data?

    var carriedOverSpans: [CarriedOverSpan] {
        get {
            let stored = [CarriedOverSpan].decoded(carriedOverSpansData)
            guard stored.isEmpty else { return stored }
            // A playthrough tagged with the single year that shipped first
            // reads as one span, so the two never disagree and nothing has to
            // be migrated.
            guard let year = carriedOverYear() else { return [] }
            return [CarriedOverSpan(seconds: carriedOverSeconds, fromYear: year)]
        }
        set { carriedOverSpansData = newValue.encoded }
    }

    /// Hours not placed in any year — the remainder the person hasn't said
    /// anything about. Never negative, however the spans are edited.
    var unattributedCarriedSeconds: TimeInterval {
        max(0, carriedOverSeconds - carriedOverSpans.totalSeconds)
    }
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

    /// Time played before this app was tracking it. **Build 37.**
    ///
    /// Steam says 42 hours; a Switch profile says 9. That number is real and
    /// there is no session history behind it, so the only honest way to keep
    /// it was one enormous manual session dated the day you typed it — which
    /// is what the CSV importer does today, and what its own comment calls
    /// "without inventing a fake play history". It still lands in the Journal
    /// as a play that never happened on that day.
    ///
    /// So this is a number, not an event: it adds to every total and appears
    /// in no history. Tim: *"being able to put that in, and then add your
    /// sessions after that to the number as you continue to play."*
    ///
    /// Non-optional with a zero default, like `accumulatedDuration` — an
    /// additive field a CloudKit record simply does not carry yet reads as
    /// zero, which is the right answer for every library that has never set
    /// it.
    var carriedOverSeconds: TimeInterval = 0

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
