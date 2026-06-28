import React, { useState, useCallback } from 'react';
import { createHadesSave, migrateSave } from '../../utils/factories.js';
import { ArrowLeft, Plus, ChevronDown } from 'lucide-react';
import RunsTab from './RunsTab.jsx';
import ProgressTab from './ProgressTab.jsx';
import RunView from './RunView.jsx';
import SessionPanel from '../shared/SessionPanel.jsx';

const TABS = [
  { id: 'runs',     label: 'Runs' },
  { id: 'progress', label: 'Progress' },
];

export default function HadesTracker({ game, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('runs');
  const [activeRunMode, setActiveRunMode] = useState(false);
  const [resumingRun, setResumingRun] = useState(null); // run object to resume, or null
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  const saves = (game.saves || []).map(migrateSave);
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
    const save = createHadesSave(name);
    onUpdateGame({ ...game, saves: [...saves, save], currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  const switchSave = (saveId) => {
    onUpdateGame({ ...game, currentSaveId: saveId });
    setShowSaveDropdown(false);
  };

  // Persist activeRun immediately so crashes don't lose the run
  const handleStartRun = (run) => {
    updateSave(s => ({ ...s, activeRun: run }));
  };

  const startRun = () => {
    setResumingRun(null);
    setActiveRunMode(true);
  };

  const resumeRun = () => {
    setResumingRun(currentSave.activeRun);
    setActiveRunMode(true);
  };

  const discardActiveRun = () => {
    updateSave(s => ({ ...s, activeRun: null }));
  };

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
    setResumingRun(null);
  };

  const cancelRun = () => {
    updateSave(s => ({ ...s, activeRun: null }));
    setActiveRunMode(false);
    setResumingRun(null);
  };

  // Playtime: runs + general sessions
  const runTime = (currentSave?.runs || []).reduce((sum, r) => sum + (r.duration || 0), 0);
  const sessionTime = (currentSave?.sessions || []).reduce((sum, s) => sum + (s.duration || 0), 0);
  const totalPlaytime = runTime + sessionTime;

  // Welcome screen (no saves yet)
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
        onStartRun={handleStartRun}
        initialRun={resumingRun}
      />
    );
  }

  // Main tracker
  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-purple-900/30 to-slate-900 safe-area-bottom">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-slate-900/90 backdrop-blur border-b border-purple-500/20 safe-area-top">
        <div className="max-w-7xl mx-auto px-4 py-3">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-3">
              <button onClick={onBack} className="text-gray-400 hover:text-white p-1 min-h-[44px] min-w-[44px] flex items-center justify-center">
                <ArrowLeft className="w-5 h-5" />
              </button>
              <div>
                <h1 className="text-lg font-bold">🔥 Hades</h1>
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
                        <button key={s.id} onClick={() => switchSave(s.id)}
                          className={`w-full text-left px-3 py-2 rounded text-sm min-h-[44px] ${
                            s.id === currentSave?.id ? 'bg-purple-600 text-white' : 'hover:bg-white/10 text-gray-300'
                          }`}
                        >
                          {s.name}
                          <span className="text-xs text-gray-500 ml-2">({s.runs?.length || 0} runs)</span>
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

          {/* Tabs */}
          <div className="flex gap-1 overflow-x-auto scroll-smooth-ios -mx-4 px-4">
            {TABS.map(tab => (
              <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                className={`${activeTab === tab.id ? 'tab-button-active' : 'tab-button-inactive'} whitespace-nowrap text-sm`}
              >
                {tab.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Resume banner */}
      {currentSave?.activeRun && (
        <div className="max-w-7xl mx-auto px-4 pt-3">
          <div className="flex items-center justify-between gap-3 px-4 py-3 bg-amber-900/20 border border-amber-500/30 rounded-xl text-sm">
            <span className="text-amber-300">⚡ You have a run in progress</span>
            <div className="flex gap-2 shrink-0">
              <button onClick={resumeRun} className="text-xs px-3 py-1.5 bg-amber-600 hover:bg-amber-500 text-white rounded-lg transition-colors">
                Resume
              </button>
              <button onClick={discardActiveRun} className="text-xs px-3 py-1.5 border border-white/10 text-gray-400 hover:text-white rounded-lg transition-colors">
                Discard
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Session Panel */}
      <SessionPanel
        game={game}
        totalPlaytime={totalPlaytime}
        sessions={currentSave?.sessions || []}
        onUpdateGame={onUpdateGame}
        onSessionStart={({ id, startTime }) => updateSave(s => ({
          ...s,
          activeSession: { id, startTime, endTime: null, duration: 0 },
          lastPlayedAt: startTime,
        }))}
        onAddSession={(session) => updateSave(s => ({
          ...s,
          sessions: [...(s.sessions || []), session],
          activeSession: null,
          lastPlayedAt: session.endTime,
        }))}
        onDeleteSession={(id) => updateSave(s => ({
          ...s,
          sessions: (s.sessions || []).filter(sess => sess.id !== id),
        }))}
        onUpdateSession={(updated) => updateSave(s => ({
          ...s,
          sessions: (s.sessions || []).map(sess => sess.id === updated.id ? updated : sess),
        }))}
      />

      {/* Tab content */}
      <div className="max-w-7xl mx-auto px-4 py-4">
        {activeTab === 'runs' && (
          <RunsTab save={currentSave} />
        )}
        {activeTab === 'progress' && (
          <ProgressTab save={currentSave} updateSave={updateSave} />
        )}
      </div>

      {/* New Save modal */}
      {showNewSave && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => setShowNewSave(false)}
        >
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
            <button onClick={handleCreateSave} className="btn-primary w-full">Create Save</button>
          </div>
        </div>
      )}
    </div>
  );
}
