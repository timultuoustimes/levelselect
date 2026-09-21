import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// The recap engine: one walk over sessions, completions and the ledger for a
/// date range, serving month, quarter and year alike.
@MainActor
struct ReplayTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    /// A fixed calendar so a test of the rule is not a test of the machine's
    /// time zone.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Sessions are inserted through the repository so they carry the same
    /// shape the app writes.
    @discardableResult
    private func play(_ repo: Repository, _ game: Game,
                      from start: Date, hours: Double) -> Session {
        let playthrough = game.activePlaythrough ?? repo.addPlaythrough(to: game, named: "Main")
        let session = Session(startDate: start)
        session.endDate = start.addingTimeInterval(hours * 3600)
        session.accumulatedDuration = hours * 3600
        session.state = .stopped
        session.playthrough = playthrough
        repo.context.insert(session)
        return session
    }

    private func source(_ repo: Repository, badges: [String: Date] = [:]) -> Replay.Source {
        Replay.Source(
            games: (try? repo.context.fetch(FetchDescriptor<Game>())) ?? [],
            completions: (try? repo.context.fetch(FetchDescriptor<CompletionEvent>())) ?? [],
            memories: (try? repo.context.fetch(FetchDescriptor<Memory>())) ?? [],
            badgeDates: badges)
    }

    // MARK: The span

    @Test("A quarter runs three months, whichever month you ask from")
    func quarterCoversThreeMonths() {
        for month in [7, 8, 9] {
            let interval = Replay.Span.quarter(date(2026, month, 15)).interval(calendar)
            #expect(interval.start == date(2026, 7, 1, 0))
            #expect(interval.end == date(2026, 10, 1, 0))
        }
    }

    @Test("A span knows what to call itself")
    func spansAreNamed() {
        #expect(Replay.Span.year(date(2026, 3, 4)).title(calendar) == "2026")
        #expect(Replay.Span.quarter(date(2026, 8, 4)).title(calendar) == "Q3 2026")
        #expect(Replay.Span.month(date(2026, 8, 4)).title(calendar) == "August 2026")
    }

    // MARK: What it counts

    @Test("Play inside the period is counted; play outside it is not")
    func countsOnlyThePeriod() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight")
        play(repo, game, from: date(2026, 3, 2), hours: 2)
        play(repo, game, from: date(2025, 12, 2), hours: 40)   // the year before

        let replay = Replay.make(.year(date(2026, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.sessionCount == 1)
        #expect(abs(replay.totalSeconds - 2 * 3600) < 1)
        #expect(replay.played.map(\.name) == ["Hollow Knight"])
    }

    /// A session begun on New Year's Eve and stopped after midnight is not
    /// four hours of January.
    @Test("A session straddling the boundary is split, not double-counted")
    func straddlingSessionIsClipped() {
        let repo = store()
        let game = repo.addGame(name: "Celeste")
        // 22:00 on 31 December, four hours long: two in each year.
        play(repo, game, from: date(2025, 12, 31, 22), hours: 4)

        let old = Replay.make(.year(date(2025, 6, 1)), from: source(repo),
                              calendar: calendar, now: date(2026, 12, 31))
        let new = Replay.make(.year(date(2026, 6, 1)), from: source(repo),
                              calendar: calendar, now: date(2026, 12, 31))
        #expect(abs(old.totalSeconds - 2 * 3600) < 60)
        #expect(abs(new.totalSeconds - 2 * 3600) < 60)
        #expect(abs((old.totalSeconds + new.totalSeconds) - 4 * 3600) < 60)
    }

    @Test("Games are ranked by how much of the period they had")
    func playedIsRankedByTime()  {
        let repo = store()
        let little = repo.addGame(name: "A little")
        let lots = repo.addGame(name: "A lot")
        play(repo, little, from: date(2026, 3, 2), hours: 1)
        play(repo, lots, from: date(2026, 3, 3), hours: 9)
        play(repo, lots, from: date(2026, 4, 3), hours: 2)

        let replay = Replay.make(.year(date(2026, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.played.map(\.name) == ["A lot", "A little"])
        #expect(replay.played.first?.sessions == 2)
        #expect(replay.gamesPlayedCount == 2)
    }

    @Test("Days played counts days, not sessions")
    func daysPlayedCountsDays() {
        let repo = store()
        let game = repo.addGame(name: "Tunic")
        play(repo, game, from: date(2026, 3, 2, 9), hours: 1)
        play(repo, game, from: date(2026, 3, 2, 20), hours: 1)   // same day
        play(repo, game, from: date(2026, 3, 5), hours: 1)

        let replay = Replay.make(.year(date(2026, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.sessionCount == 3)
        #expect(replay.daysPlayed == 2)
        #expect(replay.busiestDay?.day == calendar.startOfDay(for: date(2026, 3, 2)))
        #expect(abs((replay.busiestDay?.seconds ?? 0) - 2 * 3600) < 1)
    }

    @Test("A finish inside the period is listed with the label you gave it")
    func finishesAreListed() {
        let repo = store()
        let game = repo.addGame(name: "Outer Wilds")
        repo.addCompletion(to: game, label: .cleared, date: date(2026, 5, 9))
        repo.addCompletion(to: game, label: .cleared, date: date(2024, 5, 9))

        let replay = Replay.make(.year(date(2026, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.finished.count == 1)
        #expect(replay.finished.first?.name == "Outer Wilds")
        #expect(replay.finished.first?.label == CompletionLabel.cleared.display)
    }

    @Test("Badges earned in the period come from the ledger's own dates")
    func badgesComeFromTheLedger() {
        let repo = store()
        _ = repo.addGame(name: "Hades")
        let replay = Replay.make(
            .year(date(2026, 6, 1)),
            from: source(repo, badges: ["first.beaten": date(2026, 2, 2),
                                        "first.session": date(2019, 2, 2)]),
            calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.badges.map(\.id) == ["first.beaten"])
    }

    /// A recap of a month you didn't play is a reproach, not a gift — the
    /// screen needs to be able to ask.
    @Test("A period with nothing in it says so")
    func emptyPeriodKnowsItIsEmpty() {
        let repo = store()
        let game = repo.addGame(name: "Chrono Trigger")
        play(repo, game, from: date(2020, 3, 2), hours: 3)

        let replay = Replay.make(.month(date(2026, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.isEmpty)
        #expect(replay.totalSeconds == 0)
    }

    @Test("A month sees its own month and not the quarter around it")
    func monthIsNarrowerThanQuarter() {
        let repo = store()
        let game = repo.addGame(name: "Balatro")
        play(repo, game, from: date(2026, 7, 5), hours: 3)
        play(repo, game, from: date(2026, 8, 5), hours: 5)

        let july = Replay.make(.month(date(2026, 7, 20)), from: source(repo),
                               calendar: calendar, now: date(2026, 12, 31))
        let quarter = Replay.make(.quarter(date(2026, 7, 20)), from: source(repo),
                                  calendar: calendar, now: date(2026, 12, 31))
        #expect(abs(july.totalSeconds - 3 * 3600) < 1)
        #expect(abs(quarter.totalSeconds - 8 * 3600) < 1)
    }

    // MARK: Carried-over time, attributed by hand

    /// Steam reports one lifetime number with no dates. The person can say
    /// which year it was — Tim, 09-21: *"I know I played cities skylines the
    /// most in 2020-2021."*
    @Test("Imported hours placed in a year show up in that year's replay")
    func carriedTimeLandsInItsYear() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(300 * 3600, on: pt)
        repo.setCarriedOverSpans([CarriedOverSpan(seconds: 300 * 3600, fromYear: 2020)], on: pt, calendar: calendar)

        let hit = Replay.make(.year(date(2020, 6, 1)), from: source(repo),
                              calendar: calendar, now: date(2026, 12, 31))
        let miss = Replay.make(.year(date(2021, 6, 1)), from: source(repo),
                               calendar: calendar, now: date(2026, 12, 31))
        #expect(hit.carried.map(\.name) == ["Cities: Skylines"])
        #expect(miss.carried.isEmpty)
    }

    /// Tim, 09-21: *"I played more around 2021-2023, because I had stopped
    /// around the release date of cities skylines 2."* A range appears whole
    /// on every year it covers — it is not divided between them, because the
    /// last year is a part year and nobody said how much of it there was.
    @Test("A range shows whole on every year it covers, and is split between none")
    func rangeShowsOnEveryYearUndivided() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(300 * 3600, on: pt)
        repo.setCarriedOverSpans(
            [CarriedOverSpan(seconds: 300 * 3600, fromYear: 2021, toYear: 2023)],
            on: pt, calendar: calendar)

        for year in [2021, 2022, 2023] {
            let replay = Replay.make(.year(date(year, 6, 1)), from: source(repo),
                                     calendar: calendar, now: date(2026, 12, 31))
            #expect(replay.carried.count == 1)
            #expect(abs(replay.carriedSeconds - 300 * 3600) < 1)
            #expect(replay.carried.first?.span == "2021–2023")
            #expect(replay.carried.first?.isRange == true)
        }
        let outside = Replay.make(.year(date(2024, 6, 1)), from: source(repo),
                                  calendar: calendar, now: date(2026, 12, 31))
        #expect(outside.carried.isEmpty)
    }

    /// The other half: somebody who does know the split says it year by year,
    /// and each year gets its own real number.
    @Test("Per-year spans each land in their own year")
    func perYearSpansLandSeparately() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(300 * 3600, on: pt)
        repo.setCarriedOverSpans([
            CarriedOverSpan(seconds: 120 * 3600, fromYear: 2021),
            CarriedOverSpan(seconds: 150 * 3600, fromYear: 2022),
            CarriedOverSpan(seconds: 30 * 3600, fromYear: 2023),
        ], on: pt, calendar: calendar)

        let expected = [2021: 120.0, 2022: 150.0, 2023: 30.0]
        for (year, hours) in expected {
            let replay = Replay.make(.year(date(year, 6, 1)), from: source(repo),
                                     calendar: calendar, now: date(2026, 12, 31))
            #expect(replay.carried.count == 1)
            #expect(abs(replay.carriedSeconds - hours * 3600) < 1)
            #expect(replay.carried.first?.isRange == false)
        }
    }

    @Test("Hours left unplaced stay in the total and out of every year")
    func unplacedHoursStayUnplaced() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(300 * 3600, on: pt)
        repo.setCarriedOverSpans(
            [CarriedOverSpan(seconds: 120 * 3600, fromYear: 2021)],
            on: pt, calendar: calendar)

        #expect(abs(pt.unattributedCarriedSeconds - 180 * 3600) < 1)
        let replay = Replay.make(.year(date(2022, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.carried.isEmpty)
    }

    @Test("A span given backwards is read as the range it means")
    func backwardsRangeIsNormalised() {
        let span = CarriedOverSpan(seconds: 3600, fromYear: 2023, toYear: 2021)
        #expect(span.fromYear == 2021)
        #expect(span.toYear == 2023)
        #expect(span.label == "2021–2023")
    }

    /// It is a recollection, not a record: it must never be added to the
    /// hours that came from real sessions.
    @Test("Attributed hours stay out of the timed total")
    func carriedTimeIsNotAddedToTheTotal() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(300 * 3600, on: pt)
        repo.setCarriedOverSpans([CarriedOverSpan(seconds: 300 * 3600, fromYear: 2020)], on: pt, calendar: calendar)
        play(repo, game, from: date(2020, 5, 5), hours: 2)

        let replay = Replay.make(.year(date(2020, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(abs(replay.totalSeconds - 2 * 3600) < 1)
        #expect(abs(replay.carriedSeconds - 300 * 3600) < 1)
    }

    /// A year is the finest grain anybody has for these hours, so a month
    /// must not claim them.
    @Test("A month replay does not claim a year's attributed hours")
    func monthDoesNotClaimCarriedTime() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(300 * 3600, on: pt)
        repo.setCarriedOverSpans([CarriedOverSpan(seconds: 300 * 3600, fromYear: 2020)], on: pt, calendar: calendar)

        let month = Replay.make(.month(date(2020, 6, 1)), from: source(repo),
                                calendar: calendar, now: date(2026, 12, 31))
        let quarter = Replay.make(.quarter(date(2020, 6, 1)), from: source(repo),
                                  calendar: calendar, now: date(2026, 12, 31))
        #expect(month.carried.isEmpty)
        #expect(quarter.carried.isEmpty)
    }

    @Test("Taking the years back removes the hours from every replay")
    func clearingTheSpansRemovesThem() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOver(300 * 3600, on: pt)
        repo.setCarriedOverSpans([CarriedOverSpan(seconds: 300 * 3600, fromYear: 2020)],
                                 on: pt, calendar: calendar)
        repo.setCarriedOverSpans([], on: pt, calendar: calendar)

        let replay = Replay.make(.year(date(2020, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.carried.isEmpty)
        #expect(pt.carriedOverYear(calendar) == nil)
        // The hours themselves are untouched — only the claim about when.
        #expect(abs(pt.carriedOverSeconds - 300 * 3600) < 1)
        #expect(abs(pt.unattributedCarriedSeconds - 300 * 3600) < 1)
    }

    /// A span with no hours in it is not a claim about anything, and must not
    /// conjure a zero-hour line on a year.
    @Test("A year with no hours behind it says nothing")
    func yearWithoutHoursIsIgnored() {
        let repo = store()
        let game = repo.addGame(name: "Cities: Skylines")
        let pt = repo.addPlaythrough(to: game, named: "Steam")
        repo.setCarriedOverSpans([CarriedOverSpan(seconds: 0, fromYear: 2020)],
                                 on: pt, calendar: calendar)

        let replay = Replay.make(.year(date(2020, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.carried.isEmpty)
        // And nothing else put anything in 2020 either — the game was added
        // today — so the year stays empty rather than gaining a blank line.
        #expect(replay.isEmpty)
    }

    /// The library a replay describes is the one you have now: a game deleted
    /// since must not surface in last year's recap.
    @Test("A deleted game's finish is left out")
    func deletedGamesAreLeftOut() {
        let repo = store()
        let game = repo.addGame(name: "Gone")
        repo.addCompletion(to: game, label: .cleared, date: date(2026, 5, 9))
        game.deletedAt = .now

        let replay = Replay.make(.year(date(2026, 6, 1)), from: source(repo),
                                 calendar: calendar, now: date(2026, 12, 31))
        #expect(replay.finished.isEmpty)
    }
}
