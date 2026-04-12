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
import HadesTracker from './hades/HadesTracker.jsx';
import LoneRuinTracker from './loneruin/LoneRuinTracker.jsx';
import GenericRoguelikeTracker from './gonner/GenericRoguelikeTracker.jsx';
import ChecklistTracker from './checklist/ChecklistTracker.jsx';
import CitizenSleeperTracker from './citizensleeper/CitizenSleeperTracker.jsx';
import MessengerTracker from './messenger/MessengerTracker.jsx';
import GeneralGameTracker from './general/GeneralGameTracker.jsx';
import StructuredTracker from './structured/StructuredTracker.jsx';
import { GONNERS_CONFIG, CURSED_TO_GOLF_CONFIG } from '../data/genericRoguelikeData.js';
import { BLAZING_CHROME_CONFIG, SAYONARA_CONFIG, CAST_N_CHILL_CONFIG, HITMAN_CONFIG, UNDER_THE_ISLAND_CONFIG } from '../data/checklistGameData.js';
import { HOLLOW_KNIGHT_CONFIG } from '../data/hollowKnightData.js';

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
    <div className="fixed bottom-4 right-4 z-50 flex flex-col items-end gap-2">
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
          navSource={navSource}
          onBack={backToLibrary}
          onGoHome={goToHome}
          onGoLibrary={goToLibrary}
          onOpenTracker={openTracker}
          onUpdateGame={handleUpdateGame}
          onOpenGame={openGame}
        />
        <SyncBar />
      </>
    );
  }

  if (view === 'game' && currentGame) {
    // IGDB ID → trackerType fallback (catches games added before name mapping existed)
    const IGDB_TRACKER_IDS = { 151501: 'under-the-island', 338082: 'hitman' };
    const trackerType = currentGame.trackerType || IGDB_TRACKER_IDS[currentGame.igdbId] || null;

    // ── Hades ────────────────────────────────────────────────────────────────
    if (trackerType === 'hades') {
      return (
        <>
          <HadesTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />
          <SyncBar />
        </>
      );
    }

    // ── Lone Ruin ─────────────────────────────────────────────────────────────
    if (trackerType === 'lone-ruin') {
      return (
        <>
          <LoneRuinTracker game={currentGame} onBack={backToGamePage} onUpdateGame={handleUpdateGame} />
          <SyncBar />
        </>
      );
    }

    // ── GONNER ────────────────────────────────────────────────────────────────
    if (trackerType === 'gonner') {
      return (
        <>
          <GenericRoguelikeTracker
            game={currentGame}
            config={GONNERS_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Cursed to Golf ────────────────────────────────────────────────────────
    if (trackerType === 'cursed-to-golf') {
      return (
        <>
          <GenericRoguelikeTracker
            game={currentGame}
            config={CURSED_TO_GOLF_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Blazing Chrome ────────────────────────────────────────────────────────
    if (trackerType === 'blazing-chrome') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={BLAZING_CHROME_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Sayonara Wild Hearts ──────────────────────────────────────────────────
    if (trackerType === 'sayonara-wild-hearts') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={SAYONARA_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Cast n Chill ──────────────────────────────────────────────────────────
    if (trackerType === 'cast-n-chill') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={CAST_N_CHILL_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Hitman: World of Assassination ───────────────────────────────────────
    if (trackerType === 'hitman') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={HITMAN_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Under the Island ─────────────────────────────────────────────────────
    if (trackerType === 'under-the-island') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={UNDER_THE_ISLAND_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Citizen Sleeper ───────────────────────────────────────────────────────
    if (trackerType === 'citizen-sleeper') {
      return (
        <>
          <CitizenSleeperTracker
            game={currentGame}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Hollow Knight (StructuredTracker / generic, config-driven) ───────────
    if (trackerType === 'hollow-knight') {
      return (
        <>
          <StructuredTracker
            game={currentGame}
            config={HOLLOW_KNIGHT_CONFIG}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── AI-generated structured tracker (game carries its own schema) ────────
    if (currentGame.structuredData) {
      return (
        <>
          <StructuredTracker
            game={currentGame}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── The Messenger ─────────────────────────────────────────────────────────
    if (trackerType === 'messenger') {
      return (
        <>
          <MessengerTracker
            game={currentGame}
            onBack={backToGamePage}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── General tracker (fallback for all other games) ────────────────────────
    return (
      <>
        <GeneralGameTracker
          game={currentGame}
          onBack={backToGamePage}
          onUpdateGame={handleUpdateGame}
        />
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
