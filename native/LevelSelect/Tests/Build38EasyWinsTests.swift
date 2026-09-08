import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Build 38's small wins, each pinned: memories reach Recently Deleted, the
/// question card waits a day, and a dead layout value repairs itself.
@MainActor
struct Build38EasyWinsTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func memory(in repo: Repository, title: String = "First LAN party",
                        pictures: Int = 0) -> Memory {
        let memory = Memory(title: title, earliest: .now, latest: .now)
        repo.context.insert(memory)
        for i in 0..<pictures {
            let image = GameImage(data: Data(repeating: UInt8(i), count: 64))
            image.memory = memory
            repo.context.insert(image)
        }
        try? repo.context.save()
        return memory
    }

    // MARK: Recently Deleted holds memories

    @Test("A deleted memory is listed, newest first")
    func deletedMemoryIsListed() {
        let repo = store()
        let older = memory(in: repo, title: "Older")
        let newer = memory(in: repo, title: "Newer")
        repo.deleteMemory(older, at: .now.addingTimeInterval(-60))
        repo.deleteMemory(newer)
        #expect(repo.trashedMemories().map(\.title) == ["Newer", "Older"])
    }

    @Test("Restoring a memory brings back the pictures that left with it, and only those")
    func restoreBringsItsPicturesBack() {
        let repo = store()
        let memory = memory(in: repo, pictures: 2)
        // One picture was removed on its own, a minute earlier — the person
        // chose that, and a restore of the memory must not undo it.
        let removedFirst = (memory.images ?? [])[0]
        repo.softDelete(removedFirst, at: .now.addingTimeInterval(-60))
        repo.deleteMemory(memory)
        #expect((memory.images ?? []).allSatisfy { $0.deletedAt != nil })

        repo.restore(memory)
        #expect(memory.deletedAt == nil)
        let live = (memory.images ?? []).filter { $0.deletedAt == nil }
        #expect(live.count == 1)
        #expect(removedFirst.deletedAt != nil)
    }

    @Test("A memory's pictures are not listed separately while it is in the trash")
    func picturesRideWithTheMemory() {
        let repo = store()
        let memory = memory(in: repo, pictures: 1)
        repo.deleteMemory(memory)
        #expect(repo.trashedImages().isEmpty)
        #expect(repo.trashedMemories().count == 1)
    }

    @Test("A memory deleted long ago goes for good, pictures included")
    func expiredMemoryPurges() {
        let repo = store()
        let memory = memory(in: repo, pictures: 1)
        repo.deleteMemory(memory, at: .now.addingTimeInterval(-Repository.trashRetention - 60))
        #expect(repo.purgeExpiredTrash() == 1)
        #expect(((try? repo.context.fetch(FetchDescriptor<Memory>())) ?? []).isEmpty)
        #expect(((try? repo.context.fetch(FetchDescriptor<GameImage>())) ?? []).isEmpty)
    }

    @Test("Delete Forever removes the memory and its pictures")
    func deleteForeverCascades() {
        let repo = store()
        let memory = memory(in: repo, pictures: 2)
        repo.deleteMemory(memory)
        repo.deleteForever(memory)
        #expect(((try? repo.context.fetch(FetchDescriptor<Memory>())) ?? []).isEmpty)
        #expect(((try? repo.context.fetch(FetchDescriptor<GameImage>())) ?? []).isEmpty)
    }

    // MARK: The question card waits a day

    @Test("No games, no questions")
    func emptyLibraryIsNeverAsked() {
        #expect(!BetaQuestionCard.isTimeToAsk(firstGameAdded: nil))
    }

    @Test("A game added four minutes ago is not enough")
    func freshLibraryWaits() {
        let now = Date()
        #expect(!BetaQuestionCard.isTimeToAsk(firstGameAdded: now.addingTimeInterval(-240), now: now))
    }

    @Test("A day after the first game, the card may appear")
    func aDayLaterItAsks() {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-BetaQuestionCard.settlingPeriod)
        #expect(BetaQuestionCard.isTimeToAsk(firstGameAdded: dayAgo, now: now))
        #expect(!BetaQuestionCard.isTimeToAsk(firstGameAdded: dayAgo.addingTimeInterval(1), now: now))
    }

    // MARK: A dead layout value repairs itself

    @Test("A stored 'banner' layout becomes showcase, once")
    func bannerBecomesShowcase() {
        let repo = store()
        let settings = ThemeSettings()
        settings.gamePageLayoutRaw = "banner"
        repo.context.insert(settings)
        try? repo.context.save()

        #expect(repo.repairDeadPreferenceValues() == 1)
        #expect(settings.gamePageLayoutRaw == GamePageLayout.showcase.rawValue)
        #expect(repo.repairDeadPreferenceValues() == 0)
    }

    @Test("A live layout value is left alone")
    func liveValueUntouched() {
        let repo = store()
        let settings = ThemeSettings()
        settings.gamePageLayoutRaw = GamePageLayout.classic.rawValue
        repo.context.insert(settings)
        try? repo.context.save()
        #expect(repo.repairDeadPreferenceValues() == 0)
        #expect(settings.gamePageLayoutRaw == GamePageLayout.classic.rawValue)
    }
}

/// A memory written in the evening is filed on the day it was written.
@MainActor
struct Build38MemoryDayTests {

    private var newYork: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private var tokyo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        Memory.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test("22:30 in New York on the 7th is the 7th, not the 8th")
    func lateEveningStaysOnItsDay() {
        // 02:30 UTC on the 8th is 22:30 EDT on the 7th.
        let instant = utc(2026, 9, 8, 2).addingTimeInterval(30 * 60)
        let day = Memory.utcDay(fromLocal: instant, local: newYork)
        #expect(day == utc(2026, 9, 7))
    }

    @Test("Local midnight east of Greenwich is still that day")
    func tokyoMidnightStaysOnItsDay() {
        // 00:00 JST on the 7th is 15:00 UTC on the 6th — the calendar tap
        // hands the sheet exactly this instant.
        let localMidnight = tokyo.date(from: DateComponents(year: 2026, month: 9, day: 7))!
        #expect(Memory.utcDay(fromLocal: localMidnight, local: tokyo) == utc(2026, 9, 7))
    }

    @Test("A stored UTC day round-trips through the picker unchanged")
    func roundTrip() {
        let stored = utc(1995, 12, 25)
        for cal in [newYork, tokyo] {
            let shown = Memory.localDay(fromUTC: stored, local: cal)
            #expect(cal.dateComponents([.year, .month, .day], from: shown)
                    == DateComponents(year: 1995, month: 12, day: 25))
            #expect(Memory.utcDay(fromLocal: shown, local: cal) == stored)
        }
    }
}
