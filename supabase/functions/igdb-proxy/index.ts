// Supabase Edge Function: IGDB API proxy
// Handles Twitch OAuth token management and forwards queries to IGDB.
// Deploy with: supabase functions deploy igdb-proxy
//
// Required secrets (set via: supabase secrets set KEY=value):
//   IGDB_CLIENT_ID     — from dev.twitch.tv
//   IGDB_CLIENT_SECRET — from dev.twitch.tv

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';

// Endpoints the app actually uses. Anything else is refused so the proxy can't
// be repurposed as a general-purpose IGDB scraper.
const ALLOWED_ENDPOINTS = new Set([
  'games',
  'covers',
  'platforms',
  'genres',
  'screenshots',
  'artworks',
  // IGDB split covers and logos out of artworks into their own contributable
  // data in Aug 2026, and `artwork_type` is deprecated at the end of the year
  // in favour of `image_type`. This is the lookup that says which numeric type
  // means "logo" rather than us hardcoding a magic number we can't verify.
  'image_types',
  // Regional cover variants — the Japanese Super Metroid box, which carries
  // the logo and is a different painting, is a localization rather than an
  // extra cover, so it never appeared in the cover picker.
  'game_localizations',
  // Average completion times, contributed by IGDB's community. The licensed
  // answer to "how long is this?" — HowLongToBeat has no public API, disallows
  // /api in robots.txt by name, and bans commercial use outright.
  'game_time_to_beats',
]);

// The app's longest query (search + full field list) is ~450 chars.
const MAX_QUERY_LENGTH = 2000;

// Token cache (in-memory, reused across warm invocations)
let cachedToken: string | null = null;
let tokenExpiry = 0;

async function getTwitchToken(): Promise<string> {
  if (cachedToken && Date.now() < tokenExpiry) return cachedToken;

  const clientId = Deno.env.get('IGDB_CLIENT_ID');
  const clientSecret = Deno.env.get('IGDB_CLIENT_SECRET');

  if (!clientId || !clientSecret) {
    throw new Error('IGDB credentials not configured. Set IGDB_CLIENT_ID and IGDB_CLIENT_SECRET secrets.');
  }

  const res = await fetch(
    `https://id.twitch.tv/oauth2/token?client_id=${clientId}&client_secret=${clientSecret}&grant_type=client_credentials`,
    { method: 'POST' }
  );

  if (!res.ok) throw new Error(`Twitch auth failed: ${res.status}`);
  const json = await res.json();

  cachedToken = json.access_token;
  tokenExpiry = Date.now() + (json.expires_in - 300) * 1000; // 5 min buffer
  return cachedToken!;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  // Cheap upstream (IGDB is free and rate-limits us anyway), so a quota-store
  // outage should not break the app's main Add Game flow — fail open.
  const { rejection, body } = await guard(req, {
    fn: 'igdb',
    maxBodyBytes: 4_000,
    quotas: [
      { scope: 'install', windowSeconds: 60, limit: 60 },
      { scope: 'install', windowSeconds: 86_400, limit: 2_000 },
      { scope: 'global', windowSeconds: 86_400, limit: 20_000 },
    ],
    onQuotaError: 'allow',
  });
  if (rejection) return rejection;

  try {
    const endpoint = body?.endpoint;
    const query = body?.query;

    if (typeof endpoint !== 'string' || typeof query !== 'string' || !endpoint || !query) {
      return jsonResponse({ error: 'endpoint and query required' }, 400);
    }
    if (!ALLOWED_ENDPOINTS.has(endpoint)) {
      return jsonResponse({ error: 'Unsupported endpoint.' }, 400);
    }
    if (query.length > MAX_QUERY_LENGTH) {
      return jsonResponse({ error: 'Query too long.' }, 400);
    }

    const clientId = Deno.env.get('IGDB_CLIENT_ID');
    const token = await getTwitchToken();

    const igdbRes = await fetch(`https://api.igdb.com/v4/${endpoint}`, {
      method: 'POST',
      headers: {
        'Client-ID': clientId!,
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'text/plain',
      },
      body: query,
    });

    if (!igdbRes.ok) {
      // Log upstream detail; don't hand backend internals to the client.
      console.error(`IGDB error ${igdbRes.status}: ${await igdbRes.text()}`);
      return jsonResponse({ error: 'Game lookup failed. Try again.' }, 502);
    }

    const data = await igdbRes.json();
    return jsonResponse(data);
  } catch (err) {
    console.error('igdb-proxy error:', String(err));
    return jsonResponse({ error: 'Game lookup failed. Try again.' }, 500);
  }
});
