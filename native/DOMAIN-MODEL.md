# LevelSelect Native — Domain Model (SwiftData V1)

*Roadmap step 7g #2 ("Design native domain model and migration fixtures"). Designed against `fixtures/LEGACY-SCHEMA.md` (frozen 2026-06-30). This is the spec for 7g #3 (implement SwiftData V1 + repository layer). Targets iOS 26 / macOS 26, Swift 6.*

## Design principles

1. **SwiftData is the source of truth; Supabase is backup + cross-device sync** (roadmap §Phase 1.3). Every model carries sync metadata; a separate outbox drives upserts.
2. **Identity is the account, not the device.** No device IDs. `userID` = Supabase `auth.uid()`. The legacy device-ID / JSON-blob model is cut entirely (the 20 device blobs were one library snapshotted 20× — see LEGACY-SCHEMA.md).
3. **Immutable tracker schema is stored separately from mutable progress** (roadmap §Phase 2.1) so a schema can be replaced/regenerated without touching a playthrough's checked-off state.
4. **Two tracker engines, not 13.** Legacy `trackerType` strings map onto either an *objective schema* (StructuredTracker family) or a *run template* (roguelikes). Hades stays bespoke but reuses these records.
5. **Version the schema from V1** (roadmap §7f.1) even though V1 has no migration stage yet — never repeat the web app's unversioned drift.
6. **Motion/animation is first-class** (see `dev/projects/LevelSelect/LevelSelect design inspiration.md`) — the model must expose what the UI animates (progress %, active-session timestamps, completion moments) as clean derived values.

---

## Sync metadata (mixed into every synced @Model)

Not a protocol SwiftData can persist directly; implemented as the same stored properties on each model:

```
id:         UUID        // stable across local + remote (PK both sides)
userID:     UUID        // Supabase auth.uid(); RLS scopes rows to the owner
createdAt:  Date
updatedAt:  Date        // bumped on every local mutation
revision:   Int         // per-record version for conflict detection
deletedAt:  Date?       // soft-delete tombstone (nil = live)
legacyID:   String?     // original web id ("1772048677564-…") for idempotent migration; nil for natively-created rows
```

Deletion is **soft** (`deletedAt`) so tombstones can propagate; a periodic compaction hard-deletes old tombstones locally after they're acknowledged remotely.

---

## Entities

### Profile
The signed-in user (one row locally).
```
id: UUID (= auth.uid())
appleUserIdentifier: String     // from Sign in with Apple
email: String?
displayName: String?
createdAt / updatedAt
```

### Game  ← legacy `library[]` element
```
// identity & metadata
name: String
summary: String?                // legacy summary
notes: String                   // game-level notes
igdbID: Int?                    // legacy igdbId
igdbSlug: String?
firstReleaseDate: Date?
franchise: String?
coverURLString: String?         // legacy coverUrl (remote IGDB art)
coverImageID: String?           // legacy coverImageId (chosen cover variant)

// user state
status: GameStatus              // enum, see below
pinned: Bool                    // Phase 2 feature; default false
rating: Int?                    // CONSOLIDATED game-level (legacy userRating + saves[].rating)
review: String?                 // CONSOLIDATED game-level review
addedAt: Date                   // legacy addedAt

// arrays (value metadata; kept as [String])
platforms: [String]
userTags: [String]
genres: [String]
themes: [String]
gameModes: [String]
playerPerspectives: [String]
developers: [String]
publishers: [String]

// relationships
playthroughs:      [Playthrough]        // .cascade
completionEvents:  [CompletionEvent]    // .cascade
maps:              [GameMap]            // .cascade
trackerSchema:     TrackerSchemaRecord?  // .cascade, 0..1 per game

// sync metadata (above)
```
**Cut from legacy** (do not port): `complexity`, `coverColor`, `yearPlayed`, root-level `currentSaveId`, the always-empty `games` map, per-save duplicate `rating`/`review` (consolidated to game level), `playPeriods` (superseded by sessions + completionEvents).
`currentSaveID` → keep as a lightweight `currentPlaythroughID: UUID?` on Game (which playthrough is active), not a root-level field.

### Playthrough  ← legacy `saves[]` element
```
name: String                    // "Playthrough" (renamed from Save/File/Tracker File)
notes: String?                  // playthrough-specific commentary (kept per-playthrough)
progressPercent: Double         // legacy progressPercent (also derivable; store denormalized for fast lists)
startedAt: Date?                // legacy createdAt
lastPlayedAt: Date?

game: Game                      // inverse
sessions:      [Session]        // .cascade
trackerStates: [TrackerStateRecord]  // .cascade
runs:          [Run]            // .cascade (roguelikes)
// active session = the Session whose state != .stopped (no separate field)
```
Most games have exactly one playthrough (validated: 19 saves across 18 games). The UI hides playthrough switching until a 2nd exists (roadmap §Phase 1).

