import React, { useState, useEffect, useRef } from 'react';
import { Play, Square, Clock, ChevronDown, Check } from 'lucide-react';

// ─── Constants ────────────────────────────────────────────────────────────────

const STATUS_COLORS = {
  playing:   'bg-green-500',
  queued:    'bg-cyan-500',
  paused:    'bg-yellow-500',
  completed: 'bg-blue-500',
  backlog:   'bg-gray-500',
  shelved:   'bg-orange-500',
  abandoned: 'bg-red-500',
};

const STATUS_LABELS = {
  playing:   'Playing',
  queued:    'Up Next',
  paused:    'Paused',
  completed: 'Completed',
  backlog:   'Backlog',
  shelved:   'Shelved',
  abandoned: 'Abandoned',
};

const ALL_STATUSES = ['playing', 'queued', 'paused', 'backlog', 'completed', 'shelved', 'abandoned'];

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatDuration(seconds) {
  if (!seconds || seconds <= 0) return '0m';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function formatDurationShort(seconds) {
  if (!seconds || seconds <= 0) return '0:00';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${m}:${String(s).padStart(2, '0')}`;
}

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

// ─── Status Picker ────────────────────────────────────────────────────────────

function StatusPicker({ status, onChange }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  const color = STATUS_COLORS[status] || 'bg-gray-500';
  const label = STATUS_LABELS[status] || status;

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen(o => !o)}
        className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-white/10 hover:bg-white/20 text-xs transition-colors"
      >
        <span className={`w-2 h-2 rounded-full flex-shrink-0 ${color}`} />
        {label}
        <ChevronDown className="w-3 h-3 ml-0.5" />
      </button>
      {open && (
        <div className="absolute left-0 top-full mt-1 z-30 bg-slate-800 border border-white/10 rounded-xl shadow-2xl overflow-hidden min-w-[160px]">
          {ALL_STATUSES.map(s => (
            <button
              key={s}
              onClick={() => { onChange(s); setOpen(false); }}
              className={`w-full text-left px-3 py-2 text-xs flex items-center gap-2.5 hover:bg-white/10 transition-colors ${status === s ? 'text-white' : 'text-gray-400'}`}
            >
              <span className={`w-2 h-2 rounded-full flex-shrink-0 ${STATUS_COLORS[s]}`} />
              {STATUS_LABELS[s]}
              {status === s && <Check className="w-3 h-3 text-purple-400 ml-auto" />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Main Component ───────────────────────────────────────────────────────────

/**
 * SessionPanel — always-visible compact bar above the tab nav in specialized trackers.
 *
 * Props:
 *   game          — full game object (for status and notes)
 *   totalPlaytime — number (seconds), derived by parent from save data
 *   onUpdateGame  — (updatedGame) => void
 *   onAddSession  — ({ id, startTime, endTime, duration }) => void — persists session to save
 */
export default function SessionPanel({ game, totalPlaytime = 0, onUpdateGame, onAddSession }) {
  const [sessionActive, setSessionActive] = useState(false);
  const [sessionDisplay, setSessionDisplay] = useState(0);
  const [notesOpen, setNotesOpen] = useState(false);
  const [notesDraft, setNotesDraft] = useState(game.notes || '');
  const sessionStartRef = useRef(null);
  const intervalRef = useRef(null);

  // Timestamp-based timer — accurate even when app is backgrounded
  useEffect(() => {
    if (sessionActive) {
      intervalRef.current = setInterval(() => {
        if (sessionStartRef.current) {
          setSessionDisplay(Math.round((Date.now() - sessionStartRef.current) / 1000));
        }
      }, 1000);
    } else {
      clearInterval(intervalRef.current);
    }
    return () => clearInterval(intervalRef.current);
  }, [sessionActive]);

  // Recalculate when tab becomes visible again after being backgrounded
  useEffect(() => {
    if (!sessionActive) return;
    const handler = () => {
      if (!document.hidden && sessionStartRef.current) {
        setSessionDisplay(Math.round((Date.now() - sessionStartRef.current) / 1000));
      }
    };
    document.addEventListener('visibilitychange', handler);
    return () => document.removeEventListener('visibilitychange', handler);
  }, [sessionActive]);

  const startSession = () => {
    sessionStartRef.current = Date.now();
    setSessionDisplay(0);
    setSessionActive(true);
  };

  const stopSession = () => {
    const endMs = Date.now();
    const startMs = sessionStartRef.current || endMs;
    const elapsed = Math.round((endMs - startMs) / 1000);
    setSessionActive(false);
    setSessionDisplay(0);
    sessionStartRef.current = null;
    if (elapsed > 0 && onAddSession) {
      onAddSession({
        id: generateId(),
        startTime: new Date(startMs).toISOString(),
        endTime: new Date(endMs).toISOString(),
        duration: elapsed,
      });
    }
  };

  const handleStatusChange = (newStatus) => {
    onUpdateGame({ ...game, status: newStatus });
  };

  const saveNotes = () => {
    onUpdateGame({ ...game, notes: notesDraft });
    setNotesOpen(false);
  };

  return (
    <div className="bg-black/30 border-b border-white/10 px-4 py-2">
      <div className="max-w-7xl mx-auto flex items-center gap-3 flex-wrap">
        {/* Session timer */}
        <div className="flex items-center gap-2">
          {sessionActive ? (
            <>
              <span className="font-mono text-green-400 text-sm animate-pulse">
                ● {formatDurationShort(sessionDisplay)}
              </span>
              <button
                onClick={stopSession}
                className="flex items-center gap-1 px-2.5 py-1 rounded-lg bg-red-800/70 hover:bg-red-700/70 text-xs transition-colors"
              >
                <Square className="w-3 h-3" /> Stop
              </button>
            </>
          ) : (
            <button
              onClick={startSession}
              className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-green-700/70 hover:bg-green-600/70 text-xs transition-colors"
            >
              <Play className="w-3 h-3" /> Start Session
            </button>
          )}
        </div>

        {/* Separator */}
        <div className="w-px h-4 bg-white/10 hidden sm:block" />

        {/* Total playtime */}
        <div className="flex items-center gap-1.5 text-xs text-gray-400">
          <Clock className="w-3.5 h-3.5" />
          <span>Total: <span className="text-gray-200 font-medium">{formatDuration(totalPlaytime + (sessionActive ? sessionDisplay : 0))}</span></span>
        </div>

        {/* Separator */}
        <div className="w-px h-4 bg-white/10 hidden sm:block" />

        {/* Status */}
        <StatusPicker status={game.status} onChange={handleStatusChange} />

        {/* Notes quick-access */}
        <div className="ml-auto relative">
          <button
            onClick={() => {
              setNotesDraft(game.notes || '');
              setNotesOpen(o => !o);
            }}
            className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs transition-colors ${
              notesOpen
                ? 'bg-purple-600/60 text-white'
                : 'bg-white/10 hover:bg-white/20 text-gray-300'
            }`}
          >
            📝 {game.notes ? 'Notes' : 'Add note'}
          </button>
          {notesOpen && (
            <div className="absolute right-0 top-full mt-1 z-30 bg-slate-800 border border-white/10 rounded-xl shadow-2xl p-3 w-72">
              <textarea
                autoFocus
                value={notesDraft}
                onChange={e => setNotesDraft(e.target.value)}
                placeholder="Where I left off, current goals…"
                className="w-full bg-black/40 border border-white/10 rounded-lg px-3 py-2 text-sm text-gray-200 resize-none focus:outline-none focus:border-purple-500/50"
                rows={4}
              />
              <div className="flex gap-2 mt-2">
                <button
                  onClick={saveNotes}
                  className="flex-1 px-3 py-1.5 bg-purple-600 hover:bg-purple-500 rounded-lg text-xs transition-colors"
                >
                  Save
                </button>
                <button
                  onClick={() => setNotesOpen(false)}
                  className="px-3 py-1.5 bg-white/10 hover:bg-white/20 rounded-lg text-xs transition-colors"
                >
                  Cancel
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
