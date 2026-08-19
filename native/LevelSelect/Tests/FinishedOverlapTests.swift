import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The retrospective half of the overlapping-timer work: two FINISHED
/// sessions that claim the same wall-clock minutes, which means a library
/// total counts that time twice.
///
/// Most of these tests are about what must NOT be reported. Acting on this
/// prompt deletes recorded playtime, so a false positive costs someone real
/// data — a far worse failure than missing a genuine overlap, which only
/// leaves a total slightly high.
@MainActor
struct FinishedOverlapTests {

    private func game(named name: String) -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: name, status: .playing)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @discardableResult
    private func finished(_ repo: Repository, _ pt: Playthrough,
                          device: String?, start: TimeInterval, minutes: Double,
                          manual: Bool = false) -> Session {
        let session = Session(startDate: t0.addingTimeInterval(start),
                              state: .stopped, isManual: manual)
        session.originDevice = device
        session.accumulatedDuration = minutes * 60
        session.endDate = t0.addingTimeInterval(start + minutes * 60)
        repo.context.insert(session)
        session.playthrough = pt
        return session
    }

    /// The real thing: two devices recorded the same hour.
    @Test func twoDevicesClaimingTheSameTimeAreReported() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, pt, device: "Piccolo", start: 1800, minutes: 60)   // 30 min in

        let overlaps = repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200))
        #expect(overlaps.count == 1)
        #expect(overlaps.first?.seconds == 1800)                          // the shared half hour
    }

    /// Sessions from ONE device overlapping is ordinary bookkeeping, not a
    /// two-device double count.
    @Test func sameDeviceOverlapsAreNotReported() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, pt, device: "King Kai", start: 1800, minutes: 60)

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200)).isEmpty)
    }

    /// A hand-logged block routinely covers a period a timer also covered —
    /// that is the user's own accounting and must never be questioned.
    @Test func manualSessionsAreNeverReported() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, pt, device: "Piccolo", start: 0, minutes: 60, manual: true)

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200)).isEmpty)
    }

    /// Sessions that merely touch at the edges aren't an overlap.
    @Test func adjacentSessionsAreNotReported() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, pt, device: "Piccolo", start: 3600, minutes: 60)   // starts as one ends

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200)).isEmpty)
    }

    /// A few seconds of intersection is noise, not a conflict worth a prompt.
    @Test func trivialIntersectionsAreNotReported() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, pt, device: "Piccolo", start: 3570, minutes: 60)   // 30s shared

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200)).isEmpty)
    }

    /// Different games can't double-count each other.
    @Test func overlapsAcrossDifferentGamesAreNotReported() {
        let (repo, _, pt) = game(named: "Hades")
        let other = repo.addGame(name: "Celeste", status: .playing)
        let otherPT = repo.ensureDefaultPlaythrough(for: other)
        finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, otherPT, device: "Piccolo", start: 0, minutes: 60)

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200)).isEmpty)
    }

    /// A session with no recorded device predates Schema V2 — nothing can be
    /// said about which device it came from, so it is left alone.
    @Test func sessionsWithoutADeviceAreNotReported() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: nil, start: 0, minutes: 60)
        finished(repo, pt, device: "Piccolo", start: 1800, minutes: 60)

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200)).isEmpty)
    }

    /// Deleted sessions are already out of every total.
    @Test func deletedSessionsAreNotReported() {
        let (repo, _, pt) = game(named: "Hades")
        let first = finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, pt, device: "Piccolo", start: 1800, minutes: 60)
        repo.deleteSession(first)

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(7200)).isEmpty)
    }

    /// Resolving removes one side from totals without erasing it — "this
    /// looks like a duplicate" is never certain enough to destroy a record.
    @Test func removingOneSideDropsItFromTotalsButKeepsTheRecord() {
        let (repo, _, pt) = game(named: "Hades")
        let kept = finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        let removed = finished(repo, pt, device: "Piccolo", start: 1800, minutes: 60)

        repo.deleteSession(removed)

        #expect(pt.totalPlaytime(asOf: t0.addingTimeInterval(7200)) == 3600)
        #expect(removed.deletedAt != nil)
        #expect(removed.accumulatedDuration == 3600)   // the record is intact
        #expect(kept.deletedAt == nil)
    }

    /// The scan is bounded to recent play, and says so rather than pretending
    /// to be exhaustive.
    @Test func overlapsOlderThanTheWindowAreNotReported() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: "King Kai", start: 0, minutes: 60)
        finished(repo, pt, device: "Piccolo", start: 1800, minutes: 60)

        let muchLater = t0.addingTimeInterval(200 * 24 * 3600)
        #expect(repo.overlappingFinishedSessions(asOf: muchLater).isEmpty)
        #expect(!repo.overlappingFinishedSessions(asOf: muchLater,
                                                  within: 365 * 24 * 3600).isEmpty)
    }

    /// Three-way pile-ups report each conflicting pair rather than collapsing
    /// them into one, so resolving one doesn't silently decide the others.
    @Test func threeOverlappingSessionsReportEachPair() {
        let (repo, _, pt) = game(named: "Hades")
        finished(repo, pt, device: "King Kai", start: 0, minutes: 90)
        finished(repo, pt, device: "Piccolo", start: 1800, minutes: 90)
        finished(repo, pt, device: "Mac", start: 3600, minutes: 90)

        #expect(repo.overlappingFinishedSessions(asOf: t0.addingTimeInterval(20000)).count == 3)
    }
}

