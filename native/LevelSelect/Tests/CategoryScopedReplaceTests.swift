import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// "Regenerate just this category." The roadmap named it as the gap that
/// blocks stepped generation: the merge modes were whole-schema, and a
/// stepped run fills one category at a time without disturbing the ones
/// already accepted.
@MainActor
struct CategoryScopedReplaceTests {

    private func game() -> (Repository, Game, Playthrough) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        return (repo, game, repo.ensureDefaultPlaythrough(for: game))
    }

    private func schema(_ categories: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "categories": categories])
    }

    private func category(_ id: String, _ name: String, _ items: [(String, String)],
                          locked: Bool = false) -> [String: Any] {
        var cat: [String: Any] = ["id": id, "name": name, "type": "checklist",
                                  "items": items.map { ["id": $0.0, "name": $0.1] }]
        if locked { cat["locked"] = true }
        return cat
    }

    private func items(_ repo: Repository, _ game: Game, _ categoryID: String) -> [String] {
        repo.trackerCategories(for: game)
            .first { $0.id == categoryID }?.items.map(\.id) ?? []
    }

    /// The whole point: one category is rebuilt, the others are untouched.
    @Test func onlyTheNamedCategoryIsReplaced() {
        let (repo, game, _) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet")]),
            category("charms", "Charms", [("wayward", "Wayward Compass")]),
        ]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("grimm", "Grimm"), ("radiance", "Radiance")]),
            category("charms", "Charms", [("nothing", "Should be ignored")]),
        ]), mode: .replaceCategories(ids: ["bosses"]))

        #expect(items(repo, game, "bosses").sorted() == ["grimm", "radiance"])
        #expect(items(repo, game, "charms") == ["wayward"])   // untouched
    }

    /// Progress still follows a rename inside the category being rebuilt.
    @Test func progressMigratesForRenamesInsideTheScope() {
        let (repo, game, pt) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet")]),
        ]), mode: .addAll)
        repo.setTrackerItem(pt, itemID: "hornet", done: true)

        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("boss-hornet", "Hornet")]),
        ]), mode: .replaceCategories(ids: ["bosses"]))

        #expect(outcome.migrated == 1)
        #expect(repo.trackerState(pt, itemID: "boss-hornet")?.completed == true)
    }

    /// And progress in a category the step never touched is neither migrated
    /// nor reported as lost — claiming either would be a lie about work that
    /// did not happen.
    @Test func untouchedCategoriesAreNotReportedAsChanged() {
        let (repo, game, pt) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet")]),
            category("charms", "Charms", [("wayward", "Wayward Compass")]),
        ]), mode: .addAll)
        repo.setTrackerItem(pt, itemID: "wayward", done: true)

        // The incoming payload omits Charms entirely — under a full Replace
        // that would strand it; scoped to Bosses it must not.
        let outcome = repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("grimm", "Grimm")]),
        ]), mode: .replaceCategories(ids: ["bosses"]))

        #expect(outcome.lostProgress.isEmpty)
        #expect(items(repo, game, "charms") == ["wayward"])
        #expect(repo.trackerState(pt, itemID: "wayward")?.completed == true)
    }

    /// A user's own note survives the rebuild, exactly as under a full
    /// Replace — the carry is the same tested code path.
    @Test func userNotesSurviveAScopedRebuild() {
        let (repo, game, _) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet")]),
        ]), mode: .addAll)
        _ = repo.editTrackerItem(game, categoryID: "bosses", itemID: "hornet",
                                 name: nil, location: nil, note: "dash to dodge")

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet"), ("grimm", "Grimm")]),
        ]), mode: .replaceCategories(ids: ["bosses"]))

        let hornet = repo.trackerCategories(for: game).flatMap(\.items).first { $0.id == "hornet" }
        #expect(hornet?.note == "dash to dodge")
    }

    /// Locked categories and Personal Goals are the user's own content:
    /// naming one in the scope must still not overwrite it.
    @Test func lockedCategoriesAreNeverReplacedEvenWhenNamed() {
        let (repo, game, _) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("pasted", "My List", [("mine", "My item")], locked: true),
        ]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("pasted", "My List", [("theirs", "Generated junk")]),
        ]), mode: .replaceCategories(ids: ["pasted"]))

        #expect(items(repo, game, "pasted") == ["mine"])
    }

    /// A category the incoming payload doesn't mention is left alone rather
    /// than emptied — "regenerate this" that returns nothing must not wipe it.
    @Test func aScopedCategoryMissingFromThePayloadIsLeftAlone() {
        let (repo, game, _) = self.game()
        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("bosses", "Bosses", [("hornet", "Hornet")]),
        ]), mode: .addAll)

        repo.applyGeneratedSchema(for: game, jsonData: schema([
            category("charms", "Charms", [("wayward", "Wayward Compass")]),
        ]), mode: .replaceCategories(ids: ["bosses"]))

        #expect(items(repo, game, "bosses") == ["hornet"])
    }
}
