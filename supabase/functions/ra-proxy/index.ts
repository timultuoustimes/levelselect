// Supabase Edge Function: RetroAchievements proxy
// Finds a game on RetroAchievements and returns its achievement list as tracker
// content. Deploy with: supabase functions deploy ra-proxy
//
// Required secrets (set via: supabase secrets set KEY=value):
//   RA_API_KEY   — retroachievements.org → Settings → Web API Key
//   RA_USERNAME  — the account that key belongs to (RA wants both on every call)
//
// Why a proxy at all: the key would otherwise ship inside a public repo's app
// binary. It also means the console list and per-console game lists can be
// cached across warm invocations instead of re-downloaded by every device.
//
// This is NOT generation. For a game RA covers, the achievement list is the
// real, authored one — no model, no guessing, no minute of waiting.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';

const RA_BASE = 'https://retroachievements.org/API';
const MAX_GAME_NAME = 200;
const MAX_PLATFORM = 80;

// ─── Caches (in-memory, reused across warm invocations) ──────────────────────

let consoles: { id: number; name: string }[] | null = null;
const gameLists = new Map<number, { games: RAGame[]; fetchedAt: number }>();
const GAME_LIST_TTL = 6 * 60 * 60 * 1000;   // 6h; RA adds sets, slowly

interface RAGame {
  ID: number;
  Title: string;
  NumAchievements?: number;
  ImageIcon?: string;
}

/// Credentials for a call made AS THE USER.
///
/// User-scoped reads (their unlocks, their profile) go out under their own key,
/// not the app's: RA then sees the right account doing the reading, the rate
/// limit is theirs, and this server never has to store anyone's key. Sent per
/// request, used once, never written down.
function userAuth(body: Record<string, unknown> | undefined): string | null {
  const user = typeof body?.raUsername === 'string' ? body.raUsername.trim() : '';
  const key = typeof body?.raApiKey === 'string' ? body.raApiKey.trim() : '';
  if (!user || !key || user.length > 64 || key.length > 128) return null;
  return `z=${encodeURIComponent(user)}&y=${encodeURIComponent(key)}`;
}

function auth(): string {
  const key = Deno.env.get('RA_API_KEY');
  const user = Deno.env.get('RA_USERNAME');
  if (!key || !user) throw new Error('RA credentials not configured');
  return `z=${encodeURIComponent(user)}&y=${encodeURIComponent(key)}`;
}

/// Case-, punctuation- and diacritic-insensitive key. Same idea as the app's
/// TrackerMerge.matchKey, so "Castlevania II: Simon's Quest" and
/// "castlevania ii simons quest" collapse together.
function matchKey(value: string): string {
  return value
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

async function getConsoles(): Promise<{ id: number; name: string }[]> {
  if (consoles) return consoles;
  // g=1 → gaming systems only. Without it the list carries Hubs and Events,
  // which are not consoles and have no business in a "which system is this?"
  // picker. a=1 drops systems RA has retired.
  const res = await fetch(`${RA_BASE}/API_GetConsoleIDs.php?g=1&a=1&${auth()}`);
  if (!res.ok) throw new Error(`RA consoles failed: ${res.status}`);
  const raw = await res.json() as { ID: number | string; Name: string }[];
  consoles = raw.map((c) => ({ id: Number(c.ID), name: String(c.Name) }));
  return consoles;
}

/// Resolve the app's platform string to an RA console.
///
/// The two vocabularies don't line up — the app says "NES", RA says
/// "NES/Famicom"; the app says "PC (Microsoft Windows)", RA has no such
/// console at all. So: exact key match, then either side containing the other,
/// then a couple of aliases RA words differently enough that containment
/// misses. Anything else returns null and the caller asks the user.
async function resolveConsole(platform: string): Promise<{ id: number; name: string } | null> {
  const list = await getConsoles();
  const key = matchKey(platform);
  if (!key) return null;

  const aliases: Record<string, string> = {
    'nes': 'nes famicom',
    'famicom': 'nes famicom',
    'snes': 'snes super famicom',
    'super nintendo': 'snes super famicom',
    'super nintendo entertainment system': 'snes super famicom',
    'nintendo entertainment system': 'nes famicom',
    'sega genesis': 'genesis mega drive',
    'genesis': 'genesis mega drive',
    'mega drive': 'genesis mega drive',
    'turbografx 16': 'pc engine turbografx 16',
    'turbografx16': 'pc engine turbografx 16',
    'game boy advance': 'game boy advance',
    'sega master system': 'master system',
    'playstation': 'playstation',
    'psx': 'playstation',
    'ps1': 'playstation',
  };
  const target = aliases[key] ?? key;

  const exact = list.find((c) => matchKey(c.name) === target);
  if (exact) return exact;

  // Containment either way, longest name first so "Game Boy Advance" is
  // preferred over "Game Boy" for a Game Boy Advance game.
  const byLength = [...list].sort((a, b) => b.name.length - a.name.length);
  return byLength.find((c) => {
    const name = matchKey(c.name);
    return name.includes(target) || target.includes(name);
  }) ?? null;
}

/// Postgres-backed half of the game-list cache.
///
/// RA's docs say of this endpoint: "Consider aggressively caching this
/// endpoint's response… Frequent calls to this endpoint may prompt us to look
/// into your bandwidth usage." An in-memory cache dies with every cold start,
/// so a quiet app could still pull the whole NES list many times a day — all
/// of it attributed to one personal API key. This survives the instance.
async function readCachedGames(consoleID: number): Promise<RAGame[] | null> {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return null;
  try {
    const res = await fetch(
      `${url}/rest/v1/ra_game_cache?console_id=eq.${consoleID}&select=payload,fetched_at`,
      { headers: { apikey: key, Authorization: `Bearer ${key}` } });
    if (!res.ok) return null;
    const rows = await res.json() as { payload: RAGame[]; fetched_at: string }[];
    const row = rows[0];
    if (!row) return null;
    if (Date.now() - Date.parse(row.fetched_at) > GAME_LIST_TTL) return null;
    return row.payload;
  } catch (err) {
    // A cache miss, not a failure — fall through to RA.
    console.warn('ra cache read failed:', String(err));
    return null;
  }
}

async function writeCachedGames(consoleID: number, games: RAGame[]): Promise<void> {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return;
  try {
    await fetch(`${url}/rest/v1/ra_game_cache?on_conflict=console_id`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: key,
        Authorization: `Bearer ${key}`,
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
      body: JSON.stringify({
        console_id: consoleID,
        payload: games,
        fetched_at: new Date().toISOString(),
      }),
    });
  } catch (err) {
    console.warn('ra cache write failed:', String(err));
  }
}

