import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// Two devices, two "single" records, and nothing lost when they meet.
///
/// `ThemeSettings` and `PlayerProfile` say "one record" and CloudKit has no
/// way to enforce it. `fetchOrCreate` resolved to the oldest — deterministic,
/// and still wrong, because the newer row is where the OTHER device's edits
/// are. Codex data #9; Tim, on how they should merge: *"per field."*
@MainActor
struct SingletonMergeTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    private func themes(_ repo: Repository) -> [ThemeSettings] {
        ((try? repo.context.fetch(FetchDescriptor<ThemeSettings>())) ?? [])
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The exact loss the finding describes: an avatar set on one device and a
    /// palette on the other, and "oldest wins" throws one of them away.
    @Test func independentEditsOnTwoRowsBothSurvive() {
        let repo = store()
        let older = ThemeSettings()
        older.createdAt = .now.addingTimeInterval(-100)
        older.accentHex = "#FF0000"
        repo.context.insert(older)

        let newer = ThemeSettings()
        newer.createdAt = .now
        newer.updatedAt = .now.addingTimeInterval(50)
        newer.backgroundHexDark = "#101010"
        repo.context.insert(newer)

        #expect(repo.reconcileSingletons() == 1)
        let rows = themes(repo)
        #expect(rows.count == 1)
        #expect(rows.first?.accentHex == "#FF0000")
        #expect(rows.first?.backgroundHexDark == "#101010")
    }

    /// When BOTH rows set the same field, the newer edit wins — the only
    /// honest tiebreak without per-field causality.
    @Test func aRealConflictGoesToTheNewerEdit() {
        let repo = store()
        let older = ThemeSettings()
        older.createdAt = .now.addingTimeInterval(-100)
        older.updatedAt = .now.addingTimeInterval(-100)
        older.accentHex = "#FF0000"
        repo.context.insert(older)

        let newer = ThemeSettings()
        newer.createdAt = .now
        newer.updatedAt = .now
        newer.accentHex = "#00FF00"
        repo.context.insert(newer)

        _ = repo.reconcileSingletons()
        #expect(themes(repo).first?.accentHex == "#00FF00")
    }

    /// The surviving row is the one `fetchOrCreate` already returns, so
    /// nothing holding a reference to it is invalidated by the fold.
    @Test func theOldestRowIsTheOneThatSurvives() {
        let repo = store()
        let older = ThemeSettings()
        older.createdAt = .now.addingTimeInterval(-100)
        repo.context.insert(older)
        let newer = ThemeSettings()
        newer.createdAt = .now
        repo.context.insert(newer)

        _ = repo.reconcileSingletons()
        #expect(themes(repo).first === older)
        #expect(ThemePalette.fetchOrCreate(in: repo.context) === older)
    }

    @Test func oneRowIsNotAConflictAndIsNotTouched() {
        let repo = store()
        let only = ThemeSettings()
        only.accentHex = "#ABCDEF"
        repo.context.insert(only)

        #expect(repo.reconcileSingletons() == 0)
        #expect(themes(repo).count == 1)
        #expect(themes(repo).first?.accentHex == "#ABCDEF")
    }

    @Test func profilesMergeTheSameWay() {
        let repo = store()
        let older = PlayerProfile()
        older.createdAt = .now.addingTimeInterval(-100)
        older.displayName = "Tim"
        repo.context.insert(older)

        let newer = PlayerProfile()
        newer.createdAt = .now
        newer.updatedAt = .now.addingTimeInterval(50)
        newer.avatarData = Data(repeating: 4, count: 32)
        repo.context.insert(newer)

        #expect(repo.reconcileSingletons() == 1)
        let rows = ((try? repo.context.fetch(FetchDescriptor<PlayerProfile>())) ?? [])
        #expect(rows.count == 1)
        #expect(rows.first?.displayName == "Tim")
        #expect(rows.first?.avatarData?.count == 32)
    }

