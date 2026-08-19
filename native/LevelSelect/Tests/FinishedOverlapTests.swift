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
