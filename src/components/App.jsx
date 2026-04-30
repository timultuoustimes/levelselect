import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  loadLocal,
  saveLocal,
  loadFromCloud,
  debouncedCloudSave,
  createDefaultState,
  getDeviceIdPublic,
  adoptDeviceData,
  exportData,
  importData,
} from '../utils/storage.js';
import Library, { TRACKER_TYPES } from './Library.jsx';
import GamePage from './GamePage.jsx';
import MapPanel from './maps/MapPanel.jsx';
import HadesTracker from './hades/HadesTracker.jsx';
import LoneRuinTracker from './loneruin/LoneRuinTracker.jsx';
import GenericRoguelikeTracker from './gonner/GenericRoguelikeTracker.jsx';
import ChecklistTracker from './checklist/ChecklistTracker.jsx';
import CitizenSleeperTracker from './citizensleeper/CitizenSleeperTracker.jsx';
import DeadCellsTracker from './deadcells/DeadCellsTracker.jsx';
import MessengerTracker from './messenger/MessengerTracker.jsx';
import GeneralGameTracker from './general/GeneralGameTracker.jsx';
import StructuredTracker from './structured/StructuredTracker.jsx';
import { GONNERS_CONFIG, CURSED_TO_GOLF_CONFIG } from '../data/genericRoguelikeData.js';
import { BLAZING_CHROME_CONFIG, SAYONARA_CONFIG, CAST_N_CHILL_CONFIG, HITMAN_CONFIG, UNDER_THE_ISLAND_CONFIG } from '../data/checklistGameData.js';
import { HOLLOW_KNIGHT_CONFIG } from '../data/hollowKnightData.js';

// ─── Tracker layout with optional map panel (desktop) ────────────────────────

function TrackerWithMaps({ game, deviceId, onUpdateGame, children }) {
  const [activeMapId, setActiveMapId] = useState(null);
  const [panelWidth, setPanelWidth]   = useState(() => {
    return parseInt(localStorage.getItem('mapPanelWidth') || '384', 10);
  });
  const isResizing = useRef(false);
  const startX     = useRef(0);
  const startWidth = useRef(0);
  const hasMaps    = (game.maps || []).length > 0;

  const beginResize = useCallback((clientX) => {
    isResizing.current = true;
    startX.current     = clientX;
    startWidth.current = panelWidth;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [panelWidth]);

  const onDragStart      = useCallback((e) => beginResize(e.clientX), [beginResize]);
  const onTouchDragStart = useCallback((e) => beginResize(e.touches[0].clientX), [beginResize]);

  useEffect(() => {
    const onMove = (clientX) => {
      if (!isResizing.current) return;
      const delta = startX.current - clientX; // dragging left = wider
      const next  = Math.max(280, Math.min(800, startWidth.current + delta));
      setPanelWidth(next);
    };
    const onEnd = () => {
      if (!isResizing.current) return;
      isResizing.current = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      setPanelWidth(w => { localStorage.setItem('mapPanelWidth', String(w)); return w; });
    };
    const onMouseMove = (e) => onMove(e.clientX);
    const onTouchMove = (e) => { e.preventDefault(); onMove(e.touches[0].clientX); };

    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onEnd);
    document.addEventListener('touchmove', onTouchMove, { passive: false });
    document.addEventListener('touchend', onEnd);
    return () => {
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onEnd);
      document.removeEventListener('touchmove', onTouchMove);
      document.removeEventListener('touchend', onEnd);
    };
  }, []);

  if (!hasMaps) return children;

  return (
    <div className="lg:flex lg:h-screen lg:overflow-hidden">
      <div className="lg:flex-1 lg:overflow-y-auto min-w-0">
        {children}
      </div>
      {/* Drag handle */}
      <div
        className="hidden lg:flex items-center justify-center w-1.5 shrink-0 cursor-col-resize hover:bg-purple-500/30 bg-white/5 transition-colors group"
        onMouseDown={onDragStart}
        onTouchStart={onTouchDragStart}
      >
        <div className="w-0.5 h-8 rounded-full bg-white/20 group-hover:bg-purple-400/60 transition-colors" />
      </div>
      {/* Map panel */}
      <div
        className="hidden lg:flex lg:flex-col lg:h-screen shrink-0 border-l border-white/10 bg-slate-950"
        style={{ width: panelWidth }}
      >
        <MapPanel
          game={game}
          deviceId={deviceId}
          activeMapId={activeMapId}
          onActiveMapChange={setActiveMapId}
          onUpdateGame={onUpdateGame}
        />
      </div>
    </div>
  );
}

