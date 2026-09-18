// Supabase Edge Function: AI Tracker Generator
// Calls the Anthropic Claude API to auto-generate structured game tracker data.
// Deploy with: supabase functions deploy ai-tracker-generator
//
// Required secrets (set via: supabase secrets set KEY=value):
//   ANTHROPIC_API_KEY — from console.anthropic.com

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';
import { gameIdentity, identityContext, identityQualifier } from '../_shared/igdb.ts';
import {
  categoryTokenBudget,
  FULL_GENERATION_MAX_TOKENS,
  PLAN_MAX_TOKENS,
  quotaPlanForAI,
} from '../_shared/ai-limits.ts';
import {
  keepRequestedCategories,
  parseRequestedCategories,
  type RequestedCategory,
  scopeInstructions,
  slugify,
} from '../_shared/tracker-scope.ts';

// Input caps — every one of these bounds what reaches the Anthropic API.
const MAX_GAME_NAME = 200;
const MAX_PAYLOAD = 60_000; // pasted guide text
const MAX_URL = 500;
const MAX_CATEGORY_NAME = 80;
// 'plan' asks for the SHAPE of a tracker and no items; 'category' fills exactly
// one named category. Both exist because the only unit this function used to
// know was "the whole tracker", which is the wrong unit twice over: you cannot
// ask it what a tracker for a game should even contain, and filling one part of
// a big game meant generating all of it and discarding the rest — Breath of the
// Wild timed out doing that for a single 18-item category.
// 'runFields' suggests what a run records (loadout, score, the list it fills)
// for a game that already has a tracker.
const ALLOWED_MODES = new Set(['auto', 'paste', 'url', 'plan', 'category', 'runFields']);

// The shapes a person can ask a plan to stay inside. The app offers them by
// genre; the instruction for each is here so the wording lives in one place.
const SHAPES: Record<string, string> = {
  story: 'the main story only: chapters, levels or main quests in order as one "sequence" category, plus the major bosses if the game has them. Nothing optional.',
  checklist: 'a plain checklist: the few sets a typical player cares about, as ordinary checklists. No rosters, no sequences, nothing counted.',
  roster: 'party building: a "roster" category for the recruitable characters (with fields and party size) and the supports or bonds between them if the game has them.',
  completionist: 'everything the game counts toward 100%: every collectible set, side quest line, upgrade and ending.',
  collectibles: 'the collectible sets only.',
  unlocks: 'what a roguelike unlocks between runs: characters, weapons, upgrades, bosses beaten and endings. No run-by-run content.',
  runs: 'a small tracker for a roguelike played for its runs: the bosses and endings, kept short, since the runs themselves are logged separately.',
  seasonal: 'a life sim: the collections (fish, bugs, crops, recipes, museum sets) and relationships, with filters for seasons and weather on the items.',
};
const MAX_SHAPES = 3;
const MAX_LISTS = 30;

// ─── Schema definition (embedded in system prompt) ───────────────────────────

const SYSTEM_PROMPT = `You are a game tracker data generator. Your job is to produce structured JSON tracker data for video games, so a player can track their progress through the game.

## Output format

Call the generate_tracker_data tool with the complete tracker data. The schema has these top-level fields:
- categories: array of category objects (REQUIRED)
- runTemplate: optional, for roguelike/run-based games
- estimatedHours: approximate time to complete
- completionNotes: free-text notes about 100% completion
- tags: game-level tags (genres, descriptors)

## Category types

Each category has a \`type\` that controls how items render:

1. **checklist** — flat yes/no items. Use for: bosses, missions, achievements, story chapters.
2. **collectibles** — countable items, often with locations. Use for: items to find, charms, upgrades, collectible sets.
3. **leveled** — items with rank 0..maxRank. Use for: upgradeable gear, spells with tiers, skill trees.
   - Include \`maxRank\` and optionally \`rankNames\` (array of length maxRank+1, e.g. ["Not acquired", "Base", "Upgraded"]).
4. **sequence** — ordered progression steps, done in order. Use for: story chapters, questlines, endings.
5. **roster** — one item per recruitable character (units, party members, confidants, Pokémon). Use for: who you can recruit in a party RPG or tactics game (Fire Emblem, Persona, Octopath, Xenoblade, Suikoden).
   - Include \`fields\`: up to 4 of \`{ id, name, type: "text"|"number"|"choice"|"toggle", options? }\` for what a player records about each character in THEIR playthrough — typically Class (choice, with the game's class names as options when you know them), Level (number), and In party (toggle, id "party"). Never stats, growth rates or calculations.
   - Include \`partySize\` when the game limits how many can be deployed at once.
   - Missable recruits: \`missable: true\`, and \`requires\` / \`locksOut\` when a route decides who joins.

## Item fields

Each item in a category can have:
- id (string, required) — stable kebab-case identifier
- name (string, required) — display name
- description (string) — optional helper text
- location (string) — where to find it in the game world
- source (string) — how to acquire it ("Defeat boss X", "Purchase from shop")
- missable (boolean) — true if permanently lockable
- hideUntilDiscovered (boolean) — true for spoiler items (show as "???" until revealed)
- tags (string[]) — for DLC grouping, categories
- filters (string[]) — only for life sims and seasonal games (Stardew Valley, Animal Crossing, Story of Seasons): the player-facing conditions an item depends on, as short Title Case words the player filters by — seasons ("Spring"), weather ("Rain"), time of day ("Night"), place types ("Ocean"). Omit "All"/"Any".
- maxRank, rankNames — for leveled items only
- metadata (object) — freeform game-specific extras (costs, stats, etc.)

## Run template (optional, for roguelikes)

If the game has a run-based structure (roguelikes, roguelites, arcade modes):
- fields: array of { id, label, type: "text"|"select"|"multi"|"number"|"time"|"list", options?: string[], phase?: "start"|"end", best?: "high"|"low" }
  - "select": one pick before the run (weapon, character, deck). "multi": several picks.
  - "number" / "time": a score, a floor reached, a clear time (seconds). Use phase "end" and set best ("high" for scores, "low" for times).
  - "list": what the run picks up while it's live — boons, relics, jokers — with options when the set is known.
- outcomes: array of strings like ["victory", "death", "abandoned"]

## Spoiler policy

- Story-critical reveals, secret bosses, endings: set hideUntilDiscovered: true
- Regular content you encounter naturally: leave visible
- When in doubt, hide it — the user can always reveal manually

## Guidelines

1. Be thorough but don't pad. Include real game content, not filler.
2. Use area-level locations when you know them, omit location if unsure.
3. For DLC content, add tags like "dlc:expansion-name".
4. Group items logically — one category per concept (e.g., "Main Bosses", "Charms", "Spells"), not one giant checklist.
5. For games with 50+ collectibles of one type (like grubs, seeds, shrines), list them individually with area-based names if possible, or numbered if not.
6. Set missable: true only for items that can be permanently locked out.
7. Include completion notes explaining what counts toward 100% if the game has a defined completion metric.
8. For the id field, use kebab-case derived from the name (e.g., "boss-false-knight", "charm-wayward-compass").

## Example (partial — Hollow Knight charms category)

{
  "id": "charms",
  "name": "Charms",
  "description": "Equippable charms with notch costs.",
  "type": "collectibles",
  "items": [
    { "id": "charm-wayward-compass", "name": "Wayward Compass", "location": "Forgotten Crossroads", "source": "Purchased from Iselda", "metadata": { "notchCost": 1 } },
    { "id": "charm-grimmchild", "name": "Grimmchild", "location": "Howling Cliffs", "source": "Grimm Troupe ritual", "missable": true, "tags": ["dlc:grimm-troupe", "route-exclusive"], "metadata": { "notchCost": 2 } }
  ]
}`;

