// Supabase Edge Function: AI Tracker Generator
// Calls the Anthropic Claude API to auto-generate structured game tracker data.
// Deploy with: supabase functions deploy ai-tracker-generator
//
// Required secrets (set via: supabase secrets set KEY=value):
//   ANTHROPIC_API_KEY — from console.anthropic.com

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

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

  if (mode === 'auto') {
    parts.push('\nSearch the web for game guides, wikis, and walkthroughs to find the most accurate and thorough information about this game\'s content, collectibles, bosses, upgrades, and progression systems.');
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
    return new Response(
      JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured. Set it via: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...' }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }

  try {
    const { gameName, igdbData, mode, payload } = await req.json();

    if (!gameName) {
      return new Response(
        JSON.stringify({ error: 'gameName is required' }),
        { status: 400, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    const userMessage = buildUserMessage(gameName, igdbData || null, mode || 'auto', payload || null);

    // Build tools array: always include our structured output tool,
    // plus web_search for auto/url modes.
    const tools: unknown[] = [TRACKER_TOOL];
    if (mode === 'auto' || mode === 'url' || !mode) {
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
      const errText = await claudeRes.text();
      console.error('Claude API error:', claudeRes.status, errText);
      return new Response(
        JSON.stringify({ error: `Claude API error: ${claudeRes.status}`, detail: errText }),
        { status: 502, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    const claudeData = await claudeRes.json();

    // Extract the tool call result from the response.
    // Claude may include multiple content blocks (text, web search results,
    // tool_use). We want the generate_tracker_data tool_use block.
    const toolUseBlock = (claudeData.content || []).find(
      (block: { type: string; name?: string }) =>
        block.type === 'tool_use' && block.name === 'generate_tracker_data'
    );

    if (!toolUseBlock) {
      // Claude didn't call the tool — return whatever it said for debugging
      const textBlocks = (claudeData.content || [])
        .filter((b: { type: string }) => b.type === 'text')
        .map((b: { text: string }) => b.text)
        .join('\n');
      return new Response(
        JSON.stringify({ error: 'Claude did not generate tracker data', claudeResponse: textBlocks }),
        { status: 422, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
      );
    }

    // Build the complete structuredData object
    const generated = toolUseBlock.input;
    const structuredData = {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      generatedBy: 'claude-sonnet-4-6',
      sources: [
        { type: mode || 'auto', ...(payload && mode === 'url' ? { url: payload } : {}) },
      ],
      categories: generated.categories || [],
      ...(generated.runTemplate ? { runTemplate: generated.runTemplate } : {}),
      runs: [],
      estimatedHours: generated.estimatedHours || undefined,
      completionNotes: generated.completionNotes || undefined,
      tags: generated.tags || [],
    };

    // Return the structured data + usage info
    return new Response(
      JSON.stringify({
        structuredData,
        usage: claudeData.usage || null,
      }),
      { headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('Edge function error:', err);
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } },
    );
  }
});