    /// **All five authored fields, not three.**
    ///
    /// The fold copied `displayName`, `avatarData` and `handlesData` and left
    /// `nameColorRaw` and `useHandleAsName` behind — then deleted the row that
    /// held them. Codex found it on 2026-09-07; the exact trigger is a second
    /// device that links its name to a handle and picks a name color.
    @Test func aNameColorAndAHandleLinkSurviveTheFold() {
        let repo = store()
        let older = PlayerProfile()
        older.createdAt = .now.addingTimeInterval(-100)
        older.displayName = "Tim"
        repo.context.insert(older)

        let newer = PlayerProfile()
        newer.createdAt = .now
        newer.updatedAt = .now.addingTimeInterval(50)
        newer.nameColorRaw = "#8B2F63"
        newer.useHandleAsName = true
        newer.handles = ["steam": "timultuoustimes"]
        repo.context.insert(newer)

        #expect(repo.reconcileSingletons() == 1)
        let rows = ((try? repo.context.fetch(FetchDescriptor<PlayerProfile>())) ?? [])
        #expect(rows.count == 1)
        let kept = rows.first
        #expect(kept?.displayName == "Tim")
        #expect(kept?.nameColorRaw == "#8B2F63")
        #expect(kept?.useHandleAsName == true)
        #expect(kept?.handles["steam"] == "timultuoustimes")
    }

    /// A name color already chosen is not replaced by the loser's — identity
    /// fields fill blanks, they do not take the newer value.
    @Test func anExistingNameColorIsNotOverwritten() {
        let repo = store()
        let older = PlayerProfile()
        older.createdAt = .now.addingTimeInterval(-100)
        older.nameColorRaw = "accent"
        repo.context.insert(older)

        let newer = PlayerProfile()
        newer.createdAt = .now
        newer.updatedAt = .now.addingTimeInterval(50)
        newer.nameColorRaw = "#00FF00"
        repo.context.insert(newer)

        #expect(repo.reconcileSingletons() == 1)
        #expect((try? repo.context.fetch(FetchDescriptor<PlayerProfile>()))?
                    .first?.nameColorRaw == "accent")
    }

    /// **The winner cannot depend on a coin flip.**
    ///
    /// Both folds passed `{ _ in UUID() }` as the tie-break, so rows created in
    /// the same instant sorted at random inside the comparator. Two devices
    /// doing that could keep different rows and delete each other's winner.
    @Test func rowsCreatedInTheSameInstantFoldTheSameWayEveryTime() {
        let instant = Date.now
        var survivors: [String] = []
        for _ in 0..<8 {
            let repo = store()
            for name in ["a", "b", "c"] {
                let p = PlayerProfile()
                p.createdAt = instant
                p.id = UUID(uuidString: "0000000\(name == "a" ? 1 : name == "b" ? 2 : 3)-0000-0000-0000-000000000000")!
                p.displayName = name
                repo.context.insert(p)
            }
            _ = repo.reconcileSingletons()
            survivors.append(
                ((try? repo.context.fetch(FetchDescriptor<PlayerProfile>())) ?? [])
                    .first?.displayName ?? "?")
        }
        #expect(Set(survivors).count == 1, "fold picked \(Set(survivors)) across runs")
        #expect(survivors.first == "a")
    }

    /// Three rows fold to one, not to two — the sweep has to be complete or a
    /// later launch does it again with different content.
    @Test func threeRowsFoldToOne() {
        let repo = store()
        for i in 0..<3 {
            let t = ThemeSettings()
            t.createdAt = .now.addingTimeInterval(Double(i) * -10)
            repo.context.insert(t)
        }
        #expect(repo.reconcileSingletons() == 2)
        #expect(themes(repo).count == 1)
    }
}

/// **Time played before the app was tracking it.**
///
/// A number, not an event: it adds to every total and appears in no history.
/// The alternative the CSV importer has to use — one enormous manual session
/// dated today — puts a play in the Journal on a day nothing happened.
@MainActor
struct Build37CarriedOverTests {

    private func store() -> Repository {
        Repository(ModelContext(LevelSelectStore.makeContainer(inMemory: true)))
    }

