import Testing
import Foundation
@testable import LevelSelect

/// The badge rules, which are the whole of build 40's promise: a badge earned
/// once is earned, and a badge not yet earned says what it wants.
struct BadgeCatalogTests {

    @Test("Every badge id is unique — a duplicate would award twice or never")
    func idsAreUnique() {
        let ids = Badges.catalog.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("An empty library has earned nothing")
    func emptyLibraryEarnsNothing() {
        #expect(Badges.earned(from: BadgeFacts()).isEmpty)
    }

    @Test("A first is earned by one, and the tiers by their thresholds")
    func firstsAndTiers() {
        var facts = BadgeFacts()
        facts.gamesBeaten = 1
        #expect(Badges.earned(from: facts) == ["first.beaten"])

        facts.gamesBeaten = 25
        let earned = Badges.earned(from: facts)
        #expect(earned.contains("beaten.10"))
        #expect(earned.contains("beaten.25"))
        #expect(!earned.contains("beaten.50"))
    }

    /// The ledger is what keeps a badge; the rules only ever say what the
    /// numbers justify, and they justify every tier below the one you hit.
    @Test("Passing a tier keeps the ones under it")
    func lowerTiersStay() {
        var facts = BadgeFacts()
        facts.hoursPlayed = 1000
        let earned = Badges.earned(from: facts)
        for n in [10, 100, 500, 1000] { #expect(earned.contains("hours.\(n)")) }
    }

    @Test("Hours round down — 9.9 hours is not ten hours")
    func hoursRoundDown() {
        var facts = BadgeFacts()
        facts.hoursPlayed = 9.9
        #expect(!Badges.earned(from: facts).contains("hours.10"))
        facts.hoursPlayed = 10
        #expect(Badges.earned(from: facts).contains("hours.10"))
    }

    @Test("The habits and history flags each earn their own badge")
    func flagsEarnTheirBadges() {
        var facts = BadgeFacts()
        facts.longestStreakDays = 30
        facts.hadMonthWithEveryWeek = true
        facts.returnedAfterSixMonths = true
        facts.beatEverySystemGame = true
        facts.completedACollection = true
        facts.beatenBeforeInstall = true
        facts.hasVagueDate = true
        facts.yearsOfHistory = 10
        let earned = Set(Badges.earned(from: facts))
        for id in ["streak.7", "streak.30", "habit.everyWeek", "habit.return",
                   "collection.systemBeaten", "collection.finished",
                   "history.beforeApp", "history.vague",
                   "historyYears.5", "historyYears.10"] {
            #expect(earned.contains(id), "missing \(id)")
        }
    }

    @Test("Everything earned is in the catalog, in catalog order")
    func earnedFollowsTheCatalog() {
        var facts = BadgeFacts()
        facts.gamesBeaten = 100
        facts.consoles = 10
        facts.sessionsLogged = 500
        let earned = Badges.earned(from: facts)
        #expect(earned.allSatisfy { Badges.definition($0) != nil })
        let order = Badges.catalog.map(\.id)
        #expect(earned == order.filter(earned.contains))
    }
}