async function getGames(consoleID: number): Promise<RAGame[]> {
  const warm = gameLists.get(consoleID);
  if (warm && Date.now() - warm.fetchedAt < GAME_LIST_TTL) return warm.games;

  const stored = await readCachedGames(consoleID);
  if (stored) {
    gameLists.set(consoleID, { games: stored, fetchedAt: Date.now() });
    return stored;
  }

  // f=1 → only games that actually have an achievement set. Without it the
  // list is mostly entries with nothing to track.
  const res = await fetch(`${RA_BASE}/API_GetGameList.php?i=${consoleID}&f=1&${auth()}`);
  if (!res.ok) throw new Error(`RA game list failed: ${res.status}`);
  const games = await res.json() as RAGame[];
  gameLists.set(consoleID, { games, fetchedAt: Date.now() });
  await writeCachedGames(consoleID, games);
  return games;
}

/// Rank candidates against the name the user's library uses.
///
/// Deliberately returns several rather than picking one: RA titles carry
/// regional variants ("Castlevania | Akumajou Dracula"), subsets ("[Subset -
/// Bonus]"), and hacks, so an automatic pick would confidently install the
/// wrong achievement set. The user chooses.
function rank(games: RAGame[], gameName: string): RAGame[] {
  const key = matchKey(gameName);
  const scored = games.map((game) => {
    const title = matchKey(game.Title);
    // RA often writes "Title | Regional Title"; score each half.
    const parts = title.split(' | ').map((p) => p.trim());
    let score = 0;
    if (title === key || parts.includes(key)) score = 100;
    else if (parts.some((p) => p.startsWith(key) || key.startsWith(p))) score = 70;
    else if (title.includes(key) || key.includes(title)) score = 50;
    else {
      // Word overlap, so "Castlevania Simons Quest" still finds
      // "Castlevania II - Simon's Quest".
      const words = new Set(key.split(' ').filter((w) => w.length > 2));
      const hit = [...words].filter((w) => title.includes(w)).length;
      score = words.size > 0 ? Math.round((hit / words.size) * 40) : 0;
    }
    // A subset or a hack is rarely what someone means by the base game.
    if (/\[(subset|hack)/i.test(game.Title)) score -= 25;
    return { game, score };
  });
  return scored
    .filter((s) => s.score >= 20)
    .sort((a, b) => b.score - a.score || a.game.Title.localeCompare(b.game.Title))
    .slice(0, 12)
    .map((s) => s.game);
}

interface RAAchievement {
  ID: number | string;
  Title: string;
  Description?: string;
  Points?: number | string;
  DisplayOrder?: number | string;
  type?: string | null;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  // Free upstream, and the answer is a lookup rather than a generation, so a
  // quota-store outage shouldn't block it — fail open, like the IGDB proxy.
  const { rejection, body } = await guard(req, {
    fn: 'ra',
    maxBodyBytes: 4_000,
    quotas: [
      { scope: 'install', windowSeconds: 3_600, limit: 60 },
      { scope: 'global', windowSeconds: 86_400, limit: 5_000 },
    ],
    onQuotaError: 'allow',
  });
  if (rejection) return rejection;

  const mode = typeof body?.mode === 'string' ? body.mode : 'search';

  // `verify` and `progress` run entirely on the USER's key, so they work even
  // if the app's own credentials were never configured. Only the catalogue
  // lookups (which console, which game) need the server's.
  if (mode !== 'verify' && mode !== 'progress' &&
      (!Deno.env.get('RA_API_KEY') || !Deno.env.get('RA_USERNAME'))) {
    console.error('RA_API_KEY / RA_USERNAME not configured');
    return jsonResponse({ error: 'RetroAchievements is not set up yet.' }, 503);
  }

  try {

    // ── search: which RA game is this?
    if (mode === 'search') {
      const gameName = typeof body?.gameName === 'string' ? body.gameName.trim() : '';
      const platform = typeof body?.platform === 'string' ? body.platform.trim() : '';
      if (!gameName || gameName.length > MAX_GAME_NAME) {
        return jsonResponse({ error: 'gameName is required.' }, 400);
      }
      if (platform.length > MAX_PLATFORM) {
        return jsonResponse({ error: 'platform is too long.' }, 400);
      }

      const consoleID = Number.isFinite(body?.consoleID) ? Number(body?.consoleID) : null;
      const resolved = consoleID !== null
        ? (await getConsoles()).find((c) => c.id === consoleID) ?? null
        : await resolveConsole(platform);

      if (!resolved) {
        // Not an error the user can't act on: hand back the console list so
        // the app can ask which system this copy is, rather than dead-ending
        // on a platform name RA words differently.
        return jsonResponse({
          needsConsole: true,
          consoles: (await getConsoles()).sort((a, b) => a.name.localeCompare(b.name)),
        });
      }

      const matches = rank(await getGames(resolved.id), gameName);
      return jsonResponse({
        console: resolved,
        results: matches.map((g) => ({
          id: g.ID,
          title: g.Title,
          achievements: Number(g.NumAchievements ?? 0),
          iconPath: g.ImageIcon ?? null,
        })),
      });
    }

    // ── achievements: the real, authored list for one RA game.
    if (mode === 'achievements') {
      const gameID = Number.isFinite(body?.gameID) ? Number(body?.gameID) : null;
      if (gameID === null || gameID <= 0) {
        return jsonResponse({ error: 'gameID is required.' }, 400);
      }

      const res = await fetch(`${RA_BASE}/API_GetGameExtended.php?i=${gameID}&${auth()}`);
      if (!res.ok) {
        console.error('RA game extended failed:', res.status, await res.text());
        return jsonResponse({ error: 'RetroAchievements is unavailable right now.' }, 502);
      }
      const game = await res.json() as {
        Title?: string;
        ConsoleName?: string;
        Achievements?: Record<string, RAAchievement>;
      };

      const raw = Object.values(game.Achievements ?? {});
      if (raw.length === 0) {
        return jsonResponse({ error: 'That game has no achievements on RetroAchievements.' }, 422);
      }

      const items = raw
        .sort((a, b) => Number(a.DisplayOrder ?? 0) - Number(b.DisplayOrder ?? 0))
        .map((a) => ({
          // Prefixed so an achievement id can never collide with a generated
          // item id in the same tracker.
          id: `ra-${a.ID}`,
          name: String(a.Title ?? '').trim() || `Achievement ${a.ID}`,
          ...(a.Description ? { description: String(a.Description) } : {}),
          // RA marks these itself, so this is a fact rather than the guess a
          // generated tracker makes.
          ...(a.type === 'missable' ? { missable: true } : {}),
          metadata: { points: Number(a.Points ?? 0), raID: Number(a.ID) },
        }));

      const structuredData = {
        schemaVersion: 1,
        generatedAt: new Date().toISOString(),
        generatedBy: 'retroachievements',
        sources: [{ type: 'retroachievements', url: `https://retroachievements.org/game/${gameID}` }],
        categories: [{
          id: 'retroachievements',
          name: 'Achievements',
          // Stamped on the CATEGORY, not just in `sources`: an import into a
          // game that already has a tracker merges category-by-category and
          // keeps the root's own sources, so this is the copy that survives.
          // It's what a later unlock sync looks the game up by.
          raGameID: gameID,
          description: `RetroAchievements set for ${game.Title ?? 'this game'}`,
          type: 'checklist',
          items,
        }],
        runs: [],
      };
      return jsonResponse({
        structuredData,
        title: game.Title ?? null,
        consoleName: game.ConsoleName ?? null,
        count: items.length,
        points: items.reduce((sum, i) => sum + (i.metadata.points || 0), 0),
      });
    }

    // ── verify: are these credentials real? Checked against the user's own
    // profile, which is the cheapest call that fails cleanly on a bad key.
    if (mode === 'verify') {
      const credentials = userAuth(body);
      if (!credentials) return jsonResponse({ error: 'Username and API key are required.' }, 400);
      const user = String(body?.raUsername).trim();

      const res = await fetch(
        `${RA_BASE}/API_GetUserProfile.php?u=${encodeURIComponent(user)}&${credentials}`);
      if (res.status === 401 || res.status === 403) {
        return jsonResponse({ error: 'RetroAchievements rejected that key. Check both fields.' }, 401);
      }
      if (!res.ok) {
        console.error('RA verify failed:', res.status);
        return jsonResponse({ error: 'RetroAchievements is unavailable right now.' }, 502);
      }
      const profile = await res.json() as {
        User?: string; ULID?: string; TotalPoints?: number | string;
      };
      // RA answers 200 with an empty body for a bad key rather than a 401, so
      // "the request worked" is not the same question as "the key is good".
      if (!profile?.User) {
        return jsonResponse({ error: 'RetroAchievements rejected that key. Check both fields.' }, 401);
      }
      // RA's docs: "the username is not considered a stable value" — users
      // have been able to change it since 2025, and every user-scoped endpoint
      // accepts the ULID in its place. Handing that back means a rename on RA
      // doesn't quietly break someone's sync months later.
      return jsonResponse({
        user: profile.User,
        ulid: profile.ULID ?? null,
        points: Number(profile.TotalPoints ?? 0),
      });
    }

    // ── progress: which of this game's achievements the user has unlocked.
    if (mode === 'progress') {
      const credentials = userAuth(body);
      if (!credentials) return jsonResponse({ error: 'Username and API key are required.' }, 400);
      const gameID = Number.isFinite(body?.gameID) ? Number(body?.gameID) : null;
      if (gameID === null || gameID <= 0) {
        return jsonResponse({ error: 'gameID is required.' }, 400);
      }
      // `u` takes a username OR a ULID, and the ULID is the stable one.
      const ulid = typeof body?.raULID === 'string' ? body.raULID.trim() : '';
      const user = ulid || String(body?.raUsername).trim();

      const res = await fetch(
        `${RA_BASE}/API_GetGameInfoAndUserProgress.php?g=${gameID}&u=${encodeURIComponent(user)}&${credentials}`);
      if (!res.ok) {
        console.error('RA progress failed:', res.status);
        return jsonResponse({ error: 'Could not read your progress from RetroAchievements.' }, 502);
      }
      const game = await res.json() as {
        Title?: string;
        Achievements?: Record<string, RAAchievement & {
          DateEarned?: string | null;
          DateEarnedHardcore?: string | null;
        }>;
      };

      const all = Object.values(game.Achievements ?? {});
      const unlocked = all
        .filter((a) => a.DateEarned || a.DateEarnedHardcore)
        .map((a) => ({
          id: `ra-${a.ID}`,
          // Hardcore is the stricter earn (no savestates, no rewind). Reported
          // so the app can say which, not so it can filter: an unlock is an
          // unlock either way and refusing to tick a softcore one would be
          // telling someone they didn't do a thing they did.
          hardcore: Boolean(a.DateEarnedHardcore),
          earnedAt: a.DateEarnedHardcore || a.DateEarned || null,
          points: Number(a.Points ?? 0),
        }));

      return jsonResponse({
        title: game.Title ?? null,
        total: all.length,
        unlocked,
        points: unlocked.reduce((sum, a) => sum + a.points, 0),
        totalPoints: all.reduce((sum, a) => sum + Number(a.Points ?? 0), 0),
      });
    }

    return jsonResponse({ error: 'Unsupported mode.' }, 400);
  } catch (err) {
    console.error('ra-proxy error:', String(err));
    return jsonResponse({ error: 'RetroAchievements lookup failed. Try again.' }, 500);
  }
});
