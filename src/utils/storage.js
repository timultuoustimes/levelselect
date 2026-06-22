// Storage layer: localStorage for instant reads + Supabase for cross-device sync
import { supabase } from './supabase.js';

const STORAGE_KEY = 'game-tracker-data';
const DEVICE_ID_KEY = 'game-tracker-device-id';
const STORAGE_VERSION = 1;
const TABLE = 'game_data';

// ---------- Device ID ----------
// Each browser gets a stable ID. On first sync, we use this to find/create
// the user's row in Supabase. The user can "link" devices by copying their
// device ID into a new device.

function getDeviceId() {
  let id = localStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}

export function getDeviceIdPublic() {
  return getDeviceId();
}

// ---------- Local ----------

export function loadLocal() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const data = JSON.parse(raw);
    if (data.version !== STORAGE_VERSION) return migrateData(data);
    return data;
  } catch (e) {
    console.error('Failed to load local data:', e);
    return null;
  }
}

export function saveLocal(data) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...data, version: STORAGE_VERSION, lastSavedAt: new Date().toISOString() }));
  } catch (e) {
    console.error('Failed to save local data:', e);
  }
}

// ---------- Supabase ----------

export async function loadFromCloud() {
  const deviceId = getDeviceId();
  try {
    const { data, error } = await supabase
      .from(TABLE)
      .select('data')
      .eq('device_id', deviceId)
      .single();

    if (error) {
      if (error.code === 'PGRST116') return null; // no row yet, that's fine
      console.error('Supabase load error:', error);
      return null;
    }
    return data?.data ?? null;
  } catch (e) {
    console.error('Cloud load failed:', e);
    return null;
  }
}

export async function saveToCloud(appData) {
  const deviceId = getDeviceId();
  try {
    const { error } = await supabase
      .from(TABLE)
      .upsert(
        { device_id: deviceId, data: appData, updated_at: new Date().toISOString() },
        { onConflict: 'device_id' }
      );
    if (error) {
      console.error('Supabase save error:', error);
      return { ok: false, error: error.message };
    }
    return { ok: true };
  } catch (e) {
    console.error('Cloud save failed:', e);
    return { ok: false, error: e.message || 'Network error' };
  }
}

// Load from another device by ID (for linking devices)
export async function loadFromDeviceId(targetDeviceId) {
  try {
    const { data, error } = await supabase
      .from(TABLE)
      .select('data, updated_at')
      .eq('device_id', targetDeviceId)
      .single();

    if (error) return null;
    return data;
  } catch (e) {
    return null;
  }
}

// Copy another device's data into this device's cloud slot
export async function adoptDeviceData(targetDeviceId) {
  const remote = await loadFromDeviceId(targetDeviceId);
  if (!remote) return false;

  const deviceId = getDeviceId();
  const { error } = await supabase
    .from(TABLE)
    .upsert(
      { device_id: deviceId, data: remote.data, updated_at: new Date().toISOString() },
      { onConflict: 'device_id' }
    );
  if (error) return false;

  saveLocal(remote.data);
  return remote.data;
}

// ---------- Debounced cloud save ----------
let saveTimer = null;
let pendingData = null;

export function debouncedCloudSave(data, delayMs = 2000, onResult) {
  pendingData = data;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    const snapshot = pendingData;
    pendingData = null;
    const result = await saveToCloud(snapshot);
    if (onResult) onResult(result);
  }, delayMs);
}

export async function flushCloudSave() {
  if (!pendingData) return;
  clearTimeout(saveTimer);
  const snapshot = pendingData;
  pendingData = null;
  return saveToCloud(snapshot);
}

// ---------- Helpers ----------

function migrateData(data) {
  return { ...data, version: STORAGE_VERSION };
}

export function createDefaultState() {
  return {
    version: STORAGE_VERSION,
    library: [],
    currentGameId: null,
    currentSaveId: null,
  };
}

export function exportData(data) {
  return JSON.stringify(data, null, 2);
}

export function importData(jsonString) {
  try {
    return JSON.parse(jsonString);
  } catch (e) {
    console.error('Failed to parse import data:', e);
    return null;
  }
}