### Session  ← legacy `saves[].sessions[]`
```
startDate: Date                 // legacy startTime
endDate: Date?                  // legacy endTime (nil while active)
accumulatedDuration: TimeInterval  // legacy accumulatedTime (time before current pause segment)
pausedAt: Date?                 // legacy pausedAt (nil unless paused)
state: SessionState             // .running / .paused / .stopped  (derived from legacy shape)
isManual: Bool                  // legacy manual (hand-logged vs timed)
notes: String?

playthrough: Playthrough        // inverse
```
**Duration is derived, never stored as a ticking value** (roadmap §Phase 1.7): `elapsed = accumulatedDuration + (state == .running ? now - (pausedAt ?? startDate resume point) : 0)`. Display via `TimelineView`; no per-second writes. Legacy `duration` becomes a computed convenience for stopped sessions.

### CompletionEvent  ← legacy `clears[]` (+ status transitions)
```
date: Date                      // legacy clearedAt
label: CompletionLabel          // .completed / .hundredPercent / .newGamePlus / .cleared / .custom(String)
platform: String?
notes: String?

game: Game                      // inverse
```
Library "games completed in year N" stats derive from `date`. First completion event may flip `Game.status` to `.completed`. Legacy `yearPlayed` is dropped in favor of these dates.

### TrackerSchemaRecord  ← legacy `structuredData` (immutable definition)
```
schemaVersion: Int              // legacy structuredData.schemaVersion
source: TrackerSource           // .builtIn / .aiGenerated  (from legacy generatedBy)
engine: TrackerEngine           // .objective / .run  (derived from legacy trackerType mapping)
generatedAt: Date?
generatedBy: String?            // model/tool that produced an AI schema
jsonData: Data                  // Codable-encoded schema tree (categories→items, and/or runTemplate)
sourcesJSON: Data?              // legacy structuredData.sources (reference URLs/notes)

game: Game                      // inverse
```
Stored as **versioned JSON blob**, not exploded into rows (roadmap §Phase 2.2): AI schemas are read-mostly, built-in schemas use the same decoder, replacement is trivial. Decoded into strongly-typed `Codable` DTOs (`TrackerSchemaDTO { sections:[Section], runTemplate:RunTemplate? , tags:[String] }`) before display.

### TrackerStateRecord  ← mutable per-playthrough progress
```
itemID: String                  // stable id of the schema item this state belongs to
completed: Bool
count: Int?                     // for count-type items
rank: Int?                      // for rank-type items (e.g. Boss Cells)
revealed: Bool                  // spoiler gating
notes: String?

playthrough: Playthrough        // inverse
```
One row per (playthrough, schema item) that has non-default state (sparse). "Personal Goals" = a section every schema carries; user-created goals are items with state here (replaces legacy `milestones`, which were empty).

### Run  ← legacy `structuredData.runs[]` / roguelike run tracker
```
templateID: String              // which run template (within the schema jsonData)
startedAt: Date
endedAt: Date?
outcome: RunOutcome             // .success / .failure / .neutral / .inProgress
fieldsJSON: Data                // setup + in-run field values (per RunTemplate)
notes: String?

playthrough: Playthrough        // inverse
```
Persist active runs **immediately** (roadmap §Phase 2.5 — fixes the web bug where a run lived only in component state).

### GameMap  ← legacy `maps[]`
```
name: String
kind: MapKind                   // legacy type: .world / .area / .other
storageType: String             // legacy storageType ("upload")
remoteStoragePath: String       // legacy storagePath (canonical reference — NOT a public URL)
remoteURLString: String?        // legacy imageUrl (may be a signed/derived URL; recomputed)
localCacheURL: URL?             // cached full-res bytes for offline (roadmap §Phase 3.4)
pixelWidth: Int?
pixelHeight: Int?
addedAt: Date

game: Game                      // inverse
markers: [Marker]               // .cascade
```
Image **bytes stay in Supabase Storage**; only metadata + path migrate (roadmap §Phase 3.3).

### Marker  ← legacy `maps[].markers[]`
```
normalizedX: Double             // 0…1  (legacy x / 100)
normalizedY: Double             // 0…1  (legacy y / 100)
category: MarkerCategory        // .collectible / .note / .warning / .secret
label: String
notes: String?
createdAt: Date
linkedTrackerItemID: String?    // optional link to a TrackerSchema item ("Show on map" ↔ "Open objective")

map: GameMap                    // inverse
```
Legacy coords appear to be 0–100; **normalize to 0…1** on import (roadmap §Phase 3.2). Confirm legacy scale against real data during migration and assert bounds.

### SyncOperation (outbox — local only, not synced)
```
id: UUID
entityType: String              // "Game", "Session", …
entityID: UUID
opType: SyncOpType              // .upsert / .delete
payloadJSON: Data?              // snapshot for the remote upsert
attempts: Int
lastError: String?
createdAt: Date
```
Drives retry-with-backoff to Supabase; acknowledged ops are removed.

