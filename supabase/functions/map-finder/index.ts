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

const BROWSER_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  Accept: 'image/avif,image/webp,image/png,image/*,*/*;q=0.8',
};

type FoundMap = { url: string; name: string; type?: string };

/** Keep only suggestions whose URL answers with an image. */
async function verified(list: FoundMap[]): Promise<FoundMap[]> {
  const checks = list.map(async (s) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8_000);
    try {
      let host = '';
      try { host = new URL(s.url).host; } catch { return null as FoundMap | null; }
      const headers = { ...BROWSER_HEADERS, Referer: `https://${host}/` };
      // HEAD first; a CDN that rejects HEAD gets a one-byte GET.
      let res = await fetch(s.url, { method: 'HEAD', headers, redirect: 'follow', signal: controller.signal });
      if (res.status === 405 || res.status === 403) {
        res = await fetch(s.url, { method: 'GET', headers: { ...headers, Range: 'bytes=0-0' }, redirect: 'follow', signal: controller.signal });
      }
      const type = res.headers.get('content-type') ?? '';
      if (!res.ok || !type.startsWith('image/')) return null;
      // An icon is an image too. A map is not 12KB. A CDN that omits the
      // length on HEAD tells it on a one-byte ranged GET.
      let length = Number(res.headers.get('content-length') ?? '0');
      if (length === 0) {
        const probe = await fetch(s.url, { method: 'GET', headers: { ...headers, Range: 'bytes=0-0' }, redirect: 'follow', signal: controller.signal });
        length = Number(probe.headers.get('content-range')?.split('/')[1] ?? probe.headers.get('content-length') ?? '0');
      }
      if (length > 0 && length < 30_000) return null;
      // The URL after redirects is the one the app should keep.
      return { ...s, url: res.url || s.url };
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }
  });
  return (await Promise.all(checks)).filter((s): s is FoundMap => s !== null);
}


/**
 * Read a page the person gave us and take its images off it — no model.
 *
 * A search model asked for "the map images on this page" composes paths;
 * the page itself has them. MediaWiki thumbnails (`/images/thumb/…/300px-X.png`)
 * are unwound to the original. Icons, logos and sprites are dropped by name;
 * what survives is verified like everything else.
 */
async function imagesOnPage(pageUrl: string): Promise<FoundMap[]> {
  let html = '';
  try {
    const res = await fetch(pageUrl, {
      headers: { ...BROWSER_HEADERS, Accept: 'text/html,*/*;q=0.8' },
      redirect: 'follow',
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) return [];
    html = await res.text();
  } catch {
    return [];
  }
  const found = new Map<string, FoundMap>();
  const add = (raw: string, alt: string) => {
    let url: URL;
    try { url = new URL(raw.replace(/&amp;/g, '&'), pageUrl); } catch { return; }
    if (!/\.(png|jpe?g|webp|gif)(\?.*)?$/i.test(url.pathname) && !url.pathname.includes('/images/')) return;
    // MediaWiki thumb → original.
    const thumb = url.pathname.match(/^(.*)\/thumb(\/.+)\/[^/]+$/);
    if (thumb) url.pathname = thumb[1] + thumb[2];
    if (url.pathname.includes('/resources/assets/')) return;
    const file = decodeURIComponent(url.pathname.split('/').pop() ?? '');
    const fileName = file.replace(/\.[a-z0-9]+$/i, '').replace(/_/g, ' ').trim();
    // The filename says "Forgotten Crossroads Map"; the alt says "Marked".
    // The filename wins whenever it names a map.
    const name = (/map/i.test(fileName) || !alt) ? fileName : alt.replace(/_/g, ' ').trim();
    if (/\b(icon|logo|sprite|button|badge|favicon|arrow|wordmark|powered by)\b/i.test(fileName) || /^\d+px-/.test(file)) return;
    if (!name) return;
    const key = url.origin + url.pathname;
    if (!found.has(key)) {
      const type = /world/i.test(fileName) ? 'world' : /map|region|area/i.test(fileName) ? 'area' : 'other';
      found.set(key, { url: url.toString(), name, type });
    }
  };
  for (const m of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = m[0];
    const src = tag.match(/\ssrc="([^"]+)"/i)?.[1] ?? '';
    const alt = tag.match(/\salt="([^"]*)"/i)?.[1] ?? '';
    if (src) add(src, alt);
    const set = tag.match(/\ssrcset="([^"]+)"/i)?.[1] ?? '';
    for (const part of set.split(',')) { const u = part.trim().split(/\s+/)[0]; if (u) add(u, alt); }
  }
  for (const m of html.matchAll(/href="([^"]+\.(?:png|jpe?g|webp|gif))"/gi)) add(m[1], '');
  const list = [...found.values()];
  // Files called maps first, world maps before area maps, the rest after.
  const rank = (m: FoundMap) => (m.type === 'world' ? 0 : m.type === 'area' ? 1 : 2);
  list.sort((a, b) => rank(a) - rank(b));
  return list.slice(0, 20);
}

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

    // A page in hand needs no model: read it, verify what is on it.
    if (pageUrl) {
      const onPage = await verified(await imagesOnPage(pageUrl));
      if (onPage.length > 0) return jsonResponse({ suggestions: onPage });
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

    // **Then check that each one exists.** A search model will happily
    // compose a plausible wiki path that was never there — six confident
    // Fandom URLs for Hollow Knight, all dead (2026-09-08). The app fetches
    // the bytes itself, so a dead URL reached the person as "that site
    // wouldn't hand the image over". Asking here, with the headers a
    // browser sends, keeps the invented ones out of the list.
    suggestions = await verified((suggestions as FoundMap[]).slice(0, 12));

    return jsonResponse({ suggestions });
  } catch (err) {
    console.error('Map finder error:', String(err));
    return jsonResponse({ error: 'Map search failed. Try again.' }, 500);
  }
});
