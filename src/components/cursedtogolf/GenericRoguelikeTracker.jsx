import React, { useState, useEffect, useCallback, useRef } from 'react';
import { ArrowLeft, Plus, Play, Pause, Trophy, Skull, X, ChevronDown, Timer, TrendingUp, FileText } from 'lucide-react';
import { createGenericRoguelikeSave, createGenericRun, migrateGenericRoguelikeSave } from '../../utils/genericRoguelikeFactory.js';
import SessionPanel from '../shared/SessionPanel.jsx';

const formatTime = (secs) => {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h > 0) return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
  return `${m}:${String(s).padStart(2,'0')}`;
};

const OUTCOME_STYLES = {
  victory:   { label: '🏆 Victory',   bg: 'bg-green-900/30',  border: 'border-green-500/50',  text: 'text-green-400' },
  escaped:   { label: '🏆 Escaped',   bg: 'bg-green-900/30',  border: 'border-green-500/50',  text: 'text-green-400' },
  death:     { label: '💀 Death',     bg: 'bg-red-900/30',    border: 'border-red-500/50',    text: 'text-red-400' },
  abandoned: { label: '↩ Abandoned',  bg: 'bg-gray-900/30',   border: 'border-gray-500/50',   text: 'text-gray-400' },
};

// ── Run View ─────────────────────────────────────────────────────────────────
function RunView({ config, run, onUpdateRun, onEndRun, onCancel }) {
  const [elapsed, setElapsed] = useState(run.accumulatedTime || 0);
  const [paused, setPaused] = useState(false);
  const intervalRef = useRef(null);

  useEffect(() => {
    if (!paused) {
      intervalRef.current = setInterval(() => setElapsed(e => e + 1), 1000);
    }
    return () => clearInterval(intervalRef.current);
  }, [paused]);

  const handleEnd = (outcome) => {
    clearInterval(intervalRef.current);
    onEndRun({ ...run, outcome, duration: elapsed, endTime: new Date().toISOString() });
  };

  const accentColor = config.accent || 'purple';

  return (
    <div className={`min-h-screen bg-gradient-to-br ${config.color} text-white p-4`}>
      <div className="max-w-2xl mx-auto space-y-4">
        {/* Timer */}
        <div className="text-center py-6">
          <div className="text-6xl font-mono font-bold tabular-nums">{formatTime(elapsed)}</div>
          <div className="text-gray-400 mt-1">Run in progress</div>
        </div>

        {/* Controls */}
        <div className="flex gap-3 justify-center flex-wrap">
          <button
            onClick={() => setPaused(p => !p)}
            className="flex items-center gap-2 px-4 py-2 rounded-lg border border-white/20 bg-white/10 hover:bg-white/20"
          >
            {paused ? <Play className="w-4 h-4" /> : <Pause className="w-4 h-4" />}
            {paused ? 'Resume' : 'Pause'}
          </button>
          <button
            onClick={onCancel}
            className="flex items-center gap-2 px-4 py-2 rounded-lg border border-white/20 bg-white/10 hover:bg-white/20 text-gray-300"
          >
            <X className="w-4 h-4" /> Cancel
          </button>
        </div>

        {/* Loadout fields */}
        <div className="bg-black/40 rounded-xl border border-white/10 p-4 space-y-3">
          <h3 className="font-semibold text-sm text-gray-300 uppercase tracking-wider">Loadout</h3>
          {config.loadoutFields.map(field => (
            <div key={field.id}>
              <label className="block text-xs text-gray-400 mb-1">{field.label}</label>
              {field.type === 'select' ? (
                <select
                  value={run.loadout?.[field.id] || ''}
                  onChange={e => onUpdateRun({ ...run, loadout: { ...run.loadout, [field.id]: e.target.value } })}
                  className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-white/30"
                >
                  <option value="">Select...</option>
                  {field.options.map(o => <option key={o} value={o}>{o}</option>)}
                </select>
              ) : (
                <input
                  type="text"
                  placeholder={field.placeholder}
                  value={run.loadout?.[field.id] || ''}
                  onChange={e => onUpdateRun({ ...run, loadout: { ...run.loadout, [field.id]: e.target.value } })}
                  className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-white/30"
                />
              )}
            </div>
          ))}
        </div>

        {/* Notes */}
        <div className="bg-black/40 rounded-xl border border-white/10 p-4">
          <label className="block text-xs text-gray-400 mb-2">Notes</label>
          <textarea
            rows={3}
            placeholder="What happened? Strategy, what went wrong..."
            value={run.notes || ''}
            onChange={e => onUpdateRun({ ...run, notes: e.target.value })}
            className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-white/30 resize-none"
          />
        </div>

        {/* End run buttons */}
        <div className="flex gap-3 flex-wrap">
          {config.outcomes.map(outcome => {
            const style = OUTCOME_STYLES[outcome] || OUTCOME_STYLES.victory;
            const isWin = outcome === 'victory' || outcome === 'escaped';
            return (
              <button
                key={outcome}
                onClick={() => handleEnd(outcome)}
                className={`flex-1 min-w-[120px] flex items-center justify-center gap-2 px-4 py-3 rounded-xl border font-semibold ${
                  isWin
                    ? 'bg-green-700 hover:bg-green-600 border-green-500 text-white'
                    : outcome === 'death'
                    ? 'bg-red-800 hover:bg-red-700 border-red-500 text-white'
                    : 'bg-gray-700 hover:bg-gray-600 border-gray-500 text-white'
                }`}
              >
                {isWin ? <Trophy className="w-4 h-4" /> : outcome === 'death' ? <Skull className="w-4 h-4" /> : <X className="w-4 h-4" />}
                {style.label}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
function OverviewTab({ save, config }) {
  const runs = save.runs || [];
  const wins = runs.filter(r => r.outcome === 'victory' || r.outcome === 'escaped');
  const totalTime = runs.reduce((sum, r) => sum + (r.duration || 0), 0);
  const winRate = runs.length > 0 ? ((wins.length / runs.length) * 100).toFixed(0) : 0;

  return (
    <div className="space-y-4">
      {/* Stats */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[
          { label: 'Total Runs', value: runs.length, color: 'text-purple-400' },
          { label: 'Wins', value: wins.length, color: 'text-green-400' },
          { label: 'Win Rate', value: `${winRate}%`, color: 'text-blue-400' },
          { label: 'Time Played', value: formatTime(totalTime), color: 'text-yellow-400' },
        ].map(s => (
          <div key={s.label} className="bg-black/40 rounded-xl border border-white/10 p-3 text-center">
            <div className={`text-2xl font-bold ${s.color}`}>{s.value}</div>
            <div className="text-xs text-gray-400 mt-1">{s.label}</div>
          </div>
        ))}
      </div>

      {/* Recent runs */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <h3 className="font-semibold mb-3 text-sm text-gray-300 uppercase tracking-wider">Recent Runs</h3>
        {runs.length === 0 ? (
          <div className="text-gray-500 text-sm text-center py-8">No runs yet. Start your first run!</div>
        ) : (
          <div className="space-y-2">
            {[...runs].reverse().slice(0, 15).map(run => {
              const style = OUTCOME_STYLES[run.outcome] || OUTCOME_STYLES.abandoned;
              return (
                <div key={run.id} className={`flex items-center justify-between p-3 rounded-lg border ${style.bg} ${style.border}`}>
                  <div className="min-w-0 flex-1">
                    <div className={`text-sm font-medium ${style.text}`}>{style.label}</div>
                    {/* Loadout summary */}
                    {run.loadout && Object.keys(run.loadout).length > 0 && (
                      <div className="text-xs text-gray-400 mt-0.5 truncate">
                        {Object.entries(run.loadout)
                          .filter(([, v]) => v)
                          .map(([k, v]) => `${v}`)
                          .join(' · ')}
                      </div>
                    )}
                    {run.notes && <div className="text-xs text-gray-500 mt-0.5 truncate">{run.notes}</div>}
                  </div>
                  <div className="text-xs text-gray-500 ml-3 shrink-0">{formatTime(run.duration || 0)}</div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Analytics Tab ─────────────────────────────────────────────────────────────
function AnalyticsTab({ save, config }) {
  const runs = save.runs || [];
  if (runs.length === 0) return (
    <div className="text-gray-500 text-center py-16">No runs yet to analyze.</div>
  );

  // Group by each loadout field
  const fieldStats = {};
  config.loadoutFields.forEach(field => {
    const groups = {};
    runs.forEach(run => {
      const val = run.loadout?.[field.id] || 'Unknown';
      if (!groups[val]) groups[val] = { total: 0, wins: 0 };
      groups[val].total++;
      if (run.outcome === 'victory' || run.outcome === 'escaped') groups[val].wins++;
    });
    fieldStats[field.id] = { label: field.label, groups };
  });

  return (
    <div className="space-y-4">
      {config.loadoutFields.map(field => {
        const { label, groups } = fieldStats[field.id];
        const entries = Object.entries(groups).sort(([,a],[,b]) => (b.wins/b.total) - (a.wins/a.total));
        if (entries.length <= 1 && entries[0]?.[0] === 'Unknown') return null;
        return (
          <div key={field.id} className="bg-black/40 rounded-xl border border-white/10 p-4">
            <h3 className="font-semibold mb-3 text-sm text-gray-300 uppercase tracking-wider">{label} Performance</h3>
            <div className="space-y-2">
              {entries.map(([name, stats]) => {
                const rate = stats.total > 0 ? stats.wins / stats.total : 0;
                return (
                  <div key={name}>
                    <div className="flex justify-between text-sm mb-1">
                      <span className="text-gray-200">{name}</span>
                      <span className="text-gray-400">{stats.wins}/{stats.total} ({(rate*100).toFixed(0)}%)</span>
                    </div>
                    <div className="h-1.5 bg-black/30 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-gradient-to-r from-green-600 to-green-400 rounded-full transition-all"
                        style={{ width: `${rate * 100}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      }).filter(Boolean)}
    </div>
  );
}

// ── Main Tracker ──────────────────────────────────────────────────────────────
export default function GenericRoguelikeTracker({ game, config, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [activeRun, setActiveRun] = useState(null);
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  const saves = (game.saves || []).map(migrateGenericRoguelikeSave);
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  const updateCurrentSave = useCallback((updater) => {
    const updated = typeof updater === 'function' ? updater(currentSave) : updater;
    const newSaves = saves.map(s => s.id === updated.id ? updated : s);
    onUpdateGame({ ...game, saves: newSaves });
  }, [currentSave, saves, game, onUpdateGame]);

  const createSave = () => {
    if (!newSaveName.trim()) return;
    const save = createGenericRoguelikeSave(newSaveName.trim());
    const newSaves = [...saves, save];
    onUpdateGame({ ...game, saves: newSaves, currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  const startRun = () => {
    const run = createGenericRun({});
    setActiveRun(run);
  };

  const endRun = (completedRun) => {
    updateCurrentSave(s => ({ ...s, runs: [...(s.runs || []), completedRun] }));
    setActiveRun(null);
  };

  if (activeRun) {
    return (
      <RunView
        config={config}
        run={activeRun}
        onUpdateRun={setActiveRun}
        onEndRun={endRun}
        onCancel={() => setActiveRun(null)}
      />
    );
  }

  const TABS = [
    { id: 'overview', label: 'Overview', icon: <FileText className="w-3.5 h-3.5" /> },
    { id: 'analytics', label: 'Analytics', icon: <TrendingUp className="w-3.5 h-3.5" /> },
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-black text-white">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-black/60 backdrop-blur border-b border-white/10 px-4 py-3">
        <div className="max-w-4xl mx-auto flex items-center gap-3 flex-wrap">
          <button onClick={onBack} className="p-2 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <span className="text-xl">{config.icon}</span>
          <span className="font-bold text-lg">{config.name}</span>

          {/* Save selector */}
          {saves.length > 0 && (
            <div className="relative ml-auto">
              <button
                onClick={() => setShowSaveDropdown(d => !d)}
                className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm"
              >
                {currentSave?.name || 'Select save'}
                <ChevronDown className="w-3.5 h-3.5" />
              </button>
              {showSaveDropdown && (
                <div className="absolute right-0 mt-1 w-48 bg-gray-900 border border-white/20 rounded-xl shadow-xl z-20">
                  {saves.map(s => (
                    <button
                      key={s.id}
                      onClick={() => { onUpdateGame({ ...game, currentSaveId: s.id }); setShowSaveDropdown(false); }}
                      className={`w-full text-left px-3 py-2 text-sm hover:bg-white/10 first:rounded-t-xl last:rounded-b-xl ${s.id === game.currentSaveId ? 'text-white font-medium' : 'text-gray-300'}`}
                    >
                      {s.name}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          <button
            onClick={() => setShowNewSave(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm"
          >
            <Plus className="w-3.5 h-3.5" /> New Save
          </button>

          {currentSave && (
            <button
              onClick={startRun}
              className="flex items-center gap-2 px-4 py-2 rounded-lg bg-purple-600 hover:bg-purple-500 font-medium text-sm"
            >
              <Play className="w-4 h-4" /> Start Run
            </button>
          )}
        </div>
      </div>

      {/* Session Panel */}
      <SessionPanel
        game={game}
        totalPlaytime={(currentSave?.runs || []).reduce((sum, r) => sum + (r.duration || 0), 0)}
        onUpdateGame={onUpdateGame}
        onAddSession={(session) => updateCurrentSave(s => ({
          ...s,
          sessions: [...(s.sessions || []), session],
          lastPlayedAt: session.endTime,
        }))}
      />

      <div className="max-w-4xl mx-auto px-4 py-4">
        {/* New save form */}
        {showNewSave && (
          <div className="mb-4 p-4 bg-black/40 rounded-xl border border-white/10 flex gap-3 flex-wrap">
            <input
              type="text"
              placeholder="Save name..."
              value={newSaveName}
              onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && createSave()}
              className="flex-1 min-w-0 bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-white/30"
              autoFocus
            />
            <button onClick={createSave} className="px-4 py-2 bg-purple-600 hover:bg-purple-500 rounded-lg text-sm font-medium">Create</button>
            <button onClick={() => setShowNewSave(false)} className="px-3 py-2 bg-white/10 hover:bg-white/20 rounded-lg text-sm">Cancel</button>
          </div>
        )}

        {!currentSave ? (
          <div className="text-center py-20 text-gray-500">
            <div className="text-4xl mb-4">{config.icon}</div>
            <div className="text-lg mb-2">No saves yet</div>
            <button onClick={() => setShowNewSave(true)} className="px-4 py-2 bg-purple-600 rounded-lg text-sm mt-2">Create First Save</button>
          </div>
        ) : (
          <>
            {/* Tabs */}
            <div className="flex gap-1 mb-4 border-b border-white/10 pb-1">
              {TABS.map(tab => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-1.5 px-3 py-2 rounded-t-lg text-sm font-medium transition-colors ${
                    activeTab === tab.id ? 'text-white bg-white/10' : 'text-gray-400 hover:text-white hover:bg-white/5'
                  }`}
                >
                  {tab.icon}{tab.label}
                </button>
              ))}
            </div>

            {activeTab === 'overview' && <OverviewTab save={currentSave} config={config} />}
            {activeTab === 'analytics' && <AnalyticsTab save={currentSave} config={config} />}
          </>
        )}
      </div>
    </div>
  );
}
