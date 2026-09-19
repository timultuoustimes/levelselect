# What the retired web app still does that the native app doesn't

The original React web app (`src/`) is not deployed and not maintained, but it is kept in the repo because it is currently the only record of a few things the native app hasn't caught up to. This file exists so that stops being true — when the list is empty, the web app can go.

Compiled 2026-08-22 by reading `src/components/Library.jsx` (`LibraryStats`) against `native/LevelSelect/LevelSelect/UI/StatsView.swift`. **Extended 2026-08-25** with a full sweep of `src/` against `native/` — the sections below now cover everything found, not only stats.

## Stats

The native Stats tab has: library size, completions, most played, recent play (this week / this month), session counts.

The web app's Stats view has all of the following, and the native one has none of them:

| Web app | What it showed |
|---|---|
| Completion rate | Completed as a percentage of the library, as a headline number |
| Average rating | With the count of games actually rated, so one 5-star game doesn't read as "5.0 average" |
| Rating distribution | How many games at each star, as bars |
| Status breakdown | Every status as a proportion of the library, not just a count |
| By platform | Games per system, ranked, as bars |
| By franchise | Top 10 franchises by count |
| Games played by year | Distribution across release years |
| Top tags | The 20 most-used tags |

Two notes on porting these rather than copying them:

**Some are now navigation rather than statistics.** The native app has facet browsing — tapping a developer, publisher, genre or year opens everything in the library matching it. "By platform" and "by franchise" as *stats* would be a second way to see the same relationships, so they may want to be entry points into that rather than bars for their own sake.

**Average rating needs its denominator.** The web version showed the rated count beside it for a reason: most libraries have a minority of games rated, and an average without that context is misleading.

## Per-game bespoke trackers

The web app carries hand-written trackers for specific games — Hades, Dead Cells, Mina the Hollower, The Messenger, Lone Ruin, Citizen Sleeper, Cursed to Golf, GONNER — each with its own components and, in Lone Ruin's case, its own analytics view (`LoneRuinAnalytics.jsx`).

These are **deliberately not ported**. The native app replaced the whole idea with generated and pasted trackers plus the built-in tracker set, which is the reason it works for any game rather than eight. They are listed here only so nobody mistakes their absence for an oversight.

The one thing worth mining from them is shape: they are evidence of what a really good tracker for a specific game looks like, which is a useful test for whether a generated one is good enough.

*(2026-08-25 refinement: "deliberately not ported" covers the bespoke **rendering**, and that gap closed — rank pips, keepsake hearts and Alt chips shipped in `3418d3f`. Two game-agnostic pieces of the bespoke trackers are real parity items and are listed below: run analytics and run setup pickers.)*

## Maps — the largest remaining gap

The web app has a complete maps subsystem (`src/components/maps/`, `src/utils/mapStorage.js`); the native app has none of it (zero map/marker references in `native/`). What the web version does:

| Piece | Where |
|---|---|
| Multiple maps per game, images uploaded to Supabase Storage (`map-images` bucket) | `mapStorage.js` |
| Zoom/pan viewer with crisp-zoom fit logic, in modal and side-panel modes | `MapViewer.jsx` (556 lines) |
| Markers with categories and colors, tap-to-place, edit modal | `MapViewer.jsx`, `MarkerEditModal.jsx` |
| Map linked to a tracker category (`linkedCategoryId`) so a category can open "its" map | `mapStorage.js:30`, `AddMapModal.jsx:77` |
| `map-finder` edge function for locating map images online | `supabase/functions/map-finder` (still deployed) |

The beta roadmap's P2 spec ("offline full-resolution cache and map↔tracker links") **exceeds** the web version: web has no offline cache and links at category level only, not per item. Parity is the table above; the P2 extras are aspiration.

## Run tracking — two game-agnostic gaps ✅ CLOSED 2026-08-25

Both gaps below were closed generically: run fields gained `optionsFrom` /
`onlyUnlocked` / `dependsOn` / `phase` (schema JSON keys, no schema version),
`RunFieldSupport` resolves options from the tracker's own categories with
full-list fallbacks, End Run collects end-phase fields (gods, where you fell),
and a collapsible Analytics section shows win rate grouped by every
option-backed field — fractions always visible, percentages only from three
uses. The Hades template regenerated with aspects scoped to the chosen weapon
(via item `location`), keepsakes filtered to unlocked, and the two missing
fields restored. Not carried over: web's per-weapon hammer lists, and
outcome-conditional fields ("Fell in" shows even after an escape — blank is
harmless). The original gap description, for the record:

Native has the run engine (start/log/end, outcomes, history, per-template fields, a win-rate line) but not:

1. **Run analytics.** Web `AnalyticsSection` (`src/components/hades/RunsTab.jsx:128`): weapon win rates, where defeats happen, gods present in victories, plus outcome/weapon filters on history. `LoneRuinAnalytics.jsx` is a second instance. Native has no aggregation at all beyond the single win-rate line.
2. **Run setup pickers.** Web run fields draw options from the tracker's own state — keepsakes filtered to what's unlocked with full-list fallback (`RunView.jsx:64-66`), aspects scoped to the selected weapon. Native's Hades template has `select` on weapon only; aspect/keepsake/heat are free text, and `gods`/`deathLocation` (which feed two of the three analytics) aren't recorded at all — even though the option lists sit in the same `builtin-trackers.json` entry as tracker categories.

Both are logged as a background task (fix pickers first — analytics over free text fragments on typos).

## Bulk editing

Web library select mode: multi-select with **bulk status change, bulk platform assignment, bulk delete** (`Library.jsx:1232-1240,1703`). Native has none (single-game context menus only). This was "Delay: bulk editing" in the conversion plan and then never resurfaced on any list — it is recorded here so the omission is visible.

## Stats

*(unchanged below — see the table; working plan now lives in the vault note "LevelSelect stats expansion and Replay")*

## Shipped at or beyond web parity — verified 2026-08-25, for the record

Library grid/list with sort, status/system/ownership filters and adjustable cover sizes · facet browsing (replacing web's Platform/Franchise hubs) · home shelves, Continue Playing, pinning · sessions with editing, manual logging, discard, and detached-session recovery · playthroughs (web "saves") · the schema tracker with paste import, merge review, hidden items, counters, ranks/pips/hearts/alts · stepped AI generation (beyond web's one-shot modal) · CSV import · JSON export · IGDB add-game with id search · tags, notes, review · related games · sync status UI (beyond web's SyncBar) · RetroAchievements account sync and import (no web equivalent) · wishlist with Deku integration (web had a hardcoded link) · critic scores · collections with templates · widgets, Live Activities, App Intents, watch app (native-only).

## The build-time dependency that outlives the web app

`scripts/build-builtin-trackers.mjs` **imports from `src/data/*` and `src/utils/structuredFactory.js`** to generate `native/LevelSelect/LevelSelect/Resources/builtin-trackers.json`. So "the web app can go" never meant deleting all of `src/`: either `src/data` + that one util stay behind as the generator's inputs, or the generated JSON is declared hand-maintained and the script retires with the app. Decide when the time comes; until then this file is the reason a clean `rm -rf src` would break a native resource build.
