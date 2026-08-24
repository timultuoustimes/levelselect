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
  /** What KIND of game it is — the thing a familiar franchise name hides. */
  genres: string[];
  themes: string[];
  /** IGDB's own description, trimmed. The cheapest possible retrieval. */
  summary: string | null;
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
      body: `fields name,first_release_date,summary,genres.name,themes.name,involved_companies.developer,involved_companies.company.name; where id = ${id};`,
    });
    if (!res.ok) {
      console.warn(`igdb identity lookup failed: ${res.status}`);
      return null;
    }

    const rows = await res.json() as Array<{
      name?: string;
      first_release_date?: number;
      summary?: string;
      genres?: Array<{ name?: string }>;
      themes?: Array<{ name?: string }>;
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
      genres: (row.genres ?? []).map((g) => g.name).filter((n): n is string => !!n),
      themes: (row.themes ?? []).map((t) => t.name).filter((n): n is string => !!n),
      // Trimmed: this rides in every prompt, and the first paragraph carries
      // what kind of game it is. The rest is marketing.
      summary: row.summary ? row.summary.slice(0, 600) : null,
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
function words(value: string): Set<string> {
  return new Set(
    value.toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((w) => w.length > 2),
  );
}

/**
 * Do these two titles plausibly name the same game?
 *
 * Used to decide whether the stored id can be trusted to RENAME the game in
 * the prompt. "Zelda BOTW" vs "The Legend of Zelda: Breath of the Wild" shares
 * enough; "Hitman World of Assassination" vs "Baldur's Gate III" shares
 * nothing, which is the signal that the id and the name disagree.
 */
function plausiblySameGame(a: string, b: string): boolean {
  const left = words(a);
  const right = words(b);
  if (left.size === 0 || right.size === 0) return true;
  for (const w of left) if (right.has(w)) return true;
  return false;
}

export function identityQualifier(identity: GameIdentity | null, typedName: string): string {
  if (!identity) return '';

  // A stored id can be WRONG — that is the whole reason Fix Match is wanted —
  // and a wrong id used to be inert. Now it feeds the prompt, so it can assert
  // a confident falsehood instead: a probe with Baldur's Gate III's id told the
  // model that a Hitman request was "known on IGDB as Baldur's Gate III". It
  // ignored that and answered correctly, which was luck, not design.
  //
  // So the canonical name is only offered when it shares a word with the name
  // the user has. Year and developer stay either way: if they disagree with the
  // title they read as extra context the model can weigh, not as an
  // instruction to track a different game.
  const trusted = plausiblySameGame(identity.name, typedName);

  const parts: string[] = [];
  // Only worth saying when it differs — IGDB's canonical title is the one the
  // guides use, and a user's shorthand ("Zelda BOTW") is not.
  if (trusted && identity.name.toLowerCase() !== typedName.trim().toLowerCase()) {
    parts.push(`known on IGDB as "${identity.name}"`);
  }
  if (identity.year) parts.push(`released ${identity.year}`);
  if (identity.developer) parts.push(`developed by ${identity.developer}`);
  return parts.length > 0 ? ` (${parts.join(', ')})` : '';
}

/**
 * What the game actually IS, for a prompt that would otherwise guess from the
 * title.
 *
 * This exists because of Pokémon Pokopia. Plan mode does no web search — by
 * design, since it has to answer in seconds — so the model saw a familiar
 * franchise name and produced the mainline RPG skeleton: Gym Badges, Elite
 * Four & Champion, Moves & TMs. Pokopia is a sandbox life sim where you play
 * as a Ditto rebuilding a withered world. It has none of those things, and the
 * plan looked completely plausible, which is the dangerous part.
 *
 * IGDB knew: Simulator, Adventure, Sandbox, and a summary that says so in one
 * sentence. The identity lookup was already making this call, so the retrieval
 * costs nothing extra — the cheapest possible fix for the app's most confident
 * failure mode.
 */
export function identityContext(identity: GameIdentity | null): string {
  if (!identity) return '';
  const lines: string[] = [];
  const kinds = [...identity.genres, ...identity.themes];
  if (kinds.length > 0) lines.push(`IGDB classifies it as: ${kinds.join(', ')}.`);
  if (identity.summary) lines.push(`IGDB's description: ${identity.summary}`);
  if (lines.length === 0) return '';
  return '\n\n' + lines.join('\n') +
    '\nTrust this over any assumption from the title. A familiar series name does not mean the usual structure — spin-offs, sandboxes and remakes share names with games they are nothing like.';
}