// ─── Tool definition for structured output ───────────────────────────────────

// What a roster's characters record per playthrough. Four kinds, matching the
// app's `TrackerFieldDTO.Kind`; anything else is dropped by `cleanFields`.
const ROSTER_FIELDS_SCHEMA = {
  type: 'array',
  description: 'Roster only: up to 4 things a player records about each character in their own playthrough (Class, Level, In party). No stats.',
  items: {
    type: 'object',
    required: ['id', 'name', 'type'],
    properties: {
      id:      { type: 'string', description: 'kebab-case; use "party" for the in-party toggle' },
      name:    { type: 'string' },
      type:    { type: 'string', enum: ['text', 'number', 'choice', 'multi', 'toggle'] },
      options: { type: 'array', items: { type: 'string' } },
      max:     { type: 'number', description: 'multi only: how many can be picked at once (2 skills, 4 moves)' },
    },
  },
};

const FIELD_KINDS = new Set(['text', 'number', 'choice', 'multi', 'toggle']);

function cleanFields(raw: unknown): Array<Record<string, unknown>> | undefined {
  if (!Array.isArray(raw)) return undefined;
  const seen = new Set<string>();
  const out = raw
    .filter((f) => f && typeof f.id === 'string' && typeof f.name === 'string' && FIELD_KINDS.has(f.type))
    .map((f) => ({
      id: String(f.id).trim().toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^[-_]+/, '').slice(0, 40),
      name: String(f.name).trim().slice(0, 40),
      type: f.type,
      ...((f.type === 'choice' || f.type === 'multi') && Array.isArray(f.options)
        ? { options: f.options.filter((o: unknown) => typeof o === 'string').map((o: string) => o.slice(0, 40)).slice(0, 60) }
        : {}),
      ...(f.type === 'multi' && Number.isFinite(f.max) && Number(f.max) > 0
        ? { max: Math.min(20, Math.round(Number(f.max))) }
        : {}),
    }))
    .filter((f) => f.id && f.name && !seen.has(f.id) && seen.add(f.id))
    .slice(0, 4);
  return out.length ? out : undefined;
}

