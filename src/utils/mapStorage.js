import { supabase } from './supabase.js';

const BUCKET = 'map-images';

// ─── Storage helpers ──────────────────────────────────────────────────────────

export async function uploadMapImage(deviceId, gameId, mapId, file) {
  const ext = file.name.split('.').pop() || 'jpg';
  const path = `${deviceId}/${gameId}/${mapId}.${ext}`;

  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { upsert: true, contentType: file.type });

  if (error) throw new Error(`Upload failed: ${error.message}`);

  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
  return { url: data.publicUrl, storagePath: path };
}

export async function deleteMapImage(storagePath) {
  if (!storagePath) return;
  await supabase.storage.from(BUCKET).remove([storagePath]);
}

// ─── Game map CRUD (returns updated game object) ──────────────────────────────

export function getLinkedMap(game, categoryId) {
  if (!categoryId || !game?.maps) return null;
  return game.maps.find(m => m.linkedCategoryId === categoryId) || null;
}

export function addMapToGame(game, mapDef) {
  const maps = [...(game.maps || []), mapDef];
  return { ...game, maps };
}

export function updateMapInGame(game, mapId, changes) {
  const maps = (game.maps || []).map(m => m.id === mapId ? { ...m, ...changes } : m);
  return { ...game, maps };
}

export function removeMapFromGame(game, mapId) {
  const map = (game.maps || []).find(m => m.id === mapId);
  const maps = (game.maps || []).filter(m => m.id !== mapId);
  return { updatedGame: { ...game, maps }, storagePath: map?.storagePath || null };
}

export function addMarker(game, mapId, marker) {
  const maps = (game.maps || []).map(m =>
    m.id === mapId
      ? { ...m, markers: [...(m.markers || []), marker] }
      : m
  );
  return { ...game, maps };
}

export function updateMarker(game, mapId, markerId, changes) {
  const maps = (game.maps || []).map(m =>
    m.id === mapId
      ? { ...m, markers: (m.markers || []).map(mk => mk.id === markerId ? { ...mk, ...changes } : mk) }
      : m
  );
  return { ...game, maps };
}

export function removeMarker(game, mapId, markerId) {
  const maps = (game.maps || []).map(m =>
    m.id === mapId
      ? { ...m, markers: (m.markers || []).filter(mk => mk.id !== markerId) }
      : m
  );
  return { ...game, maps };
}

// ─── ID generator ─────────────────────────────────────────────────────────────

export function newId() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

// ─── Image URL upgrader ───────────────────────────────────────────────────────

export function upgradeImageUrl(url) {
  if (!url) return url;
  // Fandom/Wikia CDN: strip thumbnail scale limit to load full-res
  if (url.includes('static.wikia.nocookie.net') || url.includes('vignette.wikia.nocookie.net')) {
    return url.replace(/\/scale-to-width-down\/\d+/, '/scale-to-width-down/4096');
  }
  // Wikimedia: strip /thumb/ path to get original file
  if (url.includes('upload.wikimedia.org') && url.includes('/thumb/')) {
    const m = url.match(/upload\.wikimedia\.org\/(wikipedia\/[^/]+)\/thumb\/([^?]+?)\/[^/?]+(\?.*)?$/);
    if (m) return `https://upload.wikimedia.org/${m[1]}/${m[2]}`;
  }
  return url;
}
