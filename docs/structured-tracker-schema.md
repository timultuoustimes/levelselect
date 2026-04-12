# Structured Tracker Schema (v1 draft)

The **structured tracker** is a generic, schema-driven tracker that can
represent most games without a custom React component. It's the target
output format for the AI tracker generator (Phase 3) and the rendering
target of the `StructuredTracker` component (Phase 2).

Custom hand-built trackers (`HadesTracker`, `CitizenSleeperTracker`,
`LoneRuinTracker`) are **not** replaced — they remain for games that
need specialized UI. The structured tracker covers everything else,
which is now the majority of the user's library.

## Design principles

1. **Flat concepts over clever taxonomies.** One `categories` array with
   a type discriminator handles checklists, collectibles, leveled items,
   and ordered sequences. No separate top-level fields for "questlines"
   or "collectibles" — they're all categories with a different `type`.
2. **Optional-by-default fields.** Every game fills in only what it
   needs. A linear indie platformer might use one `checklist` category
   and nothing else. A Metroidvania might use six categories of mixed
   types plus run templates.
3. **Non-breaking additions only.** New fields are always optional.
   Existing tracker data keeps working forever. The `schemaVersion`
   field lets the renderer migrate silently when shapes change.
4. **Freeform per-item metadata** via `metadata: {}`. Charm notch
   costs, grub rewards, shrine locations, geo prices — anything
   game-specific goes in there without schema bloat. Rendered as a
   generic key-value list.
5. **Source attribution is load-bearing.** Every generated tracker
   records where its data came from (`sources` array). Required for
   CC-BY-SA wiki content if this app is ever shipped publicly.

## Top-level shape

```ts
interface StructuredTrackerData {
  schemaVersion: 1;

  // Generation provenance
  generatedAt: string;                    // ISO 8601
  generatedBy: 'user' | string;           // 'user' | 'claude-sonnet-4-6' | ...
  sources: Source[];                       // attribution + traceability

  // Progression (the main thing)
  categories: Category[];

  // Optional: roguelike run structure
  runTemplate?: RunTemplate;
  runs: Run[];                             // always present, may be []

  // Game-level metadata
  estimatedHours?: number;
  completionNotes?: string;                // free-text notes about 100%/true-ending
  tags?: string[];                         // free-form game-level tags
}

interface Source {
  type: 'web' | 'paste' | 'file' | 'user';
  url?: string;
  title?: string;
  license?: string;                        // e.g. 'CC-BY-SA-3.0'
  excerpt?: string;                        // short snippet for transparency
}
```

## Categories

A category is a bucket of related trackable items. Its `type` controls
how the renderer displays the items and which fields on each item are
meaningful.

```ts
interface Category {
  id: string;                              // stable, e.g. 'charms'
  name: string;                            // display name, e.g. 'Charms'
  description?: string;                    // optional helper text
  type: CategoryType;
  tags?: string[];                         // e.g. ['dlc:godmaster', 'optional']
  items: Item[];
}

type CategoryType =
  | 'checklist'      // flat list of independent yes/no items
  | 'collectibles'   // like checklist, but counted; often has locations
  | 'leveled'        // items with rank 0..maxRank
  | 'sequence';      // ordered checklist (questlines, endings, story arcs)
```

### `checklist` vs `collectibles`

Both are done/not-done items, but they render differently and
communicate different intent:

- **`checklist`**: discrete milestones. Bosses beaten, achievements,
  missions completed. Rendered as a flat list of checkboxes. Progress
  shown as "7 / 12".
- **`collectibles`**: countable pick-up-able things. Charms, grubs,
  mask shards, Korok seeds. Rendered as a grid or compact list with a
  prominent count ("32 / 46 grubs"). Items typically have `location`
  set.

Functionally they're the same — the renderer chooses different layouts.

### `leveled`

Items with a rank from 0 to `maxRank`. Optional `rankNames` gives each
rank a display name.

```ts
// Example: Nail upgrades in Hollow Knight
{
  id: 'nail-upgrades',
  name: 'Nail Upgrades',
  type: 'leveled',
  items: [{
    id: 'nail',
    name: 'Nail',
    rank: 0,
    maxRank: 4,
    rankNames: ['Old Nail', 'Sharpened', 'Channelled', 'Coiled', 'Pure'],
    description: 'Upgraded by the Nailsmith in the City of Tears.',
  }],
}
```

**When `rankNames` isn't enough** — if each rank needs its own
description or unlock condition (e.g. Hades weapon aspects, where
rank 3 vs rank 5 is a meaningful mechanical difference), we'll add an
optional `ranks?: Rank[]` field in a future schema revision. That
change is non-breaking: old items use `rankNames`, new items use
`ranks`. We're punting it until we actually hit a case that needs it.

### `sequence`

An ordered series of steps representing one narrative or objective
arc. Replaces what was previously conceptualized as "questlines."
Steps are just items marked as done in order.