const TRACKER_TOOL = {
  name: 'generate_tracker_data',
  description: 'Generate complete structured tracker data for a game. Call this tool exactly once with the full tracker data.',
  input_schema: {
    type: 'object',
    required: ['categories'],
    properties: {
      categories: {
        type: 'array',
        description: 'Array of category objects. Each game should have at least one.',
        items: {
          type: 'object',
          required: ['id', 'name', 'type', 'items'],
          properties: {
            id:          { type: 'string', description: 'Stable kebab-case identifier' },
            name:        { type: 'string', description: 'Display name' },
            description: { type: 'string' },
            type:        { type: 'string', enum: ['checklist', 'collectibles', 'leveled', 'sequence', 'roster'] },
            tags:        { type: 'array', items: { type: 'string' } },
            fields:      ROSTER_FIELDS_SCHEMA,
            partySize:   { type: 'number', description: 'For a roster: how many can be deployed at once.' },
            items: {
              type: 'array',
              items: {
                type: 'object',
                required: ['id', 'name'],
                properties: {
                  id:                  { type: 'string' },
                  name:                { type: 'string' },
                  description:         { type: 'string' },
                  location:            { type: 'string' },
                  source:              { type: 'string' },
                  missable:            { type: 'boolean' },
                  hideUntilDiscovered: { type: 'boolean' },
                  tags:                { type: 'array', items: { type: 'string' } },
                  filters:             { type: 'array', items: { type: 'string' }, description: 'Life sims only: seasons, weather, time of day, place types the player filters by.' },
                  maxRank:             { type: 'number' },
                  rankNames:           { type: 'array', items: { type: 'string' } },
                  countTarget:         { type: 'number', description: 'For a set tracked as a running total rather than individual rows (e.g. 900 Korok Seeds): the target count.' },
                  metadata:            { type: 'object', additionalProperties: true },
                },
              },
            },
          },
        },
      },
      runTemplate: {
        type: 'object',
        properties: {
          fields: {
            type: 'array',
            items: {
              type: 'object',
              required: ['id', 'label', 'type'],
              properties: {
                id:      { type: 'string' },
                label:   { type: 'string' },
                type:    { type: 'string', enum: ['text', 'select', 'multi', 'number', 'time', 'list'] },
                options: { type: 'array', items: { type: 'string' } },
                phase:   { type: 'string', enum: ['start', 'end'] },
                best:    { type: 'string', enum: ['high', 'low'] },
              },
            },
          },
          outcomes: { type: 'array', items: { type: 'string' } },
        },
      },
      estimatedHours:  { type: 'number' },
      completionNotes: { type: 'string' },
      tags:            { type: 'array', items: { type: 'string' } },
    },
  },
};

// A plan is a list of headings and rough sizes. No items, which is the whole
// point: it comes back in seconds instead of minutes, and the user approves the
// shape before anyone spends two minutes filling it in.
const PLAN_TOOL = {
  name: 'plan_tracker_categories',
  description: 'Propose the categories a tracker for this game should have. Names and approximate sizes only — do NOT list individual items. Call this tool exactly once.',
  input_schema: {
    type: 'object',
    required: ['categories'],
    properties: {
      categories: {
        type: 'array',
        description: 'Between 2 and 10 categories, ordered by how central they are to the game.',
        items: {
          type: 'object',
          required: ['name', 'plannedCount'],
          properties: {
            name: {
              type: 'string',
              description: 'What players and guides actually call this set, e.g. "Shrines", "Divine Beasts", "Korok Seeds". Plain plural noun, no game name in it.',
            },
            plannedCount: {
              type: 'number',
              description: 'Approximate number of items. Best known figure; an estimate is fine.',
            },
            type: { type: 'string', enum: ['checklist', 'collectibles', 'leveled', 'sequence', 'roster'] },
            description: { type: 'string', description: 'One short line on what belongs in it.' },
            fields: ROSTER_FIELDS_SCHEMA,
            partySize: { type: 'number', description: 'For a roster: how many can be deployed at once.' },
            counted: {
              type: 'boolean',
              description: 'True when this set is far too large to list individually (roughly 150+) and is better tracked as a running total.',
            },
          },
        },
      },
      estimatedHours:  { type: 'number' },
      completionNotes: { type: 'string' },
    },
  },
};

const CATEGORY_TOOL = {
  name: 'generate_tracker_category',
  description: 'Generate the items for ONE named category. Call this tool exactly once, with that category only.',
  input_schema: {
    type: 'object',
    required: ['category'],
    properties: {
      category: {
        type: 'object',
        required: ['name', 'type', 'items'],
        properties: {
          name:        { type: 'string', description: 'Echo the requested category name back exactly.' },
          description: { type: 'string' },
          type:        { type: 'string', enum: ['checklist', 'collectibles', 'leveled', 'sequence', 'roster'] },
          items:       TRACKER_TOOL.input_schema.properties.categories.items.properties.items,
          fields:      ROSTER_FIELDS_SCHEMA,
          partySize:   { type: 'number' },
        },
      },
    },
  },
};

// ─── Stage 1: find best guide URL for auto mode ──────────────────────────────

