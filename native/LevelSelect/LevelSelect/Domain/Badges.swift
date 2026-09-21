import Foundation

/// **What you've done, recorded once.**
///
/// The catalogue and the rule for each badge, as pure evaluation over a
/// snapshot of counts — no SwiftData here, so every threshold is testable
/// without a store. `BadgeAwarder` does the writing.
///
/// Counts are of the library, not of your time with the app: a Steam library
/// imported on day one earns the hours it carries. The app is a record of
/// what you played, not of what you have done since installing it.
///
/// Spec: vault, "LevelSelect badges and celebrations — build 40".
enum Badges {

    /// What a badge is. `id` is what lands in `EarnedBadge.badgeID` and must
    /// never change — a renamed id is a badge everyone loses.
    struct Definition: Identifiable, Hashable, Sendable {
        let id: String
        let family: Family
        let title: String
        /// What earned it, in the app's own voice, shown under the title.
        let earnedBy: String
        let symbol: String
        /// The number this tier asks for, when it is one of a series.
        let threshold: Int?

        var isTiered: Bool { threshold != nil }
    }

    enum Family: String, CaseIterable, Identifiable, Sendable {
        case firsts, counts, habits, collection, history
        var id: String { rawValue }
        var label: String {
            switch self {
            case .firsts:     "Firsts"
            case .counts:     "Milestones"
            case .habits:     "Habits"
            case .collection: "Your shelf"
            case .history:    "Your history"
            }
        }
    }

    /// Everything the app knows how to award, in the order the Journal shows
    /// it. Adding a badge is adding a row here and a line in `earned(from:)`.
    static let catalogue: [Definition] = firsts + counts + habits + collection + history

    // MARK: Firsts

    private static let firsts: [Definition] = [
        .init(id: "first.session", family: .firsts, title: "On the clock",
              earnedBy: "Timed your first session.", symbol: "stopwatch", threshold: nil),
        .init(id: "first.beaten", family: .firsts, title: "Roll credits",
              earnedBy: "Beat your first game.", symbol: "flag.checkered", threshold: nil),
        .init(id: "first.tracker", family: .firsts, title: "Every box ticked",
              earnedBy: "Finished your first tracker.", symbol: "checklist", threshold: nil),
        .init(id: "first.memory", family: .firsts, title: "Before all this",
              earnedBy: "Wrote your first memory.", symbol: "photo.on.rectangle.angled", threshold: nil),
        .init(id: "first.console", family: .firsts, title: "Something to play it on",
              earnedBy: "Recorded your first console.", symbol: "gamecontroller", threshold: nil),
    ]

    // MARK: Counts

    private static let counts: [Definition] = [
        tier("beaten", 10, .counts, "Ten down", "Beat 10 games.", "flag.checkered"),
        tier("beaten", 25, .counts, "Twenty-five", "Beat 25 games.", "flag.checkered"),
        tier("beaten", 50, .counts, "Fifty", "Beat 50 games.", "flag.checkered"),
        tier("beaten", 100, .counts, "A hundred games", "Beat 100 games.", "flag.checkered"),
        tier("hours", 10, .counts, "Ten hours", "Played for 10 hours.", "hourglass"),
        tier("hours", 100, .counts, "A hundred hours", "Played for 100 hours.", "hourglass"),
        tier("hours", 500, .counts, "Five hundred hours", "Played for 500 hours.", "hourglass"),
        tier("hours", 1000, .counts, "A thousand hours", "Played for 1,000 hours.", "hourglass"),
        tier("sessions", 10, .counts, "Ten sessions", "Logged 10 sessions.", "stopwatch"),
        tier("sessions", 100, .counts, "A hundred sessions", "Logged 100 sessions.", "stopwatch"),
        tier("sessions", 500, .counts, "Five hundred sessions", "Logged 500 sessions.", "stopwatch"),
        tier("added", 10, .counts, "A shelf", "Added 10 games.", "books.vertical"),
        tier("added", 100, .counts, "A collection", "Added 100 games.", "books.vertical"),
        tier("added", 500, .counts, "A library", "Added 500 games.", "books.vertical"),
    ]

    // MARK: Habits

    private static let habits: [Definition] = [
        .init(id: "streak.7", family: .habits, title: "A week of it",
              earnedBy: "Played seven days running.", symbol: "flame", threshold: 7),
        .init(id: "streak.30", family: .habits, title: "A month of it",
              earnedBy: "Played thirty days running.", symbol: "flame.fill", threshold: 30),
        .init(id: "habit.everyWeek", family: .habits, title: "Every week counted",
              earnedBy: "Played in every week of a month.", symbol: "calendar", threshold: nil),
        .init(id: "habit.return", family: .habits, title: "Right, where was I",
              earnedBy: "Went back to a game you hadn't touched in six months.",
              symbol: "arrow.uturn.backward", threshold: nil),
    ]

