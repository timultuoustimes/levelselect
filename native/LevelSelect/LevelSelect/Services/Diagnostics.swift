import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

/// The facts that ride along with a message to the developer.
///
/// This is the whole of what "include diagnostics" means, and it is assembled
/// **on demand and shown to you before it goes anywhere**. Nothing here is
/// recorded, stored, or sent on its own — there is no logging at rest and no
/// crash reporter. Gamery attaches a `Logs.txt` collected by Sentry; the point
/// of doing it this way instead is that the App Store card for LevelSelect can
/// keep saying Data Not Collected and mean it.
///
/// What is deliberately NOT in here: game titles, notes, review text, your
/// profile, handles, the RetroAchievements username or any key. Counts, not
/// contents. A bug report should never be the first time your library leaves
/// your device.
enum Diagnostics {
    /// Matches the `Logger(subsystem:)` used by Repository, PersistenceMonitor
    /// and SyncStatusMonitor — the only log lines this app writes.
    static let subsystem = "com.timultuoustimes.levelselect"

    /// How many of our own log lines to carry. Enough to see the shape of what
    /// just happened; short enough that a person can read it before sending.
    static let logLineLimit = 40

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// `iPhone17,2` rather than "iPhone" — the model identifier is the part
    /// that distinguishes a report on a phone from one on the iPad.
    static var modelIdentifier: String {
        #if os(macOS)
        return "Mac"
        #else
        // On a simulator `uname` reports the Mac's architecture — "arm64",
        // which is true and useless. The simulated device is in the
        // environment, and a report that says so is one nobody has to
        // second-guess.
        if let simulated = ProcessInfo.processInfo
            .environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var system = utsname()
        uname(&system)
        let identifier = withUnsafeBytes(of: &system.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return identifier.isEmpty ? "unknown" : identifier
        #endif
    }

    static var systemVersion: String {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #else
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #endif
    }

    /// Everything except the log, which is fetched separately because reading
    /// it is the one part that can be slow.
    ///
    /// Counts are passed in rather than queried here so this stays a pure
    /// function of what the caller already has on screen — and so it can be
    /// tested without a store.
    static func summary(games: Int,
                        sessions: Int,
                        sync: String,
                        services: [String],
                        appearance: String) -> String {
        var lines = [
            "LevelSelect \(versionString)",
            "\(modelIdentifier) · \(systemVersion)",
            "Locale: \(Locale.current.identifier)",
            "iCloud: \(sync)",
            "Library: \(games) games · \(sessions) sessions",
            "Appearance: \(appearance)",
        ]
        lines.append("Services: " + (services.isEmpty ? "none connected"
                                     : services.joined(separator: ", ")))
        return lines.joined(separator: "\n")
    }

    /// How far back to read. Ten minutes is "what just went wrong" — and it is
    /// the difference between a screen that opens and one that hangs.
    ///
    /// `position(timeIntervalSinceLatestBoot: 0)` scans from boot, which on a
    /// device that has been up for days is a long walk through every log line
    /// the process ever wrote. Tim, on the first build of this screen: *"Send
    /// feedback takes 7 seconds to load."* That was this call, on the main
    /// actor, doing exactly that.
    static let logWindow: TimeInterval = 600

    /// Recent log lines from our own subsystem, oldest first.
    ///
    /// `.currentProcessIdentifier` is the only scope an app is allowed on
    /// iOS, which suits this exactly: it can read what IT did since launch and
    /// nothing else on the device. When the store refuses — it does, on some
    /// configurations — the report says so rather than silently arriving
    /// without the half that would have explained the bug.
    ///
    /// **Call this off the main actor.** It is a synchronous scan of the log
    /// store and it is not fast even with the window above.
    static func recentLog(limit: Int = logLineLimit,
                          window: TimeInterval = logWindow) -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let since = store.position(date: Date().addingTimeInterval(-window))
            let entries = try store.getEntries(
                at: since,
                matching: NSPredicate(format: "subsystem == %@", subsystem))
            let lines = entries
                .compactMap { $0 as? OSLogEntryLog }
                .map { entry in
                    let time = entry.date.formatted(date: .omitted,
                                                    time: .standard)
                    return "\(time) [\(entry.category)] \(entry.composedMessage)"
                }
            if lines.isEmpty { return "No log entries in the last \(Int(window / 60)) minutes." }
            return lines.suffix(limit).joined(separator: "\n")
        } catch {
            return "Log unavailable (\(error.localizedDescription))."
        }
    }
}