    @Test func itDefaultsToZeroSoEveryExistingLibraryIsUnchanged() {
        let repo = store()
        let pt = repo.ensureDefaultPlaythrough(for: repo.addGame(name: "Hades", status: .playing))
        #expect(pt.carriedOverSeconds == 0)
        #expect(pt.totalPlaytime() == 0)
    }

    @Test func itAddsToTheTotalWithoutCreatingASession() {
        let repo = store()
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setCarriedOver(42 * 3600, on: pt)

        #expect(pt.totalPlaytime() == 42 * 3600)
        // The point of the field: no history was invented.
        #expect((pt.sessions ?? []).isEmpty)
    }

    @Test func sessionsAddOnTopOfIt() {
        let repo = store()
        let game = repo.addGame(name: "Celeste", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setCarriedOver(10 * 3600, on: pt)
        repo.logManualSession(on: pt, duration: 1800)

        #expect(pt.totalPlaytime() == 10 * 3600 + 1800)
        #expect((pt.sessions ?? []).count == 1)
    }

    @Test func theGamesTotalIncludesIt() {
        let repo = store()
        let game = repo.addGame(name: "Spyro the Dragon", status: .paused)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setCarriedOver(3 * 3600, on: pt)
        #expect(game.livePlaythroughs.reduce(0) { $0 + $1.totalPlaytime() } == 3 * 3600)
        #expect(CollectionSeeding.played(game) == 3 * 3600)
    }

    /// **Lifetime, not this week.** It is time you played and it is not time
    /// you played in the last seven days.
    @Test func itCountsInTheLifetimeTotalAndNotInTheWeek() {
        let repo = store()
        let game = repo.addGame(name: "Vampire Survivors", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setCarriedOver(20 * 3600, on: pt)
        repo.logManualSession(on: pt, duration: 600)

        let all = (try? repo.context.fetch(FetchDescriptor<Game>())) ?? []
        let summary = PlayerSummary.make(from: all)
        #expect(summary.totalSeconds == 20 * 3600 + 600)
        #expect(summary.weekSeconds == 600)
    }

    @Test func negativeInputIsClampedRatherThanStored() {
        let repo = store()
        let pt = repo.ensureDefaultPlaythrough(for: repo.addGame(name: "Hades", status: .playing))
        repo.setCarriedOver(-500, on: pt)
        #expect(pt.carriedOverSeconds == 0)
    }

    @Test func zeroClearsIt() {
        let repo = store()
        let pt = repo.ensureDefaultPlaythrough(for: repo.addGame(name: "Hades", status: .playing))
        repo.setCarriedOver(3600, on: pt)
        repo.setCarriedOver(0, on: pt)
        #expect(pt.carriedOverSeconds == 0)
        #expect(pt.totalPlaytime() == 0)
    }

    /// It has to survive the file that exists to rescue a library.
    @Test func itRoundTripsThroughExportAndImport() throws {
        let source = store()
        let game = source.addGame(name: "Chrono Trigger", status: .completed)
        let pt = source.ensureDefaultPlaythrough(for: game)
        source.setCarriedOver(9 * 3600 + 1800, on: pt)

        let data = try LibraryExport.makeJSON(context: source.context)
        let target = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        _ = try LibraryImport.apply(data: data, context: target)

        let restored = try #require(try target.fetch(FetchDescriptor<Playthrough>()).first)
        #expect(restored.carriedOverSeconds == 9 * 3600 + 1800)
    }

    /// A file written before build 37 has no such key, and zero is the right
    /// reading of its absence.
    @Test func anOlderExportImportsAsZero() throws {
        let file = Data("""
        {"manifest":{"formatVersion":1},
         "games":[{"id":"\(UUID().uuidString)","name":"Sonic the Hedgehog 2",
                   "playthroughs":[{"id":"\(UUID().uuidString)","name":"Main"}]}]}
        """.utf8)
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        _ = try LibraryImport.apply(data: file, context: context)
        let pt = try #require(try context.fetch(FetchDescriptor<Playthrough>()).first)
        #expect(pt.carriedOverSeconds == 0)
    }
}
