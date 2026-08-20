import Testing
import Foundation
@testable import LevelSelect

/// Critic scores and completion times.
///
/// The threshold is the feature. Measured against a real 163-game library:
/// without it, Sonic 2 and Sonic Mania each claim "2 hours" on one submission
/// (both are roughly three times that), and Super Metroid, Super Mario World
/// and A Link to the Past each show a critic score of 100 from a single
/// outlet. A wrong number is worse than no number — it teaches you to
/// distrust the right ones too.
@MainActor
struct GameReferenceTests {

    /// Pinned because the whole design rests on it, and because lowering it
    /// silently is exactly how the bad figures come back.
    @Test func theThresholdIsThreeSources() {
        #expect(GameReferenceService.minimumSources == 3)
    }

    @Test func aReferenceWithNothingInItIsEmpty() {
        let blank = GameReferenceService.Reference()
        #expect(blank.isEmpty)
        #expect(!blank.hasCritic)
        #expect(!blank.hasTime)
    }

    /// One half can be present without the other — plenty of games have
    /// reviews and no completion times, or the reverse.
    @Test func eachHalfStandsAlone() {
        let criticOnly = GameReferenceService.Reference(criticScore: 87, criticSources: 8)
        #expect(criticOnly.hasCritic)
        #expect(!criticOnly.hasTime)
        #expect(!criticOnly.isEmpty)

        var timeOnly = GameReferenceService.Reference()
        timeOnly.normally = 15.5 * 3600
        timeOnly.timeReports = 3
        #expect(timeOnly.hasTime)
        #expect(!timeOnly.hasCritic)
        #expect(!timeOnly.isEmpty)
    }

    // MARK: The formatter these numbers are read through

    /// Approximations shouldn't be dressed as measurements. An average of a
    /// dozen strangers' playthroughs does not justify "14h 24m".
    @Test func hoursAreRoundedToMatchThePrecisionTheyActuallyHave() {
        // Ten hours is the line. Below it a decimal earns its place; above it
        // "15.5h" claims half-hour accuracy about a figure averaged from a
        // dozen strangers, so it rounds.
        #expect(Format.hours(2 * 3600) == "2.0h")
        #expect(Format.hours(5.7 * 3600) == "5.7h")
        #expect(Format.hours(15.5 * 3600) == "16h")
        #expect(Format.hours(36.9 * 3600) == "37h")
        #expect(Format.hours(109.1 * 3600) == "109h")
    }

    /// Short games keep a decimal, because "2h" and "2.5h" are a meaningfully
    /// different evening; long ones don't, because "109.1h" implies six
    /// minutes of accuracy across four days of play.
    @Test func shortGamesKeepADecimalAndLongOnesDont() {
        #expect(Format.hours(9.9 * 3600).contains("."))
        #expect(!Format.hours(10.4 * 3600).contains("."))
    }

    /// Zero is a real answer from the API for a game nobody has submitted, and
    /// must not render as an empty string or a crash.
    @Test func zeroFormatsRatherThanBreaking() {
        #expect(Format.hours(0) == "0.0h")
    }
}
