import Foundation
import SwiftData

/// Gathers what a `Replay` reads, so the engine itself stays a pure function
/// of its inputs and can be tested without a store.
///
/// The badge dates come from the ledger rather than from re-running the rules:
/// a replay says when you earned something, and the ledger is the only record
/// of that which cannot drift.
@MainActor
enum ReplayBuilder {

    static func source(in context: ModelContext) -> Replay.Source {
        let games = ((try? context.fetch(FetchDescriptor<Game>())) ?? [])
            .filter { $0.deletedAt == nil }
        let completions = ((try? context.fetch(FetchDescriptor<CompletionEvent>())) ?? [])
            .filter { $0.deletedAt == nil }
        let memories = ((try? context.fetch(FetchDescriptor<Memory>())) ?? [])
            .filter { $0.deletedAt == nil }
        let earned = ((try? context.fetch(FetchDescriptor<EarnedBadge>())) ?? [])
            .filter { $0.deletedAt == nil }

        return Replay.Source(
            games: games,
            completions: completions,
            memories: memories,
            // Earliest wins: CloudKit sync twins are two rows with one badge
            // id, and a replay should date a badge from when it was earned
            // rather than from whichever copy came back last.
            badgeDates: Dictionary(earned.map { ($0.badgeID, $0.earnedAt) },
                                   uniquingKeysWith: min))
    }

    /// Which periods are worth offering, newest first.
    ///
    /// Only periods with something in them: a picker full of empty months is
    /// a list of reproaches, and the whole point of a recap is that there is
    /// something to recap.
    static func availableSpans(in context: ModelContext,
                               calendar: Calendar = .current,
                               now: Date = .now) -> [Replay.Span] {
        let source = source(in: context)
        var spans: [Replay.Span] = []

        // This month and this quarter lead when they have anything, then
        // every year back to the earliest thing recorded.
        for span in [Replay.Span.month(now), .quarter(now)] {
            if !Replay.make(span, from: source, calendar: calendar, now: now).isEmpty {
                spans.append(span)
            }
        }

        // **Everything a replay can show, not just what arrived when.** This
        // looked only at when games were added, finished and remembered — so
        // a game added this year with sessions in 2020, or Steam hours placed
        // in 2020, made a 2020 replay that `make` would happily build and
        // this list would never offer (Codex, build 40, 09-21).
        let sessionStarts = source.games
            .flatMap(\.livePlaythroughs)
            .flatMap { ($0.sessions ?? []).filter { $0.deletedAt == nil } }
            .map(\.startDate)
        let placedYears = source.games
            .flatMap(\.livePlaythroughs)
            .flatMap(\.carriedOverSpans)
            .compactMap { calendar.date(from: DateComponents(year: $0.fromYear, month: 1, day: 1)) }
        let earliest = [
            source.games.map(\.addedAt).min(),
            source.completions.map(\.date).min(),
            source.memories.map(\.createdAt).min(),
            sessionStarts.min(),
            placedYears.min(),
            source.badgeDates.values.min(),
        ].compactMap { $0 }.min() ?? now

        let firstYear = calendar.component(.year, from: earliest)
        let thisYear = calendar.component(.year, from: now)
        for year in stride(from: thisYear, through: firstYear, by: -1) {
            var components = DateComponents()
            components.year = year
            components.month = 6
            components.day = 15
            guard let inYear = calendar.date(from: components) else { continue }
            let span = Replay.Span.year(inYear)
            if !Replay.make(span, from: source, calendar: calendar, now: now).isEmpty {
                spans.append(span)
            }
        }
        return spans
    }
}
