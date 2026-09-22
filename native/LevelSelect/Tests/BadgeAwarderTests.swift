import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The ledger side of badges: written once, never twice, and quiet the first
/// time over a library that has already earned things.
@MainActor
struct BadgeAwarderTests {

    private func store() -> Repository {
        UserDefaults.standard.removeObject(forKey: "levelselect.badges.backfilled")
        return Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    /// Everything an existing library has earned lands at once, silently —
    /// otherwise build 40's first launch is fourteen celebrations deep.
    @Test("The first pass writes what's earned and celebrates none of it")
    func firstPassIsQuiet() {
        let repo = store()
        let game = repo.addGame(name: "Hades")
        repo.addCompletion(to: game, label: .cleared, date: .now)

        let result = BadgeAwarder.award(in: repo.context)
        #expect(result.wasBackfill)
        #expect(result.newlyEarned.isEmpty)
        #expect(BadgeAwarder.existing(in: repo.context).contains { $0.badgeID == "first.beaten" })
    }

    @Test("After the first pass, a new badge is returned so it can be celebrated")
    func laterBadgesCelebrate() {
        let repo = store()
        let first = repo.addGame(name: "Hades")
        repo.addCompletion(to: first, label: .cleared, date: .now)
        _ = BadgeAwarder.award(in: repo.context)     // the quiet pass

        let memory = Memory(title: "Christmas 1996", earliest: .now, precision: "year")
        repo.context.insert(memory)
        let result = BadgeAwarder.award(in: repo.context)
        #expect(!result.wasBackfill)
        #expect(result.newlyEarned.map(\.id).contains("first.memory"))
    }

    @Test("Running twice writes nothing the second time")
    func awardingIsIdempotent() {
        let repo = store()
        let game = repo.addGame(name: "Celeste")
        repo.addCompletion(to: game, label: .cleared, date: .now)
        _ = BadgeAwarder.award(in: repo.context)
        let count = BadgeAwarder.existing(in: repo.context).count
        let again = BadgeAwarder.award(in: repo.context)
        #expect(again.newlyEarned.isEmpty)
        #expect(BadgeAwarder.existing(in: repo.context).count == count)
    }

    /// The ledger's whole reason for existing: undoing the thing that earned
    /// a badge does not take the badge away.
    @Test("A badge survives the completion that earned it being removed")
    func badgesDoNotUnEarn() {
        let repo = store()
        let game = repo.addGame(name: "Tunic")
        repo.addCompletion(to: game, label: .cleared, date: .now)
        _ = BadgeAwarder.award(in: repo.context)

        for event in (game.completionEvents ?? []) { repo.removeCompletion(event) }
        _ = BadgeAwarder.award(in: repo.context)
        #expect(BadgeAwarder.existing(in: repo.context).contains { $0.badgeID == "first.beaten" })
    }

    /// Tim, King Kai, 09-21: every backfilled badge claimed it was earned
    /// today. The tenth completion has a date; use it.
    @Test("A backfilled badge is dated from what earned it, not from today")
    func badgesAreBackdated() {
        let repo = store()
        let when = Date(timeIntervalSinceNow: -400 * 86_400)
        let game = repo.addGame(name: "Chrono Trigger")
        repo.addCompletion(to: game, label: .cleared, date: when)

        _ = BadgeAwarder.award(in: repo.context)
        let badge = BadgeAwarder.existing(in: repo.context).first { $0.badgeID == "first.beaten" }
        #expect(badge != nil)
        #expect(abs((badge?.earnedAt ?? .now).timeIntervalSince(when)) < 60)
    }

    @Test("The tenth game beaten is dated to the tenth completion")
    func tiersUseTheirOwnDate() {
        let repo = store()
        var tenth = Date.now
        for i in 1...10 {
            let game = repo.addGame(name: "Game \(i)")
            let date = Date(timeIntervalSinceNow: Double(-500 + i * 10) * 86_400)
            repo.addCompletion(to: game, label: .cleared, date: date)
            if i == 10 { tenth = date }
        }
        _ = BadgeAwarder.award(in: repo.context)
        let badge = BadgeAwarder.existing(in: repo.context).first { $0.badgeID == "beaten.10" }
        #expect(abs((badge?.earnedAt ?? .now).timeIntervalSince(tenth)) < 60)
    }

    // MARK: Every badge has a date — Codex, build 40 static assessment

    private func day(_ daysAgo: Double) -> Date { Date(timeIntervalSinceNow: -daysAgo * 86_400) }

    @discardableResult
    private func play(_ repo: Repository, _ game: Game, on date: Date, hours: Double = 1) -> Session {
        let pt = game.activePlaythrough ?? repo.addPlaythrough(to: game, named: "Main")
        let session = Session(startDate: date, state: .stopped)
        session.endDate = date.addingTimeInterval(hours * 3600)
        session.accumulatedDuration = hours * 3600
        session.playthrough = pt
        repo.context.insert(session)
        return session
    }

    private func dated(_ repo: Repository, _ id: String) -> Date? {
        _ = BadgeAwarder.award(in: repo.context)
        return BadgeAwarder.existing(in: repo.context).first { $0.badgeID == id }?.earnedAt
    }

    private func near(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return abs(a.timeIntervalSince(b)) < 60
    }

    /// The count is of games; so is the date. A replay of a game you had
    /// already beaten used to move "10 games beaten" earlier.
    @Test("Beaten tiers are dated by the tenth distinct game, not the tenth finish")
    func beatenTiersCountDistinctGames() {
        let repo = store()
        let first = repo.addGame(name: "Replayed")
        repo.addCompletion(to: first, label: .cleared, date: day(500))
        repo.addCompletion(to: first, label: .cleared, date: day(490))   // replay
        var tenth = Date.now
        for i in 2...10 {
            let game = repo.addGame(name: "Game \(i)")
            let when = day(Double(480 - i * 10))
            repo.addCompletion(to: game, label: .cleared, date: when)
            if i == 10 { tenth = when }
        }
        #expect(near(dated(repo, "beaten.10"), tenth))
    }

    @Test("The first finished tracker is dated to its last tick")
    func firstTrackerIsDated() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight")
        let pt = repo.addPlaythrough(to: game, named: "Main")
        pt.progressPercent = 100
        let last = day(200)
        for (i, when) in [day(210), last].enumerated() {
            let state = TrackerStateRecord(itemID: "item-\(i)", completed: true)
            state.completedAt = when
            state.playthrough = pt
            repo.context.insert(state)
        }
        #expect(near(dated(repo, "first.tracker"), last))
    }

