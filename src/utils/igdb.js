// IGDB API integration via Supabase Edge Function proxy
// The Edge Function has JWT verification disabled — no auth header needed.

const PROXY_URL = 'https://sextftevxqrtodlmnyve.supabase.co/functions/v1/igdb-proxy';

// IGDB image URL helper
export function igdbCoverUrl(imageId, size = 'cover_big') {
  if (!imageId) return null;
  return `https://images.igdb.com/igdb/image/upload/t_${size}/${imageId}.jpg`;
}

// Build IGDB game page URL from slug
export function igdbGameUrl(slug) {
  if (!slug) return null;
  return `https://www.igdb.com/games/${slug}`;
}

// Parse an InvolvedCompany array into { developers: string[], publishers: string[] }
function parseCompanies(involvedCompanies) {
  const developers = [];
  const publishers = [];
  (involvedCompanies || []).forEach(ic => {
    const name = ic.company?.name;
    if (!name) return;
    if (ic.developer) developers.push(name);
    if (ic.publisher) publishers.push(name);
  });
  return { developers, publishers };
}

// Search IGDB for games by name
export async function searchIGDB(query) {
  if (!query || query.trim().length < 2) return [];

  try {
    const response = await fetch(PROXY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        endpoint: 'games',
        query: `
          search "${query.replace(/"/g, '')}";
          fields name, slug, cover.image_id, franchises.name, first_release_date,
                 platforms.name, game_type,
                 genres.name, themes.name, game_modes.name, player_perspectives.name,
                 involved_companies.developer, involved_companies.publisher,
                 involved_companies.company.name;
          where game_type = (0) & version_parent = null;
          limit 8;
        `,
      }),
    });

    if (!response.ok) {
      console.error('IGDB proxy error:', response.status);
      return [];
    }

    const games = await response.json();
    if (!Array.isArray(games)) return [];

    return games.map(g => {
      const { developers, publishers } = parseCompanies(g.involved_companies);
      return {
        igdbId: String(g.id),
        igdbSlug: g.slug || null,
        name: g.name,
        franchise: g.franchises?.[0]?.name || null,
        coverImageId: g.cover?.image_id || null,
        coverUrl: g.cover?.image_id ? igdbCoverUrl(g.cover.image_id) : null,
        firstReleaseDate: g.first_release_date
          ? new Date(g.first_release_date * 1000).getFullYear()
          : null,
        platforms: (g.platforms || []).map(p => p.name),
        genres: (g.genres || []).map(x => x.name),
        themes: (g.themes || []).map(x => x.name),
        gameModes: (g.game_modes || []).map(x => x.name),
        playerPerspectives: (g.player_perspectives || []).map(x => x.name),
        developers,
        publishers,
      };
    });
  } catch (e) {
    console.error('IGDB search failed:', e);
    return [];
  }
}

// Batch-fetch multiple games by IGDB ID — used after CSV import
// Returns a Map of igdbId (string) → game data
export async function batchFetchIGDB(igdbIds) {
  if (!igdbIds || igdbIds.length === 0) return new Map();

  // IGDB allows up to 500 results per query; chunk just in case
  const CHUNK = 40;
  const resultMap = new Map();

  for (let i = 0; i < igdbIds.length; i += CHUNK) {
    const chunk = igdbIds.slice(i, i + CHUNK);
    const idList = chunk.join(',');

    try {
      const response = await fetch(PROXY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          endpoint: 'games',
          query: `
            fields name, slug, cover.image_id, franchises.name, first_release_date,
                   platforms.name, genres.name, themes.name, game_modes.name,
                   player_perspectives.name,
                   involved_companies.developer, involved_companies.publisher,
                   involved_companies.company.name;
            where id = (${idList});
            limit ${CHUNK};
          `,
        }),
      });

      if (!response.ok) continue;
      const games = await response.json();
      if (!Array.isArray(games)) continue;

      games.forEach(g => {
        const { developers, publishers } = parseCompanies(g.involved_companies);
        resultMap.set(String(g.id), {
          igdbSlug: g.slug || null,
          coverImageId: g.cover?.image_id || null,
          coverUrl: g.cover?.image_id ? igdbCoverUrl(g.cover.image_id) : null,
          franchise: g.franchises?.[0]?.name || null,
          firstReleaseDate: g.first_release_date
            ? new Date(g.first_release_date * 1000).getFullYear()
            : null,
          igdbPlatforms: (g.platforms || []).map(p => p.name),
          genres: (g.genres || []).map(x => x.name),
          themes: (g.themes || []).map(x => x.name),
          gameModes: (g.game_modes || []).map(x => x.name),
          playerPerspectives: (g.player_perspectives || []).map(x => x.name),
          developers,
          publishers,
        });
      });
    } catch (e) {
      console.error('IGDB batch fetch chunk failed:', e);
    }
  }

  return resultMap;
}

// Search IGDB by name — used to look up a game when only name is known (no igdbId)
export async function fetchIGDBByName(name) {
  if (!name) return null;
  const results = await searchIGDB(name);
  // Return the first result that closely matches the name
  const lower = name.toLowerCase();
  return results.find(r => r.name.toLowerCase() === lower) || results[0] || null;
}

// Fetch a single game by IGDB ID (for refreshing existing game data)
export async function fetchIGDBGame(igdbId) {
  if (!igdbId) return null;

  try {
    const response = await fetch(PROXY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        endpoint: 'games',
        query: `
          fields name, slug, cover.image_id, franchises.name, first_release_date,
                 platforms.name, genres.name, themes.name, game_modes.name,
                 player_perspectives.name,
                 involved_companies.developer, involved_companies.publisher,
                 involved_companies.company.name;
          where id = ${igdbId};
          limit 1;
        `,
      }),
    });

    if (!response.ok) return null;
    const games = await response.json();
    const g = games?.[0];
    if (!g) return null;

    const { developers, publishers } = parseCompanies(g.involved_companies);

    return {
      igdbId: String(g.id),
      igdbSlug: g.slug || null,
      name: g.name,
      franchise: g.franchises?.[0]?.name || null,
      coverImageId: g.cover?.image_id || null,
      coverUrl: g.cover?.image_id ? igdbCoverUrl(g.cover.image_id) : null,
      firstReleaseDate: g.first_release_date
        ? new Date(g.first_release_date * 1000).getFullYear()
        : null,
      platforms: (g.platforms || []).map(p => p.name),
      genres: (g.genres || []).map(x => x.name),
      themes: (g.themes || []).map(x => x.name),
      gameModes: (g.game_modes || []).map(x => x.name),
      playerPerspectives: (g.player_perspectives || []).map(x => x.name),
      developers,
      publishers,
    };
  } catch (e) {
    console.error('IGDB fetch failed:', e);
    return null;
  }
}