```ts
// Example: Hollow Knight ending paths
{
  id: 'endings',
  name: 'Endings',
  type: 'sequence',
  items: [{
    id: 'ending-dream-no-more',
    name: 'Dream No More',
    description: 'Acquire the Dream Nail, defeat The Radiance.',
    done: false,
    missable: false,
  }, {
    id: 'ending-embrace-the-void',
    name: 'Embrace the Void',
    description: 'Complete the Path of Pain and defeat the Absolute Radiance (requires Godmaster DLC for the full path).',
    tags: ['dlc:godmaster'],
  }],
}
```

If we later need true cross-category prerequisites (e.g. "ending X
requires charm Y equipped"), we'll add `prerequisites?: ItemRef[]` to
items. Non-breaking.

## Items

```ts
interface Item {
  id: string;
  name: string;
  description?: string;

  // Acquisition info
  location?: string;                       // where you find it
  source?: string;                         // how you get it ('Shop: Sly', 'Defeat Hornet 1')
  missable?: boolean;                      // can be permanently locked out

  // Progression state
  done: boolean;                           // for checklist/collectibles/sequence
  rank: number;                            // for leveled; 0 if untouched
  maxRank?: number;                        // for leveled
  rankNames?: string[];                    // for leveled; length = maxRank + 1

  // Spoiler handling
  hideUntilDiscovered?: boolean;           // render as "???" until user reveals or completes
  revealed?: boolean;                      // user manually unhid it

  // Freeform
  tags?: string[];
  metadata?: { [key: string]: string | number | boolean };

  // Notes
  notes?: string;                          // user-editable per-item notes
}
```

### `done`, `rank`: one of them is meaningful per item

- `checklist`, `collectibles`, `sequence` items: `done` is the
  source of truth; `rank` is ignored.
- `leveled` items: `rank` is the source of truth; `done` is computed
  from `rank >= maxRank` when the renderer needs a boolean.

### Spoiler hiding

When `hideUntilDiscovered: true`, the renderer shows the item as
`???` with a "reveal" button. Once either:

- the user clicks "reveal" (sets `revealed: true`), OR
- the user marks the item `done: true` (for checklists) or raises
  `rank` above 0 (for leveled),

the real name and description show. `revealed` is persistent —
hitting reveal stays revealed even after a page refresh. This lets
users unhide individual spoilers without abandoning the feature for
the whole tracker.

### `metadata`: freeform game-specific extras

No structured schema. Renderer displays it as a small key-value list
below the description. Claude (or a human author) puts whatever's
useful:

```ts
// Charm in Hollow Knight
metadata: { notchCost: 3, isOvercharmed: false }

// Grub in Hollow Knight
metadata: { reward: '1 Geo + 1 Rancid Egg' }

// Shrine in Breath of the Wild
metadata: { region: 'Hyrule Field', quest: 'Trial of Thunder' }
```

## Run template

Optional. Only present for games with roguelike or run-based structure.

```ts
interface RunTemplate {
  fields: RunField[];
  outcomes: string[];                      // default ['victory', 'death', 'abandoned']
}

interface RunField {
  id: string;
  label: string;
  type: 'text' | 'select' | 'number';
  options?: string[];                      // for type 'select'
  required?: boolean;
}

interface Run {
  id: string;
  startedAt: string;                       // ISO
  endedAt?: string;
  values: { [fieldId: string]: string | number };
  outcome: string;
  notes?: string;
}
```

Games without runs simply omit `runTemplate` and leave `runs` as `[]`.

## Example: Hollow Knight partial fill

This is a partial example showing every category type at least once.
The real Hollow Knight tracker will have ~15 categories and ~200 items.
The hand-authored full version lives in `src/data/hollowKnightData.js`
(Phase 2).

```ts
{
  schemaVersion: 1,
  generatedAt: '2026-04-11T00:00:00Z',
  generatedBy: 'user',
  sources: [{
    type: 'user',
    title: 'Hand-authored by hand as schema reference',
  }],

  categories: [
    // --- checklist example ---
    {
      id: 'main-bosses',
      name: 'Main Bosses',
      type: 'checklist',
      items: [
        { id: 'false-knight', name: 'False Knight',
          location: 'Forgotten Crossroads', done: false },
        { id: 'hornet-1', name: 'Hornet Protector',
          location: 'Greenpath', done: false },
        { id: 'mantis-lords', name: 'Mantis Lords',
          location: 'Fungal Wastes', done: false },
        { id: 'soul-master', name: 'Soul Master',
          location: 'City of Tears', done: false },
        { id: 'hollow-knight', name: 'The Hollow Knight',
          location: 'Temple of the Black Egg', done: false },
      ],
    },

    // --- collectibles example, with metadata + missable ---
    {
      id: 'charms',
      name: 'Charms',
      description: '45 charms. Some are missable on certain routes.',
      type: 'collectibles',
      items: [
        { id: 'charm-wayward-compass', name: 'Wayward Compass',
          location: 'Forgotten Crossroads',
          source: 'Purchased from Iselda',
          metadata: { notchCost: 1 }, done: false },
        { id: 'charm-grubsong', name: 'Grubsong',
          location: 'Forgotten Crossroads (Grubfather)',
          source: 'Rescue 10 grubs',
          metadata: { notchCost: 1 }, done: false },
        { id: 'charm-grimmchild', name: 'Grimmchild',
          location: 'Howling Cliffs',
          source: 'Start the Grimm Troupe ritual',
          missable: true,
          tags: ['dlc:grimm-troupe', 'route-exclusive'],
          metadata: { notchCost: 2 }, done: false },
        { id: 'charm-carefree-melody', name: 'Carefree Melody',
          location: 'Howling Cliffs (Nymm)',
          source: 'Banish the Grimm Troupe',
          missable: true,
          tags: ['dlc:grimm-troupe', 'route-exclusive'],
          metadata: { notchCost: 3 }, done: false },
      ],
    },

    // --- leveled example ---
    {
      id: 'nail-upgrades',
      name: 'Nail Upgrades',
      type: 'leveled',
      items: [{
        id: 'nail',
        name: 'Nail',
        description: 'Upgrade with pale ore + geo at the Nailsmith.',
        rank: 0,
        maxRank: 4,
        rankNames: ['Old Nail', 'Sharpened', 'Channelled', 'Coiled', 'Pure'],
      }],
    },

    // --- sequence example, with spoiler hiding ---
    {
      id: 'endings',
      name: 'Endings',
      description: 'Multiple endings. Names are hidden until you reach them.',
      type: 'sequence',
      items: [
        { id: 'ending-hollow-knight', name: 'The Hollow Knight',
          description: 'The default ending.',
          hideUntilDiscovered: true, done: false },
        { id: 'ending-sealed-siblings', name: 'Sealed Siblings',
          description: 'Acquire Void Heart, then defeat The Hollow Knight.',
          hideUntilDiscovered: true, done: false },
        { id: 'ending-dream-no-more', name: 'Dream No More',
          description: 'Acquire Void Heart, enter the dream, defeat The Radiance.',
          hideUntilDiscovered: true, done: false },
        { id: 'ending-embrace-the-void', name: 'Embrace the Void',
          description: 'Complete Pantheon of Hallownest (Godmaster).',
          tags: ['dlc:godmaster'],
          hideUntilDiscovered: true, done: false },
      ],
    },
  ],

  runs: [],

  estimatedHours: 40,
  completionNotes: '112% requires all charms including route-exclusive ones. Pantheons require Godmaster DLC.',
  tags: ['metroidvania', 'soulslike', 'indie'],
}
```

## Storage location

Structured tracker data is stored as a field on the save object in the
existing `game_data` Supabase row:

```ts
{
  // ...existing save fields
  structuredData: StructuredTrackerData,
}
```

This means:
- Existing sync (localStorage + Supabase debounced writes) works unchanged.
- The save object continues to carry sessions, playtime, rating, review, etc.
  — `structuredData` is just one more field inside it.
- Games with a custom tracker (Hades, etc.) won't have `structuredData`;
  `Library.jsx` routes them to their custom component as today.

## Rendering rules

`StructuredTracker` renders top-to-bottom:

1. Optional summary header (progress bars per category).
2. Each category as a collapsible section.
3. Each item in its type-appropriate layout:
   - `checklist` → list of checkboxes, one per row.
   - `collectibles` → grid or compact list, prominent count in section header.
   - `leveled` → stepper (−/+) with current rank name shown.
   - `sequence` → vertical ordered list with connector lines between steps.
4. Existing `SessionPanel` appears below (shared with other trackers).
5. Optional run template editor below that if present.

Items with `hideUntilDiscovered: true` show as `???` with a reveal button
unless `revealed: true` or the item is marked done.

Items with `missable: true` display a warning indicator.

## AI generator target (Phase 3 preview)

The Supabase Edge Function `ai-tracker-generator` will use Claude's
[tool-use structured output](https://docs.claude.com/en/docs/build-with-claude/tool-use/overview)
feature, defining a single tool whose input schema matches this file.
Claude calls the tool; the edge function unwraps the tool input and
returns it as the function response.

System prompt (cached) contains:
- This schema definition
- 2–3 few-shot examples (starting with the hand-authored Hollow Knight
  tracker as the primary reference)
- Instructions on which category types to prefer for which content
- Instructions on missable detection, DLC tagging, source attribution
- Instructions to mark spoilery items with `hideUntilDiscovered: true`

Input modes:
- `auto` — only the game name + IGDB metadata; `web_search` tool enabled
- `url` — server-side fetch the URL, pass text to Claude; web_search as gap-filler
- `paste` — pasted text in the prompt; web_search as gap-filler
- `file` — PDF/txt/md as native content block; web_search as gap-filler

## Schema evolution

Breaking changes bump `schemaVersion`. Non-breaking additions
(new optional fields) do not. The renderer reads `schemaVersion` and
applies migrations silently for old data.

Known future additions being punted:
- `ranks: [{ name, description, unlockCondition }]` for rich per-rank
  info on leveled items (needed only if a generic-tracker game wants
  Hades-aspect-level detail)
- `prerequisites: itemId[]` on items for cross-category dependencies
- `progressMetrics: [{ label, formula }]` for computed percentages
  like Hollow Knight's 112%
- A `runs` analytics view for roguelike trackers

None of these are in v1. Add only when a real game needs them.
