import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Recently Deleted empties itself after thirty days.
///
/// It never used to. The screen shipped with a comment calling a retention
/// window "a policy to decide with testers, not a default to guess at", and
/// then nobody decided it for ten builds. Tim did: *"I don't see why we have
/// to have an endless buildup of data that they already said they wanted to
/// delete. Especially because this is in their personal iCloud."*
@MainActor
struct TrashRetentionTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private let window = Repository.trashRetention

    @Test func thirtyDaysIsTheWindow() {
        #expect(Repository.trashRetention == 30 * 24 * 60 * 60)
    }

    @Test func somethingDeletedLongAgoGoesForGood() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.softDelete(game, at: .now.addingTimeInterval(-window - 60))

        #expect(repo.purgeExpiredTrash() == 1)
        #expect(repo.trashedGames().isEmpty)
        #expect(((try? repo.context.fetch(FetchDescriptor<Game>())) ?? []).isEmpty)
    }

    /// The day before the deadline is still the user's to change their mind
    /// about. An off-by-one here deletes a library a day early.
    @Test func somethingDeletedYesterdayStays() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.softDelete(game, at: .now.addingTimeInterval(-24 * 60 * 60))

        #expect(repo.purgeExpiredTrash() == 0)
        #expect(repo.trashedGames().count == 1)
    }

    /// **Restoring resets the clock**, by construction rather than by a second
    /// timestamp: the sweep only ever looks at rows that still have a
    /// `deletedAt`, and restore clears it.
    @Test func restoringResetsTheClock() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        repo.softDelete(game, at: .now.addingTimeInterval(-window - 60))
        repo.restore(game)

        #expect(repo.purgeExpiredTrash() == 0)

        // And deleting it again starts the thirty days over.
        repo.softDelete(game)
        #expect(repo.purgeExpiredTrash() == 0)
        #expect(repo.trashedGames().count == 1)
    }

    /// A picture is the reason the window matters — it is the only thing here
    /// that costs real bytes in someone's iCloud.
    @Test func anExpiredPictureAndItsBytesGo() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let image = GameImage(data: Data(repeating: 9, count: 4096))
        repo.context.insert(image)
        image.game = game
        repo.softDelete(image, at: .now.addingTimeInterval(-window - 60))

        #expect(repo.purgeExpiredTrash() == 1)
        #expect(((try? repo.context.fetch(FetchDescriptor<GameImage>())) ?? []).isEmpty)
        // The game itself was never deleted and must not be touched.
        #expect(repo.trashedGames().isEmpty)
        #expect(game.deletedAt == nil)
    }

    /// An expired game takes its children with it in one step rather than
    /// leaving them for a later sweep to find as orphans.
    @Test func anExpiredGameTakesItsChildrenWithIt() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let image = GameImage(data: Data(repeating: 1, count: 64))
        repo.context.insert(image)
        image.game = game
        _ = pt

        repo.softDelete(game, at: .now.addingTimeInterval(-window - 60))
        _ = repo.purgeExpiredTrash()

        #expect(((try? repo.context.fetch(FetchDescriptor<Game>())) ?? []).isEmpty)
        #expect(((try? repo.context.fetch(FetchDescriptor<Playthrough>())) ?? []).isEmpty)
        #expect(((try? repo.context.fetch(FetchDescriptor<GameImage>())) ?? []).isEmpty)
    }

    /// Nothing to do is the normal case, and it must cost nothing and change
    /// nothing.
    @Test func aHealthyLibraryIsUntouched() {
        let repo = store()
        _ = repo.addGame(name: "Hollow Knight", status: .playing)
        _ = repo.addGame(name: "Hades", status: .paused)

        #expect(repo.purgeExpiredTrash() == 0)
        #expect(((try? repo.context.fetch(FetchDescriptor<Game>())) ?? []).count == 2)
    }
}