/// A session must never exist without its playthrough — the failure Tim's
/// devices hit on 2026-08-19, where sessions were created detached, invisible
/// in the game, absent from totals and export, their time accruing into
/// nothing.
@MainActor
struct SessionAttachmentTests {

    private func newRepo() -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    @Test func startedSessionsAreAttachedAndStaySaved() throws {
        let (repo, game, pt) = newRepo()
        let session = repo.startSession(on: pt)
        try repo.context.save()

        #expect(session.playthrough?.id == pt.id)
        // And visible through the paths that matter: the game's own totals
        // and the orphan list.
        #expect(repo.orphanedSessions().isEmpty)
        #expect(game.livePlaythroughs.flatMap { $0.sessions ?? [] }.contains { $0.id == session.id })
    }

    @Test func manuallyLoggedSessionsAreAttached() throws {
        let (repo, _, pt) = newRepo()
        let session = repo.logManualSession(on: pt, duration: 600)
        try repo.context.save()

        #expect(session.playthrough?.id == pt.id)
        #expect(repo.orphanedSessions().isEmpty)
    }

    /// Starting repeatedly — the shape that produced several of the detached
    /// records — must leave every session attached, including the ones the
    /// new start stops.
    @Test func repeatedStartsLeaveEverySessionAttached() throws {
        let (repo, _, pt) = newRepo()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var sessions: [Session] = []
        for offset in stride(from: 0.0, to: 300.0, by: 60.0) {
            sessions.append(repo.startSession(on: pt, at: t0.addingTimeInterval(offset)))
        }
        try repo.context.save()

        #expect(sessions.allSatisfy { $0.playthrough?.id == pt.id })
        #expect(repo.orphanedSessions().isEmpty)
    }

    /// The user can give a detached session back to a game, since the app
    /// cannot infer where it belongs but the person who played it can.
    @Test func aDetachedSessionCanBeReattachedToAGame() throws {
        let (repo, game, pt) = newRepo()
        let orphan = Session(startDate: Date(timeIntervalSince1970: 1_700_000_000),
                             state: .stopped)
        orphan.accumulatedDuration = 3600
        orphan.endDate = orphan.startDate.addingTimeInterval(3600)
        repo.context.insert(orphan)
        try repo.context.save()
        #expect(repo.orphanedSessions().count == 1)

        repo.reattachSession(orphan, to: game)

        #expect(repo.orphanedSessions().isEmpty)
        #expect(orphan.playthrough?.id == pt.id)
        #expect(pt.totalPlaytime(asOf: orphan.endDate!) == 3600)
    }
}

/// The ledger that makes a detached session repairable: the device that
/// created it wrote down which playthrough it belonged to, at the moment it
/// knew for certain. Repairing from that is acting on a record, not a guess —
/// which is the distinction that makes it allowed at all, given this project
/// refuses to re-parent anything by inference.
@MainActor
struct SessionParentLedgerTests {

    private func newRepo() -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    @Test func aSessionDetachedAfterCreationIsRepairedFromTheLedger() throws {
        let (repo, _, pt) = newRepo()
        let session = repo.startSession(on: pt)
        try repo.context.save()

        // Exactly what the devices produced: attached at save, detached later.
        session.playthrough = nil
        try repo.context.save()
        #expect(repo.orphanedSessions().count == 1)

        #expect(repo.repairDetachedSessionsFromLedger() == 1)
        #expect(session.playthrough?.id == pt.id)
        #expect(repo.orphanedSessions().isEmpty)
    }

    /// A session this device never created has no recorded parent, so it stays
    /// detached for the user to place by hand. Repair never guesses.
    @Test func aSessionWithNoLedgerEntryIsLeftAlone() throws {
        let (repo, _, _) = newRepo()
        let stranger = Session(startDate: Date(timeIntervalSince1970: 1_700_000_000),
                               state: .stopped)
        stranger.accumulatedDuration = 600
        stranger.endDate = stranger.startDate.addingTimeInterval(600)
        repo.context.insert(stranger)
        try repo.context.save()

        #expect(repo.repairDetachedSessionsFromLedger() == 0)
        #expect(repo.orphanedSessions().count == 1)
    }

    /// If the playthrough itself is gone, the recorded answer is no longer
    /// true and must not be applied.
    @Test func repairSkipsAPlaythroughThatNoLongerExists() throws {
        let (repo, game, pt) = newRepo()
        let session = repo.startSession(on: pt)
        repo.stopSession(session)
        try repo.context.save()

        session.playthrough = nil
        repo.deletePlaythrough(pt, from: game)
        try repo.context.save()

        #expect(repo.repairDetachedSessionsFromLedger() == 0)
        #expect(repo.orphanedSessions().count == 1)
    }
}
