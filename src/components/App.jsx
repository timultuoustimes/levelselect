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
import Library from './Library.jsx';
import HadesTracker from './hades/HadesTracker.jsx';
import LoneRuinTracker from './loneruin/LoneRuinTracker.jsx';
import GenericRoguelikeTracker from './gonner/GenericRoguelikeTracker.jsx';
import ChecklistTracker from './checklist/ChecklistTracker.jsx';
import CitizenSleeperTracker from './citizensleeper/CitizenSleeperTracker.jsx';
import MessengerTracker from './messenger/MessengerTracker.jsx';
import { GONNERS_CONFIG, CURSED_TO_GOLF_CONFIG } from '../data/genericRoguelikeData.js';
import { BLAZING_CHROME_CONFIG, SAYONARA_CONFIG, CAST_N_CHILL_CONFIG } from '../data/checklistGameData.js';

export default function App() {
  const [data, setData] = useState(null); // null = still loading
  const [view, setView] = useState('library');
  const [syncStatus, setSyncStatus] = useState('loading'); // 'loading' | 'synced' | 'saving' | 'offline'
  const [showSyncPanel, setShowSyncPanel] = useState(false);
  const [linkInput, setLinkInput] = useState('');
  const [linkStatus, setLinkStatus] = useState(null); // null | 'loading' | 'success' | 'error'
  const isFirstLoad = useRef(true);

  // On mount: load local immediately, then try cloud
  useEffect(() => {
    async function init() {
      const local = loadLocal() || createDefaultState();
      setData(local);
      setSyncStatus('loading');

      const cloud = await loadFromCloud();
      if (cloud) {
        setData(cloud);
        saveLocal(cloud);
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

  const openGame = useCallback((gameId) => {
    setData(prev => prev ? { ...prev, currentGameId: gameId } : prev);
    setView('game');
  }, []);

  const backToLibrary = useCallback(() => setView('library'), []);

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

  if (view === 'game' && currentGame) {
    // ── Hades ────────────────────────────────────────────────────────────────
    if (currentGame.trackerType === 'hades') {
      return (
        <>
          <HadesTracker game={currentGame} onBack={backToLibrary} onUpdateGame={handleUpdateGame} />
          <SyncBar />
        </>
      );
    }

    // ── Lone Ruin ─────────────────────────────────────────────────────────────
    if (currentGame.trackerType === 'lone-ruin') {
      return (
        <>
          <LoneRuinTracker game={currentGame} onBack={backToLibrary} onUpdateGame={handleUpdateGame} />
          <SyncBar />
        </>
      );
    }

    // ── GONNER ────────────────────────────────────────────────────────────────
    if (currentGame.trackerType === 'gonner') {
      return (
        <>
          <GenericRoguelikeTracker
            game={currentGame}
            config={GONNERS_CONFIG}
            onBack={backToLibrary}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Cursed to Golf ────────────────────────────────────────────────────────
    if (currentGame.trackerType === 'cursed-to-golf') {
      return (
        <>
          <GenericRoguelikeTracker
            game={currentGame}
            config={CURSED_TO_GOLF_CONFIG}
            onBack={backToLibrary}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Blazing Chrome ────────────────────────────────────────────────────────
    if (currentGame.trackerType === 'blazing-chrome') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={BLAZING_CHROME_CONFIG}
            onBack={backToLibrary}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Sayonara Wild Hearts ──────────────────────────────────────────────────
    if (currentGame.trackerType === 'sayonara-wild-hearts') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={SAYONARA_CONFIG}
            onBack={backToLibrary}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Cast n Chill ──────────────────────────────────────────────────────────
    if (currentGame.trackerType === 'cast-n-chill') {
      return (
        <>
          <ChecklistTracker
            game={currentGame}
            config={CAST_N_CHILL_CONFIG}
            onBack={backToLibrary}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Citizen Sleeper ───────────────────────────────────────────────────────
    if (currentGame.trackerType === 'citizen-sleeper') {
      return (
        <>
          <CitizenSleeperTracker
            game={currentGame}
            onBack={backToLibrary}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── The Messenger ─────────────────────────────────────────────────────────
    if (currentGame.trackerType === 'messenger') {
      return (
        <>
          <MessengerTracker
            game={currentGame}
            onBack={backToLibrary}
            onUpdateGame={handleUpdateGame}
          />
          <SyncBar />
        </>
      );
    }

    // ── Fallback: no tracker configured ──────────────────────────────────────
    return (
      <>
        <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900 p-4">
          <div className="max-w-4xl mx-auto">
            <button onClick={backToLibrary} className="btn-secondary mb-4 gap-2">
              ← Back to Library
            </button>
            <div className="card p-8 text-center">
              <h2 className="text-2xl font-bold mb-2">{currentGame.name}</h2>
              <p className="text-gray-400 mb-4">{currentGame.platforms?.join(', ')}</p>
              <div className="bg-purple-900/20 rounded-lg p-6 inline-block">
                <p className="text-gray-300">Tracking not yet configured for this game.</p>
                <p className="text-gray-500 text-sm mt-2">
                  Detailed tracking available for: Hades, Lone Ruin, GONNER, Cursed to Golf,
                  Blazing Chrome, Sayonara Wild Hearts, Cast n Chill, Citizen Sleeper, The Messenger
                </p>
              </div>
            </div>
          </div>
        </div>
        <SyncBar />
      </>
    );
  }

  return (
    <>
      <Library data={data} updateData={updateData} onOpenGame={openGame} />
      <SyncBar />
    </>
  );
}
