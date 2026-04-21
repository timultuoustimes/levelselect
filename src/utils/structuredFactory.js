// Save-state factory for the StructuredTracker.
//
// The config (or game.structuredData in Phase 3) defines WHAT exists —
// categories, items, ranks. The save below tracks WHAT IS DONE on this
// particular playthrough.
//
// Per-item state lives in `itemState: { [itemId]: { done?, rank?, revealed?, notes? } }`
// so we only store diffs from the config defaults.

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

export function createStructuredSave(name) {
  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    lastPlayedAt: new Date().toISOString(),

    // Per-item mutable state. Keys are item ids from the schema.
    // Only populated for items the user has touched.
    //   { done: boolean, rank: number, revealed: boolean, notes: string }
    itemState: {},

    // Run history (for games whose schema has runTemplate). Always
    // present so the renderer can blindly push to it.
    runs: [],

    // Shared session/playtime pattern (same shape as every other tracker).
    sessions: [],
    activeSession: null,
    totalPlaytime: 0,
    notes: '',

    // Optional user-edited schema override. null = use the config/game
    // schema as-is; object = the user has customized categories/items
    // for this save and we should use the override instead.
    customSchema: null,
  };
}

// Safe accessor — never returns undefined. Defaults to unstarted.
export function getItemState(save, itemId) {
  const s = save?.itemState?.[itemId] || {};
  return {
    done: s.done ?? false,
    rank: s.rank ?? 0,
    revealed: s.revealed ?? false,
    notes: s.notes ?? '',
  };
}

// Immutable update helper — returns a new save with a partial item
// state merged in. Callers pass this through updateCurrentSave.
export function setItemState(save, itemId, partial) {
  const prev = save?.itemState?.[itemId] || {};
  return {
    ...save,
    itemState: {
      ...(save?.itemState || {}),
      [itemId]: { ...prev, ...partial },
    },
  };
}