### MigrationReceipt (local + remote — idempotency for the one-time import)
```
id: UUID
sourceDeviceID: String          // which legacy game_data.device_id was imported
importedAt: Date
appVersion: String
countsJSON: Data                // {games, playthroughs, sessions, completionEvents, maps, markers}
```
Prevents a second import from duplicating rows (roadmap §Phase 1.8).

---

## Enums

```swift
enum GameStatus: String, Codable, CaseIterable {   // legacy status (7 values, verified)
  case backlog, playing, paused, completed, queued, shelved, abandoned
}
enum SessionState: String, Codable { case running, paused, stopped }
enum CompletionLabel: Codable { case completed, hundredPercent, newGamePlus, cleared, custom(String) }
enum TrackerSource: String, Codable { case builtIn, aiGenerated }
enum TrackerEngine: String, Codable { case objective, run }
enum RunOutcome: String, Codable { case inProgress, success, failure, neutral }
enum MapKind: String, Codable { case world, area, other }
enum MarkerCategory: String, Codable { case collectible, note, warning, secret }
enum SyncOpType: String, Codable { case upsert, delete }
```

### Legacy `trackerType` → engine mapping
| legacy trackerType | native engine | notes |
|---|---|---|
| `"None"` (145 games) | *(no schema)* | general tracker: sessions + Personal Goals + rating/review/completion |
| hollow-knight, dead-cells, hitman, under-the-island, sayonara-wild-hearts, cast-n-chill, mina-the-hollower, messenger, citizen-sleeper | `.objective` | objective schema (some already have `structuredData`; others rebuilt as schema) |
| gonner, lone-ruin, cursed-to-golf | `.run` | run template |
| hades | `.objective` + bespoke UI | keep custom Hades view; data uses objective records + sessions |

---

## SwiftData versioning

```swift
enum LevelSelectSchemaV1: VersionedSchema {
  static var versionIdentifier = Schema.Version(1, 0, 0)
  static var models: [any PersistentModel.Type] = [
    Profile.self, Game.self, Playthrough.self, Session.self, CompletionEvent.self,
    TrackerSchemaRecord.self, TrackerStateRecord.self, Run.self,
    GameMap.self, Marker.self, SyncOperation.self, MigrationReceipt.self
  ]
}
enum LevelSelectMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] = [LevelSelectSchemaV1.self]
  static var stages: [MigrationStage] = []   // none yet; add on V2
}
```
Independent version numbers to maintain (roadmap §7f.1): SwiftData schema, tracker-schema JSON, sync-protocol.

---

## Remote Supabase schema (paired, built during Phase 1.4)

One table per synced entity, snake_case, with RLS `auth.uid() = user_id`:
```
profiles, games, playthroughs, sessions, completion_events,
tracker_schemas, tracker_states, runs, game_maps, map_markers
```
Every row: `id uuid pk, user_id uuid, created_at, updated_at, revision int, deleted_at`. `SyncOperation` and `MigrationReceipt` are client-side only (receipt may also be mirrored for cross-device idempotency). `game_data` (legacy blob table) stays untouched until migration is verified, then is retired.

---

## Migration fixtures (the rest of 7g #2)

1. **Primary fixture (real):** `fixtures/legacy-canonical-7f86df1b-20260628.json` — the 158-game canonical blob. Drives the importer's field-mapping and the dry-run/reconciliation report. Gitignored (personal data).
2. **Committable synthetic fixture (to build):** `fixtures/synthetic-legacy-sample.json` — a hand-built, anonymized mini-library (~6 games) exercising every path: a `None` game with sessions, an `.objective` game with `structuredData` + Personal Goals, a `.run` game with runs, a Hades game, a game with a map + markers (0–100 coords), a game with `clears`. Safe to commit; backs unit tests for the importer + decoder.
3. **Migration test:** import synthetic fixture → assert entity counts, coord normalization (x/y → 0…1), rating/review consolidation, dropped-field absence, idempotency (second import is a no-op via MigrationReceipt).

## Open questions
- [x] **Marker `x/y` scale = 0–100** (confirmed vs canonical fixture: Hogwarts Legacy marker x=43.16, y=61.37). Importer maps `normalizedX = x/100`, `normalizedY = y/100`, and asserts 0…1 bounds.
- [x] **Rating scale = 1–5**, and consolidation is **conflict-free**: no game carries both a game-level `userRating` and a save-level `rating` (verified). Rule: `Game.rating = userRating ?? firstPlaythrough.rating`.
- [ ] Does any game legitimately need >1 tracker schema? (Assumed 0..1 per game.) Hades objective+bespoke is the edge case — resolve when porting Hades.
- [ ] Personal Goals: implicit universal section in every schema, or a tiny always-present schema for `None` games? (Leaning: universal section.) Decide when building the objective tracker (Phase 2).
