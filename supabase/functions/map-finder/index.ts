// Supabase Edge Function: Map Finder (Genie)
// Finds map images for a game via web search, or parses a user-provided page URL.
// Deploy: supabase functions deploy map-finder

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';

const MAX_GAME_NAME = 200;
const MAX_URL = 500;

const SYSTEM_PROMPT = `You are a game map image finder. Given a game name (and optionally a wiki page URL), find image URLs for game maps — world maps, area maps, and level maps.

Return ONLY a JSON array of map objects. Each object must have:
- name: string — descriptive name (e.g. "Green Hill Zone Act 1", "World Map", "Norfair")
- type: "world" | "area" — "world" for full-game overview maps, "area" for level/zone/area maps
- url: string — direct URL to the image file (must end in .jpg, .jpeg, .png, .gif, .webp, or similar)
- source: string — website name (e.g. "Sonic Fandom Wiki", "The Cutting Room Floor")

Rules:
1. Only include DIRECT image file URLs (not page URLs). The URL must point to an actual image file.
2. CRITICAL — hotlink policy: Only use URLs from sources that allow cross-origin image embedding. Preferred:
   - Fandom/Wikia CDN: URLs containing "static.wikia.nocookie.net" or "vignette.wikia.nocookie.net"
   - Wikimedia Commons / MediaWiki: URLs containing "upload.wikimedia.org"
   - The Cutting Room Floor: tcrf.net wiki image paths
   - GitHub raw: "raw.githubusercontent.com"
   - Any MediaWiki-based game wiki's /images/ path (e.g. sonic.fandom.com/wiki/Special:FilePath/...)
   AVOID sites that block hotlinking: vgmaps.com, vgmaps.de, GameFAQs image hosting, neoseeker.com. Images from these appear broken when embedded.
3. Prefer high-resolution map images over low-res thumbnails.
4. Include both world maps and individual area/level maps when available.
5. If given a specific page URL, extract ALL map images from that page.
6. If doing a general search, return the 6–10 best maps for the game. Search specifically on Fandom wikis and Wikimedia for the game name + "map".
7. Skip screenshots, character art, or box art — only actual maps/level layouts.
8. Return valid JSON only, no markdown, no explanation.`;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) {
    console.error('ANTHROPIC_API_KEY not configured');
    return jsonResponse({ error: 'Map search is not available right now.' }, 503);
  }

  // Paid upstream (Claude + web search) — deny on quota-store failure.
  const { rejection, body } = await guard(req, {
    fn: 'maps',
    maxBodyBytes: 8_000,
    quotas: [
      { scope: 'install', windowSeconds: 3_600, limit: 10 },
      { scope: 'install', windowSeconds: 86_400, limit: 40 },
      { scope: 'global', windowSeconds: 86_400, limit: 300 },
    ],
    onQuotaError: 'deny',
  });
  if (rejection) return rejection;

  try {
    const igdbData = body?.igdbData as Record<string, unknown> | null | undefined;
    const gameName = typeof body?.gameName === 'string' ? body.gameName.trim() : '';
    const pageUrl = typeof body?.pageUrl === 'string' ? body.pageUrl : null;

    if (!gameName) {
      return jsonResponse({ error: 'gameName is required' }, 400);
    }
    if (gameName.length > MAX_GAME_NAME) {
      return jsonResponse({ error: 'Game name is too long.' }, 400);
    }
    if (pageUrl && (pageUrl.length > MAX_URL || !/^https:\/\/[\w.-]+\//.test(pageUrl))) {
      return jsonResponse({ error: 'Page URL must be a plain https link.' }, 400);
    }

    const meta: string[] = [];
    if (igdbData?.genres)     meta.push(`Genres: ${(igdbData.genres as string[]).join(', ')}`);
    if (igdbData?.developers) meta.push(`Developer: ${(igdbData.developers as string[]).join(', ')}`);

    let userMessage: string;
    if (pageUrl) {
      userMessage = [
        `Game: "${gameName}"${meta.length > 0 ? ` (${meta.join('; ')})` : ''}`,
        ``,
        `The user provided this page URL which should contain game maps: ${pageUrl}`,
        `Search the web for this page and extract ALL map image URLs from it.`,
        `Return a JSON array of map objects as described.`,
      ].join('\n');
    } else {
      userMessage = [
        `Game: "${gameName}"${meta.length > 0 ? ` (${meta.join('; ')})` : ''}`,
        ``,
        `Search the web for map images for this game. Focus on:`,
        `- Fandom/Wikia game wikis (search: site:*.fandom.com "${gameName}" map)`,
        `- Wikimedia Commons or MediaWiki-based wikis`,
        `- The Cutting Room Floor (tcrf.net)`,
        `- GitHub repositories with game assets`,
        ``,
        `Return only image URLs from hotlink-friendly sources (Fandom CDN, Wikimedia, tcrf.net).`,
        `Return a JSON array of map objects as described.`,
      ].join('\n');
    }

    const claudeRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 2000,
        system: SYSTEM_PROMPT,
        tools: [{
          type: 'web_search_20250305',
          name: 'web_search',
          max_uses: pageUrl ? 1 : 3,
        }],
        messages: [{ role: 'user', content: userMessage }],
      }),
    });

    if (!claudeRes.ok) {
      console.error('Claude API error:', claudeRes.status, await claudeRes.text());
      return jsonResponse({ error: 'Map search is busy right now. Try again shortly.' }, 502);
    }

    const claudeData = await claudeRes.json();

    // Extract text response
    const textBlock = (claudeData.content || []).find(
      (b: { type: string }) => b.type === 'text'
    ) as { text: string } | undefined;

    if (!textBlock?.text) {
      return jsonResponse({ suggestions: [] });
    }

    // Parse the JSON array from Claude's response
    let suggestions = [];
    try {
      const jsonMatch = textBlock.text.match(/\[[\s\S]*\]/);
      if (jsonMatch) {
        suggestions = JSON.parse(jsonMatch[0]);
      }
    } catch {
      suggestions = [];
    }

    // Filter to only entries that look like direct image URLs
    suggestions = suggestions.filter((s: { url?: string; name?: string; type?: string }) => {
      if (!s.url || !s.name) return false;
      return /\.(jpg|jpeg|png|gif|webp|svg)(\?.*)?$/i.test(s.url) || s.url.includes('/images/');
    });

    return jsonResponse({ suggestions });
  } catch (err) {
    console.error('Map finder error:', String(err));
    return jsonResponse({ error: 'Map search failed. Try again.' }, 500);
  }
});
