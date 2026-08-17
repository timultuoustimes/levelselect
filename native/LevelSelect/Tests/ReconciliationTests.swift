import Testing
import Foundation
import SwiftData
@testable import LevelSelect

/// CloudKit syncs records without knowing this app's logical invariants, so
/// two devices editing before sync can leave the store holding both versions
/// of the truth: two state rows for one item, two running sessions, two
/// default playthroughs. These tests build exactly the post-sync shapes the
/// external review described — by inserting the duplicate rows a sync would
/// deliver — and check the repair pass folds rather than drops.
@MainActor
struct ReconciliationTests {

    private func game(named name: String) -> (Repository, Game) {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        return (repo, repo.addGame(name: name, status: .playing))
    }

    /// What another device's `setTrackerItem` produces, arriving via sync.
    private func syncedState(_ repo: Repository, pt: Playthrough, itemID: String,
                             completed: Bool = false, rank: Int? = nil,
                             updatedAt: Date? = nil) -> TrackerStateRecord {
        let record = TrackerStateRecord(itemID: itemID, completed: completed, rank: rank)
        repo.context.insert(record)
        record.playthrough = pt
        if let updatedAt { record.updatedAt = updatedAt }
        return record
    }

    // MARK: Duplicate tracker states

    @Test func duplicateStatesFoldIntoOneRow() {
        let (repo, game) = self.game(named: "Hollow Knight")
        let pt = repo.ensureDefaultPlaythrough(for: game)

        // This device ranked it 2; the other device ticked it complete.
        repo.setTrackerRank(pt, itemID: "charm", rank: 2, maxRank: 5)
        _ = syncedState(repo, pt: pt, itemID: "charm", completed: true)

        let outcome = repo.reconcile(game)

        #expect(outcome.mergedStates == 1)
        let live = (pt.trackerStates ?? []).filter { $0.itemID == "charm" && $0.deletedAt == nil }
        #expect(live.count == 1)
        // Folded, not dropped: the tick AND the rank both survive in one row.
        #expect(live.first?.completed == true)
        #expect(live.first?.rank == 2)
    }

    /// Before the sweep has run, the read itself must already prefer the twin
    /// carrying the user's work — a tick made on the other device must never
    /// show as unticked because of relationship ordering.
    @Test func readPrefersTheTickedTwinEvenBeforeReconcile() {
        let (repo, game) = self.game(named: "Hollow Knight")
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let old = Date(timeIntervalSince1970: 1_700_000_000)
        _ = syncedState(repo, pt: pt, itemID: "boss", completed: true, updatedAt: old)
        _ = syncedState(repo, pt: pt, itemID: "boss", completed: false, updatedAt: old.addingTimeInterval(9999))

        #expect(repo.trackerState(pt, itemID: "boss")?.completed == true)
    }

    // MARK: Doubled sessions

    /// Two devices both timing: playtime must not be the sum of overlapping
    /// clocks. The older session is credited up to the newer one's start and
    /// the survivor carries on from there.
    @Test func doubledRunningSessionsDoNotDoubleCount() {
        let (repo, game) = self.game(named: "Hades")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        // Phone started at t0; iPad's session arrived via sync, started t0+600.
        _ = repo.startSession(on: pt, at: t0)
        let synced = Session(startDate: t0.addingTimeInterval(600), state: .running)
        repo.context.insert(synced)
        synced.playthrough = pt

        let outcome = repo.reconcile(game)

        #expect(outcome.closedSessions == 1)
        let open = (pt.sessions ?? []).filter { $0.state != .stopped && $0.deletedAt == nil }
        #expect(open.count == 1)
        // At t0+1200: 600s credited to the closed one + 600s live = 1200, not 1800.
        #expect(pt.totalPlaytime(asOf: t0.addingTimeInterval(1200)) == 1200)
    }

