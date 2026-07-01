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
}
