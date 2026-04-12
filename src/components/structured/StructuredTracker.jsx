import React, { useState, useCallback, useMemo } from 'react';
import {
  ArrowLeft, Plus, ChevronDown, ChevronRight, CheckCircle, Circle,
  Trash2, Trophy, AlertTriangle, Eye, EyeOff, Minus,
} from 'lucide-react';
import {
  createStructuredSave, getItemState, setItemState,
} from '../../utils/structuredFactory.js';
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

// Compute fractional progress for a single item based on its category type
// and current save state. 1.0 = fully done, 0.0 = untouched.
function itemProgress(item, categoryType, state) {
  if (categoryType === 'leveled') {
    const max = item.maxRank ?? 0;
    if (max <= 0) return 0;
    return Math.max(0, Math.min(1, (state.rank ?? 0) / max));
  }
  return state.done ? 1 : 0;
}

// Aggregate progress across a category: average item progress.
function categoryProgress(category, save) {
  const items = category.items || [];
  if (items.length === 0) return { pct: 0, done: 0, total: 0 };
  let sum = 0;
  let doneCount = 0;
  for (const item of items) {
    const s = getItemState(save, item.id);
    const p = itemProgress(item, category.type, s);
    sum += p;
    if (p >= 1) doneCount += 1;
  }
  return {
    pct: Math.round((sum / items.length) * 100),
    done: doneCount,
    total: items.length,
  };
}

// Overall progress across all categories — each item weighted equally.
function overallProgress(categories, save) {
  let sum = 0;
  let count = 0;
  for (const c of categories) {
    for (const item of c.items || []) {
      const s = getItemState(save, item.id);
      sum += itemProgress(item, c.type, s);
      count += 1;
    }
  }
  return {
    pct: count > 0 ? Math.round((sum / count) * 100) : 0,
    items: count,
  };
}

// Decide whether to mask an item's name/description behind "???".
function isHidden(item, state) {
  if (!item.hideUntilDiscovered) return false;
  if (state.revealed) return false;
  if (state.done) return false;
  if ((state.rank ?? 0) > 0) return false;
  return true;
}

// ─── Item renderers, one per category type ───────────────────────────────────

function ChecklistItemRow({ item, state, onToggle, onReveal }) {
  const hidden = isHidden(item, state);
  const done = state.done;
  return (
    <div className="group flex items-start gap-3 px-4 py-3 hover:bg-white/5 transition-colors">
      <button
        onClick={() => onToggle(item.id)}
        className="mt-0.5 shrink-0"
        aria-label={done ? 'Mark not done' : 'Mark done'}
      >
        {done
          ? <CheckCircle className="w-5 h-5 text-green-400" />
          : <Circle className="w-5 h-5 text-gray-600 group-hover:text-gray-400" />
        }
      </button>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className={`text-sm ${done ? 'line-through text-gray-500' : hidden ? 'italic text-gray-500' : 'text-gray-200'}`}>
            {hidden ? '???' : item.name}
          </span>
          {item.missable && !hidden && (
            <span
              title="Missable"
              className="flex items-center gap-0.5 text-[10px] text-yellow-400/90 bg-yellow-900/30 border border-yellow-700/40 rounded px-1.5 py-0.5"
            >
              <AlertTriangle className="w-2.5 h-2.5" /> missable
            </span>
          )}
          {!hidden && item.tags?.map(t => (
            <span key={t} className="text-[10px] text-slate-400 bg-slate-800/60 rounded px-1.5 py-0.5">
              {t}
            </span>
          ))}
        </div>
        {!hidden && (item.description || item.location || item.source) && (
          <div className="text-xs text-gray-500 mt-0.5 space-y-0.5">
            {item.description && <div>{item.description}</div>}
            {item.location && <div><span className="text-gray-600">Location:</span> {item.location}</div>}
            {item.source && <div><span className="text-gray-600">Source:</span> {item.source}</div>}
          </div>
        )}
        {!hidden && item.metadata && Object.keys(item.metadata).length > 0 && (
          <div className="text-[11px] text-gray-500 mt-1 flex flex-wrap gap-x-3 gap-y-0.5">
            {Object.entries(item.metadata).map(([k, v]) => (
              <span key={k}>
                <span className="text-gray-600">{k}:</span> {String(v)}
              </span>
            ))}
          </div>
        )}
        {hidden && (
          <button
            onClick={() => onReveal(item.id)}
            className="mt-1 flex items-center gap-1 text-[11px] text-gray-500 hover:text-gray-300 transition-colors"
          >
            <Eye className="w-3 h-3" /> reveal (spoiler)
          </button>
        )}
      </div>
    </div>
  );
}

