import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import LevelSelect

/// Build 37 — F1, A4 and B4.
///
/// Three answers from Tim's open questions, and what each is actually
/// promising:
///
/// - **F1** — after the welcome, Home carries the welcome's own promises into
///   its empty shelves. The thing worth pinning is that they are the SAME
///   strings, because the whole point was that the two screens read as one
///   product; a copy that drifts is the bug.
/// - **A4** — custom status colors reach the widgets and the Watch, and — just
///   as importantly — a status nobody has touched sends nothing, so no one's
///   Home Screen changes color because the feature shipped.
/// - **B4** — at accessibility sizes the year heatmap becomes twelve month
///   summaries. The written line and the spoken one come off one type.
@MainActor
struct Build37PromiseAndThemeReachTests {

    // MARK: F1 — the welcome's promises, on the shelves

    /// Every promise that claims a shelf claims a Home shelf, and the privacy
    /// promise claims none. A promise pointing at Backlog would put a welcome
    /// line on a screen the welcome never mentions.
    @Test func promisesPointAtHomeShelves() {
        for promise in AppPromise.allCases {
            guard let shelf = promise.shelf else {
                #expect(promise == .privacy)
                continue
            }
            #expect(GameStatus.homeOrder.contains(shelf),
                    "\(promise) points at \(shelf), which Home does not draw")
        }
    }

    /// No two promises share a shelf — otherwise one silently never appears.
    @Test func eachShelfClaimedOnce() {
        let claimed = AppPromise.allCases.compactMap(\.shelf)
        #expect(claimed.count == Set(claimed).count)
    }

    /// **One home, not one sentence.** This asserted the caption was the
    /// promise verbatim, which was the wrong invariant: it made Paused say
    /// "Start from the app, a widget, your watch, or the Lock Screen" and Up
    /// Next say "Import real achievements…", neither of which is about pausing
    /// or queueing. Fable caught it on 2026-09-07.
    ///
    /// What actually has to hold is that both surfaces read from the same
    /// file, so editing one screen cannot leave the other behind — and that
    /// every shelf with a promise says something.
    @Test func everyPromisedShelfSpeaksFromTheSameFile() {
        for promise in AppPromise.allCases {
            guard let shelf = promise.shelf else { continue }
            #expect(shelf.emptyShelfCaption == promise.shelfCaption)
            #expect(!(promise.shelfCaption ?? "").isEmpty)
        }
    }

    /// The one promise that IS about its shelf still says it unchanged — the
    /// welcome and Home really are the same sentence there.
    @Test func theShelfPromiseIsStillVerbatim() {
        #expect(AppPromise.shelf.shelfCaption == AppPromise.shelf.body)
        #expect(GameStatus.playing.emptyShelfCaption == AppPromise.shelf.body)
    }

    /// And the two that are not must not silently drift BACK to the welcome's
    /// wording — that is the regression this whole change exists to prevent.
    @Test func theOtherTwoSayTheirOwnShelf() {
        #expect(AppPromise.sessions.shelfCaption != AppPromise.sessions.body)
        #expect(AppPromise.checklist.shelfCaption != AppPromise.checklist.body)
        // Each names what its shelf is for.
        #expect(GameStatus.paused.emptyShelfCaption?.contains("stepped away") == true)
        #expect(GameStatus.queued.emptyShelfCaption?.contains("next") == true)
    }

    /// Every shelf Home draws has something to say while it is empty. A silent
    /// shelf sitting between three captioned ones reads as a rendering bug.
    @Test func everyHomeShelfHasACaption() {
        for status in GameStatus.homeOrder {
            let caption = status.emptyShelfCaption
            #expect(caption != nil, "\(status) has no empty-shelf caption")
            #expect(!(caption ?? "").isEmpty)
        }
    }

    /// A status Home does not draw gets no caption — there is nowhere to put
    /// one, and inventing copy for it is how dead strings accumulate.
    @Test func nonHomeStatusesHaveNoCaption() {
        let offHome = GameStatus.allCases.filter { !GameStatus.homeOrder.contains($0) }
        for status in offHome {
            #expect(status.emptyShelfCaption == nil, "\(status) captions a shelf Home never draws")
        }
    }

    // MARK: A4 — custom status colors reaching the widgets

    /// Nothing chosen, nothing sent. This is what keeps an existing Home
    /// Screen exactly as it was: the widgets fall back to their own built-in
    /// colors, which they can only do if the map is empty.
    @Test func untouchedStatusesSendNothing() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let settings = ThemeSettings()
        context.insert(settings)
        ThemePalette.refresh(from: settings)
        #expect(ThemePalette.statusColorHexes.isEmpty)
    }

    /// A chosen color travels, and only that one.
    @Test func chosenStatusColorTravelsAlone() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let settings = ThemeSettings()
        settings.statusColors = ["paused": "#FF0000"]
        context.insert(settings)
        ThemePalette.refresh(from: settings)

        let sent = ThemePalette.statusColorHexes
        #expect(sent.count == 1)
        #expect(sent["paused"]?.uppercased() == "#FF0000")
        #expect(sent["playing"] == nil)
    }

    /// A status color that isn't a color is dropped rather than shipped as
    /// garbage — the widget would fail to parse it and fall back anyway, but
    /// it should never leave the app in the first place.
    @Test func unparseableStatusColorIsNotSent() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let settings = ThemeSettings()
        settings.statusColors = ["paused": "not a color"]
        context.insert(settings)
        ThemePalette.refresh(from: settings)
        #expect(ThemePalette.statusColorHexes["paused"] == nil)
    }

    /// The snapshot carries the map across the process boundary intact.
    @Test func snapshotRoundTripsStatusColors() throws {
        let snapshot = Self.snapshot(statusColors: ["paused": "#FF0000", "playing": "#00FF00"])
        let data = try JSONEncoder.iso8601.encode(snapshot)
        let decoded = try JSONDecoder.iso8601.decode(WidgetSnapshot.self, from: data)
        #expect(decoded.statusColors == ["paused": "#FF0000", "playing": "#00FF00"])
    }

    /// A snapshot written by a build that predates this field still decodes —
    /// the widget extension reads whatever file is on disk, and on the first
    /// launch after an update that file is always the old one.
    @Test func olderSnapshotWithoutStatusColorsStillDecodes() throws {
        let snapshot = Self.snapshot(statusColors: ["paused": "#FF0000"])
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder.iso8601.encode(snapshot)) as? [String: Any] ?? [:]
        json.removeValue(forKey: "statusColors")
        let stripped = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder.iso8601.decode(WidgetSnapshot.self, from: stripped)
        #expect(decoded.statusColors.isEmpty)
        #expect(decoded.gameName == "Hades")
    }

    // MARK: B4 — twelve months in words

    /// A month with play in it says how many days and how long, in both forms.
    @Test func monthLoadDescribesABusyMonth() {
        let calendar = JournalBuilder.calendar
        let month = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let load: [Date: DayLoad] = [
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: 2, to: month)!):
                DayLoad(seconds: 3600, entries: 1),
            calendar.startOfDay(for: calendar.date(byAdding: .day, value: 9, to: month)!):
                DayLoad(seconds: 1800, entries: 2),
        ]
        let summary = MonthLoad(month: month, calendar: calendar, load: load)

        #expect(summary.activeDays == 2)
        #expect(summary.seconds == 5400)
        #expect(!summary.isEmpty)
        #expect(summary.detail.hasPrefix("2 days · "))
        #expect(summary.spoken.hasPrefix("March 2026, 2 days, "))
    }

    /// One day is "day", not "days". The grid has said this to VoiceOver for
    /// builds; now it is also on screen, where a plural error is visible.
    @Test func oneDayIsSingular() {
        let calendar = JournalBuilder.calendar
        let month = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let load: [Date: DayLoad] = [
            calendar.startOfDay(for: month): DayLoad(seconds: 0, entries: 1)
        ]
        let summary = MonthLoad(month: month, calendar: calendar, load: load)
        #expect(summary.detail == "1 day")
        #expect(summary.spoken == "March 2026, 1 day")
    }

    /// An empty month is still listed, and says so. Dropping it would leave a
    /// year with holes in it, which reads as a bug rather than as a quiet year.
    @Test func emptyMonthSaysNothingRecorded() {
        let calendar = JournalBuilder.calendar
        let month = calendar.date(from: DateComponents(year: 1995, month: 7, day: 1))!
        let summary = MonthLoad(month: month, calendar: calendar, load: [:])
        #expect(summary.isEmpty)
        #expect(summary.detail == "Nothing recorded")
        #expect(summary.spoken == "July 1995, nothing recorded")
    }

    /// A day recorded with no time on it counts as a day and claims no hours —
    /// a memory written against a date is exactly this case.
    @Test func aDayWithNoTimeCountsButSaysNoDuration() {
        let calendar = JournalBuilder.calendar
        let month = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let load: [Date: DayLoad] = [
            calendar.startOfDay(for: month): DayLoad(seconds: 0, entries: 1)
        ]
        let summary = MonthLoad(month: month, calendar: calendar, load: load)
        #expect(summary.seconds == 0)
        #expect(!summary.detail.contains("·"))
    }

    /// The day walk survives a spring-forward month.
    ///
    /// The obvious implementation — add N days to the 1st — silently produces
    /// 1 a.m. timestamps in a month with a 23-hour day, which then miss the
    /// start-of-day keys `load` is built on and lose a day's play. Walking the
    /// month's own interval is why this passes.
    @Test func dayWalkHandlesDaylightSaving() {
        var calendar = JournalBuilder.calendar
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // March 2026: DST starts on the 8th in the US.
        let march = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let days = MonthLoad.days(of: march, calendar: calendar)

        #expect(days.count == 31)
        #expect(Set(days).count == 31)
        for day in days {
            #expect(day == calendar.startOfDay(for: day))
        }
    }

    /// Twelve months, every one of them, whatever the year.
    @Test func aYearIsTwelveMonths() {
        let calendar = JournalBuilder.calendar
        let months = (1...12).compactMap {
            calendar.date(from: DateComponents(year: 2026, month: $0, day: 1))
        }
        #expect(months.count == 12)
        let summaries = months.map { MonthLoad(month: $0, calendar: calendar, load: [:]) }
        let emptyCount = summaries.filter(\.isEmpty).count
        #expect(emptyCount == 12)
        #expect(Set(summaries.map(\.spoken)).count == 12)
    }

    // MARK: Fixtures

    private static func snapshot(statusColors: [String: String]) -> WidgetSnapshot {
        WidgetSnapshot(
            gameID: "g1", gameName: "Hades", statusRaw: "playing",
            isPlaying: true, isPaused: false, playtimeSeconds: 60,
            lastPlayedAt: nil, nextObjective: nil, nextObjectiveID: nil,
            completionDone: 0, completionTotal: 0, coverFileName: nil,
            activeSessionID: nil, generatedAt: .init(timeIntervalSince1970: 0),
            objectives: [], nowPlaying: [], weeklySeconds: [],
            gamesPlayedThisWeek: 0, runGame: nil,
            statusColors: statusColors)
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}
