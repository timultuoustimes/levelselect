// Supabase Edge Function: SteamGridDB API proxy
// Deploy with: supabase functions deploy steamgriddb-proxy
//
// Required secret (set via: supabase secrets set KEY=value):
//   STEAMGRIDDB_API_KEY — from steamgriddb.com/profile/preferences/api
//
// WHY A SHARED APP KEY, NOT THE USER'S
//
// The rule this app follows is not "app key for basics, user key for extras".
// It is: the server handles anything carrying NO user identity; anything
// carrying a user's credential goes device-direct, because Supabase's Function
// Invocation logs capture request and response bodies and would write a
// password-equivalent into platform telemetry. That is why RetroAchievements
// user keys live in the Keychain and never touch this proxy.
//
// SteamGridDB has no user-scoped data this app wants. Every call here is a
// catalogue lookup for a named game. A personal key would only raise that
// person's rate limit — and would mean asking every tester to make an account
// on a service they have never heard of before their game pages look right.
//
// Caching matters more here than for IGDB because one key now serves every
// install: the app stores the CHOSEN url on the Game, so a game is resolved
// once and never looked up again.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';

// SteamGridDB's asset kinds map onto the app's artwork roles:
//   grids  → Cover      (600x900 portrait box art, and wider variants)
//   heroes → Backdrop   (1920x620 banners, drawn to sit behind text)
//   logos  → Logo       (transparent PNG wordmarks)
//   icons  → not a role yet; allowed so it needs no redeploy to become one
const ASSET_KINDS = new Set(['grids', 'heroes', 'logos', 'icons']);

const MAX_TERM_LENGTH = 200;

function apiKey(): string {
  const key = Deno.env.get('STEAMGRIDDB_API_KEY');
  if (!key) {
    throw new Error(
      'SteamGridDB key not configured. Set STEAMGRIDDB_API_KEY as a Supabase secret.'
    );
  }
  return key;
}

async function sgdb(path: string): Promise<Response> {
  return await fetch(`https://www.steamgriddb.com/api/v2/${path}`, {
    headers: { Authorization: `Bearer ${apiKey()}` },
  });
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  // Unlike IGDB, this one fails CLOSED on a quota-store outage. IGDB backs the
  // Add Game flow, so breaking it would break the app's core loop; artwork is
  // a refinement of a game page that already renders. When in doubt, protect
  // the shared key.
  const { rejection, body } = await guard(req, {
    fn: 'steamgriddb',
    maxBodyBytes: 2_000,
    quotas: [
      { scope: 'install', windowSeconds: 60, limit: 30 },
      { scope: 'install', windowSeconds: 86_400, limit: 500 },
      { scope: 'global', windowSeconds: 86_400, limit: 10_000 },
    ],
    onQuotaError: 'deny',
  });
  if (rejection) return rejection;

  try {
    const action = body?.action;

    // Two actions only. There is no passthrough: the app names what it wants
    // and this builds the URL, so the proxy can't be driven at arbitrary
    // SteamGridDB paths by anything holding an app key.
    if (action === 'search') {
      const term = body?.term;
      if (typeof term !== 'string' || !term.trim()) {
        return jsonResponse({ error: 'term required' }, 400);
      }
      if (term.length > MAX_TERM_LENGTH) {
        return jsonResponse({ error: 'Term too long.' }, 400);
      }
      const res = await sgdb(`search/autocomplete/${encodeURIComponent(term.trim())}`);
      if (!res.ok) {
        console.error(`SGDB search ${res.status}: ${await res.text()}`);
        return jsonResponse({ error: 'Artwork lookup failed. Try again.' }, 502);
      }
      return jsonResponse(await res.json());
    }

    if (action === 'assets') {
      const kind = body?.kind;
      const gameID = body?.gameID;
      if (typeof kind !== 'string' || !ASSET_KINDS.has(kind)) {
        return jsonResponse({ error: 'Unsupported asset kind.' }, 400);
      }
      if (!Number.isInteger(gameID) || gameID <= 0) {
        return jsonResponse({ error: 'gameID required.' }, 400);
      }
      // `nsfw=false&humor=false` at the source rather than filtering after:
      // this is a game shelf, and nobody asked for a joke cover.
      const res = await sgdb(`${kind}/game/${gameID}?nsfw=false&humor=false`);
      if (!res.ok) {
        console.error(`SGDB ${kind} ${res.status}: ${await res.text()}`);
        return jsonResponse({ error: 'Artwork lookup failed. Try again.' }, 502);
      }
      return jsonResponse(await res.json());
    }

    return jsonResponse({ error: 'Unsupported action.' }, 400);
  } catch (err) {
    console.error('steamgriddb-proxy error:', String(err));
    return jsonResponse({ error: 'Artwork lookup failed. Try again.' }, 500);
  }
});
