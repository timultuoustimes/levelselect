import React, { useState } from 'react';
import { Map, Plus, Sparkles, Loader, Trash2, X } from 'lucide-react';
import AddMapModal from './AddMapModal.jsx';
import MapViewer from './MapViewer.jsx';
import { addMapToGame, removeMapFromGame, deleteMapImage, newId } from '../../utils/mapStorage.js';

const MAP_FINDER_URL = 'https://sextftevxqrtodlmnyve.supabase.co/functions/v1/map-finder';

// ─── Thumbnail card ───────────────────────────────────────────────────────────

function MapThumb({ map, onOpen, onDelete }) {
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [imgFailed, setImgFailed] = useState(false);

  return (
    <div className="relative group rounded-xl overflow-hidden border border-white/10 bg-black/30 aspect-video cursor-pointer"
      onClick={onOpen}
    >
      {imgFailed ? (
        <div className="w-full h-full flex flex-col items-center justify-center gap-1 bg-slate-800/50">
          <Map className="w-6 h-6 text-gray-600" />
          <span className="text-[10px] text-gray-600">Image unavailable</span>
        </div>
      ) : (
        <img
          src={map.imageUrl}
          alt={map.name}
          className="w-full h-full object-cover"
          loading="lazy"
          onError={() => setImgFailed(true)}
        />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-transparent" />
      <div className="absolute bottom-0 inset-x-0 px-2 py-2">
        <div className="text-xs font-medium text-white truncate">{map.name}</div>
        <div className="text-[10px] text-gray-400 uppercase tracking-wide">
          {map.type} · {map.markers?.length || 0} markers
        </div>
      </div>

      {/* Delete button */}
      {!confirmDelete ? (
        <button
          onClick={(e) => { e.stopPropagation(); setConfirmDelete(true); }}
          className="absolute top-1.5 right-1.5 opacity-0 group-hover:opacity-100 p-1 rounded-lg bg-black/60 text-gray-400 hover:text-red-400 transition-all"
          title="Remove map"
        >
          <Trash2 className="w-3.5 h-3.5" />
        </button>
      ) : (
        <div
          className="absolute inset-0 bg-black/80 flex flex-col items-center justify-center gap-2 p-2"
          onClick={e => e.stopPropagation()}
        >
          <p className="text-xs text-white text-center">Remove this map?</p>
          <div className="flex gap-2">
            <button onClick={() => onDelete(map)} className="btn-danger !px-2 !py-1 !min-h-0 text-xs">
              Remove
            </button>
            <button onClick={() => setConfirmDelete(false)} className="btn-secondary !px-2 !py-1 !min-h-0 text-xs">
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Suggestion row with image fallback ──────────────────────────────────────

function SuggestionRow({ suggestion: s, onAdd }) {
  const [imgFailed, setImgFailed] = useState(false);
  return (
    <div className="flex items-center gap-3 p-2 rounded-lg bg-white/5 border border-white/10">
      {imgFailed ? (
        <div className="w-16 h-10 rounded bg-white/5 border border-white/10 flex items-center justify-center shrink-0">
          <Map className="w-4 h-4 text-gray-600" />
        </div>
      ) : (
        <img
          src={s.url}
          alt={s.name}
          className="w-16 h-10 object-cover rounded shrink-0"
          onError={() => setImgFailed(true)}
        />
      )}
      <div className="flex-1 min-w-0">
        <div className="text-sm text-white truncate">{s.name}</div>
        <div className="text-xs text-gray-500 truncate">
          {s.source} · {s.type}
          {imgFailed && <span className="text-yellow-600 ml-1">(preview unavailable)</span>}
        </div>
      </div>
      <button
        onClick={() => onAdd(s)}
        className="btn-primary !px-2 !py-1 !min-h-0 text-xs shrink-0"
      >
        Add
      </button>
    </div>
  );
}

// ─── Genie map finder ─────────────────────────────────────────────────────────

function GenieMapFinder({ game, onAddUrl, onDismiss }) {
  const [loading, setLoading]   = useState(false);
  const [suggestions, setSuggestions] = useState(null);
  const [error, setError]       = useState(null);
  const [pageUrl, setPageUrl]   = useState('');
  const [showUrlInput, setShowUrlInput] = useState(false);

  const handleSearch = async (url = '') => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(MAP_FINDER_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          gameName: game.name,
          igdbData: {
            genres: game.genres,
            themes: game.themes,
            developers: game.developers,
          },
          pageUrl: url || undefined,
        }),
      });
      if (!res.ok) throw new Error('Genie could not find maps right now.');
      const data = await res.json();
      setSuggestions(data.suggestions || []);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-sm text-purple-300 py-2">
        <Loader className="w-4 h-4 animate-spin" />
        Genie is searching for maps…
      </div>
    );
  }

  if (suggestions) {
    if (suggestions.length === 0) {
      return (
        <div className="text-sm text-gray-500 py-1">
          Genie couldn't find any map images. Try adding one manually.
          <button onClick={onDismiss} className="ml-2 text-gray-600 hover:text-gray-400 text-xs underline">Dismiss</button>
        </div>
      );
    }
    return (
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-xs text-gray-400">Select maps to add:</span>
          <button onClick={onDismiss} className="text-gray-600 hover:text-gray-400">
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
        {suggestions.map((s, i) => (
          <SuggestionRow key={i} suggestion={s} onAdd={onAddUrl} />
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-3 flex-wrap">
        <button
          onClick={() => handleSearch()}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-purple-900/30 border border-purple-500/30 text-purple-300 text-sm hover:bg-purple-900/50 transition-colors"
        >
          <Sparkles className="w-3.5 h-3.5" />
          Ask Genie to find maps
        </button>
        <button
          onClick={() => setShowUrlInput(v => !v)}
          className="text-xs text-gray-500 hover:text-gray-300 underline underline-offset-2 transition-colors"
        >
          or paste a maps page URL
        </button>
        {error && <span className="text-xs text-red-400">{error}</span>}
        <button onClick={onDismiss} className="text-gray-600 hover:text-gray-400 ml-auto">
          <X className="w-3.5 h-3.5" />
        </button>
      </div>
      {showUrlInput && (
        <div className="flex gap-2">
          <input
            type="url"
            placeholder="e.g. https://info.sonicretro.org/Sonic_Mania/Maps"
            value={pageUrl}
            onChange={e => setPageUrl(e.target.value)}
            className="input-field text-sm flex-1 !py-1.5"
          />
          <button
            onClick={() => handleSearch(pageUrl.trim())}
            disabled={!pageUrl.trim()}
            className="btn-primary !px-3 !py-1.5 !min-h-0 text-sm disabled:opacity-50"
          >
            Parse
          </button>
        </div>
      )}
    </div>
  );
}

// ─── MapSection ───────────────────────────────────────────────────────────────

export default function MapSection({
  game,
  deviceId,
  onUpdateGame,
  activeMapId,        // controlled from parent (desktop panel syncs with this)
  onActiveMapChange,  // (mapId | null) => void
  panelMode = false,  // true when rendered inside MapPanel (hides section header)
}) {
  const maps = game.maps || [];
  const [showAddModal, setShowAddModal]   = useState(false);
  const [showGenie, setShowGenie]         = useState(!panelMode && maps.length === 0);
  const [viewingMapId, setViewingMapId]   = useState(null); // for mobile modal

  const openMap = (mapId) => {
    if (onActiveMapChange) {
      onActiveMapChange(mapId);
    } else {
      setViewingMapId(mapId); // mobile: open modal
    }
  };

  const handleAdd = (mapDef) => {
    onUpdateGame(addMapToGame(game, mapDef));
    setShowAddModal(false);
  };

  const handleAddGenie = (suggestion) => {
    onUpdateGame(addMapToGame(game, {
      id: newId(),
      name: suggestion.name,
      type: suggestion.type,
      storageType: 'url',
      imageUrl: suggestion.url,
      storagePath: null,
      addedAt: new Date().toISOString(),
      markers: [],
    }));
  };

  const handleDelete = async (map) => {
    const { updatedGame, storagePath } = removeMapFromGame(game, map.id);
    onUpdateGame(updatedGame);
    if (storagePath) deleteMapImage(storagePath);
    if (activeMapId === map.id && onActiveMapChange) onActiveMapChange(null);
    if (viewingMapId === map.id) setViewingMapId(null);
  };

  return (
    <>
      <div className={panelMode ? '' : 'mt-6'}>
        {!panelMode && (
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Map className="w-4 h-4 text-purple-400" />
              <span className="font-semibold text-white">Maps</span>
              {maps.length > 0 && (
                <span className="text-xs text-gray-500">{maps.length}</span>
              )}
            </div>
            <button
              onClick={() => setShowAddModal(true)}
              className="flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm text-gray-300 hover:text-white transition-colors"
            >
              <Plus className="w-3.5 h-3.5" /> Add map
            </button>
          </div>
        )}

        {panelMode && (
          <div className="flex items-center justify-between px-3 py-2 border-b border-white/10">
            <span className="text-sm font-medium text-gray-300">Maps</span>
            <button
              onClick={() => setShowAddModal(true)}
              className="flex items-center gap-1 px-2 py-1 rounded-lg bg-white/10 hover:bg-white/20 text-xs text-gray-300 hover:text-white transition-colors"
            >
              <Plus className="w-3 h-3" /> Add
            </button>
          </div>
        )}

        {/* Genie finder (shown initially when no maps, can be dismissed) */}
        {showGenie && (
          <div className={`mb-3 ${panelMode ? 'px-3 py-2' : ''}`}>
            <GenieMapFinder
              game={game}
              onAddUrl={handleAddGenie}
              onDismiss={() => setShowGenie(false)}
            />
          </div>
        )}

        {maps.length === 0 && !showGenie && (
          <div className={`text-center py-6 text-gray-600 text-sm ${panelMode ? 'px-3' : ''}`}>
            <Map className="w-8 h-8 mx-auto mb-2 opacity-30" />
            <p>No maps yet.</p>
            <button
              onClick={() => setShowAddModal(true)}
              className="mt-2 text-purple-400 hover:text-purple-300 text-xs underline underline-offset-2"
            >
              Add your first map
            </button>
            <button
              onClick={() => setShowGenie(true)}
              className="mt-1 block mx-auto text-gray-600 hover:text-gray-400 text-xs"
            >
              or ask Genie to find one
            </button>
          </div>
        )}

        {maps.length > 0 && (
          <div className={`grid grid-cols-2 gap-2 ${panelMode ? 'px-3 py-2' : ''}`}>
            {maps.map(m => (
              <MapThumb
                key={m.id}
                map={m}
                onOpen={() => openMap(m.id)}
                onDelete={handleDelete}
              />
            ))}
          </div>
        )}

        {!panelMode && !showGenie && maps.length > 0 && (
          <button
            onClick={() => setShowGenie(true)}
            className="mt-2 flex items-center gap-1.5 text-xs text-gray-600 hover:text-purple-400 transition-colors"
          >
            <Sparkles className="w-3 h-3" />
            Ask Genie to find more maps
          </button>
        )}
      </div>

      {/* Mobile MapViewer modal */}
      {viewingMapId && !onActiveMapChange && (
        <MapViewer
          game={game}
          maps={maps}
          activeMapId={viewingMapId}
          onMapSwitch={setViewingMapId}
          onUpdateGame={onUpdateGame}
          mode="modal"
          onClose={() => setViewingMapId(null)}
        />
      )}

      {showAddModal && (
        <AddMapModal
          game={game}
          deviceId={deviceId}
          onAdd={handleAdd}
          onClose={() => setShowAddModal(false)}
        />
      )}
    </>
  );
}
