import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The session timer is derived from timestamps (no ticking writes), so its
/// pause/resume math is the subtle part worth pinning down.
@MainActor
struct SessionTimerTests {

    private func newContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    @Test func straightRunAccumulatesFullDuration() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let game = repo.addGame(name: "A", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let s = repo.startSession(on: pt, at: t0)
        // 60s later, still running:
        #expect(abs(s.elapsed(asOf: t0.addingTimeInterval(60)) - 60) < 0.001)
        repo.stopSession(s, at: t0.addingTimeInterval(90))
        #expect(s.state == .stopped)
        #expect(abs(s.accumulatedDuration - 90) < 0.001)
    }

    @Test func pauseResumeExcludesPausedTime() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let game = repo.addGame(name: "B", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let t0 = Date(timeIntervalSince1970: 2_000_000)
        let s = repo.startSession(on: pt, at: t0)
        repo.pauseSession(s, at: t0.addingTimeInterval(30))     // 30s counted
        #expect(s.state == .paused)
        #expect(abs(s.accumulatedDuration - 30) < 0.001)
        // paused for 70s — should NOT count:
        #expect(abs(s.elapsed(asOf: t0.addingTimeInterval(100)) - 30) < 0.001)
        repo.resumeSession(s, at: t0.addingTimeInterval(100))
        repo.stopSession(s, at: t0.addingTimeInterval(110))     // +10s
        #expect(abs(s.accumulatedDuration - 40) < 0.001)        // 30 + 10
    }

    @Test func startingNewSessionStopsTheActiveOne() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let game = repo.addGame(name: "C", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let t0 = Date(timeIntervalSince1970: 3_000_000)
        let first = repo.startSession(on: pt, at: t0)
        let second = repo.startSession(on: pt, at: t0.addingTimeInterval(50))
        #expect(first.state == .stopped)
        #expect(abs(first.accumulatedDuration - 50) < 0.001)
        #expect(second.state == .running)
        #expect(pt.activeSession?.id == second.id)
    }

    @Test func manualSessionRecordsDuration() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let game = repo.addGame(name: "D")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let s = repo.logManualSession(on: pt, duration: 3600)
        #expect(s.isManual)
        #expect(s.state == .stopped)
        #expect(abs(s.accumulatedDuration - 3600) < 0.001)
    }

    /// Round 2, finding 9: a PAUSED stale session's real boundary is its
    /// pause, not its start. The old anchor let the sheet's suggested time
    /// record a stop hours before — or after — the user actually stopped;
    /// the pause proves activity up to exactly that moment, so the recorded
    /// end and "last played" clamp to it. Duration is untouched either way.
    @Test func endingAPausedStaleSessionAnchorsToItsPause() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let game = repo.addGame(name: "E", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let s = repo.startSession(on: pt, at: t0)
        repo.pauseSession(s, at: t0.addingTimeInterval(300))   // 5 min banked

        // The user (or the old sheet default) picks a stop BEFORE the pause.
        repo.endStaleSession(s, stoppedAt: t0.addingTimeInterval(60))

        #expect(s.state == .stopped)
        #expect(abs(s.accumulatedDuration - 300) < 0.001)      // duration honest
        #expect(s.endDate == t0.addingTimeInterval(300))       // clamped to pause
        #expect(pt.lastPlayedAt == t0.addingTimeInterval(300))
    }

    /// Round 3, finding 7: a synced session whose pause anchor sits in THIS
    /// device's future must not push a future timestamp into history — the
    /// anchor clamp has to bind in both directions.
    @Test func endingAStaleSessionNeverRecordsAFutureStop() {
        let ctx = newContext()
        let repo = Repository(ctx)
        let game = repo.addGame(name: "F", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let s = repo.startSession(on: pt, at: .now.addingTimeInterval(-7 * 3600))
        repo.pauseSession(s, at: .now.addingTimeInterval(-3600))
        s.pausedAt = .now.addingTimeInterval(3600)              // clock-ahead sync

        repo.endStaleSession(s, stoppedAt: .now.addingTimeInterval(-1800))

        #expect(s.state == .stopped)
        #expect(s.endDate.map { $0 <= .now } == true)
        #expect(pt.lastPlayedAt.map { $0 <= .now } == true)
        #expect(abs(s.accumulatedDuration - 6 * 3600) < 1)      // banked time untouched
    }
}
