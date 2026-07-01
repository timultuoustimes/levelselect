# LevelSelect — Legacy Schema Freeze

*Roadmap step 7g #1 ("Freeze and export the legacy schema"). Generated 2026-06-30 from the live Supabase project `levelselect` (`sextftevxqrtodlmnyve`), table `public.game_data`. This is the authoritative record of the pre-native data shape. **Do not edit** — it is the contract the native domain model + migration are designed against.*

## Persistence model (what it is today)

- **One table:** `public.game_data` — `device_id TEXT PK`, `data JSONB`, `updated_at TIMESTAMPTZ`.
- **One row per device** = that device's *entire* library as a single JSON blob (the "one complete library JSON blob per device" the [[LevelSelect native conversion roadmap]] replaces).
- **20 device rows** exist (device-adoption history over time). RLS is enabled on `game_data`; the anon key can read all 20.
- **Canonical row** (newest, richest): device `7f86df1b-a815-4798-a9d5-00974419eec3`, updated **2026-06-28 19:54 UTC**, 277 kB, **158 games**, uniquely carries `homeSession`. This is the migration source of truth. Extracted to `legacy-canonical-7f86df1b-20260628.json`.
- Full 20-row dump: `legacy-game_data-full-20260630.json`.

## Blob root shape

```
{
  version:        number
  library:        Game[]      // ← ALL real data lives here
  games:          []          // ALWAYS EMPTY across every blob — vestigial, never populated. CUT.
  currentGameId:  string|null
  currentSaveId:  string|null // root-level duplicate of per-game currentSaveId. CUT (roadmap).
  lastSavedAt:    ISO string
  settings:       {...}       // newest blobs only (appeared 2026-06-27)
  homeSession:    {...}       // canonical blob only (Phase 2 home quick-timer state)
}
```

## Game (158 in canonical; field counts = presence across the 158)

**Always present (28):**
`id, name, notes, saves, genres, igdbId, status, themes, addedAt, summary, coverUrl, igdbSlug, userTags, franchise, gameModes, platforms, complexity, coverColor, developers, publishers, yearPlayed, playPeriods, trackerType, coverImageId, currentSaveId, firstReleaseDate, playerPerspectives`

**Sparse:** `saves` is present-but-often-empty; `structuredData` (5), `clears` (9), `userRating` (4), `maps` (2).

**Fields to CUT/migrate (per roadmap, confirmed present):**
- `complexity` (158) — no active UI behavior → cut
- `coverColor` (158) — no active UI behavior → cut
- `yearPlayed` (158) — shadowed by `playPeriods` → cut after migration
- root `currentSaveId` — duplicate → cut (keep per-game)
- game-level `userRating` vs per-save `rating` — dedupe to one game-level value

**`status` enum (7):** `backlog`(115), `completed`(20), `playing`(9), `paused`(6), `queued`(6), `shelved`(1), `abandoned`(1)

**`platforms`:** array; 18 distinct values in library.

## Save = Playthrough (18 games have saves; 19 saves total → mostly 1/game)

```
{
  id, name, createdAt, lastPlayedAt,
  notes, rating, review,          // per-playthrough commentary
  progressPercent,                // number
  totalPlaytime,                  // number (derived/accumulated)
  sessions:   Session[],
  milestones: Milestone[],        // (empty in current data)
  activeSession: null | Session   // 18 null, 1 in-progress dict → persisted active timer
}
```

### Session
```
{ id, startTime, endTime, duration, accumulatedTime, pausedAt, manual, notes }
```
`manual: bool` (hand-logged vs timed). `pausedAt`/`accumulatedTime` = pause support. Confirms native plan: derive elapsed from timestamps, persist start/accumulated/paused/state.

### Milestone
Present as an array but empty in current data. Roadmap: fold into tracker "Personal Goals" items.

## trackerType (13 tracked games; 145 = `"None"`)

Value is a string. Distribution: `None`(145), then one each of:
`hades, messenger, citizen-sleeper, cast-n-chill, cursed-to-golf, hollow-knight, hitman, dead-cells, lone-ruin, sayonara-wild-hearts, under-the-island, gonner, mina-the-hollower`.

Note: the data still carries the *old* bespoke `trackerType` strings even for trackers the web app now renders via StructuredTracker (Phase 1 consolidation changed rendering, not the stored type). Native migration should map these to the two target engines (objective schema / run template) rather than preserving the string.

### structuredData (5 games — the schema-driven trackers)
```
{ schemaVersion, categories, runs, tags, sources, generatedAt, generatedBy }
```
`generatedBy` distinguishes AI-generated vs built-in. `categories` holds the section→item tree. This is the direct input to the native `TrackerSchemaRecord` (jsonData) + `TrackerStateRecord` split.

### clears (9 games)
`[{ id, clearedAt: ISO }]` — completion events. Roadmap: fold into `completionEvents`.

## Maps (2 games)

```
Map:    { id, name, type, imageUrl, storageType, storagePath, markers, addedAt }
Marker: { id, category, label, notes, x, y, createdAt }
```
- `storageType`: `upload` (both) — images live in Supabase Storage; blob holds only metadata + path.
- `type`: `world` / `area`.
- `marker.category`: e.g. `warning` (also collectible/note/secret per app).
- `x, y`: marker coordinates (normalize to 0…1 for native, per roadmap).

## Migration implications (feed into 7g #2 — native domain model)

1. Pick canonical blob by newest `updated_at`; the other 19 are historical adoptions — keep for reconciliation, don't merge.
2. `library[]` → `Game` rows; drop `games` (always empty), `complexity`, `coverColor`, `yearPlayed`, root `currentSaveId`.
3. `saves[]` → `Playthrough` + child `Session[]`; persist `activeSession`.
4. `clears[]` → `CompletionEvent[]`.
5. `structuredData` → `TrackerSchemaRecord` (immutable jsonData) + `TrackerStateRecord` (mutable progress); map legacy `trackerType` strings onto objective-vs-run engine.
6. `maps[]`/`markers[]` → `GameMap` + `Marker`; normalize x/y; Storage bytes stay in Supabase (metadata migrates, images referenced by path).
