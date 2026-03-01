import React, { useState, useCallback } from 'react';
import {
  ArrowLeft, Plus, ChevronDown, ChevronRight, CheckCircle, Circle,
  Clock, AlertTriangle, BookOpen, Map, Star, User
} from 'lucide-react';
import SessionPanel from '../shared/SessionPanel.jsx';
import { QUESTLINES, ALL_ENDINGS, CLASSES } from '../../data/citizenSleeperData.js';

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

function createCSSave(name, chosenClass) {
  // Build initial state from QUESTLINES
  const driveCompleted = {};
  const clockCompleted = {};
  QUESTLINES.forEach(q => {
    q.drives.forEach(d => { driveCompleted[d.id] = false; });
    q.clocks.forEach(c => { clockCompleted[c.id] = false; });
  });
  const endingCompleted = {};
  ALL_ENDINGS.forEach(e => { endingCompleted[e.id] = false; });

  return {
    id: generateId(),
    name,
    chosenClass: chosenClass || null,
    createdAt: new Date().toISOString(),
    driveCompleted,
    clockCompleted,
    endingCompleted,
    questlineNotes: {}, // questlineId -> string
    currentCycle: 1,
    notes: '',
  };
}

// ── Clock badge ──────────────────────────────────────────────────────────────
function ClockBadge({ clock }) {
  const isWarning = clock.description?.toLowerCase().includes('danger') ||
                    clock.description?.toLowerCase().includes('point of no return') ||
                    clock.description?.toLowerCase().includes('caution');
  return (
    <div className="flex items-start gap-2">
      <Clock className={`w-3.5 h-3.5 mt-0.5 shrink-0 ${isWarning ? 'text-yellow-400' : 'text-blue-400'}`} />
      <div>
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className="text-sm font-medium text-gray-200">{clock.name}</span>
          <span className={`text-xs px-1.5 py-0.5 rounded-full ${
            clock.type === 'cycle'
              ? 'bg-orange-900/40 text-orange-300 border border-orange-500/30'
              : 'bg-blue-900/40 text-blue-300 border border-blue-500/30'
          }`}>
            {clock.type === 'cycle' ? `⏱ Cycle (${clock.segments})` : `📶 Step (${clock.segments})`}
          </span>
          {isWarning && (
            <span className="text-xs px-1.5 py-0.5 rounded-full bg-yellow-900/40 text-yellow-300 border border-yellow-500/30 flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" /> Warning
            </span>
          )}
        </div>
        <p className="text-xs text-gray-500 mt-0.5">{clock.description}</p>
      </div>
    </div>
  );
}

