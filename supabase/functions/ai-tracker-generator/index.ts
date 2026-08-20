// Supabase Edge Function: AI Tracker Generator
// Calls the Anthropic Claude API to auto-generate structured game tracker data.
// Deploy with: supabase functions deploy ai-tracker-generator
//
// Required secrets (set via: supabase secrets set KEY=value):
//   ANTHROPIC_API_KEY — from console.anthropic.com

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';
import {
  categoryTokenBudget,
  FULL_GENERATION_MAX_TOKENS,
  PLAN_MAX_TOKENS,
  quotaPlanForAI,
} from '../_shared/ai-limits.ts';

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
const ALLOWED_MODES = new Set(['auto', 'paste', 'url', 'plan', 'category']);

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
4. **sequence** — ordered progression steps. Use for: endings, story arcs, quest chains.

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
- maxRank, rankNames — for leveled items only
- metadata (object) — freeform game-specific extras (costs, stats, etc.)

## Run template (optional, for roguelikes)

If the game has a run-based structure (roguelikes, roguelites, arcade modes):
- fields: array of { id, label, type: "text"|"select"|"number", options?: string[] }
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
            type:        { type: 'string', enum: ['checklist', 'collectibles', 'leveled', 'sequence'] },
            tags:        { type: 'array', items: { type: 'string' } },
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
                type:    { type: 'string', enum: ['text', 'select', 'number'] },
                options: { type: 'array', items: { type: 'string' } },
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
            type: { type: 'string', enum: ['checklist', 'collectibles', 'leveled', 'sequence'] },
            description: { type: 'string', description: 'One short line on what belongs in it.' },
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
          type:        { type: 'string', enum: ['checklist', 'collectibles', 'leveled', 'sequence'] },
          items:       TRACKER_TOOL.input_schema.properties.categories.items.properties.items,
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
): string {
  const parts: string[] = [];

  parts.push(`Generate tracker data for the game: "${gameName}"`);

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

  parts.push('\nBe thorough — include all major bosses, collectibles, upgrades, story progression, and endings. Group items into logical categories using the right category type for each. Call the generate_tracker_data tool with the complete result.');

  return parts.join('\n');
}

function buildPlanMessage(gameName: string, igdbData: Record<string, unknown> | null): string {
  const parts: string[] = [
    `What should a completion tracker for "${gameName}" be divided into?`,
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
  ].join(' '));
  return parts.join('\n');
}

function buildCategoryMessage(
  gameName: string,
  categoryName: string,
  expectedCount: number | null,
  igdbData: Record<string, unknown> | null,
  payload: string | null,
): string {
  const parts: string[] = [
    `Generate ONLY the "${categoryName}" category of a completion tracker for "${gameName}".`,
  ];
  if (expectedCount && expectedCount > 0) {
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
    'If this set runs to roughly 150 or more near-identical entries (Korok Seeds, Riddler trophies), do NOT list them individually:',
    'return a single item named after the set with countTarget set to the total, so it tracks as a running count.',
  ].join(' '));
  // A long list has to be a terse one. 120 shrines with a description and a
  // source apiece is 15k tokens of output, which runs past the 150s edge
  // function ceiling and returns nothing at all — so the detail costs the user
  // the entire category. Name and location carry the checklist; the rest is
  // what makes it never arrive.
  if ((expectedCount ?? 0) > 60) {
    parts.push([
      '\nThis is a long list, so keep every entry short: an id, a name, and a brief location.',
      'No descriptions, no source text, no metadata, no tags — they would push this past the time limit,',
      'and a list that never arrives is worth less than a plain one that does.',
    ].join(' '));
  }
  return parts.join('\n');
}

function slugify(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'category';
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

    // ── plan: the shape only, no items. One small call, no web search: this
    // has to come back in seconds or it is no better than generating.
    if (mode === 'plan') {
      const planRes = await callClaude(apiKey, {
        model: 'claude-sonnet-4-6',
        max_tokens: PLAN_MAX_TOKENS,
        tools: [PLAN_TOOL],
        toolName: 'plan_tracker_categories',
        userMessage: buildPlanMessage(gameName, igdbData || null),
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
      const guideUrl = (expectedCount ?? 0) > 60
        ? null
        : await findGuideUrl(apiKey, gameName, igdbData || null);
      const catRes = await callClaude(apiKey, {
        model: 'claude-sonnet-4-6',
        max_tokens: budget,
        tools: guideUrl
          ? [CATEGORY_TOOL, { type: 'web_search_20250305', name: 'web_search', max_uses: 1 }]
          : [CATEGORY_TOOL],
        toolName: 'generate_tracker_category',
        userMessage: buildCategoryMessage(
          gameName, categoryName, expectedCount, igdbData || null, guideUrl),
      });
      if ('error' in catRes) return catRes.error;

      const category = catRes.input?.category as Record<string, unknown> | undefined;
      const items = Array.isArray(category?.items) ? category.items : [];
      if (!category || items.length === 0) {
        return jsonResponse(
          { error: `Nothing came back for "${categoryName}". Try a name closer to what the game calls it.` },
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
          id: slugify(String(category.name || categoryName)),
          name: String(category.name || categoryName),
          type: typeof category.type === 'string' ? category.type : 'checklist',
          ...(category.description ? { description: category.description } : {}),
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

    const userMessage = buildUserMessage(gameName, igdbData || null, mode, payload || null);

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
    const structuredData = {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: 'claude-sonnet-4-6',
      sources: [
        { type: mode, ...(payload && mode === 'url' ? { url: payload } : {}) },
      ],
      categories: generated.categories || [],
      ...(generated.runTemplate ? { runTemplate: generated.runTemplate } : {}),
      runs: [],
      estimatedHours: generated.estimatedHours || undefined,
      completionNotes: generated.completionNotes || undefined,
      tags: generated.tags || [],
    };

    return jsonResponse({ structuredData, usage: claudeData.usage || null });
  } catch (err) {
    console.error('Edge function error:', String(err));
    return jsonResponse({ error: 'Tracker generation failed. Try again.' }, 500);
  }
});
