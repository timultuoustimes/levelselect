import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 34 — the session editor showed wall-clock time where every other
/// surface shows played time, and saving wrote the wall clock into history.
@MainActor
struct Build34SessionEditTests {

    private func makeContext() -> ModelContext {
        ModelContext(LevelSelectStore.makeContainer(inMemory: true))
    }

    /// The case from Tim's real library, 2026-06-27: a timer left running
    /// overnight. Stopped at 08:30 after starting at 20:30, with ten minutes
    /// actually played. The editor derived duration from `endDate` and so
    /// offered to save **twelve hours**.
    @Test func aTimerLeftRunningOvernightDoesNotEditAsTwelveHours() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Skate Story", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let session = repo.startSession(on: pt)
        session.startDate = start
        session.accumulatedDuration = 600          // ten minutes played
        session.endDate = start.addingTimeInterval(43_200)   // stopped 12h later
        session.state = .stopped

        #expect(session.elapsed() == 600)
        // What the editor now seeds its "Ended" picker with.
        #expect(session.editableEnd.timeIntervalSince(start) == 600)
        // What it used to seed it with, and would have saved.
        #expect(session.endDate!.timeIntervalSince(start) == 43_200)
    }

    /// A session that was never paused is unaffected — span and played time
    /// already agree, so the editor shows exactly what it always did.
    @Test func anUninterruptedSessionEditsUnchanged() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let session = repo.startSession(on: pt)
        session.startDate = start
        session.accumulatedDuration = 3600
        session.endDate = start.addingTimeInterval(3600)
        session.state = .stopped

        #expect(session.editableEnd == session.endDate)
    }

    /// The list and the editor have to agree. They are the two places a
    /// session's length is shown, and they disagreed by 15 minutes on a
    /// six-second session.
    @Test func theListAndTheEditorReportTheSameLength() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Skate Story", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let session = repo.startSession(on: pt)
        session.startDate = start
        session.accumulatedDuration = 6                       // six seconds played
        session.endDate = start.addingTimeInterval(925)       // stopped 15m25s later
        session.state = .stopped

        let inTheList = session.elapsed()
        let inTheEditor = session.editableEnd.timeIntervalSince(session.startDate)
        #expect(inTheList == inTheEditor)
        #expect(inTheList == 6)
    }

    // MARK: The Home backdrop

    /// The header showed a game Tim had not played this week while the one he
    /// had just played sat in Continue Playing directly beneath it. The old
    /// code took the first PLAYING game with art, and the query sorts by
    /// name — so with eleven games in progress it picked alphabetically.
    @Test func theHeaderBackdropIsTheGameYouLastPlayed() {
        let context = makeContext()
        let repo = Repository(context)

        // "Animal Well" sorts first and is playing, but was last touched a
        // month ago. "Skate Story" was played today.
        let old = repo.addGame(name: "Animal Well", status: .playing)
        old.coverURLString = "animal-well.jpg"
        let recent = repo.addGame(name: "Skate Story", status: .playing)
        recent.coverURLString = "skate-story.jpg"

        let session = repo.startSession(on: repo.ensureDefaultPlaythrough(for: recent))
        session.startDate = Date.now.addingTimeInterval(-3600)
        session.accumulatedDuration = 600
        session.state = .stopped

        let summary = PlayerSummary.make(from: [old, recent])
        #expect(summary.fallbackBackdrop == "skate-story.jpg")
    }

    /// With nothing played this week there is no "last played", so it falls
    /// back to something in progress rather than showing nothing.
    @Test func aQuietWeekStillGetsABackdrop() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Animal Well", status: .playing)
        game.coverURLString = "animal-well.jpg"

        let summary = PlayerSummary.make(from: [game])
        #expect(summary.fallbackBackdrop == "animal-well.jpg")
    }

    /// And saving what the editor showed must not change the number.
    @Test func savingAnUntouchedSessionPreservesItsPlaytime() {
        let context = makeContext()
        let repo = Repository(context)
        let game = repo.addGame(name: "Skate Story", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let session = repo.startSession(on: pt)
        session.startDate = start
        session.accumulatedDuration = 600
        session.endDate = start.addingTimeInterval(43_200)
        session.state = .stopped

        // Open the editor and press Save without touching anything.
        repo.updateSession(session, start: session.startDate,
                           end: session.editableEnd, notes: nil)

        #expect(session.elapsed() == 600)
        #expect(game.lifetimePlaytime() == 600)
    }
}
