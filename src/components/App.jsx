import React, { useState, useEffect, useCallback } from 'react';
import { loadData, saveData, createDefaultState } from '../utils/storage.js';
import Library from './Library.jsx';
import HadesTracker from './hades/HadesTracker.jsx';
import LoneRuinTracker from './loneruin/LoneRuinTracker.jsx';

export default function App() {
  const [data, setData] = useState(() => loadData() || createDefaultState());
  const [view, setView] = useState('library'); // 'library' | 'game'

  // Auto-save whenever data changes
  useEffect(() => {
    saveData(data);
  }, [data]);

  // Navigate to a specific game
  const openGame = useCallback((gameId) => {
    setData(prev => ({ ...prev, currentGameId: gameId }));
    setView('game');
  }, []);

  const backToLibrary = useCallback(() => {
    setView('library');
  }, []);

  // Update library-level data
  const updateData = useCallback((updater) => {
    setData(prev => {
      const next = typeof updater === 'function' ? updater(prev) : updater;
      return next;
    });
  }, []);

  // Get current game
  const currentGame = data.library.find(g => g.id === data.currentGameId);

  const handleUpdateGame = (updatedGame) => {
    updateData(prev => ({
      ...prev,
      library: prev.library.map(g =>
        g.id === updatedGame.id ? updatedGame : g
      ),
    }));
  };

  // Render the appropriate view
  if (view === 'game' && currentGame) {
    if (currentGame.trackerType === 'hades') {
      return (
        <HadesTracker
          game={currentGame}
          onBack={backToLibrary}
          onUpdateGame={handleUpdateGame}
        />
      );
    }

    if (currentGame.trackerType === 'lone-ruin') {
      return (
        <LoneRuinTracker
          game={currentGame}
          onBack={backToLibrary}
          onUpdateGame={handleUpdateGame}
        />
      );
    }

    // Default: placeholder for games without specific trackers
    return (
      <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900 p-4">
        <div className="max-w-4xl mx-auto">
          <button onClick={backToLibrary} className="btn-secondary mb-4 gap-2">
            ← Back to Library
          </button>
          <div className="card p-8 text-center">
            <h2 className="text-2xl font-bold mb-2">{currentGame.name}</h2>
            <p className="text-gray-400 mb-4">
              {currentGame.platforms.join(', ')}
            </p>
            <div className="bg-purple-900/20 rounded-lg p-6 inline-block">
              <p className="text-gray-300">
                Tracking not yet configured for this game.
              </p>
              <p className="text-gray-500 text-sm mt-2">
                Detailed tracking is available for: Hades, Lone Ruin
              </p>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <Library
      data={data}
      updateData={updateData}
      onOpenGame={openGame}
    />
  );
}
