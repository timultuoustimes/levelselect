import Foundation
#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// The feel of dice settling: four transient knocks, each softer and duller
/// than the last, spaced like a die losing momentum. A single medium tap
/// said "notification"; this says "rolled".
@MainActor
enum DiceHaptics {
    #if os(iOS)
    /// Kept alive for the pattern's duration; recreated per tumble because
    /// the engine idles out and a stale engine plays nothing, silently.
    private static var engine: CHHapticEngine?

    static func tumble() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        do {
            let engine = try CHHapticEngine()
            Self.engine = engine
            try engine.start()

            // (delay, intensity, sharpness): a hard first landing, then the
            // bounces — later, weaker, duller.
            let knocks: [(TimeInterval, Float, Float)] = [
                (0.00, 1.00, 0.70),
                (0.09, 0.70, 0.55),
                (0.20, 0.45, 0.40),
                (0.34, 0.28, 0.25),
            ]
            let events = knocks.map { delay, intensity, sharpness in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: intensity),
                        .init(parameterID: .hapticSharpness, value: sharpness),
                    ],
                    relativeTime: delay)
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: 0)
            // Let the pattern finish, then let the engine go.
            engine.notifyWhenPlayersFinished { _ in .stopEngine }
        } catch {
            // Any engine trouble degrades to the old single tap — a roll
            // should never be silent to the hand entirely.
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }
    #else
    static func tumble() {}
    #endif
}