async function findGuideUrl(
  apiKey: string,
  gameName: string,
  igdbData: Record<string, unknown> | null,
): Promise<string | null> {
  const meta: string[] = [];
  if (igdbData?.genres)     meta.push(`Genres: ${(igdbData.genres as string[]).join(', ')}`);
  if (igdbData?.developers) meta.push(`Developer: ${(igdbData.developers as string[]).join(', ')}`);

  const prompt = [
    `Search the web for the single best comprehensive guide or wiki page for the game "${gameName}".`,
    meta.length > 0 ? `(${meta.join('; ')})` : '',
    'Return ONLY the URL of the best guide page — no other text, no explanation, just the URL.',
    'Prefer wikis (fandom, wiki.gg, neoseeker, gamefaqs) that cover collectibles and 100% completion.',
  ].filter(Boolean).join(' ');

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 300,
      tools: [{
        type: 'web_search_20250305',
        name: 'web_search',
        max_uses: 2,
      }],
      messages: [{ role: 'user', content: prompt }],
    }),
  });

  if (!res.ok) return null;

  const data = await res.json();
  const textBlock = (data.content || []).find(
    (b: { type: string }) => b.type === 'text'
  ) as { text: string } | undefined;

  if (!textBlock?.text) return null;

  // Extract the first URL-looking string from the response
  const urlMatch = textBlock.text.match(/https?:\/\/[^\s"'<>]+/);
  return urlMatch ? urlMatch[0] : null;
}

// ─── Build Claude API messages ───────────────────────────────────────────────

function buildUserMessage(
  gameName: string,
  igdbData: Record<string, unknown> | null,
  mode: string,
  payload: string | null,
  qualifier = '',
  context = '',
  requested: RequestedCategory[] | null = null,
): string {
  const parts: string[] = [];

  parts.push(`Generate tracker data for the game: "${gameName}"${qualifier}${context}`);

  if (igdbData) {
    const meta: string[] = [];
    if (igdbData.genres)     meta.push(`Genres: ${(igdbData.genres as string[]).join(', ')}`);
    if (igdbData.themes)     meta.push(`Themes: ${(igdbData.themes as string[]).join(', ')}`);
    if (igdbData.gameModes)  meta.push(`Game modes: ${(igdbData.gameModes as string[]).join(', ')}`);
    if (igdbData.developers) meta.push(`Developer: ${(igdbData.developers as string[]).join(', ')}`);
    if (meta.length > 0) {
      parts.push('\nIGDB metadata:\n' + meta.join('\n'));
    }
  }

  if (mode === 'paste' && payload) {
    parts.push('\nThe user provided the following guide/reference text. Use it as your primary source:\n\n' + payload);
  }

  if (mode === 'url' && payload) {
    parts.push(`\nThe user wants you to use this URL as a reference source. Search the web for this page and extract relevant game data from it: ${payload}`);
  }

  if (requested) {
    // A refresh. The unscoped instruction below ("include all major bosses,
    // collectibles, upgrades…") is exactly what added categories the user
    // never had, so it is not sent alongside the list.
    parts.push(scopeInstructions(requested));
    parts.push('\nBe thorough within those categories, using the right category type for each. Call the generate_tracker_data tool with the complete result.');
  } else {
    parts.push('\nBe thorough — include all major bosses, collectibles, upgrades, story progression, and endings. Group items into logical categories using the right category type for each. Call the generate_tracker_data tool with the complete result.');
  }

  return parts.join('\n');
}

function buildPlanMessage(gameName: string, igdbData: Record<string, unknown> | null,
                          qualifier = '', context = '', shapes: string[] = []): string {
  const parts: string[] = [
    `What should a completion tracker for "${gameName}"${qualifier} be divided into?${context}`,
  ];
  if (igdbData) {
    const meta: string[] = [];
    if (igdbData.genres)     meta.push(`Genres: ${(igdbData.genres as string[]).join(', ')}`);
    if (igdbData.themes)     meta.push(`Themes: ${(igdbData.themes as string[]).join(', ')}`);
    if (igdbData.gameModes)  meta.push(`Game modes: ${(igdbData.gameModes as string[]).join(', ')}`);
    if (igdbData.developers) meta.push(`Developer: ${(igdbData.developers as string[]).join(', ')}`);
    if (meta.length > 0) parts.push('\nIGDB metadata:\n' + meta.join('\n'));
  }
  parts.push([
    '\nName the categories only — do NOT list any individual items.',
    'Use the names players and guides actually use for these sets, because the user will see them as headings and may ask for one to be filled in by that name.',
    'Order them by how central they are to finishing the game.',
    'Skip anything that is not really trackable progress (difficulty settings, general tips).',
    'If the game genuinely has one flat list and no sub-structure, say so with a single category.',
    shapes.length
      ? ''
      : 'For a party RPG or tactics game, include a "roster" category for the recruitable characters, with its fields and party size, and use "sequence" for the story chapters.',
  ].join(' '));
  if (shapes.length) {
    // The person chose how big this tracker should be. Staying inside it is
    // the point: someone who asked for the story should not get 14 lists.
    parts.push('\nThe player chose what this tracker is for. Plan ONLY this, and nothing beyond it:');
    for (const shape of shapes) parts.push(`- ${SHAPES[shape]}`);
  }
  return parts.join('\n');
}

function buildRunFieldsMessage(gameName: string, igdbData: Record<string, unknown> | null,
                               qualifier = '', context = '',
                               lists: Array<{ id: string; name: string }> = []): string {
  const parts: string[] = [
    `What should a player record about each run of "${gameName}"${qualifier}?${context}`,
  ];
  if (igdbData?.genres) parts.push(`Genres: ${(igdbData.genres as string[]).join(', ')}`);
  if (lists.length) {
    parts.push('\nThe tracker already has these lists (id: name). When a field picks from one of them, set optionsFrom to its id instead of copying the names:');
    for (const list of lists) parts.push(`- ${list.id}: ${list.name}`);
  }
  parts.push([
    '\nSuggest 2 to 6 fields, the ones this game\'s players actually track:',
    'the loadout chosen before a run (select, or multi for several picks),',
    'what the run picks up while it is live (list — boons, relics, jokers),',
    'and what the run reached (number for a score, depth, heat or ascension; time for a clear time), recorded at the end with best set.',
    'Use the names the game uses. Give options when the set is known and short (under 60); otherwise leave them out.',
    'Also suggest the outcomes a run can end with, in the game\'s own words.',
  ].join(' '));
  return parts.join('\n');
}

const RUN_FIELD_KINDS = new Set(['text', 'select', 'multi', 'number', 'time', 'list']);

const RUN_FIELDS_TOOL = {
  name: 'suggest_run_fields',
  description: 'Suggest what a player records about each run of this game. Call this tool exactly once.',
  input_schema: {
    type: 'object',
    required: ['fields'],
    properties: {
      fields: {
        type: 'array',
        items: {
          type: 'object',
          required: ['id', 'label', 'type'],
          properties: {
            id:          { type: 'string', description: 'kebab-case' },
            label:       { type: 'string' },
            type:        { type: 'string', enum: [...RUN_FIELD_KINDS] },
            options:     { type: 'array', items: { type: 'string' } },
            optionsFrom: { type: 'string', description: 'The id of a tracker list the choices come from.' },
            phase:       { type: 'string', enum: ['start', 'end'] },
            best:        { type: 'string', enum: ['high', 'low'] },
          },
        },
      },
      outcomes: { type: 'array', items: { type: 'string' } },
    },
  },
};

function cleanRunFields(raw: unknown, listIDs: Set<string>): Array<Record<string, unknown>> {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  return raw
    .filter((f) => f && typeof f.id === 'string' && typeof f.label === 'string' && RUN_FIELD_KINDS.has(f.type))
    .map((f) => {
      const numeric = f.type === 'number' || f.type === 'time';
      const picks = f.type === 'select' || f.type === 'multi' || f.type === 'list';
      const from = typeof f.optionsFrom === 'string' && listIDs.has(f.optionsFrom) ? f.optionsFrom : undefined;
      return {
        id: String(f.id).trim().toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^[-_]+/, '').slice(0, 40),
        label: String(f.label).trim().slice(0, 40),
        type: f.type,
        ...(picks && from ? { optionsFrom: from } : {}),
        ...(picks && !from && Array.isArray(f.options)
          ? { options: f.options.filter((o: unknown) => typeof o === 'string').map((o: string) => o.slice(0, 40)).slice(0, 60) }
          : {}),
        ...(f.type !== 'list' && f.phase === 'end' ? { phase: 'end' } : {}),
        ...(numeric && (f.best === 'high' || f.best === 'low') ? { best: f.best } : {}),
      };
    })
    .filter((f) => f.id && f.label && !seen.has(f.id) && seen.add(f.id))
    .slice(0, 8);
}

