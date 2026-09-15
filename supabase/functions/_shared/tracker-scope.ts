// Scoping a whole-tracker generation to the categories the user already has.
//
// A regeneration used to send only the game's name, so the model decided the
// headings itself and a "refresh" added lists the user never had — Tim,
// 2026-09-14: "hitting regenerate … does every category possible". The app now
// sends its categories; these helpers hold the server to them. Finding NEW
// categories is plan mode's job.
//
// Pure functions, so the rules are testable without calling a model.

export const MAX_REQUESTED_CATEGORIES = 30;
export const MAX_REQUESTED_NAME = 80;
const MAX_REQUESTED_COUNT = 1_000;

export interface RequestedCategory {
  name: string;
  expectedCount: number | null;
  counted: boolean;
}

export function slugify(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'category';
}

/**
 * Loose enough that "Warrior's Graves" matches "Warrior Graves": case,
 * punctuation and a possessive 's are all ignored. The possessive has to go
 * BEFORE the punctuation does, or "warrior's" collapses to "warriors" and no
 * longer matches — the first version did exactly that, and its test caught it.
 */
export function matchKey(value: string): string {
  return value.toLowerCase().normalize('NFKD')
    .replace(/['\u2019\u2018`]s\b/g, '')
    .replace(/[^a-z0-9]+/g, '');
}

/**
 * The `categories` a request asked for, cleaned: names trimmed and capped,
 * duplicates dropped, sizes clamped. Null when the request didn't scope itself —
 * a first generation, and every request from a build that predates the field,
 * which must behave exactly as it always has.
 */
export function parseRequestedCategories(raw: unknown): RequestedCategory[] | null {
  if (!Array.isArray(raw)) return null;
  const seen = new Set<string>();
  const out: RequestedCategory[] = [];
  for (const entry of raw) {
    const record = entry && typeof entry === 'object' ? entry as Record<string, unknown> : {};
    const name = typeof record.name === 'string'
      ? record.name.trim().slice(0, MAX_REQUESTED_NAME)
      : '';
    const key = matchKey(name);
    if (!name || !key || seen.has(key)) continue;
    seen.add(key);
    const count = Number(record.expectedCount);
    out.push({
      name,
      expectedCount: Number.isFinite(count) && count > 0
        ? Math.min(Math.round(count), MAX_REQUESTED_COUNT)
        : null,
      counted: record.counted === true,
    });
    if (out.length >= MAX_REQUESTED_CATEGORIES) break;
  }
  return out.length > 0 ? out : null;
}

/** The prompt section that holds a regeneration to the user's categories. */
export function scopeInstructions(requested: RequestedCategory[]): string {
  const lines = requested.map((category, index) => {
    const size = category.counted
      ? ` — a RUNNING TOTAL: return exactly one item named after the set, with countTarget set to the real total${
        category.expectedCount ? ` (the user's figure is ${category.expectedCount})` : ''}`
      : category.expectedCount
      ? ` — roughly ${category.expectedCount} items (a hint, not a quota)`
      : '';
    return `${index + 1}. "${category.name}"${size}`;
  });
  return [
    '\nThe user already has a tracker for this game and is REFRESHING it. Generate exactly these categories, in this order, and no others:',
    ...lines,
    "Use each category name exactly as written — the app matches your answer to the user's lists by name. Do not add, split, merge or rename categories, however obviously something else belongs in a tracker; suggesting new categories is a separate step.",
  ].join('\n');
}

/**
 * Keep only the categories that were asked for, under the names they were asked
 * for by, in the order they were asked for. The model is told all of this; this
 * is what makes it true regardless. `missing` names the ones that didn't come
 * back, so a caller can say so instead of treating silence as "no items".
 */
export function keepRequestedCategories(
  categories: unknown[],
  requested: RequestedCategory[],
): { categories: Record<string, unknown>[]; missing: string[] } {
  const wantedByKey = new Map(requested.map((category) => [matchKey(category.name), category]));
  const kept = new Map<string, Record<string, unknown>>();
  for (const raw of categories) {
    if (!raw || typeof raw !== 'object') continue;
    const category = raw as Record<string, unknown>;
    const key = matchKey(typeof category.name === 'string' ? category.name : '');
    const wanted = wantedByKey.get(key);
    if (!wanted || kept.has(key)) continue;
    kept.set(key, { ...category, id: slugify(wanted.name), name: wanted.name });
  }
  return {
    categories: requested
      .filter((category) => kept.has(matchKey(category.name)))
      .map((category) => kept.get(matchKey(category.name))!),
    missing: requested
      .filter((category) => !kept.has(matchKey(category.name)))
      .map((category) => category.name),
  };
}
