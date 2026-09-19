import Testing
import Foundation
@testable import LevelSelect

/// **Durations in accessibility labels have to be words, not units.**
///
/// `Format.duration` is written for a label — "50m 0s" — and VoiceOver reads
/// those units as units. Tim, testing the Journal calendar on 2026-09-04:
/// a 50-minute session was announced as **"50 meters 0 S"**.
@MainActor
struct SpokenDurationTests {

    @Test func spokenFormIsWordsNotUnitLetters() {
        #expect(Format.spokenDuration(50 * 60) == "50 minutes")
        #expect(Format.spokenDuration(3600 + 19 * 60) == "1 hour 19 minutes")
        #expect(Format.spokenDuration(2 * 3600) == "2 hours")
        #expect(Format.spokenDuration(60) == "1 minute")
        #expect(Format.spokenDuration(45) == "45 seconds")
        #expect(Format.spokenDuration(1) == "1 second")
        #expect(Format.spokenDuration(0) == "0 seconds")
    }

    /// The exact case Tim heard: 50 minutes has a zero seconds component, and
    /// the written form keeps it. Spoken, a trailing "0 seconds" is noise.
    @Test func aZeroComponentIsNotSpoken() {
        #expect(Format.duration(50 * 60) == "50m 0s", "the written form is unchanged")
        #expect(!Format.spokenDuration(50 * 60).contains("0 second"))
        #expect(!Format.spokenDuration(2 * 3600).contains("0 minute"))
    }

    /// Nothing spoken should contain a bare unit letter for a screen reader to
    /// misread. This is the property, rather than a list of examples.
    @Test func noSpokenDurationContainsABareUnitLetter() {
        for seconds in [0, 1, 45, 60, 90, 600, 3000, 3600, 4740, 7200, 86_399] {
            let spoken = Format.spokenDuration(TimeInterval(seconds))
            #expect(!spoken.contains("m "), Comment(rawValue: "unit letter in \(spoken)"))
            #expect(!spoken.hasSuffix("m"), Comment(rawValue: "unit letter in \(spoken)"))
            #expect(!spoken.hasSuffix("s") || spoken.hasSuffix("seconds")
                    || spoken.hasSuffix("minutes") || spoken.hasSuffix("hours"),
                    Comment(rawValue: "unit letter in \(spoken)"))
        }
    }
}