function buildCategoryMessage(
  gameName: string,
  categoryName: string,
  expectedCount: number | null,
  igdbData: Record<string, unknown> | null,
  payload: string | null,
  qualifier = '',
  counted = false,
  context = '',
  roster = false,
): string {
  const parts: string[] = [
    `Generate ONLY the "${categoryName}" category of a completion tracker for "${gameName}"${qualifier}.${context}`,
  ];
  if (roster) {
    parts.push('This is a ROSTER: one item per recruitable character, type "roster", with missable and requires/locksOut where a route decides who joins. Include fields (Class as a choice with the game\'s class names, Level as a number, In party as a toggle with id "party") and partySize if the game limits deployment. Record-keeping only — no stats or growth rates.');
  }
  // A counted set is decided at the PLAN step and the placeholder has already
  // promised the user a counter. Asking for both "roughly 400 items" and "150+
  // means return one countTarget item" is a contradiction, and the answer came
  // back with an empty items array — a 95-second failure reported as though the
  // category name were wrong.
  if (counted) {
    parts.push(`This set is tracked as a RUNNING TOTAL, not row by row. Return EXACTLY ONE item: name it after the set, set countTarget to the real total (the user's figure is ${expectedCount ?? 'unknown'}, use the real one if you know better), and add nothing else. Do not enumerate the entries.`);
  } else if (expectedCount && expectedCount > 0) {
    parts.push(`The user expects roughly ${expectedCount} items. Treat that as a hint, not a quota — if the real number differs, use the real number.`);
  }
  if (igdbData) {
    const meta: string[] = [];
    if (igdbData.genres)     meta.push(`Genres: ${(igdbData.genres as string[]).join(', ')}`);
    if (igdbData.developers) meta.push(`Developer: ${(igdbData.developers as string[]).join(', ')}`);
    if (meta.length > 0) parts.push('\nIGDB metadata:\n' + meta.join('\n'));
  }
  if (payload) {
    parts.push(`\nUse this page as a reference source — search the web for it and take the ${categoryName} data from it: ${payload}`);
  }
  parts.push([
    `\nNothing outside "${categoryName}" — no other categories, however obviously they belong in the tracker.`,
    'Echo the category name back exactly as given, since it is how the app matches your answer to the placeholder the user made.',
    ...(counted ? [] : [
      'If this set runs to roughly 150 or more near-identical entries (Korok Seeds, Riddler trophies), do NOT list them individually:',
      'return a single item named after the set with countTarget set to the total, so it tracks as a running count.',
    ]),
  ].join(' '));
  // A long list has to be a terse one. 120 shrines with a description and a
  // source apiece is 15k tokens of output, which runs past the 150s edge
  // function ceiling and returns nothing at all — so the detail costs the user
  // the entire category. Name and location carry the checklist; the rest is
  // what makes it never arrive.
  if (!counted && (expectedCount ?? 0) > 60) {
    parts.push([
      '\nThis is a long list, so keep every entry short: an id, a name, and a brief location.',
      'No descriptions, no source text, no metadata, no tags — they would push this past the time limit,',
      'and a list that never arrives is worth less than a plain one that does.',
    ].join(' '));
  }
  return parts.join('\n');
}