    // MARK: Collection

    private static let collection: [Definition] = [
        tier("consoles", 1, .collection, "Your first machine", "Recorded a console you own.", "gamecontroller.fill"),
        tier("consoles", 5, .collection, "Five machines", "Recorded 5 consoles.", "gamecontroller.fill"),
        tier("consoles", 10, .collection, "A proper setup", "Recorded 10 consoles.", "gamecontroller.fill"),
        .init(id: "collection.systemBeaten", family: .collection, title: "Cleared the shelf",
              earnedBy: "Beat every game you own on one system.", symbol: "checkmark.seal", threshold: nil),
        .init(id: "collection.finished", family: .collection, title: "A collection, completed",
              earnedBy: "Beat every game in one of your collections.", symbol: "square.stack", threshold: nil),
    ]

    // MARK: History

    private static let history: [Definition] = [
        .init(id: "history.beforeApp", family: .history, title: "Long before this",
              earnedBy: "Dated something you beat before you had the app.",
              symbol: "clock.arrow.circlepath", threshold: nil),
        .init(id: "history.vague", family: .history, title: "Sometime around then",
              earnedBy: "Recorded a date you only half remember.", symbol: "questionmark.circle", threshold: nil),
        tier("historyYears", 5, .history, "Five years back", "Your history covers five years.", "calendar.badge.clock"),
        tier("historyYears", 10, .history, "A decade of it", "Your history covers ten years.", "calendar.badge.clock"),
    ]

    private static func tier(_ key: String, _ n: Int, _ family: Family,
                             _ title: String, _ earnedBy: String, _ symbol: String) -> Definition {
        .init(id: "\(key).\(n)", family: family, title: title, earnedBy: earnedBy,
              symbol: symbol, threshold: n)
    }

    static func definition(_ id: String) -> Definition? { catalogue.first { $0.id == id } }

    /// **Everything the library justifies right now.**
    ///
    /// Returns ids, not records: the awarder decides which of these are new.
    /// Order follows the catalogue so a first run reads top to bottom.
    static func earned(from f: BadgeFacts) -> [String] {
        var out: Set<String> = []
        if f.sessionsLogged > 0 { out.insert("first.session") }
        if f.gamesBeaten > 0 { out.insert("first.beaten") }
        if f.trackersFinished > 0 { out.insert("first.tracker") }
        if f.memories > 0 { out.insert("first.memory") }
        if f.consoles > 0 { out.insert("first.console") }

        insertTiers(&out, "beaten", f.gamesBeaten, [10, 25, 50, 100])
        insertTiers(&out, "hours", Int(f.hoursPlayed), [10, 100, 500, 1000])
        insertTiers(&out, "sessions", f.sessionsLogged, [10, 100, 500])
        insertTiers(&out, "added", f.gamesAdded, [10, 100, 500])
        insertTiers(&out, "consoles", f.consoles, [1, 5, 10])
        insertTiers(&out, "historyYears", f.yearsOfHistory, [5, 10])

        if f.longestStreakDays >= 7 { out.insert("streak.7") }
        if f.longestStreakDays >= 30 { out.insert("streak.30") }
        if f.hadMonthWithEveryWeek { out.insert("habit.everyWeek") }
        if f.returnedAfterSixMonths { out.insert("habit.return") }

        if f.beatEverySystemGame { out.insert("collection.systemBeaten") }
        if f.completedACollection { out.insert("collection.finished") }

        if f.beatenBeforeInstall { out.insert("history.beforeApp") }
        if f.hasVagueDate { out.insert("history.vague") }

        return catalogue.map(\.id).filter { out.contains($0) }
    }

    private static func insertTiers(_ out: inout Set<String>, _ key: String,
                                    _ value: Int, _ thresholds: [Int]) {
        for n in thresholds where value >= n { out.insert("\(key).\(n)") }
    }
}

/// The counts every badge rule reads, gathered once.
///
/// A plain snapshot so the rules can be tested with a literal — the store
/// side lives in `BadgeAwarder.facts(in:)`.
struct BadgeFacts: Equatable, Sendable {
    var gamesBeaten = 0
    var gamesAdded = 0
    var sessionsLogged = 0
    var hoursPlayed: Double = 0
    var trackersFinished = 0
    var memories = 0
    var consoles = 0
    /// The longest run of consecutive days with play, ever.
    var longestStreakDays = 0
    var hadMonthWithEveryWeek = false
    var returnedAfterSixMonths = false
    var beatEverySystemGame = false
    var completedACollection = false
    /// A completion dated before the library's first session.
    var beatenBeforeInstall = false
    /// A date recorded as a year, or a month, rather than a day.
    var hasVagueDate = false
    /// First to last year covered by anything dated — sessions, completions,
    /// memories.
    var yearsOfHistory = 0
}