function LeveledItemRow({ item, state, onSetRank, onReveal }) {
  const hidden = isHidden(item, state);
  const rank = state.rank ?? 0;
  const max = item.maxRank ?? 0;
  const rankLabel = item.rankNames?.[rank] ?? `Rank ${rank}`;
  return (
    <div className="px-4 py-3 hover:bg-white/5 transition-colors">
      <div className="flex items-start gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className={`text-sm ${hidden ? 'italic text-gray-500' : 'text-gray-200'}`}>
              {hidden ? '???' : item.name}
            </span>
            {!hidden && (
              <span className="text-xs text-purple-300 bg-purple-900/30 border border-purple-700/40 rounded px-1.5 py-0.5">
                {rankLabel}
              </span>
            )}
            {item.missable && !hidden && (
              <span className="flex items-center gap-0.5 text-[10px] text-yellow-400/90 bg-yellow-900/30 border border-yellow-700/40 rounded px-1.5 py-0.5">
                <AlertTriangle className="w-2.5 h-2.5" /> missable
              </span>
            )}
          </div>
          {!hidden && item.description && (
            <div className="text-xs text-gray-500 mt-0.5">{item.description}</div>
          )}
          {!hidden && item.location && (
            <div className="text-xs text-gray-500 mt-0.5">
              <span className="text-gray-600">Location:</span> {item.location}
            </div>
          )}
          {hidden && (
            <button
              onClick={() => onReveal(item.id)}
              className="mt-1 flex items-center gap-1 text-[11px] text-gray-500 hover:text-gray-300 transition-colors"
            >
              <Eye className="w-3 h-3" /> reveal (spoiler)
            </button>
          )}
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          <button
            onClick={() => onSetRank(item.id, Math.max(0, rank - 1))}
            disabled={rank <= 0}
            className="w-7 h-7 rounded bg-white/5 hover:bg-white/10 disabled:opacity-30 disabled:cursor-not-allowed flex items-center justify-center text-gray-400"
            aria-label="Decrease rank"
          >
            <Minus className="w-3.5 h-3.5" />
          </button>
          <span className="font-mono text-xs text-gray-400 w-10 text-center">
            {rank} / {max}
          </span>
          <button
            onClick={() => onSetRank(item.id, Math.min(max, rank + 1))}
            disabled={rank >= max}
            className="w-7 h-7 rounded bg-purple-700/40 hover:bg-purple-700/70 disabled:opacity-30 disabled:cursor-not-allowed flex items-center justify-center text-purple-200"
            aria-label="Increase rank"
          >
            <Plus className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  );
}

function SequenceStep({ item, state, index, isLast, onToggle, onReveal }) {
  const hidden = isHidden(item, state);
  const done = state.done;
  return (
    <div className="flex gap-3 px-4 py-3 hover:bg-white/5 transition-colors relative">
      {/* connector line */}
      {!isLast && (
        <div className="absolute left-[30px] top-[42px] bottom-0 w-px bg-white/10" aria-hidden />
      )}
      <button
        onClick={() => onToggle(item.id)}
        className={`relative z-10 shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-xs font-medium transition-colors ${
          done
            ? 'bg-green-600/80 text-white'
            : 'bg-slate-800 border border-white/10 text-gray-400 hover:border-gray-500'
        }`}
        aria-label={done ? 'Mark not done' : 'Mark done'}
      >
        {done ? <CheckCircle className="w-4 h-4" /> : (index + 1)}
      </button>
      <div className="flex-1 min-w-0 pt-0.5">
        <div className="flex items-center gap-2 flex-wrap">
          <span className={`text-sm ${done ? 'text-gray-500' : hidden ? 'italic text-gray-500' : 'text-gray-200'}`}>
            {hidden ? '???' : item.name}
          </span>
          {!hidden && item.tags?.map(t => (
            <span key={t} className="text-[10px] text-slate-400 bg-slate-800/60 rounded px-1.5 py-0.5">
              {t}
            </span>
          ))}
        </div>
        {!hidden && item.description && (
          <div className="text-xs text-gray-500 mt-0.5">{item.description}</div>
        )}
        {hidden && (
          <button
            onClick={() => onReveal(item.id)}
            className="mt-1 flex items-center gap-1 text-[11px] text-gray-500 hover:text-gray-300 transition-colors"
          >
            <Eye className="w-3 h-3" /> reveal (spoiler)
          </button>
        )}
      </div>
    </div>
  );
}