/** One Claude call that must come back as a named tool use. */
async function callClaude(
  apiKey: string,
  opts: {
    model: string;
    max_tokens: number;
    tools: unknown[];
    toolName: string;
    userMessage: string;
  },
): Promise<{ input: Record<string, unknown>; usage: unknown } | { error: Response }> {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: opts.model,
      max_tokens: opts.max_tokens,
      system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
      tools: opts.tools,
      tool_choice: { type: 'any' },
      messages: [{ role: 'user', content: opts.userMessage }],
    }),
  });

  if (!res.ok) {
    // Upstream detail goes to logs only — it can echo prompt content and names
    // the backend the app deliberately doesn't expose.
    console.error('Claude API error:', res.status, await res.text());
    return {
      error: jsonResponse({ error: 'The generator is busy right now. Try again in a moment.' }, 502),
    };
  }

  const data = await res.json();
  const block = (data.content || []).find(
    (b: { type: string; name?: string }) => b.type === 'tool_use' && b.name === opts.toolName,
  );
  if (!block) {
    // A tool call cut off mid-write parses as no tool call at all, so a
    // too-long category looked identical to "the model had no idea" and got
    // told to try a better name. Different problem, different advice.
    if (data.stop_reason === 'max_tokens') {
      console.warn(`${opts.toolName} truncated at ${opts.max_tokens} tokens`);
      return {
        error: jsonResponse(
          { error: 'That list was too long to finish in one go. Try splitting it into smaller categories.' },
          422,
        ),
      };
    }
    const said = (data.content || [])
      .filter((b: { type: string }) => b.type === 'text')
      .map((b: { text: string }) => b.text).join('\n');
    console.warn(`no ${opts.toolName} tool call; model said:`, said.slice(0, 500));
    return {
      error: jsonResponse(
        { error: "Couldn't build that from the game name given. Try a more specific name." },
        422,
      ),
    };
  }
  return { input: block.input || {}, usage: data.usage || null };
}

