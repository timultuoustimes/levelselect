import React, { useState, useCallback } from 'react';
import { createHadesSave } from '../../utils/factories.js';
import { ArrowLeft, Plus, ChevronDown } from 'lucide-react';
import OverviewTab from './OverviewTab.jsx';
import BuildsTab from './BuildsTab.jsx';
import AspectsTab from './AspectsTab.jsx';
import KeepsakesTab from './KeepsakesTab.jsx';
import AnalyticsTab from './AnalyticsTab.jsx';
import RunView from './RunView.jsx';

const TABS = [
  { id: 'overview', label: 'Overview' },
  { id: 'builds', label: 'Builds' },
  { id: 'aspects', label: 'Aspects' },
  { id: 'keepsakes', label: 'Keepsakes' },
  { id: 'analytics', label: 'Analytics' },
];

export default function HadesTracker({ game, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [activeRunMode, setActiveRunMode] = useState(false);
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  // Update current save
  const updateSave = useCallback((updater) => {
    if (!currentSave) return;
    onUpdateGame({
      ...game,
      saves: game.saves.map(s =>
        s.id === currentSave.id
          ? (typeof updater === 'function' ? updater(s) : { ...s, ...updater })
          : s
      ),
    });
  }, [currentSave, game, onUpdateGame]);

  // Create new save
  const handleCreateSave = () => {
    const name = newSaveName.trim() || `Save ${saves.length + 1}`;
    const save = createHadesSave(name);
    onUpdateGame({
      ...game,
      saves: [...saves, save],
      currentSaveId: save.id,
    });
    setNewSaveName('');
    setShowNewSave(false);
  };

  // Switch save
  const switchSave = (saveId) => {
    onUpdateGame({ ...game, currentSaveId: saveId });
    setShowSaveDropdown(false);
  };

  // Start new run
  const startRun = () => {
    setActiveRunMode(true);
  };

  // End run (save and return)
  const endRun = (completedRun) => {
    if (completedRun) {
      updateSave(s => ({
        ...s,
        runs: [...s.runs, completedRun],
        activeRun: null,
        lastPlayedAt: new Date().toISOString(),
      }));
    }
    setActiveRunMode(false);
  };

  // Cancel run
  const cancelRun = () => {
    updateSave(s => ({ ...s, activeRun: null }));
    setActiveRunMode(false);
  };

  // No saves yet - show welcome
  if (saves.length === 0) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-slate-900 via-purple-900/40 to-slate-900 flex items-center justify-center p-4">
        <div className="card p-8 max-w-md w-full text-center">
          <div className="text-5xl mb-4">🔥</div>
          <h1 className="text-2xl font-bold mb-2">Hades Tracker</h1>
          <p className="text-gray-400 mb-6">
            Track your escape attempts, analyze builds, and master the underworld.
          </p>
          <input
            type="text"
            placeholder="Save name (e.g., Main Playthrough)"
            value={newSaveName}
            onChange={e => setNewSaveName(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleCreateSave()}
            className="input-field mb-3"
            autoFocus
          />
          <button onClick={handleCreateSave} className="btn-primary w-full">
            Create First Save
          </button>
          <button onClick={onBack} className="btn-secondary w-full mt-2">
            ← Back to Library
          </button>
        </div>
      </div>
    );
  }

  // Active run view
  if (activeRunMode) {
    return (
      <RunView
        save={currentSave}
        onEndRun={endRun}
        onCancelRun={cancelRun}
      />
    );
  }

  // Main tracker view
  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-purple-900/30 to-slate-900 safe-area-bottom">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-slate-900/90 backdrop-blur border-b border-purple-500/20">
        <div className="max-w-7xl mx-auto px-4 py-3">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-3">
              <button onClick={onBack} className="text-gray-400 hover:text-white p-1 min-h-[44px] min-w-[44px] flex items-center justify-center">
                <ArrowLeft className="w-5 h-5" />
              </button>
              <div>
                <h1 className="text-lg font-bold flex items-center gap-2">
                  🔥 Hades
                </h1>
                {/* Save selector */}
                <div className="relative">
                  <button
                    onClick={() => setShowSaveDropdown(!showSaveDropdown)}
                    className="text-sm text-gray-400 hover:text-white flex items-center gap-1"
                  >
                    {currentSave?.name || 'Select Save'}
                    <ChevronDown className="w-3 h-3" />
                  </button>
                  {showSaveDropdown && (
                    <div className="absolute top-full left-0 mt-1 card p-1 min-w-[200px] z-20">
                      {saves.map(s => (
                        <button
                          key={s.id}
                          onClick={() => switchSave(s.id)}
                          className={`w-full text-left px-3 py-2 rounded text-sm min-h-[44px] ${
                            s.id === currentSave?.id
                              ? 'bg-purple-600 text-white'
                              : 'hover:bg-white/10 text-gray-300'
                          }`}
                        >
                          {s.name}
                          <span className="text-xs text-gray-500 ml-2">
                            ({s.runs?.length || 0} runs)
                          </span>
                        </button>
                      ))}
                      <hr className="border-purple-500/20 my-1" />
                      <button
                        onClick={() => { setShowSaveDropdown(false); setShowNewSave(true); }}
                        className="w-full text-left px-3 py-2 rounded text-sm text-purple-400 hover:bg-white/10 min-h-[44px] flex items-center gap-2"
                      >
                        <Plus className="w-4 h-4" /> New Save
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </div>

            <button onClick={startRun} className="btn-primary text-sm gap-1.5">
              🗡️ Start Run
            </button>
          </div>

          {/* Tab navigation */}
          <div className="flex gap-1 overflow-x-auto scroll-smooth-ios -mx-4 px-4">
            {TABS.map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`${
                  activeTab === tab.id ? 'tab-button-active' : 'tab-button-inactive'
                } whitespace-nowrap text-sm`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Tab Content */}
      <div className="max-w-7xl mx-auto px-4 py-4">
        {activeTab === 'overview' && (
          <OverviewTab save={currentSave} />
        )}
        {activeTab === 'builds' && (
          <BuildsTab save={currentSave} />
        )}
        {activeTab === 'aspects' && (
          <AspectsTab save={currentSave} updateSave={updateSave} />
        )}
        {activeTab === 'keepsakes' && (
          <KeepsakesTab save={currentSave} updateSave={updateSave} />
        )}
        {activeTab === 'analytics' && (
          <AnalyticsTab save={currentSave} />
        )}
      </div>

      {/* New Save Modal */}
      {showNewSave && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => setShowNewSave(false)}>
          <div className="card p-6 w-full max-w-md" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold mb-4">New Save File</h2>
            <input
              type="text"
              placeholder="Save name"
              value={newSaveName}
              onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && handleCreateSave()}
              className="input-field mb-3"
              autoFocus
            />
            <button onClick={handleCreateSave} className="btn-primary w-full">
              Create Save
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