// ─── Category section ────────────────────────────────────────────────────────

function CategorySection({ category, save, collapsed, onToggleCollapse, onToggleItem, onSetRank, onRevealItem }) {
  const progress = categoryProgress(category, save);
  const { type } = category;

  return (
    <div className="bg-black/40 rounded-xl border border-white/10 overflow-hidden">
      <button
        onClick={() => onToggleCollapse(category.id)}
        className="w-full px-4 py-3 border-b border-white/10 flex items-center justify-between hover:bg-white/5 transition-colors text-left"
      >
        <div className="flex items-center gap-2 min-w-0">
          {collapsed
            ? <ChevronRight className="w-4 h-4 text-gray-500 shrink-0" />
            : <ChevronDown className="w-4 h-4 text-gray-500 shrink-0" />}
          <h3 className="font-semibold text-sm text-gray-200 truncate">{category.name}</h3>
          <span className="text-[11px] text-gray-600 uppercase tracking-wider shrink-0">{type}</span>
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <span className="text-xs text-gray-400 font-mono">
            {progress.done} / {progress.total}
          </span>
          <div className="w-16 h-1.5 bg-black/40 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-purple-600 to-purple-400 transition-all duration-300"
              style={{ width: `${progress.pct}%` }}
            />
          </div>
        </div>
      </button>

      {!collapsed && (
        <>
          {category.description && (
            <div className="px-4 py-2.5 text-xs text-gray-500 border-b border-white/5 bg-white/[0.02]">
              {category.description}
            </div>
          )}
          <div className="divide-y divide-white/5">
            {type === 'leveled'
              ? category.items.map(item => (
                  <LeveledItemRow
                    key={item.id}
                    item={item}
                    state={getItemState(save, item.id)}
                    onSetRank={onSetRank}
                    onReveal={onRevealItem}
                  />
                ))
              : type === 'sequence'
              ? category.items.map((item, idx) => (
                  <SequenceStep
                    key={item.id}
                    item={item}
                    state={getItemState(save, item.id)}
                    index={idx}
                    isLast={idx === category.items.length - 1}
                    onToggle={onToggleItem}
                    onReveal={onRevealItem}
                  />
                ))
              : /* checklist | collectibles */
                category.items.map(item => (
                  <ChecklistItemRow
                    key={item.id}
                    item={item}
                    state={getItemState(save, item.id)}
                    onToggle={onToggleItem}
                    onReveal={onRevealItem}
                  />
                ))}
          </div>
        </>
      )}
    </div>
  );
}

// ─── Main component ──────────────────────────────────────────────────────────

