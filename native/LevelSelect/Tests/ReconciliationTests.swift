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

        // This device ranked it 2; the other device LATER ticked it complete.
        repo.setTrackerRank(pt, itemID: "charm", rank: 2, maxRank: 5)
        _ = syncedState(repo, pt: pt, itemID: "charm", completed: true,
                        updatedAt: .now.addingTimeInterval(60))

        let outcome = repo.reconcile(game)

        #expect(outcome.mergedStates == 1)
        let live = (pt.trackerStates ?? []).filter { $0.itemID == "charm" && $0.deletedAt == nil }
        #expect(live.count == 1)
        // The later action (the tick) wins; the rank fills in from the twin
        // because the winner never made any claim about rank.
        #expect(live.first?.completed == true)
        #expect(live.first?.rank == 2)
    }

    /// Round 2: "newest wins" folding via OR resurrected deliberate
    /// reductions. An untick that is the user's LATEST action must survive a
    /// stale completed twin — reconcile must not re-tick it.
    @Test func deliberateUncheckIsNotResurrectedByAStaleTwin() {
        let (repo, game) = self.game(named: "Hollow Knight")
        let pt = repo.ensureDefaultPlaythrough(for: game)

        let old = Date(timeIntervalSince1970: 1_700_000_000)
        _ = syncedState(repo, pt: pt, itemID: "boss", completed: true, updatedAt: old)
        _ = syncedState(repo, pt: pt, itemID: "boss", completed: false,
                        updatedAt: old.addingTimeInterval(9999))

        // The read already reflects the latest action…
        #expect(repo.trackerState(pt, itemID: "boss")?.completed == false)

        // …and the fold preserves it rather than OR-ing the stale tick back.
        repo.reconcile(game)
        let live = (pt.trackerStates ?? []).filter { $0.itemID == "boss" && $0.deletedAt == nil }
        #expect(live.count == 1)
        #expect(live.first?.completed == false)
    }

    /// Round 2: equal timestamps had no total tie-break, so each device could
    /// pick a different winner from its own relationship order — and after
    /// both devices' tombstones synced, both copies could be gone. The winner
    /// must be the same regardless of insertion order.
    @Test func equalTimestampsResolveTheSameWinnerRegardlessOfOrder() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
        let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!

        var winners: [UUID] = []
        for order in [[idA, idB], [idB, idA]] {
            let (repo, game) = self.game(named: "Hollow Knight")
            let pt = repo.ensureDefaultPlaythrough(for: game)
            for id in order {
                let record = syncedState(repo, pt: pt, itemID: "tie",
                                         completed: id == idA, updatedAt: stamp)
                record.id = id
            }
            repo.reconcile(game)
            let live = (pt.trackerStates ?? []).filter { $0.itemID == "tie" && $0.deletedAt == nil }
            #expect(live.count == 1)
            winners.append(live.first!.id)
        }
        #expect(winners[0] == winners[1])
    }

    /// Round 2: the fold was lossy for notes — one of two distinct notes
    /// silently vanished, and an empty-string "note" on the winner blocked a
    /// real one on the loser. Authored text is never dropped.
    @Test func conflictingNotesBothSurviveTheFold() {
        let (repo, game) = self.game(named: "Hollow Knight")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let old = Date(timeIntervalSince1970: 1_700_000_000)

        let loser = syncedState(repo, pt: pt, itemID: "grub", updatedAt: old)
        loser.notes = "behind the breakable wall"
        let winner = syncedState(repo, pt: pt, itemID: "grub",
                                 updatedAt: old.addingTimeInterval(100))
        winner.notes = "use the lantern"

        // Empty string must not beat a real note either.
        let loser2 = syncedState(repo, pt: pt, itemID: "charm", updatedAt: old)
        loser2.notes = "bought in Dirtmouth"
        let winner2 = syncedState(repo, pt: pt, itemID: "charm",
                                  updatedAt: old.addingTimeInterval(100))
        winner2.notes = ""

        repo.reconcile(game)

        let grubNote = repo.trackerState(pt, itemID: "grub")?.notes ?? ""
        #expect(grubNote.contains("use the lantern"))
        #expect(grubNote.contains("behind the breakable wall"))
        #expect(repo.trackerState(pt, itemID: "charm")?.notes?
            .contains("bought in Dirtmouth") == true)
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

    /// Round 2's session-intent failure: an old session RESUMED at 17:00 is a
    /// later user action than a fresh one started at 16:00. Keying the winner
    /// on original startDate stopped the session the user was actually
    /// running. The resumed session must survive.
    @Test func resumedOldSessionBeatsNewerStartedSession() {
        let (repo, game) = self.game(named: "Hades")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let t15 = Date(timeIntervalSince1970: 1_700_000_000)          // 15:00
        let t16 = t15.addingTimeInterval(3600)                        // 16:00
        let t17 = t15.addingTimeInterval(7200)                        // 17:00

        // Other device: started 15:00, played 30 min, paused, resumed 17:00.
        let resumed = Session(startDate: t15, state: .running)
        resumed.accumulatedDuration = 1800
        resumed.resumedAt = t17
        repo.context.insert(resumed)
        resumed.playthrough = pt

        // This device: a fresh session started 16:00, currently running.
        let fresh = Session(startDate: t16, state: .running)
        repo.context.insert(fresh)
        fresh.playthrough = pt

        repo.reconcile(game)

        // The genuinely active resumed session keeps running…
        #expect(resumed.state == .running)
        #expect(fresh.state == .stopped)
        // …and the loser is credited only up to the survivor's resume, so the
        // overlapping hour isn't double-counted.
        #expect(fresh.accumulatedDuration == 3600)
        // 30 min banked + 30 min live at 17:30 + the loser's hour.
        #expect(pt.totalPlaytime(asOf: t17.addingTimeInterval(1800)) == 1800 + 1800 + 3600)
    }

    /// Clock skew: a synced session anchored in this device's future must
    /// never read or record negative time.
    @Test func futureDatedSessionNeverGoesNegative() {
        let (repo, game) = self.game(named: "Hades")
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let skewed = Session(startDate: now.addingTimeInterval(3600), state: .running)
        skewed.accumulatedDuration = 120
        repo.context.insert(skewed)
        skewed.playthrough = pt

        #expect(skewed.elapsed(asOf: now) == 120)   // clamped, not 120 - 3600

        // With a local session also open, reconcile must not write a negative
        // duration into whichever side it closes.
        let local = Session(startDate: now, state: .running)
        repo.context.insert(local)
        local.playthrough = pt
        repo.reconcile(game, at: now)
        for s in (pt.sessions ?? []) {
            #expect(s.accumulatedDuration >= 0)
            #expect(s.elapsed(asOf: now) >= 0)
        }
        // The future-dated winner must not have credited the local session
        // for time that hasn't happened yet.
        #expect(local.accumulatedDuration == 0)
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

    /// The round-2 review's adversarial shape: device A creates a default
    /// playthrough and saves it; its tracker state and session are still in
    /// flight when device B foregrounds. At that instant A's playthrough is
    /// non-current, default-named, and empty — indistinguishable from a race
    /// artifact. Reconcile must NOT delete it: A is about to write children
    /// under it, and a tombstone here silently destroys that work after sync.
    @Test func emptyJustSyncedDefaultPlaythroughIsNeverRemoved() {
        let (repo, game) = self.game(named: "Celeste")
        let current = repo.ensureDefaultPlaythrough(for: game)

        // Device A's ensureDefaultPlaythrough arrived via sync — children
        // (state, session) have not.
        let inFlight = Playthrough()
        repo.context.insert(inFlight)
        inFlight.game = game

        repo.reconcile(game)

        #expect(inFlight.deletedAt == nil)
        #expect(game.livePlaythroughs.count == 2)
        #expect(game.livePlaythroughs.contains(where: { $0 === current }))

        // The children now land, exactly as device A wrote them — under a
        // parent that must still exist.
        repo.setTrackerItem(inFlight, itemID: "berry-1", done: true)
        repo.reconcile(game)
        #expect(inFlight.deletedAt == nil)
        #expect(repo.trackerState(inFlight, itemID: "berry-1")?.completed == true)
    }

    /// Anything the user touched — a rename, a note, any record — is equally
    /// out of bounds.
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

        repo.reconcile(game)

        #expect(game.livePlaythroughs.count == 3)
    }

    /// The bounded foreground sweep must still find doubled clocks — it works
    /// from a direct fetch of unstopped sessions, not a whole-library walk.
    @Test func boundedLibrarySweepClosesDoubledSessions() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hades", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        _ = repo.startSession(on: pt, at: t0)
        let synced = Session(startDate: t0.addingTimeInterval(600), state: .running)
        context.insert(synced)
        synced.playthrough = pt

        repo.reconcileLibrary(at: t0.addingTimeInterval(1200))

        let open = (pt.sessions ?? []).filter { $0.state != .stopped && $0.deletedAt == nil }
        #expect(open.count == 1)
        #expect(pt.totalPlaytime(asOf: t0.addingTimeInterval(1200)) == 1200)
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
        let entry = game.bindingEditFingerprint

        repo.finalizeEdits(game, ifChangedFrom: entry)

        #expect(game.revision == revBefore)
    }

    /// A binding-style direct mutation gets its metadata stamped at the
    /// boundary.
    @Test func finalizeEditsStampsABindingEdit() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .backlog)
        let revBefore = game.revision
        let entry = game.bindingEditFingerprint

        game.review = "wrote this through a TextField binding"
        repo.finalizeEdits(game, ifChangedFrom: entry)

        #expect(game.revision == revBefore + 1)
    }

    /// Round 2's first failure shape: some UNRELATED model is dirty when the
    /// user leaves an untouched game page. The old `context.hasChanges` gate
    /// stamped the untouched game — cross-device ordering then treated it as
    /// freshly edited. The edit-scoped gate must not.
    @Test func finalizeEditsIgnoresAnUnrelatedDirtyModel() {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let visited = repo.addGame(name: "Celeste", status: .backlog)
        let other = repo.addGame(name: "Hades", status: .playing)
        let revBefore = visited.revision
        let entry = visited.bindingEditFingerprint

        other.review = "pending, unsaved edit on a DIFFERENT game"
        #expect(context.hasChanges)   // the old gate would have fired

        repo.finalizeEdits(visited, ifChangedFrom: entry)

        #expect(visited.revision == revBefore)
    }

    /// Round 2's second failure shape: SwiftData autosave (or the scene
    /// background commit) saves the binding edit BEFORE onDisappear runs. The
    /// context is then clean, so the old gate skipped the stamp and the edit
    /// persisted without its sync metadata. A binding edit must not be able
    /// to persist unstamped.
    @Test func finalizeEditsStampsEvenAfterAutosaveAlreadyCommitted() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Celeste", status: .backlog)
        let revBefore = game.revision
        let entry = game.bindingEditFingerprint

        game.review = "typed, then autosaved"
        try context.save()            // what autosave / scene background do
        #expect(!context.hasChanges)  // the old gate would now skip the stamp

        repo.finalizeEdits(game, ifChangedFrom: entry)

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

    /// Round 2, finding 6: the file promised "stable UUIDs for round-trip"
    /// while tracker states, completion events and videos omitted theirs — so
    /// a future importer could not preserve identity for those records.
    @Test func exportCarriesStableIDsForEveryRecordType() throws {
        let context = ModelContext(LevelSelectStore.makeContainer(inMemory: true))
        let repo = Repository(context)
        let game = repo.addGame(name: "Hollow Knight", status: .playing)
        let pt = repo.ensureDefaultPlaythrough(for: game)
        repo.setTrackerItem(pt, itemID: "hornet", done: true)
        let event = repo.addCompletion(to: game, label: .completed)
        let video = GameVideo(kind: .video, urlString: "https://youtu.be/x",
                              youtubeID: "x", title: "Guide")
        context.insert(video)
        video.game = game

        let data = try LibraryExport.makeJSON(context: context)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exported = try #require((root["games"] as? [[String: Any]])?.first)

        let states = try #require(
            ((exported["playthroughs"] as? [[String: Any]])?.first?["trackerProgress"]) as? [[String: Any]])
        let stateID = try #require(states.first?["id"] as? String)
        #expect(UUID(uuidString: stateID) != nil)

        let completions = try #require(exported["completions"] as? [[String: Any]])
        #expect(completions.first?["id"] as? String == event.id.uuidString)

        let videos = try #require(exported["videos"] as? [[String: Any]])
        #expect(videos.first?["id"] as? String == video.id.uuidString)
    }
}
