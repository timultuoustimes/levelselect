// localStorage wrapper with error handling and versioning

const STORAGE_KEY = 'game-tracker-data';
const STORAGE_VERSION = 1;

export function loadData() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const data = JSON.parse(raw);
    if (data.version !== STORAGE_VERSION) {
      // Future: migration logic
      return migrateData(data);
    }
    return data;
  } catch (e) {
    console.error('Failed to load data:', e);
    return null;
  }
}

export function saveData(data) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...data, version: STORAGE_VERSION }));
  } catch (e) {
    console.error('Failed to save data:', e);
  }
}

export function exportData() {
  const data = loadData();
  if (!data) return null;
  return JSON.stringify(data, null, 2);
}

export function importData(jsonString) {
  try {
    const data = JSON.parse(jsonString);
    saveData(data);
    return data;
  } catch (e) {
    console.error('Failed to import data:', e);
    return null;
  }
}

function migrateData(data) {
  // For now, just stamp with current version
  return { ...data, version: STORAGE_VERSION };
}

// Create default app state
export function createDefaultState() {
  return {
    version: STORAGE_VERSION,
    library: [],
    currentGameId: null,
    currentSaveId: null,
  };
}
