import React, { useState, useCallback } from 'react';
import { ArrowLeft, Plus, ChevronDown, Zap } from 'lucide-react';
import { createLoneRuinSave, createLoneRuinRun } from '../../utils/loneRuinFactory.js';
import { STARTING_SPELLS, DIFFICULTIES, MODES } from '../../data/loneRuinData.js';
import LoneRuinRunView from './LoneRuinRunView.jsx';
import LoneRuinOverview from './LoneRuinOverview.jsx';
import LoneRuinAnalytics from './LoneRuinAnalytics.jsx';

const TABS = [
  { id: 'overview', label: 'Overview' },
  { id: 'analytics', label: 'Analytics' },
];

export default function LoneRuinTracker({ game, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [activeRunMode, setActiveRunMode] = useState(false);
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  // Run setup state
  const [runSetup, setRunSetup] = useState({
    startingSpell: '',
    mode: 'Campaign',
    difficulty: 'Normal',
  });
  const [showRunSetup, setShowRunSetup] = useState(false);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  const updateSave = useCallback((updater) => {
    if (!currentSave) return;
    onUpdateGame({
      ...game,
      saves: saves.map(s =>
        s.id === currentSave.id
          ? (typeof updater === 'function' ? updater(s) : { ...s, ...updater })
          : s
      ),
    });
  }, [currentSave, game, onUpdateGame, saves]);

  const handleCreateSave = () => {
    const name = newSaveName.trim() || `Save ${saves.length + 1}`;
    const save = createLoneRuinSave(name);
    onUpdateGame({
      ...game,
      saves: [...saves, save],
      currentSaveId: save.id,
    });
    setNewSaveName('');
    setShowNewSave(false);
  };

  const switchSave = (saveId) => {
    onUpdateGame({ ...game, currentSaveId: saveId });
    setShowSaveDropdown(false);
  };

  const startRun = () => {
    if (!runSetup.startingSpell) return;
    setShowRunSetup(false);
    setActiveRunMode(true);
  };

  const endRun = (completedRun) => {
    if (completedRun) {
      updateSave(s => ({
        ...s,
        runs: [...s.runs, completedRun],
        lastPlayedAt: new Date().toISOString(),
      }));
    }
    setActiveRunMode(false);
  };

  // No saves yet
  if (saves.length === 0) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-slate-900 via-indigo-900/40 to-slate-900 flex items-center justify-center p-4">
        <div className="card p-8 max-w-md w-full text-center">
          <div className="text-5xl mb-4">🔮</div>
          <h1 className="text-2xl font-bold mb-2">Lone Ruin</h1>
          <p className="text-gray-400 mb-6">Track your spellcasting runs through the ruin.</p>
          <input
            type="text"
            placeholder="Save name (e.g., Main Run)"
            value={newSaveName}
            onChange={e => setNewSaveName(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && handleCreateSave()}
            className="input-field w-full mb-4"
          />
          <button onClick={handleCreateSave} className="btn-primary w-full">
            Begin
          </button>
          <button onClick={onBack} className="btn-secondary w-full mt-2">
            ← Back to Library
          </button>
        </div>
      </div>
    );
  }

  // Active run
  if (activeRunMode && currentSave) {
    const run = createLoneRuinRun(runSetup);
    return (
      <LoneRuinRunView
        run={run}
        onEnd={endRun}
        onCancel={() => setActiveRunMode(false)}
      />
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-indigo-900/30 to-slate-900 text-white">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-slate-900/90 backdrop-blur border-b border-purple-500/20 px-4 py-3">
        <div className="max-w-4xl mx-auto flex items-center gap-3 flex-wrap">
          <button onClick={onBack} className="btn-secondary flex items-center gap-1.5 text-sm">
            <ArrowLeft size={14} /> Library
          </button>

          <div className="flex items-center gap-2 text-xl">
            <span>🔮</span>
            <span className="font-bold">Lone Ruin</span>
          </div>

          {/* Save selector */}
          <div className="relative ml-auto">
            <button
              onClick={() => setShowSaveDropdown(p => !p)}
              className="btn-secondary flex items-center gap-2 text-sm"
            >
              {currentSave?.name || 'Select Save'}
              <ChevronDown size={14} />
            </button>
            {showSaveDropdown && (
              <div className="absolute right-0 top-full mt-1 bg-gray-900 border border-purple-500/30 rounded-lg w-48 shadow-xl z-20">
                {saves.map(s => (
                  <button
                    key={s.id}
                    onClick={() => switchSave(s.id)}
                    className={`w-full text-left px-3 py-2 text-sm hover:bg-purple-900/30 ${
                      s.id === currentSave?.id ? 'text-purple-400 font-semibold' : ''
                    }`}
                  >
                    {s.name}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* New save */}
          {showNewSave ? (
            <div className="flex gap-2">
              <input
                type="text"
                value={newSaveName}
                onChange={e => setNewSaveName(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && handleCreateSave()}
                placeholder="Save name…"
                className="input-field text-sm py-1.5 w-36"
                autoFocus
              />
              <button onClick={handleCreateSave} className="btn-primary text-sm py-1.5 px-3">Create</button>
              <button onClick={() => setShowNewSave(false)} className="btn-secondary text-sm py-1.5 px-2">✕</button>
            </div>
          ) : (
            <button onClick={() => setShowNewSave(true)} className="btn-secondary flex items-center gap-1.5 text-sm">
              <Plus size={14} /> Save
            </button>
          )}

          {/* Start run */}
          <button
            onClick={() => setShowRunSetup(p => !p)}
            className="btn-primary flex items-center gap-2"
          >
            <Zap size={16} /> New Run
          </button>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-6 space-y-4">

        {/* Run setup panel */}
        {showRunSetup && (
          <div className="card p-5 border-purple-500/50">
            <h3 className="font-bold text-purple-300 mb-4">Choose Your Starting Spell</h3>

            {/* Spell grid */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mb-4">
              {STARTING_SPELLS.map(spell => (
                <button
                  key={spell.id}
                  onClick={() => setRunSetup(p => ({ ...p, startingSpell: spell.name }))}
                  className={`rounded-lg p-3 text-left transition-all border ${
                    runSetup.startingSpell === spell.name
                      ? 'border-purple-400 bg-purple-900/50'
                      : 'border-gray-700 bg-black/30 hover:border-purple-500/50'
                  }`}
                >
                  <div className="text-2xl mb-1">{spell.icon}</div>
                  <div className="font-semibold text-sm">{spell.name}</div>
                  <div className="text-xs text-gray-500 capitalize mt-0.5">{spell.type}</div>
                </button>
              ))}
            </div>

            {/* Mode + Difficulty */}
            <div className="grid grid-cols-2 gap-3 mb-4">
              <div>
                <label className="text-gray-400 text-xs block mb-1">Mode</label>
                <div className="flex gap-2">
                  {MODES.map(m => (
                    <button
                      key={m}
                      onClick={() => setRunSetup(p => ({ ...p, mode: m }))}
                      className={`flex-1 py-2 rounded-lg text-sm font-medium transition-colors ${
                        runSetup.mode === m
                          ? 'bg-purple-600 text-white'
                          : 'bg-black/30 text-gray-400 hover:bg-purple-900/30'
                      }`}
                    >
                      {m}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className="text-gray-400 text-xs block mb-1">Difficulty</label>
                <div className="flex gap-2">
                  {DIFFICULTIES.map(d => (
                    <button
                      key={d}
                      onClick={() => setRunSetup(p => ({ ...p, difficulty: d }))}
                      className={`flex-1 py-2 rounded-lg text-sm font-medium transition-colors ${
                        runSetup.difficulty === d
                          ? 'bg-indigo-600 text-white'
                          : 'bg-black/30 text-gray-400 hover:bg-indigo-900/30'
                      }`}
                    >
                      {d}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            <div className="flex gap-3">
              <button
                onClick={startRun}
                disabled={!runSetup.startingSpell}
                className="btn-primary flex-1 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {runSetup.startingSpell
                  ? `Enter the Ruin with ${runSetup.startingSpell}`
                  : 'Select a spell to begin'}
              </button>
              <button onClick={() => setShowRunSetup(false)} className="btn-secondary">
                Cancel
              </button>
            </div>
          </div>
        )}

        {/* Tab nav */}
        <div className="flex gap-1 border-b border-purple-500/20 pb-0">
          {TABS.map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-2 text-sm font-medium rounded-t-lg transition-colors ${
                activeTab === tab.id
                  ? 'bg-purple-900/50 text-purple-200 border-b-2 border-purple-400'
                  : 'text-gray-400 hover:text-gray-200'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Tab content */}
        {currentSave && (
          <>
            {activeTab === 'overview' && <LoneRuinOverview save={currentSave} />}
            {activeTab === 'analytics' && <LoneRuinAnalytics save={currentSave} />}
          </>
        )}
      </div>
    </div>
  );
}
