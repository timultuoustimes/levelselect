// Look one game up by its IGDB id, so a generator knows WHICH game it is.
//
// The app has always sent `igdbID` alongside the name; nothing read it, so the
// model was identifying games by name alone. That is how "The Messenger"
// becomes a different game from 2000 and how a Castlevania request lands on the
// wrong entry in a series where a dozen titles are near-identical strings.
//
// A bare id is useless to a language model — it cannot look one up. What
// disambiguates is what the id RESOLVES to: the canonical title, the release
// year, and who made it. That is the whole job here.
//
// Uses the same IGDB_CLIENT_ID / IGDB_CLIENT_SECRET secrets as igdb-proxy,
// which are project-wide. The token cache is per-instance, like the proxy's.

let cachedToken: string | null = null;
let tokenExpiry = 0;

async function twitchToken(): Promise<string | null> {
  if (cachedToken && Date.now() < tokenExpiry) return cachedToken;

  const clientId = Deno.env.get('IGDB_CLIENT_ID');
  const clientSecret = Deno.env.get('IGDB_CLIENT_SECRET');
  if (!clientId || !clientSecret) return null;

  const res = await fetch(
    `https://id.twitch.tv/oauth2/token?client_id=${clientId}&client_secret=${clientSecret}&grant_type=client_credentials`,
    { method: 'POST' },
  );
  if (!res.ok) return null;

  const json = await res.json();
  cachedToken = json.access_token ?? null;
  tokenExpiry = Date.now() + ((json.expires_in ?? 3600) - 300) * 1000;
  return cachedToken;
}

export interface GameIdentity {
  /** IGDB's canonical name, which may differ from what the user typed. */
  name: string;
  /** Release year, the single most useful disambiguator. */
  year: number | null;
  developer: string | null;
}

/**
 * Resolve an IGDB id to the facts that identify a game.
 *
 * Returns null for anything unusable — a missing id, missing credentials, a
 * failed lookup. Generation must still work without it, because an id is an
 * improvement to the prompt and never a requirement for it.
 */
export async function gameIdentity(rawID: unknown): Promise<GameIdentity | null> {
  const id = Number.isFinite(rawID) ? Number(rawID) : null;
  if (!id || id <= 0) return null;

  const clientId = Deno.env.get('IGDB_CLIENT_ID');
  const token = await twitchToken();
  if (!clientId || !token) return null;

  try {
    const res = await fetch('https://api.igdb.com/v4/games', {
      method: 'POST',
      headers: {
        'Client-ID': clientId,
        Authorization: `Bearer ${token}`,
        'Content-Type': 'text/plain',
      },
      body: `fields name,first_release_date,involved_companies.developer,involved_companies.company.name; where id = ${id};`,
    });
    if (!res.ok) {
      console.warn(`igdb identity lookup failed: ${res.status}`);
      return null;
    }

    const rows = await res.json() as Array<{
      name?: string;
      first_release_date?: number;
      involved_companies?: Array<{ developer?: boolean; company?: { name?: string } }>;
    }>;
    const row = rows[0];
    if (!row?.name) return null;

    const dev = (row.involved_companies ?? []).find((c) => c.developer)?.company?.name;
    return {
      name: row.name,
      year: row.first_release_date
        ? new Date(row.first_release_date * 1000).getUTCFullYear()
        : null,
      developer: dev ?? null,
    };
  } catch (err) {
    console.warn('igdb identity lookup threw:', String(err));
    return null;
  }
}

/**
 * A parenthetical that pins down which game is meant, or "" when nothing is
 * known. Deliberately plain prose: this is read by a model, not parsed.
 */
export function identityQualifier(identity: GameIdentity | null, typedName: string): string {
  if (!identity) return '';
  const parts: string[] = [];
  // Only worth saying when it differs — IGDB's canonical title is the one the
  // guides use, and a user's shorthand ("Zelda BOTW") is not.
  if (identity.name.toLowerCase() !== typedName.trim().toLowerCase()) {
    parts.push(`known on IGDB as "${identity.name}"`);
  }
  if (identity.year) parts.push(`released ${identity.year}`);
  if (identity.developer) parts.push(`developed by ${identity.developer}`);
  return parts.length > 0 ? ` (${parts.join(', ')})` : '';
}
