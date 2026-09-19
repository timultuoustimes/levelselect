import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// `ongoing` — a game with no finish line.
///
/// Minecraft, a city builder, a live-service game someone drifts back to for a
/// fortnight twice a year. Every existing status implies a finish line the game
/// doesn't have: "playing" isn't true in the gap, "paused" implies resuming a
/// run, "completed" is a category error, and "shelved" is wrong for something
/// you'll open again next month.
///
/// It costs no schema version — `status` is a String attribute and this is a
/// new value in it, exactly as `wishlist` was — so the load-bearing tests are
/// that the value survives a real store round trip and that nothing which
/// enumerates statuses quietly leaves it out.
@MainActor
struct OngoingStatusTests {

    private func repo() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @Test func aGameCanBeOngoingAndStaysThatWay() {
        let repo = self.repo()
        let game = repo.addGame(name: "Minecraft", status: .ongoing)
        #expect(game.status == .ongoing)

        repo.edit(game) { $0.status = .playing }
        repo.edit(game) { $0.status = .ongoing }
        #expect(game.status == .ongoing)
    }

    /// The raw value is what lands in the store and in CloudKit. Pinning it
    /// stops a later rename from silently orphaning every ongoing game.
    @Test func theStoredValueIsExactlyOngoing() {
        #expect(GameStatus.ongoing.rawValue == "ongoing")
        #expect(GameStatus(rawValue: "ongoing") == .ongoing)
    }

    /// Every status picker in the app is built from `allCases`, and every
    /// grouped list from `displayOrder`. A status missing from either exists
    /// in the model and nowhere a person can reach it.
    @Test func ongoingAppearsInBothStatusListings() {
        #expect(GameStatus.allCases.contains(.ongoing))
        #expect(GameStatus.displayOrder.contains(.ongoing))
        // Every case is orderable, or a game with that status silently drops
        // out of Home and the grouped library.
        #expect(Set(GameStatus.displayOrder) == Set(GameStatus.allCases))
    }

    /// It sits with the games you're actually playing, not below the finished
    /// pile — burying it would defeat the point of having the status.
    @Test func ongoingSitsNearTheTop() {
        let order = GameStatus.displayOrder
        let ongoing = order.firstIndex(of: .ongoing)!
        #expect(ongoing == 1)
        #expect(ongoing < order.firstIndex(of: .backlog)!)
        #expect(ongoing < order.firstIndex(of: .completed)!)
    }

    /// Sessions and trackers don't care what the status is, but it's worth
    /// pinning that an ongoing game is a full citizen rather than a label —
    /// these are games people log the most hours against.
    @Test func anOngoingGameLogsTimeLikeAnyOther() {
        let repo = self.repo()
        let game = repo.addGame(name: "Cities: Skylines", status: .ongoing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let session = repo.startSession(on: pt)
        repo.stopSession(session)

        #expect((pt.sessions ?? []).filter { $0.deletedAt == nil }.count == 1)
        #expect(game.status == .ongoing)
    }
}