    /// A paused duplicate keeps exactly its accumulated play and gains nothing
    /// from being closed out.
    @Test func pausedDuplicateKeepsOnlyItsAccumulatedTime() {
        let (repo, game) = self.game(named: "Hades")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        let paused = repo.startSession(on: pt, at: t0)
        repo.pauseSession(paused, at: t0.addingTimeInterval(300))          // 5 min banked
        let synced = Session(startDate: t0.addingTimeInterval(4000), state: .running)
        repo.context.insert(synced)
        synced.playthrough = pt

        repo.reconcile(game)

        #expect(paused.state == .stopped)
        #expect(paused.elapsed() == 300)
    }

    /// Starting a session must close EVERY unstopped one, not one arbitrary
    /// pick — otherwise a sync twin keeps accruing forever behind the new
    /// timer.
    @Test func startSessionStopsEveryUnstoppedSession() {
        let (repo, game) = self.game(named: "Hades")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        for offset in [0.0, 60.0] {
            let s = Session(startDate: t0.addingTimeInterval(offset), state: .running)
            repo.context.insert(s)
            s.playthrough = pt
        }

        let fresh = repo.startSession(on: pt, at: t0.addingTimeInterval(120))

        let open = (pt.sessions ?? []).filter { $0.state != .stopped && $0.deletedAt == nil }
        #expect(open.count == 1)
        #expect(open.first === fresh)
    }

    // MARK: Duplicate default playthroughs

    @Test func emptyDuplicateDefaultPlaythroughIsRemoved() {
        let (repo, game) = self.game(named: "Celeste")
        let current = repo.ensureDefaultPlaythrough(for: game)

        // The other device's ensureDefaultPlaythrough, arrived via sync.
        let twin = Playthrough()
        repo.context.insert(twin)
        twin.game = game

        let outcome = repo.reconcile(game)

        #expect(outcome.removedPlaythroughs == 1)
        #expect(game.livePlaythroughs.count == 1)
        #expect(game.livePlaythroughs.first === current)
    }

    /// Anything the user touched — a rename, a note, any record — is out of
    /// bounds, even when otherwise empty.
    @Test func renamedOrNonEmptyPlaythroughsAreNeverRemoved() {
        let (repo, game) = self.game(named: "Celeste")
        _ = repo.ensureDefaultPlaythrough(for: game)

        let renamed = Playthrough(name: "Steel Soul")
        repo.context.insert(renamed)
        renamed.game = game

        let withData = Playthrough()
        repo.context.insert(withData)
        withData.game = game
        repo.setTrackerItem(withData, itemID: "anything", done: true)

        let outcome = repo.reconcile(game)

        #expect(outcome.removedPlaythroughs == 0)
        #expect(game.livePlaythroughs.count == 3)
    }

    // MARK: Idempotence and interplay

    @Test func reconcileTwiceIsANoOpTheSecondTime() {
        let (repo, game) = self.game(named: "Hollow Knight")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "boss", done: true)
        _ = syncedState(repo, pt: pt, itemID: "boss", completed: false)
        let synced = Session(startDate: .now, state: .running)
        repo.context.insert(synced)
        synced.playthrough = pt

        let first = repo.reconcile(game)
        #expect(!first.isNoOp)
        let second = repo.reconcile(game)
        #expect(second.isNoOp)
    }

    /// The reason reconcile runs before a schema merge: migration rewrites
    /// state ids, and doing that over sync twins would either migrate one and
    /// strand the other, or carry the duplication through to the new ids.
    @Test func schemaMigrationRunsOverDedupedRows() {
        let (repo, game) = self.game(named: "Hollow Knight")
        let schema = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "bosses", "name": "Bosses", "type": "checklist",
                            "items": [["id": "hornet", "name": "Hornet"]]]],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: schema, mode: .addAll)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "hornet", done: true)
        _ = syncedState(repo, pt: pt, itemID: "hornet", completed: true)

        let reslugged = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "categories": [["id": "bosses", "name": "Bosses", "type": "checklist",
                            "items": [["id": "boss-hornet", "name": "Hornet"]]]],
        ])
        repo.applyGeneratedSchema(for: game, jsonData: reslugged, mode: .replace)

        let live = (pt.trackerStates ?? []).filter { $0.deletedAt == nil }
        #expect(live.count == 1)
        #expect(live.first?.itemID == "boss-hornet")
        #expect(live.first?.completed == true)
    }
}

