import React, { useState, useEffect, useRef } from 'react';
import {
  ArrowLeft, Play, Pause, Square, Plus, Trash2, Check,
  Star, Clock, BarChart2, BookOpen, ChevronDown, ChevronUp,
  PenLine,
} from 'lucide-react';
import {
  createGeneralSave,
  createMilestone,
  createSession,
} from '../../utils/generalGameFactory.js';
import { generateId } from '../../utils/format.js';
import { igdbCoverUrl } from '../../utils/igdb.js';

// ─── Helpers ────────────────────────────────────────────────────────────────

function formatDuration(seconds) {
  if (!seconds || seconds < 0) return '0m';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function formatDate(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatShortDate(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function getSessionDuration(session) {
  if (!session) return 0;
  if (session.endTime) return session.duration;
  const base = session.accumulatedTime || 0;
  const pausedAt = session.pausedAt;
  if (pausedAt) return base;
  return base + Math.floor((Date.now() - new Date(session.startTime).getTime()) / 1000 - (session.accumulatedTime > 0 ? 0 : 0));
}

// ─── Sub-components ──────────────────────────────────────────────────────────

function StarRating({ value, onChange, size = 'md' }) {
  const [hover, setHover] = useState(null);
  const sz = size === 'lg' ? 'w-8 h-8' : 'w-5 h-5';
  return (
    <div className="flex gap-1">
      {[1, 2, 3, 4, 5].map(n => (
        <button
          key={n}
          onClick={() => onChange(n === value ? null : n)}
          onMouseEnter={() => setHover(n)}
          onMouseLeave={() => setHover(null)}
          className="p-0.5 transition-transform hover:scale-110"
        >
          <Star
            className={`${sz} transition-colors ${
              n <= (hover ?? value ?? 0)
                ? 'fill-yellow-400 text-yellow-400'
                : 'text-gray-600'
            }`}
          />
        </button>
      ))}
    </div>
  );
}

function SessionTimer({ session, onTick }) {
  const [elapsed, setElapsed] = useState(0);
  const intervalRef = useRef(null);

  useEffect(() => {
    if (!session || session.endTime || session.pausedAt) {
      clearInterval(intervalRef.current);
      setElapsed(session?.accumulatedTime || 0);
      return;
    }

    const tick = () => {
      const base = session.accumulatedTime || 0;
      const started = new Date(session.startTime).getTime();
      // startTime was reset each time we resume, accumulatedTime holds prior elapsed
      setElapsed(base + Math.floor((Date.now() - started) / 1000));
    };

    tick();
    intervalRef.current = setInterval(tick, 1000);
    return () => clearInterval(intervalRef.current);
  }, [session]);

  return <span className="font-mono text-2xl font-bold text-purple-300">{formatDuration(elapsed)}</span>;
}

// ─── Main Component ──────────────────────────────────────────────────────────

export default function GeneralGameTracker({ game, onBack, onUpdateGame }) {
  const [tab, setTab] = useState('overview');
  const [newMilestone, setNewMilestone] = useState('');
  const [sessionNote, setSessionNote] = useState('');
  const [editingReview, setEditingReview] = useState(false);
  const [reviewDraft, setReviewDraft] = useState('');
  const [expandedSession, setExpandedSession] = useState(null);

  // Manual time entry
  const [showManualEntry, setShowManualEntry] = useState(false);
  const [manualMode, setManualMode] = useState('duration'); // 'duration' | 'range'
  const [manualHours, setManualHours] = useState('');
  const [manualMinutes, setManualMinutes] = useState('');
  const [manualDate, setManualDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [manualStartTime, setManualStartTime] = useState('');
  const [manualEndTime, setManualEndTime] = useState('');
  const [manualNote, setManualNote] = useState('');

  // Use first save, or create one if none exists
  const save = game.saves?.[0] || null;

  // Ensure save exists on mount
  useEffect(() => {
    if (!game.saves || game.saves.length === 0) {
      const newSave = createGeneralSave('Main');
      onUpdateGame({
        ...game,
        saves: [newSave],
        currentSaveId: newSave.id,
      });
    }
  }, []);

  if (!save) return null;

  const updateSave = (updater) => {
    const updated = typeof updater === 'function' ? updater(save) : updater;
    onUpdateGame({
      ...game,
      saves: [updated],
      currentSaveId: updated.id,
    });
  };

  // ── Session management ──────────────────────────────────────────────────

  const activeSession = save.activeSession;

  const startSession = () => {
    if (activeSession) return;
    const session = createSession();
    updateSave(s => ({ ...s, activeSession: session, lastPlayedAt: session.startTime }));
  };

  const pauseSession = () => {
    if (!activeSession || activeSession.pausedAt) return;
    const elapsed = Math.floor((Date.now() - new Date(activeSession.startTime).getTime()) / 1000);
    const accumulated = (activeSession.accumulatedTime || 0) + elapsed;
    updateSave(s => ({
      ...s,
      activeSession: { ...s.activeSession, pausedAt: new Date().toISOString(), accumulatedTime: accumulated },
    }));
  };

  const resumeSession = () => {
    if (!activeSession || !activeSession.pausedAt) return;
    updateSave(s => ({
      ...s,
      activeSession: {
        ...s.activeSession,
        pausedAt: null,
        startTime: new Date().toISOString(), // reset start for ticker
      },
    }));
  };

  const endSession = (noteText) => {
    if (!activeSession) return;
    const now = new Date().toISOString();
    let duration = activeSession.accumulatedTime || 0;
    if (!activeSession.pausedAt) {
      duration += Math.floor((Date.now() - new Date(activeSession.startTime).getTime()) / 1000);
    }
    const completed = { ...activeSession, endTime: now, duration, notes: noteText || '' };

    updateSave(s => ({
      ...s,
      activeSession: null,
      sessions: [completed, ...(s.sessions || [])],
      totalPlaytime: (s.totalPlaytime || 0) + duration,
    }));
    setSessionNote('');
  };

  // ── Manual session entry ─────────────────────────────────────────────────

  const addManualSession = () => {
    let duration = 0;
    let startTime = null;
    let endTime = null;

    if (manualMode === 'duration') {
      const h = parseInt(manualHours || '0', 10) || 0;
      const m = parseInt(manualMinutes || '0', 10) || 0;
      duration = h * 3600 + m * 60;
      if (duration <= 0) return;
      startTime = new Date(`${manualDate}T12:00:00`).toISOString();
      endTime = new Date(`${manualDate}T12:00:00`).toISOString();
    } else {
      if (!manualStartTime || !manualEndTime) return;
      const start = new Date(`${manualDate}T${manualStartTime}:00`);
      const end = new Date(`${manualDate}T${manualEndTime}:00`);
      if (end <= start) return;
      duration = Math.floor((end - start) / 1000);
      startTime = start.toISOString();
      endTime = end.toISOString();
    }

    const session = {
      id: generateId(),
      startTime,
      endTime,
      duration,
      pausedAt: null,
      accumulatedTime: duration,
      notes: manualNote.trim(),
      manual: true,
    };

    updateSave(s => ({
      ...s,
      sessions: [session, ...(s.sessions || [])],
      totalPlaytime: (s.totalPlaytime || 0) + duration,
      lastPlayedAt: startTime,
    }));

    // Reset form
    setManualHours('');
    setManualMinutes('');
    setManualNote('');
    setManualStartTime('');
    setManualEndTime('');
    setManualDate(new Date().toISOString().slice(0, 10));
    setShowManualEntry(false);
  };

  // ── Milestones ──────────────────────────────────────────────────────────

  const addMilestone = () => {
    if (!newMilestone.trim()) return;
    const m = createMilestone(newMilestone.trim());
    updateSave(s => ({ ...s, milestones: [...(s.milestones || []), m] }));
    setNewMilestone('');
  };

  const toggleMilestone = (id) => {
    updateSave(s => ({
      ...s,
      milestones: s.milestones.map(m =>
        m.id === id
          ? { ...m, completed: !m.completed, completedAt: !m.completed ? new Date().toISOString() : null }
          : m
      ),
    }));
  };

  const deleteMilestone = (id) => {
    updateSave(s => ({ ...s, milestones: s.milestones.filter(m => m.id !== id) }));
  };

  // Auto-compute progress from milestones if milestones exist
  const milestones = save.milestones || [];
  const computedProgress = milestones.length > 0
    ? Math.round((milestones.filter(m => m.completed).length / milestones.length) * 100)
    : save.progressPercent || 0;

  const setManualProgress = (val) => {
    if (milestones.length > 0) return; // milestones drive progress
    updateSave(s => ({ ...s, progressPercent: Math.min(100, Math.max(0, val)) }));
  };

  // ── Rating / review ─────────────────────────────────────────────────────

  const setRating = (val) => {
    updateSave(s => ({ ...s, rating: val }));
  };

  const saveReview = () => {
    updateSave(s => ({ ...s, review: reviewDraft }));
    setEditingReview(false);
  };

  // ── Playtime stats ──────────────────────────────────────────────────────

  const sessions = save.sessions || [];
  const totalPlaytime = save.totalPlaytime || 0;
  const sessionCount = sessions.length + (activeSession ? 1 : 0);
  const avgSession = sessionCount > 0 && sessions.length > 0
    ? Math.round(sessions.reduce((a, s) => a + (s.duration || 0), 0) / sessions.length)
    : 0;

  // ── Cover art ───────────────────────────────────────────────────────────
  const coverUrl = game.coverImageId ? igdbCoverUrl(game.coverImageId) : game.coverUrl || null;

  // ─── Render ────────────────────────────────────────────────────────────

  const tabs = ['overview', 'sessions', 'milestones', 'review'];

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-800 to-slate-900 safe-area-bottom">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-slate-900/90 backdrop-blur border-b border-white/10">
        <div className="max-w-4xl mx-auto px-4 py-3">
          <div className="flex items-center gap-3 mb-3">
            <button onClick={onBack} className="btn-secondary !px-3 !py-2 !min-h-0">
              <ArrowLeft className="w-4 h-4" />
            </button>
            {coverUrl && (
              <img
                src={coverUrl}
                alt={game.name}
                className="w-8 h-10 object-cover rounded shadow"
                onError={e => { e.target.style.display = 'none'; }}
              />
            )}
            <div className="flex-1 min-w-0">
              <h1 className="text-lg font-bold truncate">{game.name}</h1>
              {game.platforms?.length > 0 && (
                <p className="text-gray-400 text-xs truncate">{game.platforms.join(', ')}</p>
              )}
            </div>
          </div>

          {/* Tabs */}
          <div className="flex gap-1 overflow-x-auto scroll-smooth-ios">
            {tabs.map(t => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className={`${tab === t ? 'tab-button-active' : 'tab-button-inactive'} capitalize text-sm whitespace-nowrap`}
              >
                {t}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-4 space-y-4">

        {/* ── Overview Tab ─────────────────────────────────────────────── */}
        {tab === 'overview' && (
          <>
            {/* Cover + Stats */}
            <div className="card p-4 flex gap-4">
              {coverUrl ? (
                <img
                  src={coverUrl}
                  alt={game.name}
                  className="w-24 rounded-lg shadow-lg object-cover flex-shrink-0"
                  onError={e => { e.target.style.display = 'none'; }}
                />
              ) : (
                <div className="w-24 h-32 rounded-lg bg-purple-900/30 border border-purple-500/20 flex items-center justify-center flex-shrink-0">
                  <span className="text-3xl">🎮</span>
                </div>
              )}
              <div className="flex-1 space-y-3">
                {/* Rating */}
                <div>
                  <div className="text-xs text-gray-500 mb-1">Your Rating</div>
                  <StarRating value={save.rating} onChange={setRating} />
                </div>

                {/* Stats row */}
                <div className="grid grid-cols-3 gap-2">
                  <div className="bg-black/30 rounded-lg p-2 text-center">
                    <div className="text-lg font-bold text-purple-300">{formatDuration(totalPlaytime)}</div>
                    <div className="text-xs text-gray-500">Total</div>
                  </div>
                  <div className="bg-black/30 rounded-lg p-2 text-center">
                    <div className="text-lg font-bold text-blue-300">{sessionCount}</div>
                    <div className="text-xs text-gray-500">Sessions</div>
                  </div>
                  <div className="bg-black/30 rounded-lg p-2 text-center">
                    <div className="text-lg font-bold text-green-300">{computedProgress}%</div>
                    <div className="text-xs text-gray-500">Progress</div>
                  </div>
                </div>

                {/* Franchise */}
                {game.franchise && (
                  <div className="text-xs text-gray-500">
                    <span className="text-gray-400">Series:</span> {game.franchise}
                  </div>
                )}
              </div>
            </div>

            {/* Progress bar */}
            <div className="card p-4">
              <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-medium">Progress</span>
                <span className="text-sm text-purple-300 font-mono">{computedProgress}%</span>
              </div>
              <div className="w-full bg-black/40 rounded-full h-3 mb-3">
                <div
                  className="bg-gradient-to-r from-purple-600 to-purple-400 h-3 rounded-full transition-all duration-500"
                  style={{ width: `${computedProgress}%` }}
                />
              </div>
              {milestones.length === 0 && (
                <div className="flex items-center gap-2">
                  <input
                    type="range"
                    min="0"
                    max="100"
                    value={save.progressPercent || 0}
                    onChange={e => setManualProgress(Number(e.target.value))}
                    className="flex-1 accent-purple-500"
                  />
                  <span className="text-xs text-gray-500 w-8">{save.progressPercent || 0}%</span>
                </div>
              )}
              {milestones.length > 0 && (
                <p className="text-xs text-gray-500">
                  {milestones.filter(m => m.completed).length} / {milestones.length} milestones completed
                </p>
              )}
            </div>

            {/* Session timer */}
            <div className="card p-4">
              <div className="flex items-center justify-between mb-3">
                <span className="text-sm font-medium flex items-center gap-2">
                  <Clock className="w-4 h-4 text-purple-400" />
                  Current Session
                </span>
              </div>

              {activeSession ? (
                <div className="space-y-3">
                  <div className="text-center py-2">
                    <SessionTimer session={activeSession} />
                    <div className="text-xs text-gray-500 mt-1">
                      {activeSession.pausedAt ? 'Paused' : 'Running'}
                    </div>
                  </div>
                  <div className="flex gap-2">
                    {activeSession.pausedAt ? (
                      <button onClick={resumeSession} className="btn-primary flex-1 gap-2 text-sm">
                        <Play className="w-4 h-4" /> Resume
                      </button>
                    ) : (
                      <button onClick={pauseSession} className="btn-secondary flex-1 gap-2 text-sm">
                        <Pause className="w-4 h-4" /> Pause
                      </button>
                    )}
                    <button
                      onClick={() => endSession(sessionNote)}
                      className="bg-red-600 hover:bg-red-700 text-white font-medium px-4 py-2.5 rounded-lg flex-1 gap-2 text-sm flex items-center justify-center"
                    >
                      <Square className="w-4 h-4" /> End
                    </button>
                  </div>
                  <input
                    type="text"
                    placeholder="Session note (optional)…"
                    value={sessionNote}
                    onChange={e => setSessionNote(e.target.value)}
                    className="input-field text-sm"
                  />
                </div>
              ) : (
                <button onClick={startSession} className="btn-primary w-full gap-2">
                  <Play className="w-4 h-4" /> Start Session
                </button>
              )}
            </div>

            {/* Quick review */}
            {(save.rating || save.review) && (
              <div className="card p-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium">Review</span>
                  <button onClick={() => { setReviewDraft(save.review || ''); setEditingReview(true); setTab('review'); }} className="text-xs text-purple-400 hover:text-purple-300">
                    Edit
                  </button>
                </div>
                {save.rating && (
                  <div className="flex gap-0.5 mb-2">
                    {[1,2,3,4,5].map(n => (
                      <Star key={n} className={`w-4 h-4 ${n <= save.rating ? 'fill-yellow-400 text-yellow-400' : 'text-gray-600'}`} />
                    ))}
                  </div>
                )}
                {save.review && <p className="text-sm text-gray-300 leading-relaxed">{save.review}</p>}
              </div>
            )}
          </>
        )}

        {/* ── Sessions Tab ─────────────────────────────────────────────── */}
        {tab === 'sessions' && (
          <>
            {/* Stats summary */}
            <div className="grid grid-cols-3 gap-3">
              {[
                { label: 'Total Playtime', value: formatDuration(totalPlaytime), color: 'text-purple-300' },
                { label: 'Sessions', value: sessionCount, color: 'text-blue-300' },
                { label: 'Avg Session', value: formatDuration(avgSession), color: 'text-green-300' },
              ].map(s => (
                <div key={s.label} className="card p-3 text-center">
                  <div className={`text-xl font-bold ${s.color}`}>{s.value}</div>
                  <div className="text-xs text-gray-500">{s.label}</div>
                </div>
              ))}
            </div>

            {/* Manual time entry */}
            <div className="card p-4">
              <div className="flex items-center justify-between mb-3">
                <span className="text-sm font-medium flex items-center gap-2">
                  <PenLine className="w-4 h-4 text-purple-400" />
                  Log Time Manually
                </span>
                <button
                  onClick={() => setShowManualEntry(o => !o)}
                  className="text-xs text-purple-400 hover:text-purple-300"
                >
                  {showManualEntry ? 'Cancel' : 'Add'}
                </button>
              </div>

              {showManualEntry && (
                <div className="space-y-3">
                  {/* Mode toggle */}
                  <div className="flex gap-2">
                    <button
                      onClick={() => setManualMode('duration')}
                      className={`flex-1 py-2 rounded-lg text-xs font-medium transition-colors ${manualMode === 'duration' ? 'bg-purple-600 text-white' : 'bg-white/10 text-gray-400 hover:bg-white/20'}`}
                    >
                      Hours : Minutes
                    </button>
                    <button
                      onClick={() => setManualMode('range')}
                      className={`flex-1 py-2 rounded-lg text-xs font-medium transition-colors ${manualMode === 'range' ? 'bg-purple-600 text-white' : 'bg-white/10 text-gray-400 hover:bg-white/20'}`}
                    >
                      Start → End Time
                    </button>
                  </div>

                  {/* Date (always shown) */}
                  <div>
                    <label className="text-xs text-gray-500 mb-1 block">Date</label>
                    <input
                      type="date"
                      value={manualDate}
                      onChange={e => setManualDate(e.target.value)}
                      className="input-field text-sm"
                    />
                  </div>

                  {manualMode === 'duration' ? (
                    <div>
                      <label className="text-xs text-gray-500 mb-1 block">Duration</label>
                      <div className="flex gap-2 items-center">
                        <input
                          type="number"
                          min="0"
                          max="99"
                          placeholder="0"
                          value={manualHours}
                          onChange={e => setManualHours(e.target.value)}
                          className="input-field text-sm text-center w-20"
                        />
                        <span className="text-gray-500 text-sm">h</span>
                        <input
                          type="number"
                          min="0"
                          max="59"
                          placeholder="0"
                          value={manualMinutes}
                          onChange={e => setManualMinutes(e.target.value)}
                          className="input-field text-sm text-center w-20"
                        />
                        <span className="text-gray-500 text-sm">m</span>
                      </div>
                    </div>
                  ) : (
                    <div className="flex gap-2 items-center">
                      <div className="flex-1">
                        <label className="text-xs text-gray-500 mb-1 block">Start time</label>
                        <input
                          type="time"
                          value={manualStartTime}
                          onChange={e => setManualStartTime(e.target.value)}
                          className="input-field text-sm"
                        />
                      </div>
                      <span className="text-gray-500 mt-5">→</span>
                      <div className="flex-1">
                        <label className="text-xs text-gray-500 mb-1 block">End time</label>
                        <input
                          type="time"
                          value={manualEndTime}
                          onChange={e => setManualEndTime(e.target.value)}
                          className="input-field text-sm"
                        />
                      </div>
                    </div>
                  )}

                  {/* Note */}
                  <div>
                    <label className="text-xs text-gray-500 mb-1 block">Note (optional)</label>
                    <input
                      type="text"
                      placeholder="What did you do this session?"
                      value={manualNote}
                      onChange={e => setManualNote(e.target.value)}
                      className="input-field text-sm"
                    />
                  </div>

                  <button
                    onClick={addManualSession}
                    className="btn-primary w-full text-sm gap-2"
                  >
                    <Plus className="w-4 h-4" />
                    Add Session
                  </button>
                </div>
              )}
            </div>

            {/* Playtime bar chart (last 10 sessions) */}
            {sessions.length > 0 && (
              <div className="card p-4">
                <h3 className="text-sm font-medium mb-3 flex items-center gap-2">
                  <BarChart2 className="w-4 h-4 text-purple-400" />
                  Recent Sessions
                </h3>
                <div className="flex items-end gap-1 h-20">
                  {sessions.slice(0, 10).reverse().map((s, i) => {
                    const maxDur = Math.max(...sessions.slice(0, 10).map(x => x.duration || 0));
                    const pct = maxDur > 0 ? ((s.duration || 0) / maxDur) * 100 : 0;
                    return (
                      <div key={s.id} className="flex-1 flex flex-col items-center gap-1 group">
                        <div className="relative flex-1 w-full flex items-end">
                          <div
                            className="w-full bg-purple-600/60 group-hover:bg-purple-500 rounded-t transition-all"
                            style={{ height: `${Math.max(4, pct)}%` }}
                            title={formatDuration(s.duration)}
                          />
                        </div>
                        <span className="text-[9px] text-gray-600 hidden sm:block">
                          {formatShortDate(s.startTime)}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Session list */}
            <div className="space-y-2">
              {activeSession && (
                <div className="card p-3 border-purple-500/50">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
                      <span className="text-sm font-medium">Current session</span>
                    </div>
                    <SessionTimer session={activeSession} />
                  </div>
                </div>
              )}
              {sessions.length === 0 && !activeSession && (
                <div className="text-center py-8 text-gray-500 text-sm">
                  No sessions recorded yet. Start a session from the Overview tab.
                </div>
              )}
              {sessions.map(s => (
                <div key={s.id} className="card p-3">
                  <button
                    className="w-full text-left"
                    onClick={() => setExpandedSession(expandedSession === s.id ? null : s.id)}
                  >
                    <div className="flex items-center justify-between">
                      <div>
                        <div className="text-sm font-medium flex items-center gap-1.5">
                          {formatDate(s.startTime)}
                          {s.manual && (
                            <span className="text-[9px] bg-gray-700 text-gray-400 px-1.5 py-0.5 rounded-full">manual</span>
                          )}
                        </div>
                        {s.notes && <div className="text-xs text-gray-500 truncate max-w-xs">{s.notes}</div>}
                      </div>
                      <div className="flex items-center gap-2">
                        <span className="text-sm text-purple-300 font-mono">{formatDuration(s.duration)}</span>
                        {expandedSession === s.id
                          ? <ChevronUp className="w-3.5 h-3.5 text-gray-500" />
                          : <ChevronDown className="w-3.5 h-3.5 text-gray-500" />
                        }
                      </div>
                    </div>
                  </button>
                  {expandedSession === s.id && (
                    <div className="mt-2 pt-2 border-t border-white/10 text-xs text-gray-400 space-y-1">
                      <div>Started: {new Date(s.startTime).toLocaleTimeString()}</div>
                      {s.endTime && <div>Ended: {new Date(s.endTime).toLocaleTimeString()}</div>}
                      {s.notes && <div className="text-gray-300">{s.notes}</div>}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </>
        )}

        {/* ── Milestones Tab ───────────────────────────────────────────── */}
        {tab === 'milestones' && (
          <>
            <div className="card p-4">
              <h3 className="text-sm font-medium mb-3">
                Milestones
                <span className="text-gray-500 ml-2 font-normal">
                  ({milestones.filter(m => m.completed).length}/{milestones.length})
                </span>
              </h3>

              {/* Progress */}
              {milestones.length > 0 && (
                <div className="mb-4">
                  <div className="w-full bg-black/40 rounded-full h-2 mb-1">
                    <div
                      className="bg-gradient-to-r from-purple-600 to-purple-400 h-2 rounded-full transition-all duration-500"
                      style={{ width: `${computedProgress}%` }}
                    />
                  </div>
                  <p className="text-xs text-gray-500 text-right">{computedProgress}% complete</p>
                </div>
              )}

              {/* Add milestone */}
              <div className="flex gap-2 mb-4">
                <input
                  type="text"
                  placeholder="Add a milestone (e.g. Beat Act 1, Find all secrets…)"
                  value={newMilestone}
                  onChange={e => setNewMilestone(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && addMilestone()}
                  className="input-field flex-1 text-sm"
                />
                <button onClick={addMilestone} className="btn-primary !px-3">
                  <Plus className="w-4 h-4" />
                </button>
              </div>

              {/* Milestone list */}
              {milestones.length === 0 ? (
                <p className="text-gray-500 text-sm text-center py-4">
                  Add milestones to track your progress through the game.
                </p>
              ) : (
                <div className="space-y-2">
                  {milestones.map(m => (
                    <div key={m.id} className={`flex items-center gap-3 p-2.5 rounded-lg ${m.completed ? 'bg-green-900/20' : 'bg-black/20'}`}>
                      <button
                        onClick={() => toggleMilestone(m.id)}
                        className={`w-5 h-5 rounded border-2 flex items-center justify-center flex-shrink-0 transition-all ${
                          m.completed
                            ? 'bg-green-500 border-green-500'
                            : 'border-gray-600 hover:border-purple-400'
                        }`}
                      >
                        {m.completed && <Check className="w-3 h-3 text-white" />}
                      </button>
                      <span className={`flex-1 text-sm ${m.completed ? 'line-through text-gray-500' : 'text-gray-200'}`}>
                        {m.title}
                      </span>
                      {m.completedAt && (
                        <span className="text-xs text-gray-600">{formatShortDate(m.completedAt)}</span>
                      )}
                      <button
                        onClick={() => deleteMilestone(m.id)}
                        className="text-gray-600 hover:text-red-400 transition-colors p-1"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </>
        )}

        {/* ── Review Tab ───────────────────────────────────────────────── */}
        {tab === 'review' && (
          <div className="card p-4 space-y-4">
            <h3 className="font-medium flex items-center gap-2">
              <BookOpen className="w-4 h-4 text-purple-400" />
              Your Review
            </h3>

            <div>
              <div className="text-sm text-gray-400 mb-2">Rating</div>
              <StarRating value={save.rating} onChange={setRating} size="lg" />
              {save.rating && (
                <div className="text-sm text-gray-400 mt-1">
                  {['', 'Terrible', 'Mediocre', 'Good', 'Great', 'Excellent'][save.rating]}
                </div>
              )}
            </div>

            <div>
              <div className="text-sm text-gray-400 mb-2">Written Review</div>
              {editingReview ? (
                <div className="space-y-2">
                  <textarea
                    value={reviewDraft}
                    onChange={e => setReviewDraft(e.target.value)}
                    placeholder="Share your thoughts on this game…"
                    className="input-field resize-none h-40 text-sm"
                    autoFocus
                  />
                  <div className="flex gap-2">
                    <button onClick={saveReview} className="btn-primary flex-1 text-sm">Save</button>
                    <button onClick={() => setEditingReview(false)} className="btn-secondary flex-1 text-sm">Cancel</button>
                  </div>
                </div>
              ) : (
                <div>
                  {save.review ? (
                    <div className="space-y-2">
                      <p className="text-gray-300 text-sm leading-relaxed whitespace-pre-wrap">{save.review}</p>
                      <button
                        onClick={() => { setReviewDraft(save.review); setEditingReview(true); }}
                        className="text-xs text-purple-400 hover:text-purple-300"
                      >
                        Edit review
                      </button>
                    </div>
                  ) : (
                    <button
                      onClick={() => { setReviewDraft(''); setEditingReview(true); }}
                      className="btn-secondary w-full text-sm gap-2"
                    >
                      <BookOpen className="w-4 h-4" />
                      Write a review
                    </button>
                  )}
                </div>
              )}
            </div>

            {/* Playtime summary */}
            <div className="pt-2 border-t border-white/10">
              <div className="text-sm text-gray-400 mb-2">Play Stats</div>
              <div className="grid grid-cols-2 gap-2 text-sm">
                <div className="bg-black/30 rounded-lg p-2">
                  <div className="text-purple-300 font-medium">{formatDuration(totalPlaytime)}</div>
                  <div className="text-gray-500 text-xs">Total playtime</div>
                </div>
                <div className="bg-black/30 rounded-lg p-2">
                  <div className="text-blue-300 font-medium">{sessions.length} sessions</div>
                  <div className="text-gray-500 text-xs">Play sessions</div>
                </div>
              </div>
            </div>
          </div>
        )}

      </div>
    </div>
  );
}