export default function App() {
  const [data, setData] = useState(null); // null = still loading
  const [view, setView] = useState('library');
  const [libraryView, setLibraryView] = useState('home'); // 'home' | 'games' | 'stats'
  const [navSource, setNavSource] = useState('library'); // 'home' | 'library'
  const [syncStatus, setSyncStatus] = useState('loading'); // 'loading' | 'synced' | 'saving' | 'offline'
  const [showSyncPanel, setShowSyncPanel] = useState(false);
  const [linkInput, setLinkInput] = useState('');
  const [linkStatus, setLinkStatus] = useState(null); // null | 'loading' | 'success' | 'error'
  const isFirstLoad = useRef(true);

  // On mount: load local immediately, then try cloud
  useEffect(() => {
    async function init() {
      const raw = loadLocal() || createDefaultState();
      // Backfill trackerType for any game whose name is now recognised but was added before the mapping existed
      const local = {
        ...raw,
        games: (raw.games || []).map(g =>
          g.trackerType == null && TRACKER_TYPES[g.name]
            ? { ...g, trackerType: TRACKER_TYPES[g.name] }
            : g
        ),
      };
      setData(local);
      setSyncStatus('loading');

      const cloud = await loadFromCloud();
      if (cloud) {
        // Only adopt cloud data if it's newer than local — prevents clobbering
        // fresh local writes (e.g. timer data) before the debounce fires
        const localTime = local?.lastSavedAt ? new Date(local.lastSavedAt).getTime() : 0;
        const cloudTime = cloud?.lastSavedAt ? new Date(cloud.lastSavedAt).getTime() : 0;
        if (cloudTime > localTime) {
          // Apply the same trackerType backfill to cloud data before adopting it
          const migratedCloud = {
            ...cloud,
            games: (cloud.games || []).map(g =>
              g.trackerType == null && TRACKER_TYPES[g.name]
                ? { ...g, trackerType: TRACKER_TYPES[g.name] }
                : g
            ),
          };
          setData(migratedCloud);
          saveLocal(migratedCloud);
        }
        setSyncStatus('synced');
      } else {
        setSyncStatus('synced');
      }
      isFirstLoad.current = false;
    }
    init();
  }, []);

  // Auto-save: local immediately, cloud debounced
  useEffect(() => {
    if (data === null || isFirstLoad.current) return;
    saveLocal(data);
    setSyncStatus('saving');
    debouncedCloudSave(data, 2000);
    const timer = setTimeout(() => setSyncStatus('synced'), 2500);
    return () => clearTimeout(timer);
  }, [data]);

  const updateData = useCallback((updater) => {
    setData(prev => {
      if (!prev) return prev;
      return typeof updater === 'function' ? updater(prev) : updater;
    });
  }, []);

  const openGame = useCallback((gameId, source = 'library') => {
    setNavSource(source);
    setData(prev => prev ? { ...prev, currentGameId: gameId } : prev);
    setView('game-page');
  }, []);

  const openTracker = useCallback(() => setView('game'), []);

  const backToLibrary = useCallback(() => setView('library'), []);
  const backToGamePage = useCallback(() => setView('game-page'), []);

  // Navigate to Library home tab from anywhere (e.g. from GamePage)
  const goToHome = useCallback(() => {
    setLibraryView('home');
    setView('library');
  }, []);

  // Navigate to Library games list from anywhere (e.g. from GamePage)
  const goToLibrary = useCallback(() => {
    setLibraryView('games');
    setView('library');
  }, []);

  const handleUpdateGame = useCallback((updatedGame) => {
    updateData(prev => ({
      ...prev,
      library: prev.library.map(g => g.id === updatedGame.id ? updatedGame : g),
    }));
  }, [updateData]);

  const handleDeleteGame = useCallback((gameId) => {
    updateData(prev => ({
      ...prev,
      library: prev.library.filter(g => g.id !== gameId),
      currentGameId: prev.currentGameId === gameId ? null : prev.currentGameId,
    }));
    setView('library');
  }, [updateData]);

  // Link to another device's data
  const handleLink = async () => {
    const targetId = linkInput.trim();
    if (!targetId) return;
    setLinkStatus('loading');
    const result = await adoptDeviceData(targetId);
    if (result) {
      setData(result);
      setLinkStatus('success');
      setLinkInput('');
      setTimeout(() => { setLinkStatus(null); setShowSyncPanel(false); }, 1500);
    } else {
      setLinkStatus('error');
    }
  };

  const handleExport = () => {
    if (!data) return;
    const json = exportData(data);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'game-tracker-backup.json';
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleImport = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      const imported = importData(ev.target.result);
      if (imported) {
        setData(imported);
        saveLocal(imported);
      }
    };
    reader.readAsText(file);
  };

  // Loading screen
  if (data === null) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-slate-900 via-purple-900/30 to-slate-900 flex items-center justify-center">
        <div className="text-center">
          <div className="text-5xl mb-4 animate-pulse">🎮</div>
          <div className="text-gray-400">Loading your game data…</div>
        </div>
      </div>
    );
  }

  const currentGame = data.library.find(g => g.id === data.currentGameId);

  const SyncBar = () => (
    <div className="fixed right-4 z-50 flex flex-col items-end gap-2" style={{ bottom: 'max(1rem, env(safe-area-inset-bottom))' }}>
      {showSyncPanel && (
        <div className="card p-4 w-80 shadow-2xl border border-purple-500/30 text-sm space-y-4">
          <div className="font-bold text-purple-300">Sync & Devices</div>

          <div>
            <div className="text-gray-400 text-xs mb-1">Your Device ID</div>
            <div className="bg-black/40 rounded px-2 py-1.5 font-mono text-xs text-gray-300 break-all select-all cursor-text">
              {getDeviceIdPublic()}
            </div>
            <div className="text-gray-500 text-xs mt-1">
              On your other device, open the sync panel and paste this ID to pull your data over.
            </div>
          </div>

          <div>
            <div className="text-gray-400 text-xs mb-1">Sync from Another Device</div>
            <input
              type="text"
              value={linkInput}
              onChange={e => { setLinkInput(e.target.value); setLinkStatus(null); }}
              placeholder="Paste device ID here…"
              className="input-field w-full text-xs mb-2"
            />
            <button
              onClick={handleLink}
              disabled={linkStatus === 'loading' || !linkInput.trim()}
              className="btn-primary w-full text-sm disabled:opacity-50"
            >
              {linkStatus === 'loading' ? 'Loading…'
                : linkStatus === 'success' ? '✓ Data synced!'
                : linkStatus === 'error' ? '✗ Device ID not found'
                : 'Pull data from that device'}
            </button>
          </div>

          <div>
            <div className="text-gray-400 text-xs mb-2">Manual Backup</div>
            <div className="flex gap-2">
              <button onClick={handleExport} className="btn-secondary flex-1 text-xs">
                ↓ Export JSON
              </button>
              <label className="btn-secondary flex-1 text-xs text-center cursor-pointer">
                ↑ Import JSON
                <input type="file" accept=".json" onChange={handleImport} className="hidden" />
              </label>
            </div>
          </div>

          <button
            onClick={() => setShowSyncPanel(false)}
            className="text-gray-500 text-xs w-full text-center hover:text-gray-300 pt-1"
          >
            Close
          </button>
        </div>
      )}

      <button
        onClick={() => setShowSyncPanel(p => !p)}
        className={`px-3 py-1.5 rounded-full text-xs font-medium flex items-center gap-1.5 shadow-lg transition-all ${
          syncStatus === 'synced'  ? 'bg-green-900/80 text-green-300 border border-green-700/50'
          : syncStatus === 'saving'  ? 'bg-yellow-900/80 text-yellow-300 border border-yellow-700/50'
          : syncStatus === 'loading' ? 'bg-blue-900/80 text-blue-300 border border-blue-700/50'
          : 'bg-red-900/80 text-red-300 border border-red-700/50'
        }`}
      >
        <span className={syncStatus === 'saving' || syncStatus === 'loading' ? 'animate-pulse' : ''}>
          {syncStatus === 'synced' ? '☁️' : syncStatus === 'saving' ? '⏳' : syncStatus === 'loading' ? '🔄' : '⚠️'}
        </span>
        {syncStatus === 'synced' ? 'Synced'
          : syncStatus === 'saving' ? 'Saving…'
          : syncStatus === 'loading' ? 'Syncing…'
          : 'Offline'}
      </button>
    </div>
  );

  // ── Game Landing Page ────────────────────────────────────────────────────────
  if (view === 'game-page' && currentGame) {
    return (
      <>
        <GamePage
          game={currentGame}
          library={data.library}
          deviceId={getDeviceIdPublic()}
          navSource={navSource}
          onBack={backToLibrary}
          onGoHome={goToHome}
          onGoLibrary={goToLibrary}
          onOpenTracker={openTracker}
          onUpdateGame={handleUpdateGame}
          onDeleteGame={handleDeleteGame}
          onOpenGame={openGame}
        />
        <SyncBar />
      </>
    );
  }

  if (view === 'game' && currentGame) {
    // IGDB ID → trackerType fallback (catches games added before name mapping existed)
    const IGDB_TRACKER_IDS = { 151501: 'under-the-island', 338082: 'hitman', 26192: 'dead-cells' };
    const trackerType = currentGame.trackerType || IGDB_TRACKER_IDS[currentGame.igdbId] || null;

    let trackerEl;

    // ── Hades ────────────────────────────────────────────────────────────────
    if (trackerType === 'hades') {
      trackerEl = <HadesTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />;

    // ── Lone Ruin ─────────────────────────────────────────────────────────────
    } else if (trackerType === 'lone-ruin') {
      trackerEl = <LoneRuinTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />;

    // ── GONNER ────────────────────────────────────────────────────────────────
    } else if (trackerType === 'gonner') {
      trackerEl = (
        <GenericRoguelikeTracker
          game={currentGame}
          config={GONNERS_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── Cursed to Golf ────────────────────────────────────────────────────────
    } else if (trackerType === 'cursed-to-golf') {
      trackerEl = (
        <GenericRoguelikeTracker
          game={currentGame}
          config={CURSED_TO_GOLF_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── Blazing Chrome ────────────────────────────────────────────────────────
    } else if (trackerType === 'blazing-chrome') {
      trackerEl = (
        <ChecklistTracker
          game={currentGame}
          config={BLAZING_CHROME_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── Sayonara Wild Hearts ──────────────────────────────────────────────────
    } else if (trackerType === 'sayonara-wild-hearts') {
      trackerEl = (
        <ChecklistTracker
          game={currentGame}
          config={SAYONARA_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── Cast n Chill ──────────────────────────────────────────────────────────
    } else if (trackerType === 'cast-n-chill') {
      trackerEl = (
        <ChecklistTracker
          game={currentGame}
          config={CAST_N_CHILL_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── Hitman: World of Assassination ───────────────────────────────────────
    } else if (trackerType === 'hitman') {
      trackerEl = (
        <ChecklistTracker
          game={currentGame}
          config={HITMAN_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── Under the Island ─────────────────────────────────────────────────────
    } else if (trackerType === 'under-the-island') {
      trackerEl = (
        <ChecklistTracker
          game={currentGame}
          config={UNDER_THE_ISLAND_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── Dead Cells ────────────────────────────────────────────────────────────
    } else if (trackerType === 'dead-cells') {
      trackerEl = <DeadCellsTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />;

    // ── Citizen Sleeper ───────────────────────────────────────────────────────
    } else if (trackerType === 'citizen-sleeper') {
      trackerEl = <CitizenSleeperTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />;

    // ── Hollow Knight (StructuredTracker / generic, config-driven) ───────────
    } else if (trackerType === 'hollow-knight') {
      trackerEl = (
        <StructuredTracker
          game={currentGame}
          config={HOLLOW_KNIGHT_CONFIG}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
      );

    // ── AI-generated structured tracker (game carries its own schema) ────────
    } else if (currentGame.structuredData) {
      trackerEl = <StructuredTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />;

    // ── The Messenger ─────────────────────────────────────────────────────────
    } else if (trackerType === 'messenger') {
      trackerEl = <MessengerTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />;

    // ── General tracker (fallback for all other games) ────────────────────────
    } else {
      trackerEl = <GeneralGameTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />;
    }

    return (
      <>
        <TrackerWithMaps key={currentGame.id} game={currentGame} deviceId={getDeviceIdPublic()} onUpdateGame={handleUpdateGame}>
          {trackerEl}
        </TrackerWithMaps>
        <SyncBar />
      </>
    );
  }

  return (
    <>
      <Library
        data={data}
        updateData={updateData}
        onOpenGame={openGame}
        libraryView={libraryView}
        setLibraryView={setLibraryView}
      />
      <SyncBar />
    </>
  );
}
