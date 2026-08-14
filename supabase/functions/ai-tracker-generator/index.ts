// Supabase Edge Function: AI Tracker Generator
// Calls the Anthropic Claude API to auto-generate structured game tracker data.
// Deploy with: supabase functions deploy ai-tracker-generator
//
// Required secrets (set via: supabase secrets set KEY=value):
//   ANTHROPIC_API_KEY — from console.anthropic.com

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';

// Input caps — every one of these bounds what reaches the Anthropic API.
const MAX_GAME_NAME = 200;
const MAX_PAYLOAD = 60_000; // pasted guide text
const MAX_URL = 500;
const ALLOWED_MODES = new Set(['auto', 'paste', 'url']);

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

  // The most expensive endpoint in the app (a full Claude generation with web
  // search, per call). Tight quotas, and a quota-store outage denies rather
  // than letting spend run unmetered.
  const { rejection, body } = await guard(req, {
    fn: 'ai',
    maxBodyBytes: MAX_PAYLOAD + 8_000,
    quotas: [
      { scope: 'install', windowSeconds: 3_600, limit: 10 },
      { scope: 'install', windowSeconds: 86_400, limit: 20 },
      { scope: 'global', windowSeconds: 86_400, limit: 150 },
    ],
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
        max_tokens: 12000,
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