// ── Questline card ────────────────────────────────────────────────────────────
function QuestlineCard({ questline, save, onUpdateSave }) {
  const [expanded, setExpanded] = useState(false);

  const allDrives = questline.drives.length;
  const completedDrives = questline.drives.filter(d => save.driveCompleted?.[d.id]).length;
  const allClocks = questline.clocks.length;
  const completedClocks = questline.clocks.filter(c => save.clockCompleted?.[c.id]).length;
  const isFullyDone = completedDrives === allDrives && allDrives > 0;

  const toggleDrive = (id) => {
    onUpdateSave(s => ({ ...s, driveCompleted: { ...s.driveCompleted, [id]: !s.driveCompleted?.[id] } }));
  };

  const toggleClock = (id) => {
    onUpdateSave(s => ({ ...s, clockCompleted: { ...s.clockCompleted, [id]: !s.clockCompleted?.[id] } }));
  };

  const updateNote = (val) => {
    onUpdateSave(s => ({ ...s, questlineNotes: { ...s.questlineNotes, [questline.id]: val } }));
  };

  return (
    <div className={`bg-black/40 rounded-xl border ${isFullyDone ? 'border-green-500/30' : 'border-white/10'} overflow-hidden`}>
      {/* Header */}
      <button
        onClick={() => setExpanded(e => !e)}
        className="w-full flex items-center gap-3 px-4 py-3.5 hover:bg-white/5 text-left"
      >
        <div className="shrink-0">
          {isFullyDone
            ? <CheckCircle className="w-5 h-5 text-green-400" />
            : <User className="w-5 h-5 text-gray-500" />
          }
        </div>
        <div className="flex-1 min-w-0">
          <div className="font-semibold text-sm text-gray-100">{questline.npc}</div>
          <div className="text-xs text-gray-500">{questline.role}</div>
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <div className="text-xs text-gray-400">
            {completedDrives}/{allDrives} drives · {completedClocks}/{allClocks} clocks
          </div>
          {expanded ? <ChevronDown className="w-4 h-4 text-gray-500" /> : <ChevronRight className="w-4 h-4 text-gray-500" />}
        </div>
      </button>

      {expanded && (
        <div className="px-4 pb-4 space-y-4 border-t border-white/5">
          {/* Description */}
          <p className="text-sm text-gray-400 pt-3">{questline.description}</p>

          {/* Warning note */}
          {questline.note && (
            <div className="flex items-start gap-2 p-3 bg-yellow-900/20 border border-yellow-500/20 rounded-lg">
              <AlertTriangle className="w-4 h-4 text-yellow-400 shrink-0 mt-0.5" />
              <p className="text-xs text-yellow-300">{questline.note}</p>
            </div>
          )}

          {/* Drives */}
          <div>
            <h4 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <Map className="w-3.5 h-3.5" /> Drives (Quests)
            </h4>
            <div className="space-y-1.5">
              {questline.drives.map(drive => (
                <button
                  key={drive.id}
                  onClick={() => toggleDrive(drive.id)}
                  className="w-full flex items-start gap-2.5 text-left hover:bg-white/5 rounded-lg px-2 py-2"
                >
                  {save.driveCompleted?.[drive.id]
                    ? <CheckCircle className="w-4 h-4 text-green-400 shrink-0 mt-0.5" />
                    : <Circle className="w-4 h-4 text-gray-600 shrink-0 mt-0.5" />
                  }
                  <div>
                    <div className={`text-sm ${save.driveCompleted?.[drive.id] ? 'line-through text-gray-500' : 'text-gray-200'}`}>
                      {drive.name}
                    </div>
                    <div className="text-xs text-gray-500">{drive.description}</div>
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* Clocks */}
          <div>
            <h4 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <Clock className="w-3.5 h-3.5" /> Clocks
            </h4>
            <div className="space-y-2">
              {questline.clocks.map(clock => (
                <button
                  key={clock.id}
                  onClick={() => toggleClock(clock.id)}
                  className={`w-full text-left p-2.5 rounded-lg border transition-colors ${
                    save.clockCompleted?.[clock.id]
                      ? 'bg-green-900/20 border-green-500/20 opacity-60'
                      : 'bg-black/20 border-white/5 hover:bg-white/5'
                  }`}
                >
                  <div className="flex items-start gap-2">
                    <div className="mt-0.5 shrink-0">
                      {save.clockCompleted?.[clock.id]
                        ? <CheckCircle className="w-4 h-4 text-green-400" />
                        : <Circle className="w-4 h-4 text-gray-600" />
                      }
                    </div>
                    <ClockBadge clock={clock} />
                  </div>
                </button>
              ))}
            </div>
          </div>

          {/* Questline endings (if any) */}
          {questline.endings && (
            <div>
              <h4 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 flex items-center gap-1.5">
                <Star className="w-3.5 h-3.5 text-yellow-400" /> Possible Endings from this Questline
              </h4>
              <ul className="space-y-1">
                {questline.endings.map((e, i) => (
                  <li key={i} className="text-xs text-yellow-300/70 flex items-start gap-1.5">
                    <span className="mt-0.5">→</span> {e}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* Achievement */}
          {questline.achievement && (
            <div className="text-xs text-purple-300/70 flex items-center gap-1.5">
              <Star className="w-3.5 h-3.5" />
              Achievement: {Array.isArray(questline.achievement) ? questline.achievement.join(', ') : questline.achievement}
            </div>
          )}

          {/* Notes */}
          <div>
            <label className="text-xs text-gray-500 block mb-1">Notes</label>
            <textarea
              rows={2}
              placeholder="Route choices, what cycle you're on, spoiler notes..."
              value={save.questlineNotes?.[questline.id] || ''}
              onChange={e => updateNote(e.target.value)}
              className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none resize-none text-gray-200 placeholder-gray-600"
            />
          </div>
        </div>
      )}
    </div>
  );
}

// ── Endings Tab ───────────────────────────────────────────────────────────────
function EndingsTab({ save, onUpdateSave }) {
  const completedCount = ALL_ENDINGS.filter(e => save.endingCompleted?.[e.id]).length;

  const toggleEnding = (id) => {
    onUpdateSave(s => ({ ...s, endingCompleted: { ...s.endingCompleted, [id]: !s.endingCompleted?.[id] } }));
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-400">Track which endings you've experienced</p>
        <span className="text-sm font-bold text-yellow-400">{completedCount}/{ALL_ENDINGS.length} seen</span>
      </div>
      {ALL_ENDINGS.map(ending => (
        <button
          key={ending.id}
          onClick={() => toggleEnding(ending.id)}
          className={`w-full text-left p-4 rounded-xl border transition-colors ${
            save.endingCompleted?.[ending.id]
              ? 'bg-green-900/20 border-green-500/30'
              : 'bg-black/40 border-white/10 hover:bg-white/5'
          }`}
        >
          <div className="flex items-start gap-3">
            <div className="mt-0.5 shrink-0">
              {save.endingCompleted?.[ending.id]
                ? <CheckCircle className="w-5 h-5 text-green-400" />
                : <Circle className="w-5 h-5 text-gray-600" />
              }
            </div>
            <div className="flex-1">
              <div className={`font-semibold text-sm ${save.endingCompleted?.[ending.id] ? 'text-green-300' : 'text-gray-100'}`}>
                {ending.name}
              </div>
              <div className="text-xs text-gray-500 mt-0.5">via {ending.source}</div>
              <div className="text-xs text-gray-400 mt-1">{ending.description}</div>
              {ending.achievement && (
                <div className="text-xs text-purple-300/70 mt-1.5 flex items-center gap-1">
                  <Star className="w-3 h-3" /> {ending.achievement}
                </div>
              )}
              {ending.exclusive && (
                <div className="text-xs text-orange-300/70 mt-1 flex items-center gap-1">
                  <AlertTriangle className="w-3 h-3" /> Exclusive — locks out other endings
                </div>
              )}
            </div>
          </div>
        </button>
      ))}
    </div>
  );
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
function OverviewTab({ save, onUpdateSave }) {
  const totalDrives = QUESTLINES.reduce((sum, q) => sum + q.drives.length, 0);
  const completedDrives = Object.values(save.driveCompleted || {}).filter(Boolean).length;
  const totalClocks = QUESTLINES.reduce((sum, q) => sum + q.clocks.length, 0);
  const completedClocks = Object.values(save.clockCompleted || {}).filter(Boolean).length;
  const completedEndings = Object.values(save.endingCompleted || {}).filter(Boolean).length;

  return (
    <div className="space-y-4">
      {/* Class */}
      {save.chosenClass && (
        <div className="bg-black/40 rounded-xl border border-purple-500/20 p-4">
          <span className="text-xs text-gray-500">Playing as: </span>
          <span className="text-sm font-semibold text-purple-300 capitalize">{save.chosenClass}</span>
        </div>
      )}

      {/* Progress stats */}
      <div className="grid grid-cols-3 gap-3">
        {[
          { label: 'Drives', value: `${completedDrives}/${totalDrives}`, pct: completedDrives/totalDrives, color: 'from-purple-600 to-purple-400' },
          { label: 'Clocks', value: `${completedClocks}/${totalClocks}`, pct: completedClocks/totalClocks, color: 'from-blue-600 to-blue-400' },
          { label: 'Endings', value: `${completedEndings}/${ALL_ENDINGS.length}`, pct: completedEndings/ALL_ENDINGS.length, color: 'from-yellow-600 to-yellow-400' },
        ].map(stat => (
          <div key={stat.label} className="bg-black/40 rounded-xl border border-white/10 p-3">
            <div className="text-xs text-gray-400 mb-1">{stat.label}</div>
            <div className="text-lg font-bold text-white mb-2">{stat.value}</div>
            <div className="h-1.5 bg-black/30 rounded-full overflow-hidden">
              <div className={`h-full bg-gradient-to-r ${stat.color} rounded-full transition-all`} style={{ width: `${(stat.pct || 0) * 100}%` }} />
            </div>
          </div>
        ))}
      </div>

      {/* Cycle tracker */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <label className="text-xs text-gray-400 block mb-2 flex items-center gap-1.5">
          <Clock className="w-3.5 h-3.5" /> Current Cycle
        </label>
        <div className="flex items-center gap-3">
          <button
            onClick={() => onUpdateSave(s => ({ ...s, currentCycle: Math.max(1, (s.currentCycle || 1) - 1) }))}
            className="w-8 h-8 rounded-lg bg-white/10 hover:bg-white/20 text-lg font-bold flex items-center justify-center"
          >−</button>
          <span className="text-2xl font-mono font-bold text-blue-400 w-12 text-center">{save.currentCycle || 1}</span>
          <button
            onClick={() => onUpdateSave(s => ({ ...s, currentCycle: (s.currentCycle || 1) + 1 }))}
            className="w-8 h-8 rounded-lg bg-white/10 hover:bg-white/20 text-lg font-bold flex items-center justify-center"
          >+</button>
          <span className="text-sm text-gray-400 ml-1">cycles survived</span>
        </div>
      </div>

      {/* Run notes */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <label className="text-xs text-gray-400 block mb-2">General Notes / Route Plan</label>
        <textarea
          rows={4}
          placeholder="Route notes, save reminders, points of no return you're watching..."
          value={save.notes || ''}
          onChange={e => onUpdateSave(s => ({ ...s, notes: e.target.value }))}
          className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none resize-none text-gray-200 placeholder-gray-600"
        />
      </div>
    </div>
  );
}

// ── Main Tracker ──────────────────────────────────────────────────────────────
const TABS = [
  { id: 'overview', label: 'Overview', icon: <BookOpen className="w-3.5 h-3.5" /> },
  { id: 'questlines', label: 'Questlines', icon: <User className="w-3.5 h-3.5" /> },
  { id: 'endings', label: 'Endings', icon: <Star className="w-3.5 h-3.5" /> },
];

export default function CitizenSleeperTracker({ game, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [selectedClass, setSelectedClass] = useState('machinist');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];
  // Migrate: add sessions/totalPlaytime if missing
  const migratedSave = currentSave ? {
    ...currentSave,
    sessions: currentSave.sessions || [],
    totalPlaytime: currentSave.totalPlaytime ?? 0,
    notes: currentSave.notes ?? '',
  } : currentSave;

  const updateCurrentSave = useCallback((updater) => {
    const updated = typeof updater === 'function' ? updater(migratedSave) : updater;
    const newSaves = saves.map(s => s.id === updated.id ? updated : s);
    onUpdateGame({ ...game, saves: newSaves });
  }, [migratedSave, saves, game, onUpdateGame]);

  const createSave = () => {
    if (!newSaveName.trim()) return;
    const save = createCSSave(newSaveName.trim(), selectedClass);
    onUpdateGame({ ...game, saves: [...saves, save], currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-indigo-950 to-black text-white">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-black/70 backdrop-blur border-b border-white/10 px-4 py-3">
        <div className="max-w-2xl mx-auto flex items-center gap-3 flex-wrap">
          <button onClick={onBack} className="p-2 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <span className="text-xl">🤖</span>
          <span className="font-bold">Citizen Sleeper</span>

          {saves.length > 1 && (
            <div className="relative ml-2">
              <button onClick={() => setShowSaveDropdown(d => !d)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm">
                {currentSave?.name} <ChevronDown className="w-3.5 h-3.5" />
              </button>
              {showSaveDropdown && (
                <div className="absolute left-0 mt-1 w-48 bg-gray-900 border border-white/20 rounded-xl shadow-xl z-20">
                  {saves.map(s => (
                    <button key={s.id}
                      onClick={() => { onUpdateGame({ ...game, currentSaveId: s.id }); setShowSaveDropdown(false); }}
                      className={`w-full text-left px-3 py-2 text-sm hover:bg-white/10 first:rounded-t-xl last:rounded-b-xl ${s.id === game.currentSaveId ? 'text-white font-medium' : 'text-gray-300'}`}
                    >{s.name}</button>
                  ))}
                </div>
              )}
            </div>
          )}

          <button onClick={() => setShowNewSave(v => !v)}
            className="ml-auto flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm">
            <Plus className="w-3.5 h-3.5" /> New Playthrough
          </button>
        </div>
      </div>

      {/* Session Panel */}
      <SessionPanel
        game={game}
        totalPlaytime={migratedSave?.totalPlaytime || 0}
        onUpdateGame={onUpdateGame}
        onAddSession={(session) => updateCurrentSave(s => ({
          ...s,
          sessions: [...(s.sessions || []), session],
          totalPlaytime: (s.totalPlaytime || 0) + session.duration,
          lastPlayedAt: session.endTime,
        }))}
      />

      <div className="max-w-2xl mx-auto px-4 py-4 space-y-4">
        {/* New save form */}
        {showNewSave && (
          <div className="bg-black/40 rounded-xl border border-white/10 p-4 space-y-3">
            <h3 className="font-semibold text-sm">New Playthrough</h3>
            <input
              type="text" placeholder="Name (e.g. 'First Playthrough', 'All Endings Run')"
              value={newSaveName} onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && createSave()}
              className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none"
              autoFocus
            />
            <div>
              <label className="text-xs text-gray-400 block mb-1.5">Class</label>
              <div className="flex gap-2 flex-wrap">
                {['machinist', 'operator', 'scholar'].map(cls => (
                  <button key={cls}
                    onClick={() => setSelectedClass(cls)}
                    className={`px-3 py-1.5 rounded-lg text-sm capitalize border ${selectedClass === cls ? 'bg-indigo-600 border-indigo-500 text-white' : 'bg-black/30 border-white/10 text-gray-400 hover:text-white'}`}
                  >{cls}</button>
                ))}
              </div>
            </div>
            <div className="flex gap-2">
              <button onClick={createSave} className="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded-lg text-sm font-medium">Create</button>
              <button onClick={() => setShowNewSave(false)} className="px-3 py-2 bg-white/10 rounded-lg text-sm">Cancel</button>
            </div>
          </div>
        )}

        {!currentSave ? (
          <div className="text-center py-20 text-gray-500">
            <div className="text-5xl mb-4">🤖</div>
            <div className="text-lg mb-2 text-gray-300">No playthroughs yet</div>
            <p className="text-sm mb-4">Track all 12 questlines, 50+ clocks, and 10 endings</p>
            <button onClick={() => setShowNewSave(true)} className="px-4 py-2 bg-indigo-600 rounded-lg text-sm">Start Tracking</button>
          </div>
        ) : (
          <>
            {/* Tabs */}
            <div className="flex gap-1 border-b border-white/10 pb-1">
              {TABS.map(tab => (
                <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-1.5 px-3 py-2 rounded-t-lg text-sm font-medium transition-colors ${activeTab === tab.id ? 'text-white bg-white/10' : 'text-gray-400 hover:text-white hover:bg-white/5'}`}>
                  {tab.icon}{tab.label}
                </button>
              ))}
            </div>

            {activeTab === 'overview' && <OverviewTab save={currentSave} onUpdateSave={updateCurrentSave} />}
            {activeTab === 'questlines' && (
              <div className="space-y-3">
                <p className="text-xs text-gray-500">12 NPCs · Click any questline to expand clocks, drives, and notes</p>
                {QUESTLINES.map(q => (
                  <QuestlineCard key={q.id} questline={q} save={currentSave} onUpdateSave={updateCurrentSave} />
                ))}
              </div>
            )}
            {activeTab === 'endings' && <EndingsTab save={currentSave} onUpdateSave={updateCurrentSave} />}
          </>
        )}
      </div>
    </div>
  );
}
