const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

export function createGenericRoguelikeSave(name) {
  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    lastPlayedAt: new Date().toISOString(),
    runs: [],
    activeRun: null,
    sessions: [],
    notes: '',
  };
}

export function migrateGenericRoguelikeSave(save) {
  const migrated = { ...save };
  if (!migrated.sessions) migrated.sessions = [];
  if (migrated.notes === undefined) migrated.notes = '';
  return migrated;
}

export function createGenericRun(loadout = {}) {
  return {
    id: generateId(),
    startTime: new Date().toISOString(),
    endTime: null,
    loadout, // flexible key/value from config fields
    notes: '',
    outcome: null, // 'victory'|'death'|'escaped'|'abandoned'
    duration: 0,
    accumulatedTime: 0,
    pausedAt: null,
  };
}
