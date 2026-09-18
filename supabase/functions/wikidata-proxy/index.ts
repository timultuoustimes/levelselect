// Supabase Edge Function: Wikidata proxy
//
// Deploy with: supabase functions deploy wikidata-proxy
//
// **No secrets. That is the point.** Wikidata's query service needs no key and
// no account, which is why it cleared the bar for a project that refuses fixed
// costs before revenue and whose author does not enter API tokens. This exists
// for two other reasons:
//
//   1. Wikimedia's User-Agent policy asks for a descriptive agent with a
//      contact. Setting it here means one place tells the truth about who is
//      asking, rather than every client build carrying its own version string.
//   2. The query shape can change without shipping an app release — the same
//      reason IGDB goes through a proxy.
//
// The app sends an IGDB SLUG, never a name. Wikidata's P5794 stores the slug
// ("hollow-knight", "hades--1"), and matching by name is exactly how the wrong
// game's logo got attached to a manually added title once already.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { CORS_HEADERS, guard, jsonResponse } from '../_shared/guard.ts';

const ENDPOINT = 'https://query.wikidata.org/sparql';
const USER_AGENT =
  'LevelSelect/1.0 (https://levelselect.app; wikimedia@timrmiller.com)';

/** IGDB slugs are lowercase alphanumerics and hyphens. Nothing else goes into a query. */
const SLUG = /^[a-z0-9-]{1,120}$/;

/** One request may ask about a handful of games, not a catalogue. */
const MAX_SLUGS = 12;

/**
 * What LevelSelect asks Wikidata for, and nothing else.
 *
 * Every property here is one IGDB structurally lacks. IGDB has no person or
 * credit field at all — every credit is company-level through
 * `involved_companies` — so director, composer, designer and writer are the
 * whole reason this integration exists.
 *
 *   P57  director        P86  composer      P287 designer
 *   P58  screenwriter    P178 developer     P179 series
 *   P577 publication date (for cross-checking IGDB's, never for overwriting it)
 */
function sparql(slugs: string[]): string {
  const values = slugs.map((s) => `"${s}"`).join(' ');
  return `
SELECT ?igdb ?item ?itemLabel ?role ?personLabel ?seriesLabel ?released WHERE {
  VALUES ?igdb { ${values} }
  ?item wdt:P5794 ?igdb .
  OPTIONAL { ?item wdt:P577 ?released . }
  OPTIONAL { ?item wdt:P179 ?series . }
  {
    { ?item wdt:P57 ?person . BIND("director" AS ?role) }
    UNION { ?item wdt:P86 ?person . BIND("composer" AS ?role) }
    UNION { ?item wdt:P287 ?person . BIND("designer" AS ?role) }
    UNION { ?item wdt:P58 ?person . BIND("writer" AS ?role) }
  } UNION { BIND("" AS ?role) }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 200`;
}

/**
 * Other games by the people who made this one, in two bounded steps.
 *
 * One query asking "what else have the people on this game made" takes
 * **43 seconds** on Wikidata's public endpoint — the reverse hop over four
 * credit properties is unbounded. Asking who they are first, then asking what
 * those specific people made, answers in about a second, because the second
 * query starts from a handful of QIDs.
 *
 * IGDB has no person field at all, so this connection can come from nowhere
 * else. `?other wdt:P5794 ?otherIgdb` is required rather than optional: a game
 * the app can't look up in IGDB has no cover and no page.
 */
function peopleSparql(slugs: string[]): string {
  const values = slugs.map((s) => `"${s}"`).join(' ');
  return `
SELECT ?igdb ?person ?personLabel ?role WHERE {
  VALUES ?igdb { ${values} }
  ?item wdt:P5794 ?igdb .
  {
    { ?item wdt:P57 ?person . BIND("director" AS ?role) }
    UNION { ?item wdt:P86 ?person . BIND("composer" AS ?role) }
    UNION { ?item wdt:P287 ?person . BIND("designer" AS ?role) }
    UNION { ?item wdt:P58 ?person . BIND("writer" AS ?role) }
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 40`;
}

function creditsSparql(qids: string[]): string {
  const values = qids.map((q) => `wd:${q}`).join(' ');
  return `
SELECT ?person ?otherLabel ?otherIgdb WHERE {
  VALUES ?person { ${values} }
  ?other ?credit ?person .
  VALUES ?credit { wdt:P57 wdt:P86 wdt:P287 wdt:P58 }
  ?other wdt:P5794 ?otherIgdb .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 200`;
}

/** QIDs only: nothing else is ever interpolated into a query. */
const QID = /^Q[0-9]{1,12}$/;

