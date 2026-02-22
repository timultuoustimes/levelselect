import React, { useState, useEffect, useRef, useCallback } from 'react';
import { ArrowLeft, Plus, Play, Pause, StopCircle, ChevronDown, CheckCircle, Circle, Clock, Edit3, X, ChevronRight } from 'lucide-react';
import { createChecklistSave } from '../../utils/checklistFactory.js';

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

const formatTime = (secs) => {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
};

const formatTimeLong = (secs) => {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  if (h > 0) return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
  return `${m}:${String(s).padStart(2,'0')}`;
};

export default function ChecklistTracker({ game, config, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('checklist');
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);
  const [sessionElapsed, setSessionElapsed] = useState(0);
  const [sessionRunning, setSessionRunning] = useState(false);
  const [sessionNotes, setSessionNotes] = useState('');
  const [editingNotes, setEditingNotes] = useState(false);
  const intervalRef = useRef(null);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  // Timer
  useEffect(() => {
    if (sessionRunning) {
      intervalRef.current = setInterval(() => setSessionElapsed(e => e + 1), 1000);
    } else {
      clearInterval(intervalRef.current);
    }
    return () => clearInterval(intervalRef.current);
  }, [sessionRunning]);

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

  const startSession = () => {
    setSessionElapsed(0);
    setSessionRunning(true);
    setSessionNotes('');
  };

  const stopSession = () => {
    setSessionRunning(false);
    if (sessionElapsed > 0) {
      const session = {
        id: generateId(),
        startTime: new Date(Date.now() - sessionElapsed * 1000).toISOString(),
        endTime: new Date().toISOString(),
        duration: sessionElapsed,
        notes: sessionNotes,
      };
      updateCurrentSave(s => ({
        ...s,
        sessions: [...(s.sessions || []), session],
        totalPlaytime: (s.totalPlaytime || 0) + sessionElapsed,
      }));
    }
    setSessionElapsed(0);
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

  const totalChapters = config.chapters.length;
  const completedChapters = config.chapters.filter(c => currentSave?.chapterCompleted?.[c.id]).length;
  const pct = totalChapters > 0 ? Math.round((completedChapters / totalChapters) * 100) : 0;
  const totalPlaytime = currentSave?.totalPlaytime || 0;

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
                <div className="absolute left-0 mt-1 w-48 bg-gray-900 border border-white/20 rounded-xl shadow-xl z-20">
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

          <button onClick={() => setShowNewSave(v => !v)} className="ml-auto flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm">
            <Plus className="w-3.5 h-3.5" /> New Save
          </button>
        </div>
      </div>

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

        {/* Progress + Timer card */}
        <div className="bg-black/40 rounded-xl border border-white/10 p-4 space-y-3">
          {/* Progress bar */}
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

          {/* Playtime */}
          <div className="flex items-center justify-between flex-wrap gap-3">
            <div className="flex items-center gap-2">
              <Clock className="w-4 h-4 text-gray-400" />
              <span className="text-sm text-gray-300">Total playtime:</span>
              <span className="font-mono font-bold text-white">
                {formatTime(totalPlaytime + (sessionRunning ? sessionElapsed : 0))}
              </span>
            </div>

            {sessionRunning ? (
              <div className="flex items-center gap-2">
                <span className="font-mono text-green-400 text-sm animate-pulse">
                  ● {formatTimeLong(sessionElapsed)}
                </span>
                <button
                  onClick={stopSession}
                  className="flex items-center gap-1.5 px-3 py-1.5 bg-red-800 hover:bg-red-700 rounded-lg text-sm font-medium"
                >
                  <StopCircle className="w-4 h-4" /> Stop
                </button>
              </div>
            ) : (
              <button
                onClick={startSession}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-green-700 hover:bg-green-600 rounded-lg text-sm font-medium"
              >
                <Play className="w-4 h-4" /> Start Session
              </button>
            )}
          </div>

          {sessionRunning && (
            <input
              type="text"
              placeholder="Session notes (optional)..."
              value={sessionNotes}
              onChange={e => setSessionNotes(e.target.value)}
              className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none"
            />
          )}
        </div>

        {/* Chapter checklist */}
        <div className="bg-black/40 rounded-xl border border-white/10 overflow-hidden">
          <div className="px-4 py-3 border-b border-white/10">
            <h3 className="font-semibold text-sm text-gray-300 uppercase tracking-wider">Stages / Chapters</h3>
          </div>
          <div className="divide-y divide-white/5">
            {config.chapters.map((chapter, idx) => {
              const done = currentSave?.chapterCompleted?.[chapter.id];
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