    @Test("Coming back after six months is dated to the session that came back")
    func returnIsDated() {
        let repo = store()
        let game = repo.addGame(name: "Stardew Valley")
        play(repo, game, on: day(400))
        let back = day(150)
        play(repo, game, on: back)
        #expect(near(dated(repo, "habit.return"), back))
    }

    /// Dated to when the month was completed — its last week's first
    /// session — rather than today. Where exactly that falls depends on the
    /// locale's first weekday, so this asserts what holds for any of them:
    /// the date is inside the qualifying month, in its last week.
    @Test("Every week counted is dated inside the month that earned it")
    func everyWeekIsDated() {
        let repo = store()
        let game = repo.addGame(name: "Tunic")
        let calendar = Calendar.current
        let march = calendar.date(from: DateComponents(year: 2025, month: 3, day: 1, hour: 12))!
        for offset in 0..<31 {
            play(repo, game, on: calendar.date(byAdding: .day, value: offset, to: march)!)
        }
        let date = dated(repo, "habit.everyWeek")
        let lastWeekStart = calendar.date(from: DateComponents(year: 2025, month: 3, day: 24))!
        let monthEnd = calendar.date(from: DateComponents(year: 2025, month: 4, day: 1))!
        #expect(date.map { $0 >= lastWeekStart && $0 < monthEnd } == true,
                Comment(rawValue: "dated \(String(describing: date))"))
    }

    /// History spans sessions too, as the rule says; they were left out.
    @Test("Five years of history counts sessions and is dated to the day it reached five")
    func historyYearsIsDated() {
        let repo = store()
        let game = repo.addGame(name: "Chrono Trigger")
        play(repo, game, on: day(6 * 365 + 30))
        let reached = day(365 - 30)   // the first thing at least five years later
        play(repo, game, on: reached)
        #expect(near(dated(repo, "historyYears.5"), reached))
    }

    /// A later finish on some other system must not become the date.
    @Test("Clearing a system is dated to that system's last game")
    func systemBeatenIsDated() {
        let repo = store()
        var last = Date.now
        for i in 0..<3 {
            let game = repo.addGame(name: "Switch \(i)")
            game.ownedPlatforms = ["Nintendo Switch"]
            let when = day(Double(300 - i * 10))
            repo.addCompletion(to: game, label: .cleared, date: when)
            last = when
        }
        let elsewhere = repo.addGame(name: "PC game")
        elsewhere.ownedPlatforms = ["PC (Microsoft Windows)"]
        repo.addCompletion(to: elsewhere, label: .cleared, date: day(5))
        #expect(near(dated(repo, "collection.systemBeaten"), last))
    }

    /// Imported hours were played before tracking began, so a threshold they
    /// cross on their own is dated to the earliest thing the library knows.
    @Test("An hours badge earned by imported time alone is not dated today")
    func importedHoursAreNotDatedToday() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(40 * 3600, on: pt)
        let first = day(90)
        play(repo, game, on: first, hours: 0.5)
        #expect(near(dated(repo, "hours.10"), first))
    }

    /// Charts counts a game marked Completed as beaten; badges didn't, so the
    /// two disagreed (Fable, build 40 runtime, 09-21).
    @Test("A game finished by status alone counts as beaten, like Charts")
    func statusFinishCounts() {
        let repo = store()
        let game = repo.addGame(name: "Celeste", status: .completed)
        #expect(game.isFinished)
        #expect(BadgeAwarder.facts(in: repo.context).gamesBeaten == 1)
        _ = BadgeAwarder.award(in: repo.context)
        #expect(BadgeAwarder.existing(in: repo.context).contains { $0.badgeID == "first.beaten" })
    }

    /// With no finish on record, it is dated to the last time it was played.
    @Test("A status-only finish is dated to when it was last played")
    func statusFinishIsDated() {
        let repo = store()
        let game = repo.addGame(name: "Celeste", status: .completed)
        let last = day(40)
        play(repo, game, on: last)
        game.activePlaythrough?.lastPlayedAt = last
        #expect(near(dated(repo, "first.beaten"), last))
    }

    // MARK: Sync twins

    /// Two offline devices each earned the same badge. One row survives —
    /// the earliest — and the other is tombstoned so the removal syncs.
    @Test("Badge twins fold to one row, keeping the earliest date")
    func badgeTwinsFold() {
        let repo = store()
        let early = day(100)
        repo.context.insert(EarnedBadge(badgeID: "first.beaten", earnedAt: day(50)))
        repo.context.insert(EarnedBadge(badgeID: "first.beaten", earnedAt: early))
        repo.context.insert(EarnedBadge(badgeID: "streak.7", earnedAt: day(10)))

        #expect(repo.reconcileBadges() == 1)
        let live = BadgeAwarder.existing(in: repo.context)
        #expect(live.filter { $0.badgeID == "first.beaten" }.count == 1)
        #expect(near(live.first { $0.badgeID == "first.beaten" }?.earnedAt, early))
        #expect(live.count == 2)
        #expect(repo.reconcileBadges() == 0)   // idempotent
    }

    /// Every device must keep the same row, or each tombstones the one the
    /// other kept. Equal dates fall back to the id.
    @Test("Twins with the same date pick the same survivor however they arrive")
    func twinSurvivorIsDeterministic() {
        let same = day(30)
        let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
        var survivors: [UUID] = []
        for order in [[a, b], [b, a]] {
            let repo = store()
            for id in order {
                let badge = EarnedBadge(badgeID: "streak.7", earnedAt: same)
                badge.id = id
                repo.context.insert(badge)
            }
            repo.reconcileBadges()
            survivors += BadgeAwarder.existing(in: repo.context).map(\.id)
        }
        #expect(survivors == [a, a])
    }

    @Test("An empty library earns nothing and writes nothing")
    func emptyLibraryWritesNothing() {
        let repo = store()
        let result = BadgeAwarder.award(in: repo.context)
        #expect(result.newlyEarned.isEmpty)
        #expect(BadgeAwarder.existing(in: repo.context).isEmpty)
    }
}