export default function StructuredTracker({ game, config, onBack, onUpdateGame }) {
  // Schema source: per-game AI-generated data wins, else config, else empty.
  // In Phase 2 we only exercise the config path; Phase 3 will populate game.structuredData.
  const schema = useMemo(
    () => game?.structuredData || config?.structuredData || null,
    [game?.structuredData, config?.structuredData]
  );

  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);
  const [collapsedCategories, setCollapsedCategories] = useState(() => new Set());
  const [confirmDeleteSessionId, setConfirmDeleteSessionId] = useState(null);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  const updateCurrentSave = useCallback((updater) => {
    const updated = typeof updater === 'function' ? updater(currentSave) : updater;
    const newSaves = saves.map(s => s.id === updated.id ? updated : s);
    onUpdateGame({ ...game, saves: newSaves });
  }, [currentSave, saves, game, onUpdateGame]);

  const createSave = () => {
    if (!newSaveName.trim()) return;
    const save = createStructuredSave(newSaveName.trim());
    onUpdateGame({ ...game, saves: [...saves, save], currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  const deleteSave = (saveId) => {
    const remaining = saves.filter(s => s.id !== saveId);
    const nextId = remaining.length > 0
      ? (saveId === game.currentSaveId ? remaining[0].id : game.currentSaveId)
      : null;
    onUpdateGame({ ...game, saves: remaining, currentSaveId: nextId });
    setShowSaveDropdown(false);
  };

  const toggleItem = useCallback((itemId) => {
    updateCurrentSave(s => {
      const prev = getItemState(s, itemId);
      return setItemState(s, itemId, { done: !prev.done });
    });
  }, [updateCurrentSave]);

  const setRank = useCallback((itemId, rank) => {
    updateCurrentSave(s => setItemState(s, itemId, { rank }));
  }, [updateCurrentSave]);

  const revealItem = useCallback((itemId) => {
    updateCurrentSave(s => setItemState(s, itemId, { revealed: true }));
  }, [updateCurrentSave]);

  const toggleCollapse = useCallback((categoryId) => {
    setCollapsedCategories(prev => {
      const next = new Set(prev);
      if (next.has(categoryId)) next.delete(categoryId);
      else next.add(categoryId);
      return next;
    });
  }, []);

  const deleteSession = (sessionId) => {
    const session = (currentSave?.sessions || []).find(s => s.id === sessionId);
    updateCurrentSave(s => ({
      ...s,
      sessions: s.sessions.filter(s2 => s2.id !== sessionId),
      totalPlaytime: Math.max(0, (s.totalPlaytime || 0) - (session?.duration || 0)),
    }));
    setConfirmDeleteSessionId(null);
  };

  const markCleared = () => {
    const now = new Date();
    const updates = {
      ...game,
      clears: [...(game.clears || []), { id: generateId(), clearedAt: now.toISOString() }],
    };
    if (!(game.playPeriods || []).length) {
      updates.playPeriods = [{
        id: generateId(),
        startYear: now.getFullYear(), startMonth: null,
        endYear: now.getFullYear(), endMonth: now.getMonth() + 1,
        ongoing: false,
        platform: game.platforms?.[0] || null,
        note: '',
      }];
    }
    onUpdateGame(updates);
  };

  const clearCount = (game.clears || []).length;

  // ─── Early returns ─────────────────────────────────────────────────────────

  if (!schema) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-black text-white flex flex-col items-center justify-center gap-4 p-4">
        <div className="text-5xl">📋</div>
        <h2 className="text-xl font-bold">No tracker data yet</h2>
        <p className="text-gray-400 text-sm text-center max-w-sm">
          This game doesn't have any structured tracker data. Generating tracker data automatically is coming in Phase 3.
        </p>
        <button onClick={onBack} className="px-4 py-2 bg-white/10 hover:bg-white/20 rounded-lg text-sm transition-colors">
          Back
        </button>
      </div>
    );
  }

  if (!currentSave && saves.length === 0) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-black text-white flex flex-col items-center justify-center gap-4 p-4">
        <div className="text-5xl">{config?.icon || '📋'}</div>
        <h2 className="text-xl font-bold">{config?.name || game.name}</h2>
        {schema.completionNotes && (
          <p className="text-yellow-400/80 text-xs text-center max-w-sm">{schema.completionNotes}</p>
        )}
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
        <button onClick={onBack} className="text-gray-500 hover:text-gray-300 text-xs transition-colors">
          ← Back
        </button>
      </div>
    );
  }

  const overall = overallProgress(schema.categories || [], currentSave);
  const anyHidden = (schema.categories || []).some(c =>
    (c.items || []).some(i => i.hideUntilDiscovered)
  );
  const hiddenRevealedCount = (schema.categories || []).reduce((acc, c) => {
    for (const item of c.items || []) {
      if (item.hideUntilDiscovered) {
        const s = getItemState(currentSave, item.id);
        if (s.revealed) acc += 1;
      }
    }
    return acc;
  }, 0);
  const unhideAll = () => {
    updateCurrentSave(s => {
      let next = s;
      for (const c of schema.categories || []) {
        for (const item of c.items || []) {
          if (item.hideUntilDiscovered) {
            next = setItemState(next, item.id, { revealed: true });
          }
        }
      }
      return next;
    });
  };
  const rehideAll = () => {
    updateCurrentSave(s => {
      let next = s;
      for (const c of schema.categories || []) {
        for (const item of c.items || []) {
          if (item.hideUntilDiscovered) {
            next = setItemState(next, item.id, { revealed: false });
          }
        }
      }
      return next;
    });
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-900 to-black text-white">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-black/60 backdrop-blur border-b border-white/10 px-4 py-3">
        <div className="max-w-2xl mx-auto flex items-center gap-3 flex-wrap">
          <button onClick={onBack} className="p-2 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white">
            <ArrowLeft className="w-5 h-5" />
          </button>
          {config?.icon && <span className="text-xl">{config.icon}</span>}
          <span className="font-bold">{config?.name || game.name}</span>

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

      {/* Shared session panel */}
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

        {/* Completion notes */}
        {schema.completionNotes && (
          <div className="text-yellow-400/70 text-xs bg-yellow-900/10 border border-yellow-500/20 rounded-lg p-3">
            ⚠️ {schema.completionNotes}
          </div>
        )}

        {/* Overall progress */}
        <div className="bg-black/40 rounded-xl border border-white/10 p-4 space-y-3">
          <div>
            <div className="flex justify-between text-sm mb-1.5">
              <span className="text-gray-300">Overall — {overall.items} items tracked</span>
              <span className="font-bold text-white">{overall.pct}%</span>
            </div>
            <div className="h-2.5 bg-black/40 rounded-full overflow-hidden">
              <div
                className="h-full bg-gradient-to-r from-purple-600 to-purple-400 rounded-full transition-all duration-500"
                style={{ width: `${overall.pct}%` }}
              />
            </div>
          </div>

          <div className="flex items-center justify-between flex-wrap gap-2">
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

            {anyHidden && (
              <button
                onClick={hiddenRevealedCount > 0 ? rehideAll : unhideAll}
                className="flex items-center gap-1.5 text-xs text-gray-500 hover:text-gray-300 transition-colors"
                title={hiddenRevealedCount > 0 ? 'Rehide all revealed spoilers' : 'Reveal all hidden items'}
              >
                {hiddenRevealedCount > 0
                  ? <><EyeOff className="w-3.5 h-3.5" /> rehide all spoilers</>
                  : <><Eye className="w-3.5 h-3.5" /> reveal all spoilers</>}
              </button>
            )}
          </div>

          {(schema.estimatedHours || schema.tags?.length) && (
            <div className="flex items-center gap-3 text-xs text-gray-500 flex-wrap pt-1 border-t border-white/5">
              {schema.estimatedHours && <span>~{schema.estimatedHours}h</span>}
              {schema.tags?.map(t => (
                <span key={t} className="text-slate-400 bg-slate-800/60 rounded px-1.5 py-0.5">{t}</span>
              ))}
            </div>
          )}
        </div>

        {/* Categories */}
        {(schema.categories || []).map(category => (
          <CategorySection
            key={category.id}
            category={category}
            save={currentSave}
            collapsed={collapsedCategories.has(category.id)}
            onToggleCollapse={toggleCollapse}
            onToggleItem={toggleItem}
            onSetRank={setRank}
            onRevealItem={revealItem}
          />
        ))}

        {/* Session log */}
        {(currentSave?.sessions?.length > 0) && (
          <div className="bg-black/40 rounded-xl border border-white/10 p-4">
            <h3 className="font-semibold text-sm text-gray-300 uppercase tracking-wider mb-3">Session Log</h3>
            <div className="space-y-2">
              {[...(currentSave.sessions || [])].reverse().map(session => (
                <div key={session.id} className="flex items-center justify-between gap-2 text-sm group">
                  <div className="min-w-0">
                    <span className="text-gray-300">{new Date(session.startTime).toLocaleDateString()}</span>
                    {session.notes && <span className="text-gray-500 ml-2">— {session.notes}</span>}
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className="font-mono text-gray-400">{formatTime(session.duration)}</span>
                    {confirmDeleteSessionId === session.id ? (
                      <span className="flex items-center gap-1">
                        <span className="text-xs text-gray-500">Delete?</span>
                        <button onClick={() => deleteSession(session.id)} className="text-xs text-red-400 hover:text-red-300 font-medium transition-colors">Yes</button>
                        <button onClick={() => setConfirmDeleteSessionId(null)} className="text-xs text-gray-600 hover:text-gray-400 transition-colors">Cancel</button>
                      </span>
                    ) : (
                      <button
                        onClick={() => setConfirmDeleteSessionId(session.id)}
                        className="text-gray-700 hover:text-red-400 transition-colors opacity-0 group-hover:opacity-100"
                        title="Delete session"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Attribution sources */}
        {schema.sources?.length > 0 && (
          <div className="text-[10px] text-gray-600 text-center pt-2">
            Tracker data: {schema.sources.map((src, i) => (
              <span key={i}>
                {i > 0 && ' · '}
                {src.url
                  ? <a href={src.url} target="_blank" rel="noopener noreferrer" className="underline hover:text-gray-400">{src.title || src.url}</a>
                  : src.title || src.type}
                {src.license && <span className="text-gray-700"> ({src.license})</span>}
              </span>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