async function ask(query: string): Promise<Record<string, { value: string }>[] | null> {
  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'User-Agent': USER_AGENT,
        Accept: 'application/sparql-results+json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ query }),
    });
    if (!res.ok) return null;
    const raw = await res.json();
    return raw?.results?.bindings ?? [];
  } catch (_) {
    return null;
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });

  // Free upstream that rate-limits by user agent, so a quota-store outage
  // should not take the section down — fail open, like the IGDB proxy. The
  // per-install ceilings are lower than IGDB's because nothing here is on the
  // Add Game path: this is one lookup per game page.
  const { rejection, body } = await guard(req, {
    fn: 'wikidata',
    maxBodyBytes: 2_000,
    quotas: [
      { scope: 'install', windowSeconds: 60, limit: 30 },
      { scope: 'install', windowSeconds: 86_400, limit: 1_000 },
      { scope: 'global', windowSeconds: 86_400, limit: 10_000 },
    ],
    onQuotaError: 'allow',
  });
  if (rejection) return rejection;

  const slugs = body?.slugs;
  // "people" asks what else the people behind these games have made; the
  // default asks about the games themselves. A build that never sends the
  // field behaves exactly as it always has.
  const mode = body?.mode === 'people' ? 'people' : 'games';

  if (!Array.isArray(slugs) || slugs.length === 0) {
    return jsonResponse({ error: 'Send { slugs: [String] }.' }, 400);
  }
  if (slugs.length > MAX_SLUGS) {
    return jsonResponse({ error: `At most ${MAX_SLUGS} slugs per request.` }, 400);
  }
  // Validated rather than escaped. A slug that is not a slug is a bug or an
  // attempt, and neither belongs in a query string.
  const clean = slugs.filter((s): s is string => typeof s === 'string' && SLUG.test(s));
  if (clean.length === 0) {
    return jsonResponse({ error: 'No valid IGDB slugs in request.' }, 400);
  }

  if (mode === 'people') {
    const first = await ask(peopleSparql(clean));
    if (!first) return jsonResponse({ error: 'Wikidata is unreachable.' }, 502);
    // slug → person QIDs, and QID → who they are.
    const bySlug: Record<string, string[]> = {};
    const named: Record<string, { name: string; role: string }> = {};
    for (const row of first) {
      const slug = row.igdb?.value;
      const qid = row.person?.value?.split('/').pop() ?? '';
      const name = row.personLabel?.value ?? '';
      if (!slug || !QID.test(qid) || !name || name.startsWith('Q')) continue;
      named[qid] ??= { name, role: row.role?.value ?? '' };
      (bySlug[slug] ??= []).includes(qid) || bySlug[slug].push(qid);
    }
    const qids = Object.keys(named).slice(0, 12);
    if (qids.length === 0) return jsonResponse({ people: {} });

    const second = await ask(creditsSparql(qids));
    if (!second) return jsonResponse({ error: 'Wikidata is unreachable.' }, 502);
    const gamesByPerson: Record<string, { name: string; slug: string }[]> = {};
    for (const row of second) {
      const qid = row.person?.value?.split('/').pop() ?? '';
      const name = row.otherLabel?.value ?? '';
      const slug = row.otherIgdb?.value ?? '';
      if (!QID.test(qid) || !slug || !name || name.startsWith('Q')) continue;
      const list = (gamesByPerson[qid] ??= []);
      if (!list.some((g) => g.slug === slug)) list.push({ name, slug });
    }

    const people: Record<string, {
      name: string;
      role: string;
      games: { name: string; slug: string }[];
    }[]> = {};
    for (const [slug, personIDs] of Object.entries(bySlug)) {
      people[slug] = personIDs
        .filter((qid) => (gamesByPerson[qid]?.length ?? 0) > 0)
        .map((qid) => ({
          name: named[qid].name,
          role: named[qid].role,
          games: gamesByPerson[qid] ?? [],
        }))
        // The person credited on most of them is the better answer.
        .sort((a, b) => b.games.length - a.games.length);
    }
    return jsonResponse({ people });
  }

  let response: Response;
  try {
    response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        'User-Agent': USER_AGENT,
        Accept: 'application/sparql-results+json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ query: sparql(clean) }),
    });
  } catch (_) {
    return jsonResponse({ error: 'Wikidata is unreachable.' }, 502);
  }

  if (!response.ok) {
    // Wikidata rate-limits by user agent and asks callers to back off. Passing
    // the status through lets the app say something true rather than guess.
    return jsonResponse({ error: `Wikidata answered ${response.status}.` }, 502);
  }

  const raw = await response.json();
  const rows: Record<string, { value: string }>[] = raw?.results?.bindings ?? [];


  /**
   * One entry per game, credits deduplicated.
   *
   * Shaped here rather than in the app so the client needs no SPARQL result
   * parser — the same division of labour the changelog feed uses.
   */
  const byGame: Record<string, {
    qid: string;
    title: string | null;
    series: string | null;
    released: string | null;
    credits: { role: string; name: string }[];
  }> = {};

  for (const row of rows) {
    const slug = row.igdb?.value;
    if (!slug) continue;
    const qid = row.item?.value?.split('/').pop() ?? '';
    const entry = (byGame[slug] ??= {
      qid,
      title: null,
      series: null,
      released: null,
      credits: [],
    });
    // An entity with no English label comes back AS its Q-number, which is not
    // a title anybody wants to read.
    const label = row.itemLabel?.value ?? '';
    if (!entry.title && label && label !== qid) entry.title = label;
    if (!entry.series && row.seriesLabel?.value) entry.series = row.seriesLabel.value;
    if (!entry.released && row.released?.value) entry.released = row.released.value;

    const role = row.role?.value ?? '';
    const name = row.personLabel?.value ?? '';
    if (role && name && !name.startsWith('Q')) {
      if (!entry.credits.some((c) => c.role === role && c.name === name)) {
        entry.credits.push({ role, name });
      }
    }
  }

  return jsonResponse({ games: byGame });
});
