// Supabase Edge Function: Steam proxy
// Finds which Steam app a game is, and returns that app's achievement list.
// Deploy with: supabase functions deploy steam-proxy
//
// Required secret (set via: supabase secrets set STEAM_API_KEY=value):
//   STEAM_API_KEY — steamcommunity.com/dev/apikey
//
// RetroAchievements' split, exactly. This function only handles catalogue
// lookups that say nothing about who is asking: a search term, an app id. So
// anyone can put a Steam game's achievements on a tracker without a key of
// their own. A player's library and unlocks carry their SteamID and need their
// own key, and those go device → Steam directly (SteamService in the app).
//
// NOTE: there is deliberately no mode that accepts a player's key or SteamID.
// Supabase's invocation logs capture request bodies and headers; ra-proxy
// carried a user's key once and the modes were removed for that reason.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';
import { MAX_STEAM_TERM, shapeSchema, shapeSearch } from '../_shared/steam-store.ts';

const STEAM_API = 'https://api.steampowered.com';
const STORE = 'https://store.steampowered.com';

// One key serves every LevelSelect user, inside Valve's 100,000 calls a day,
// and achievement lists change rarely — so a warm instance answers repeats.
const SCHEMA_TTL = 6 * 60 * 60 * 1000;
const MAX_CACHED = 500;
const schemas = new Map<number, { payload: unknown; fetchedAt: number }>();

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  // A lookup, not a generation, on a free upstream — fail open on a quota
  // store outage, like ra-proxy and the IGDB proxy.
  const { rejection, body } = await guard(req, {
    fn: 'steam',
    maxBodyBytes: 4_000,
    quotas: [
      { scope: 'install', windowSeconds: 3_600, limit: 60 },
      { scope: 'global', windowSeconds: 86_400, limit: 20_000 },
    ],
    onQuotaError: 'allow',
  });
  if (rejection) return rejection;

  const mode = typeof body?.mode === 'string' ? body.mode : '';

  try {
    // ── search: which Steam app is this? Steam's store search needs no key.
    if (mode === 'search') {
      const term = typeof body?.term === 'string' ? body.term.trim() : '';
      if (!term || term.length > MAX_STEAM_TERM) {
        return jsonResponse({ error: 'term is required.' }, 400);
      }
      const res = await fetch(
        `${STORE}/api/storesearch/?term=${encodeURIComponent(term)}&cc=US&l=english`);
      if (!res.ok) {
        console.error('steam search failed:', res.status);
        return jsonResponse({ error: 'Steam search is unavailable right now.' }, 502);
      }
      return jsonResponse({ results: shapeSearch(await res.json()) });
    }

    // ── achievements: the game's own list, on LevelSelect's key.
    if (mode === 'achievements') {
      const appID = Number.isInteger(body?.appID) ? Number(body?.appID) : 0;
      if (appID <= 0) {
        return jsonResponse({ error: 'appID is required.' }, 400);
      }
      const key = Deno.env.get('STEAM_API_KEY');
      if (!key) {
        console.error('STEAM_API_KEY not configured');
        return jsonResponse({ error: 'Steam achievements are not set up yet.' }, 503);
      }

      const warm = schemas.get(appID);
      if (warm && Date.now() - warm.fetchedAt < SCHEMA_TTL) {
        return jsonResponse(warm.payload);
      }

      // The URL carries the key, so it is never logged; only the status is.
      const res = await fetch(
        `${STEAM_API}/ISteamUserStats/GetSchemaForGame/v2/?appid=${appID}&l=english&key=${encodeURIComponent(key)}`);
      if (!res.ok) {
        console.error('steam schema failed:', res.status);
        return jsonResponse({ error: 'Steam is unavailable right now.' }, 502);
      }
      const shaped = shapeSchema(await res.json());
      if (!shaped) {
        return jsonResponse({ error: 'Steam lists no achievements for that game.' }, 422);
      }
      // The shape of Steam's own answer, so the app parses one thing whether
      // it came from here or from Steam.
      const payload = {
        game: { gameName: shaped.gameName, availableGameStats: { achievements: shaped.achievements } },
      };
      if (schemas.size >= MAX_CACHED) {
        const oldest = schemas.keys().next().value;
        if (oldest !== undefined) schemas.delete(oldest);
      }
      schemas.set(appID, { payload, fetchedAt: Date.now() });
      return jsonResponse(payload);
    }

    return jsonResponse({ error: 'Unsupported mode.' }, 400);
  } catch (err) {
    console.error('steam-proxy error:', String(err));
    return jsonResponse({ error: 'Steam lookup failed. Try again.' }, 500);
  }
});