/// The repository's edit choke point — review finding #8. Views were mutating
/// models directly, leaving updatedAt/revision stale (which corrupts
/// cross-device ordering) and deferring the save to autosave, where failures
/// surface nowhere.
@MainActor
struct RepositoryEditTests {

    @Test func editBumpsSyncMetadata() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .backlog)
        let revBefore = game.revision
        let stampBefore = game.updatedAt

        repo.edit(game) { $0.pinned = true }

        #expect(game.pinned)
        #expect(game.revision == revBefore + 1)
        #expect(game.updatedAt >= stampBefore)
    }

    /// Ordinary navigation through a page that changed nothing must not write.
    @Test func finalizeEditsIsANoOpWhenNothingChanged() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .backlog)
        let revBefore = game.revision

        repo.finalizeEdits(game)

        #expect(game.revision == revBefore)
    }

    /// A binding-style direct mutation gets its metadata stamped at the
    /// boundary.
    @Test func finalizeEditsStampsABindingEdit() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .backlog)
        let revBefore = game.revision

        game.review = "wrote this through a TextField binding"
        repo.finalizeEdits(game)

        #expect(game.revision == revBefore + 1)
    }
}

/// Review finding #5: the export omitted whole models (maps, markers) and
/// user-visible fields (video notes, per-part positions, session anchors,
/// appearance). These assert the previously-dropped data actually lands in
/// the JSON — the manifest can only count what the exporter chose to visit,
/// so counting is not the proof; presence is.
@MainActor
struct ExportCompletenessTests {

    @Test func exportCarriesMapsMarkersVideoDetailAndAppearance() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)

        // A map with an annotated marker — an entire model the export dropped.
        let map = GameMap(name: "Hallownest", kind: .other)
        context.insert(map)
        map.game = game
        let marker = Marker(normalizedX: 0.25, normalizedY: 0.75, category: .note, label: "Grub here")
        marker.notes = "behind the breakable wall"
        marker.linkedTrackerItemID = "grub-17"
        context.insert(marker)
        marker.map = map

        // A playlist with a note and a per-part resume position.
        let video = GameVideo(kind: .playlist, urlString: "https://youtube.com/playlist?list=X",
                              youtubeID: "X", title: "Walkthrough")
        context.insert(video)
        video.game = game
        video.notes = "start from part 3"
        repo.cachePlaylistParts(video, ids: ["a", "b"], titles: ["a": "Part 1", "b": "Part 2"])
        repo.updateVideoProgress(video, seconds: 436, partIndex: 1)

        // A live paused session — unreconstructable without its anchors.
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let session = repo.startSession(on: pt, at: Date(timeIntervalSince1970: 1_700_000_000))
        repo.pauseSession(session, at: Date(timeIntervalSince1970: 1_700_000_600))

        let data = try LibraryExport.makeJSON(context: context)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let manifest = try #require(root["manifest"] as? [String: Any])
        #expect(manifest["maps"] as? Int == 1)
        #expect(manifest["markers"] as? Int == 1)

        let exported = try #require((root["games"] as? [[String: Any]])?.first)
        let maps = try #require(exported["maps"] as? [[String: Any]])
        let markers = try #require(maps.first?["markers"] as? [[String: Any]])
        #expect(markers.first?["notes"] as? String == "behind the breakable wall")
        #expect(markers.first?["linkedTrackerItemID"] as? String == "grub-17")

        let videos = try #require(exported["videos"] as? [[String: Any]])
        #expect(videos.first?["notes"] as? String == "start from part 3")
        let parts = try #require(videos.first?["parts"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[1]["watchedSeconds"] as? Double == 436)

        let sessions = try #require(
            ((exported["playthroughs"] as? [[String: Any]])?.first?["sessions"]) as? [[String: Any]])
        #expect(sessions.first?["pausedAt"] != nil)
    }
}