// ─── Main handler ────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) {
    console.error('ANTHROPIC_API_KEY not configured');
    return jsonResponse({ error: 'AI generation is not available right now.' }, 503);
  }

  const { rejection, body } = await guard(req, {
    fn: 'ai',
    killSwitchEnv: 'LS_KILL_AI',
    maxBodyBytes: MAX_PAYLOAD + 8_000,
    quotas: [],
    // Mode still decides the bucket, but only after the shared guard has
    // authenticated, byte-capped, and parsed the one request body. The former
    // clone peek trusted Content-Length as a bound, which raw clients need not.
    resolveQuota: quotaPlanForAI,
    onQuotaError: 'deny',
  });
  if (rejection) return rejection;

  try {
    const igdbData = body?.igdbData as Record<string, unknown> | null | undefined;
    const gameName = typeof body?.gameName === 'string' ? body.gameName.trim() : '';
    let mode = typeof body?.mode === 'string' ? body.mode : 'auto';
    let payload = typeof body?.payload === 'string' ? body.payload : null;
    // The user's own categories, when this is a regeneration. Null for a first
    // generation — and for every request from a build that predates the field,
    // which must behave exactly as it always has.
    const requested = parseRequestedCategories(body?.categories);

    if (!gameName) {
      return jsonResponse({ error: 'gameName is required' }, 400);
    }
    if (gameName.length > MAX_GAME_NAME) {
      return jsonResponse({ error: 'Game name is too long.' }, 400);
    }
    if (!ALLOWED_MODES.has(mode)) {
      return jsonResponse({ error: 'Unsupported mode.' }, 400);
    }
    if (payload && payload.length > MAX_PAYLOAD) {
      return jsonResponse({ error: 'Reference text is too long.' }, 413);
    }
    if (mode === 'url' && payload) {
      if (payload.length > MAX_URL || !/^https:\/\/[\w.-]+\//.test(payload)) {
        return jsonResponse({ error: 'Reference URL must be a plain https link.' }, 400);
      }
    }

    // Which game IS this? The app has always sent `igdbID`; until now nothing
    // read it, so every prompt identified the game by the name alone — which is
    // how "The Messenger" reaches a different game from 2000, and how a
    // Castlevania request lands on the wrong entry in a series of near-identical
    // strings. One lookup turns the id into the facts a model can actually use:
    // canonical title, year, developer. Failure is fine and silent; this
    // improves a prompt, it does not gate one.
    const identity = await gameIdentity(body?.igdbID);
    const qualifier = identityQualifier(identity, gameName);
    // What the game IS, not just which one it is. Plan mode has no web search,
    // so without this a familiar franchise name produces the franchise's usual
    // skeleton — Pokémon Pokopia got Gym Badges and an Elite Four it does not
    // have. IGDB already told us it is a sandbox life sim; we just weren't
    // asking.
    const context = identityContext(identity);

    // Shapes the person chose, from the fixed list only.
    const shapes: string[] = Array.isArray(body?.shapes)
      ? [...new Set((body.shapes as unknown[]).filter((x): x is string => typeof x === 'string' && x in SHAPES))]
          .slice(0, MAX_SHAPES)
      : [];

    // ── runFields: what a run records, for a tracker that has runs.
    if (mode === 'runFields') {
      const lists: Array<{ id: string; name: string }> = Array.isArray(body?.lists)
        ? (body.lists as Array<Record<string, unknown>>)
            .filter((l) => typeof l?.id === 'string' && typeof l?.name === 'string')
            .slice(0, MAX_LISTS)
            .map((l) => ({ id: String(l.id).slice(0, 80), name: String(l.name).slice(0, MAX_CATEGORY_NAME) }))
        : [];
      const res = await callClaude(apiKey, {
        model: 'claude-sonnet-4-6',
        max_tokens: PLAN_MAX_TOKENS,
        tools: [RUN_FIELDS_TOOL],
        toolName: 'suggest_run_fields',
        userMessage: buildRunFieldsMessage(gameName, igdbData || null, qualifier, context, lists),
      });
      if ('error' in res) return res.error;
      const fields = cleanRunFields(res.input?.fields, new Set(lists.map((l) => l.id)));
      if (fields.length === 0) {
        return jsonResponse({ error: "Couldn't suggest run fields for that game." }, 422);
      }
      const outcomes = Array.isArray(res.input?.outcomes)
        ? (res.input.outcomes as unknown[]).filter((o): o is string => typeof o === 'string' && !!o.trim())
            .map((o) => o.trim().slice(0, 30)).slice(0, 6)
        : [];
      return jsonResponse({ runFields: { fields, outcomes }, usage: res.usage });
    }

    // ── plan: the shape only, no items. One small call, no web search: this
    // has to come back in seconds or it is no better than generating.
    if (mode === 'plan') {
      const planRes = await callClaude(apiKey, {
        model: 'claude-sonnet-4-6',
        max_tokens: PLAN_MAX_TOKENS,
        tools: [PLAN_TOOL],
        toolName: 'plan_tracker_categories',
        userMessage: buildPlanMessage(gameName, igdbData || null, qualifier, context, shapes),
      });
      if ('error' in planRes) return planRes.error;

      const proposed = Array.isArray(planRes.input?.categories) ? planRes.input.categories : [];
      const categories = proposed
        .filter((c: Record<string, unknown>) => typeof c?.name === 'string' && c.name.trim())
        .slice(0, 10)
        .map((c: Record<string, unknown>) => ({
          name: String(c.name).trim().slice(0, MAX_CATEGORY_NAME),
          plannedCount: Number.isFinite(c.plannedCount) ? Math.max(0, Math.round(Number(c.plannedCount))) : null,
          type: typeof c.type === 'string' ? c.type : 'checklist',
          description: typeof c.description === 'string' ? c.description : undefined,
          counted: c.counted === true,
          ...(c.type === 'roster' ? {
            fields: cleanFields(c.fields),
            partySize: Number.isFinite(c.partySize) && Number(c.partySize) > 0
              ? Math.min(99, Math.round(Number(c.partySize))) : undefined,
          } : {}),
        }));

      if (categories.length === 0) {
        return jsonResponse(
          { error: "Couldn't work out how to divide that game up. Try a more specific name." },
          422,
        );
      }
      return jsonResponse({
        plan: {
          categories,
          estimatedHours: planRes.input?.estimatedHours || undefined,
          completionNotes: planRes.input?.completionNotes || undefined,
        },
        usage: planRes.usage,
      });
    }

    // ── category: one named category, everything else left alone. Same guide
    // lookup as a full generation, a fraction of the output.
    if (mode === 'category') {
      const categoryName = typeof body?.categoryName === 'string' ? body.categoryName.trim() : '';
      if (!categoryName) {
        return jsonResponse({ error: 'categoryName is required for category mode.' }, 400);
      }
      if (categoryName.length > MAX_CATEGORY_NAME) {
        return jsonResponse({ error: 'Category name is too long.' }, 400);
      }
      // Clamped, because this number buys output budget. Unbounded, a caller
      // could ask for a category of 10,000 items and buy the token ceiling from
      // the cheaper per-mode bucket. 400 is well past any real category;
      // beyond that the terse-output rule applies anyway.
      const { expectedCount, maxTokens: budget } = categoryTokenBudget(body?.expectedCount);
      const counted = body?.counted === true;

      // Size the budget to the category. A flat 8k cap silently truncated
      // anything past roughly a hundred items — 120 Shrines with locations
      // ran out mid-tool-call and came back as "nothing came back", which
      // reads as the generator not knowing the game rather than as a limit.
      // Terse entries above 60 items (see buildCategoryMessage), so the
      // per-item allowance drops with them rather than budgeting for prose
      // that was explicitly asked not to be written.
      // The hard ceiling stays below the full generation's 12,000. The shared
      // limits also cap this bucket at 150 calls/day, so its worst-case 1.5M
      // daily output tokens stays below the full bucket's 150 × 12,000.
      // Long lists skip the guide lookup. It costs its own round trip and then
      // drags a whole wiki page into the input, and the combination of that
      // and 120 entries of output does not fit inside 150 seconds — which
      // means no category at all rather than a slightly less sourced one.
      // Short lists keep it, where the accuracy is nearly free.
      // A counter needs one number, not a wiki page.
      const guideUrl = counted || (expectedCount ?? 0) > 60
        ? null
        : await findGuideUrl(apiKey, gameName, igdbData || null);
      const catRes = await callClaude(apiKey, {
        model: 'claude-sonnet-4-6',
        max_tokens: counted ? 1_000 : budget,
        tools: guideUrl
          ? [CATEGORY_TOOL, { type: 'web_search_20250305', name: 'web_search', max_uses: 1 }]
          : [CATEGORY_TOOL],
        toolName: 'generate_tracker_category',
        userMessage: buildCategoryMessage(
          gameName, categoryName, expectedCount, igdbData || null, guideUrl, qualifier, counted, context,
          body?.categoryType === 'roster'),
      });
      if ('error' in catRes) return catRes.error;

      const category = catRes.input?.category as Record<string, unknown> | undefined;
      const items = Array.isArray(category?.items) ? category.items : [];
      if (!category || items.length === 0) {
        return jsonResponse(
          { error: `Nothing came back for "${categoryName}". Try again, or try a name closer to what the game calls this set.` },
          422,
        );
      }

      // Returned as an ordinary one-category schema so the app applies it
      // through the same merge path as everything else. The id is a fallback:
      // a planned category's own id is device-local, so the match lands by name.
      const structuredData = {
        schemaVersion: 1,
        generatedAt: new Date().toISOString(),
        generatedBy: 'claude-sonnet-4-6',
        sources: [{ type: 'category', ...(guideUrl ? { url: guideUrl } : {}) }],
        categories: [{
          // The name that was ASKED for, not the model's rendering of it. The
          // prompt says to echo it exactly; when the answer drifted ("Warrior's
          // Graves" for "Warrior Graves") the app's by-name match found nothing,
          // and a category that filled fine was reported as "Nothing came back".
          id: slugify(categoryName),
          name: categoryName,
          type: typeof category.type === 'string' ? category.type : 'checklist',
          ...(category.description ? { description: category.description } : {}),
          ...(category.type === 'roster' ? {
            fields: cleanFields(category.fields),
            partySize: Number.isFinite(category.partySize) && Number(category.partySize) > 0
              ? Math.min(99, Math.round(Number(category.partySize))) : undefined,
          } : {}),
          items,
        }],
        runs: [],
      };
      return jsonResponse({ structuredData, usage: catRes.usage });
    }

    // Auto mode: two-stage — find a guide URL first (fast), then generate from it.
    // This splits the work into two calls each well under Supabase's 150s limit.
    if (mode === 'auto' || !mode) {
      const guideUrl = await findGuideUrl(apiKey, gameName, igdbData || null);
      if (guideUrl) {
        mode = 'url';
        payload = guideUrl;
      } else {
        // Couldn't find a URL — fall back to knowledge-only generation (no web search)
        mode = 'paste';
        payload = null;
      }
    }

    const userMessage = buildUserMessage(
      gameName, igdbData || null, mode, payload || null, qualifier, context, requested);

    // URL mode gets web_search so Claude can fetch the page content
    const tools: unknown[] = [TRACKER_TOOL];
    if (mode === 'url') {
      tools.push({
        type: 'web_search_20250305',
        name: 'web_search',
        max_uses: 1,
      });
    }

    // Call Claude API
    const claudeRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: FULL_GENERATION_MAX_TOKENS,
        system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
        tools,
        tool_choice: { type: 'any' },
        messages: [{ role: 'user', content: userMessage }],
      }),
    });

    if (!claudeRes.ok) {
      // Upstream detail goes to logs only — it can echo prompt content and
      // names the backend the app deliberately doesn't expose.
      console.error('Claude API error:', claudeRes.status, await claudeRes.text());
      return jsonResponse(
        { error: 'The generator is busy right now. Try again in a moment.' },
        502,
      );
    }

    const claudeData = await claudeRes.json();

    // Extract the tool call result from the response.
    const toolUseBlock = (claudeData.content || []).find(
      (block: { type: string; name?: string }) =>
        block.type === 'tool_use' && block.name === 'generate_tracker_data'
    );

    if (!toolUseBlock) {
      const textBlocks = (claudeData.content || [])
        .filter((b: { type: string }) => b.type === 'text')
        .map((b: { text: string }) => b.text)
        .join('\n');
      console.warn('no tracker tool call; model said:', textBlocks.slice(0, 500));
      return jsonResponse(
        { error: "Couldn't build a tracker for that game. Try a more specific name, or paste a guide." },
        422,
      );
    }

    const generated = toolUseBlock.input;
    let categories = generated.categories || [];
    let missingCategories: string[] = [];
    if (requested) {
      // Held to the list whatever the model did: extra categories dropped,
      // names put back to the user's, order kept.
      const scoped = keepRequestedCategories(categories, requested);
      if (scoped.categories.length === 0) {
        return jsonResponse(
          { error: "Couldn't regenerate those categories. Try again, or regenerate them one at a time." },
          422,
        );
      }
      categories = scoped.categories;
      missingCategories = scoped.missing;
    }
    const structuredData = {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: 'claude-sonnet-4-6',
      sources: [
        { type: mode, ...(payload && mode === 'url' ? { url: payload } : {}) },
      ],
      categories,
      ...(generated.runTemplate ? { runTemplate: generated.runTemplate } : {}),
      runs: [],
      estimatedHours: generated.estimatedHours || undefined,
      completionNotes: generated.completionNotes || undefined,
      tags: generated.tags || [],
    };

    // `missingCategories` sits beside structuredData, never inside it: the app
    // stores structuredData as the tracker, and this is a note about the
    // request, not part of anyone's tracker.
    return jsonResponse({
      structuredData,
      usage: claudeData.usage || null,
      ...(missingCategories.length > 0 ? { missingCategories } : {}),
    });
  } catch (err) {
    console.error('Edge function error:', String(err));
    return jsonResponse({ error: 'Tracker generation failed. Try again.' }, 500);
  }
});
