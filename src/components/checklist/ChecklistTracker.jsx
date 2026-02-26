import React, { useState, useCallback } from 'react';
import { ArrowLeft, Plus, ChevronDown, CheckCircle, Circle, Edit3, Trash2, Trophy } from 'lucide-react';
import { createChecklistSave } from '../../utils/checklistFactory.js';
import SessionPanel from '../shared/SessionPanel.jsx';

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

const formatTime = (secs) => {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
};


export default function ChecklistTracker({ game, config, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('checklist');
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);
  const [editingChapters, setEditingChapters] = useState(false);
  const [chapterDrafts, setChapterDrafts] = useState([]);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  const updateCurrentSave = useCallback((updater) => {
    const updated = typeof updater === 'function' ? updater(currentSave) : updater;
    const newSaves = saves.map(s => s.id === updated.id ? updated : s);
    onUpdateGame({ ...game, saves: newSaves });
  }, [currentSave, saves, game, onUpdateGame]);

  const createSave = () => {
    if (!newSaveName.trim()) return;
    const save = createChecklistSave(newSaveName.trim(), config);
    onUpdateGame({ ...game, saves: [...saves, save], currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  const toggleChapter = (chapterId) => {
    updateCurrentSave(s => ({
      ...s,
      chapterCompleted: {
        ...s.chapterCompleted,
        [chapterId]: !s.chapterCompleted?.[chapterId],
      },
    }));
  };

  const setChapterRank = (chapterId, rank) => {
    updateCurrentSave(s => ({
      ...s,
      chapterCompleted: { ...s.chapterCompleted, [chapterId]: rank !== null },
      chapterRank: { ...(s.chapterRank || {}), [chapterId]: rank },
    }));
  };

  const deleteSave = (saveId) => {
    const remaining = saves.filter(s => s.id !== saveId);
    const nextId = remaining.length > 0
      ? (saveId === game.currentSaveId ? remaining[0].id : game.currentSaveId)
      : null;
    onUpdateGame({ ...game, saves: remaining, currentSaveId: nextId });
    setShowSaveDropdown(false);
  };

  const markCleared = () => {
    const now = new Date();
    const updates = {
      ...game,
      clears: [...(game.clears || []), { id: generateId(), clearedAt: now.toISOString() }],
    };
    // Auto-add a play period ending this month if none exist yet
    if (!(game.playPeriods || []).length) {
      updates.playPeriods = [{
        id: generateId(),
        startYear: now.getFullYear(),
        startMonth: null,
        endYear: now.getFullYear(),
        endMonth: now.getMonth() + 1,
        ongoing: false,
        platform: game.platforms?.[0] || null,
        note: '',
      }];
    }
    onUpdateGame(updates);
  };

  const clearCount = (game.clears || []).length;

  // Chapter editing
  const activeChapters = currentSave?.customChapters ?? config.chapters;

  const enterEditMode = () => {
    setChapterDrafts(activeChapters.map(c => ({ ...c })));
    setEditingChapters(true);
  };

  const saveChapters = () => {
    updateCurrentSave(s => ({ ...s, customChapters: chapterDrafts }));
    setEditingChapters(false);
  };

  const resetToDefault = () => {
    updateCurrentSave(s => ({ ...s, customChapters: null }));
    setEditingChapters(false);
  };

  const addChapter = () => {
    setChapterDrafts(d => [...d, { id: generateId(), name: `Stage ${d.length + 1}`, items: [] }]);
  };

  const renameChapter = (id, name) => {
    setChapterDrafts(d => d.map(c => c.id === id ? { ...c, name } : c));
  };

  const deleteChapter = (id) => {
    setChapterDrafts(d => d.filter(c => c.id !== id));
  };

  const moveChapter = (id, dir) => {
    setChapterDrafts(d => {
      const idx = d.findIndex(c => c.id === id);
      if (dir === 'up' && idx > 0) {
        const next = [...d];
        [next[idx - 1], next[idx]] = [next[idx], next[idx - 1]];
        return next;
      }
      if (dir === 'down' && idx < d.length - 1) {
        const next = [...d];
        [next[idx], next[idx + 1]] = [next[idx + 1], next[idx]];
        return next;
      }
      return d;
    });
  };

  if (!currentSave && saves.length === 0) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-black text-white flex flex-col items-center justify-center gap-4 p-4">
        <div className="text-5xl">{config.icon}</div>
        <h2 className="text-xl font-bold">{config.name}</h2>
        {config.note && <p className="text-yellow-400/80 text-sm text-center max-w-sm">{config.note}</p>}
        {showNewSave ? (
          <div className="flex gap-2 w-full max-w-sm">
            <input
              type="text"
              placeholder="Save name (e.g. 'Main Playthrough')"
              value={newSaveName}
              onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && createSave()}
              className="flex-1 bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none"
              autoFocus
            />
            <button onClick={createSave} className="px-4 py-2 bg-purple-600 rounded-lg text-sm">Create</button>
          </div>
        ) : (
          <button onClick={() => setShowNewSave(true)} className="px-6 py-3 bg-purple-600 hover:bg-purple-500 rounded-xl font-medium">
            Create First Save
          </button>
        )}
      </div>
    );
  }

  const totalChapters = activeChapters.length;
  const completedChapters = activeChapters.filter(c => currentSave?.chapterCompleted?.[c.id]).length;
  const pct = totalChapters > 0 ? Math.round((completedChapters / totalChapters) * 100) : 0;

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-black text-white">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-black/60 backdrop-blur border-b border-white/10 px-4 py-3">
        <div className="max-w-2xl mx-auto flex items-center gap-3 flex-wrap">
          <button onClick={onBack} className="p-2 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <span className="text-xl">{config.icon}</span>
          <span className="font-bold">{config.name}</span>

          {saves.length > 1 && (
            <div className="relative ml-2">
              <button
                onClick={() => setShowSaveDropdown(d => !d)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm"
              >
                {currentSave?.name} <ChevronDown className="w-3.5 h-3.5" />
              </button>
              {showSaveDropdown && (
                <div className="absolute left-0 mt-1 w-56 bg-gray-900 border border-white/20 rounded-xl shadow-xl z-20">
                  {saves.map(s => (
                    <div key={s.id} className="flex items-center first:rounded-t-xl last:rounded-b-xl hover:bg-white/10">
                      <button
                        onClick={() => { onUpdateGame({ ...game, currentSaveId: s.id }); setShowSaveDropdown(false); }}
                        className={`flex-1 text-left px-3 py-2 text-sm ${s.id === game.currentSaveId ? 'text-white font-medium' : 'text-gray-300'}`}
                      >
                        {s.name}
                      </button>
                      {saves.length > 1 && (
                        <button
                          onClick={() => deleteSave(s.id)}
                          className="px-2 py-2 text-gray-600 hover:text-red-400 transition-colors"
                          title="Delete save"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          <button onClick={() => setShowNewSave(v => !v)} className="ml-auto flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm">
            <Plus className="w-3.5 h-3.5" /> New Save
          </button>
        </div>
      </div>

      {/* Session panel — consistent with all other trackers */}
      <SessionPanel
        game={game}
        totalPlaytime={currentSave?.totalPlaytime || 0}
        onUpdateGame={onUpdateGame}
        onAddSession={(session) => updateCurrentSave(s => ({
          ...s,
          sessions: [...(s.sessions || []), session],
          totalPlaytime: (s.totalPlaytime || 0) + session.duration,
        }))}
      />

      <div className="max-w-2xl mx-auto px-4 py-4 space-y-4">
        {/* New save inline form */}
        {showNewSave && (
          <div className="flex gap-2">
            <input
              type="text" placeholder="Save name..." value={newSaveName}
              onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && createSave()}
              className="flex-1 bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none"
              autoFocus
            />
            <button onClick={createSave} className="px-3 py-2 bg-purple-600 rounded-lg text-sm">Create</button>
            <button onClick={() => setShowNewSave(false)} className="px-3 py-2 bg-white/10 rounded-lg text-sm">Cancel</button>
          </div>
        )}

        {config.note && (
          <div className="text-yellow-400/70 text-xs bg-yellow-900/10 border border-yellow-500/20 rounded-lg p-3">
            ⚠️ {config.note}
          </div>
        )}

        {/* Progress card */}
        <div className="bg-black/40 rounded-xl border border-white/10 p-4 space-y-3">
          <div>
            <div className="flex justify-between text-sm mb-1.5">
              <span className="text-gray-300">{completedChapters} / {totalChapters} stages completed</span>
              <span className="font-bold text-white">{pct}%</span>
            </div>
            <div className="h-2.5 bg-black/40 rounded-full overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-purple-600 to-purple-400 rounded-full transition-all duration-500"
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>
          <div className="flex items-center justify-between">
            {clearCount > 0 ? (
              <div className="flex items-center gap-2">
                <Trophy className="w-4 h-4 text-yellow-400" />
                <span className="text-sm text-yellow-300 font-medium">
                  Cleared{clearCount > 1 ? ` ×${clearCount}` : ''}
                </span>
                <button
                  onClick={markCleared}
                  className="text-xs text-gray-600 hover:text-yellow-400 transition-colors ml-1"
                  title="Clear again (NG+)"
                >+ again</button>
              </div>
            ) : (
              <button
                onClick={markCleared}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium border border-yellow-700/40 bg-yellow-900/20 text-yellow-400 hover:bg-yellow-900/40 transition-colors"
              >
                <Trophy className="w-4 h-4" /> Mark Cleared
              </button>
            )}
          </div>
        </div>

        {/* Chapter checklist */}
        <div className="bg-black/40 rounded-xl border border-white/10 overflow-hidden">
          <div className="px-4 py-3 border-b border-white/10 flex items-center justify-between">
            <h3 className="font-semibold text-sm text-gray-300 uppercase tracking-wider">Stages / Chapters</h3>
            {!editingChapters && (
              <button
                onClick={enterEditMode}
                className="flex items-center gap-1 text-xs text-gray-500 hover:text-gray-300 transition-colors"
              >
                <Edit3 className="w-3 h-3" /> Edit
              </button>
            )}
          </div>

          {/* Chapter editor */}
          {editingChapters && (
            <div className="p-4 border-b border-white/10 space-y-3">
              <div className="space-y-2">
                {chapterDrafts.map((chapter, idx) => (
                  <div key={chapter.id} className="flex items-center gap-2">
                    <div className="flex flex-col gap-0.5">
                      <button
                        onClick={() => moveChapter(chapter.id, 'up')}
                        disabled={idx === 0}
                        className="text-gray-600 hover:text-gray-300 disabled:opacity-20 text-xs leading-none px-0.5"
                      >▲</button>
                      <button
                        onClick={() => moveChapter(chapter.id, 'down')}
                        disabled={idx === chapterDrafts.length - 1}
                        className="text-gray-600 hover:text-gray-300 disabled:opacity-20 text-xs leading-none px-0.5"
                      >▼</button>
                    </div>
                    <input
                      type="text"
                      value={chapter.name}
                      onChange={e => renameChapter(chapter.id, e.target.value)}
                      className="flex-1 bg-black/50 border border-white/10 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:border-purple-500/50"
                    />
                    <button
                      onClick={() => deleteChapter(chapter.id)}
                      className="text-gray-600 hover:text-red-400 transition-colors p-1"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))}
              </div>
              <button
                onClick={addChapter}
                className="flex items-center gap-1.5 text-sm text-purple-400 hover:text-purple-300 transition-colors"
              >
                <Plus className="w-3.5 h-3.5" /> Add Stage
              </button>
              <div className="flex gap-2 pt-1">
                <button onClick={saveChapters} className="flex-1 px-3 py-1.5 bg-purple-600 hover:bg-purple-500 rounded-lg text-xs font-medium transition-colors">
                  Save Changes
                </button>
                <button onClick={resetToDefault} className="px-3 py-1.5 bg-white/10 hover:bg-white/20 rounded-lg text-xs transition-colors">
                  Reset to Default
                </button>
                <button onClick={() => setEditingChapters(false)} className="px-3 py-1.5 bg-white/10 hover:bg-white/20 rounded-lg text-xs transition-colors">
                  Cancel
                </button>
              </div>
            </div>
          )}

          <div className="divide-y divide-white/5">
            {activeChapters.map((chapter) => {
              const done = currentSave?.chapterCompleted?.[chapter.id];
              const currentRank = currentSave?.chapterRank?.[chapter.id];

              if (config.hasRanks) {
                return (
                  <div
                    key={chapter.id}
                    className="flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors"
                  >
                    <span className={`text-sm flex-1 ${done ? 'text-gray-400' : 'text-gray-200'}`}>
                      {chapter.name}
                    </span>
                    <div className="flex gap-1 shrink-0">
                      {[
                        { rank: 'bronze', label: 'B', on: 'bg-amber-700 text-amber-100', off: 'bg-white/5 text-gray-600 hover:text-amber-500' },
                        { rank: 'silver', label: 'S', on: 'bg-slate-500 text-slate-100', off: 'bg-white/5 text-gray-600 hover:text-slate-300' },
                        { rank: 'gold',   label: 'G', on: 'bg-yellow-500 text-black',    off: 'bg-white/5 text-gray-600 hover:text-yellow-400' },
                      ].map(({ rank, label, on, off }) => {
                        const active = currentRank === rank;
                        return (
                          <button
                            key={rank}
                            onClick={() => setChapterRank(chapter.id, active ? null : rank)}
                            className={`w-7 h-7 rounded font-bold text-xs transition-colors ${active ? on : off}`}
                            title={rank.charAt(0).toUpperCase() + rank.slice(1)}
                          >
                            {label}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                );
              }

              return (
                <button
                  key={chapter.id}
                  onClick={() => toggleChapter(chapter.id)}
                  className={`w-full flex items-center gap-3 px-4 py-3.5 text-left hover:bg-white/5 transition-colors ${done ? 'opacity-70' : ''}`}
                >
                  {done
                    ? <CheckCircle className="w-5 h-5 text-green-400 shrink-0" />
                    : <Circle className="w-5 h-5 text-gray-600 shrink-0" />
                  }
                  <span className={`text-sm ${done ? 'line-through text-gray-500' : 'text-gray-200'}`}>
                    {chapter.name}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        {/* Session log */}
        {(currentSave?.sessions?.length > 0) && (
          <div className="bg-black/40 rounded-xl border border-white/10 p-4">
            <h3 className="font-semibold text-sm text-gray-300 uppercase tracking-wider mb-3">Session Log</h3>
            <div className="space-y-2">
              {[...(currentSave.sessions || [])].reverse().map(session => (
                <div key={session.id} className="flex items-start justify-between gap-2 text-sm">
                  <div>
                    <span className="text-gray-300">{new Date(session.startTime).toLocaleDateString()}</span>
                    {session.notes && <span className="text-gray-500 ml-2">— {session.notes}</span>}
                  </div>
                  <span className="font-mono text-gray-400 shrink-0">{formatTime(session.duration)}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
