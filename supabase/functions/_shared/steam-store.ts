// Shaping Steam's public catalogue answers for the app.
//
// Pure, so it can be tested without a network or a key. Only catalogue data
// passes through here — a search term's matches and a game's achievement list.
// Nothing about a player ever does; see steam-proxy.

export const MAX_STEAM_TERM = 200;

export interface SteamSearchResult {
  id: number;
  name: string;
}

/// storesearch returns apps, bundles and DLC together. An achievement list
/// belongs to an app, so only apps are kept.
export function shapeSearch(json: unknown, limit = 12): SteamSearchResult[] {
  const items = (json as { items?: unknown })?.items;
  if (!Array.isArray(items)) return [];
  const out: SteamSearchResult[] = [];
  for (const raw of items) {
    const item = raw as { type?: unknown; id?: unknown; name?: unknown };
    if (item?.type !== 'app') continue;
    const id = Number(item.id);
    const name = typeof item.name === 'string' ? item.name.trim() : '';
    if (!Number.isInteger(id) || id <= 0 || !name) continue;
    out.push({ id, name });
    if (out.length >= limit) break;
  }
  return out;
}

export interface SteamSchema {
  gameName: string | null;
  achievements: Record<string, unknown>[];
}

/// GetSchemaForGame, trimmed to what the app reads: the game's name and its
/// achievements. Null when Steam lists none, so the app can say so plainly.
export function shapeSchema(json: unknown): SteamSchema | null {
  const game = (json as { game?: Record<string, unknown> })?.game;
  const stats = game?.availableGameStats as { achievements?: unknown } | undefined;
  const list = stats?.achievements;
  if (!Array.isArray(list) || list.length === 0) return null;
  const achievements = list
    .map((a) => (a ?? {}) as Record<string, unknown>)
    .filter((a) => typeof a.name === 'string' && a.name !== '')
    .map((a) => ({
      name: a.name,
      ...(typeof a.displayName === 'string' ? { displayName: a.displayName } : {}),
      ...(typeof a.description === 'string' ? { description: a.description } : {}),
      ...(typeof a.icon === 'string' ? { icon: a.icon } : {}),
      ...(typeof a.icongray === 'string' ? { icongray: a.icongray } : {}),
      hidden: Number(a.hidden) === 1 ? 1 : 0,
    }));
  if (achievements.length === 0) return null;
  return {
    gameName: typeof game?.gameName === 'string' && game.gameName !== '' ? game.gameName : null,
    achievements,
  };
}
