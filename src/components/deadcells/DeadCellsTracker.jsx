import React, { useState, useCallback } from 'react';
import {
  ArrowLeft, CheckCircle, Circle, ChevronDown, ChevronRight,
  Shield, Skull, Map, Zap, Info
} from 'lucide-react';
import SessionPanel from '../shared/SessionPanel.jsx';
import { BOSS_CELLS, RUNES, BOSSES, BIOMES, SECTIONS } from '../../data/deadCellsData.js';

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

const DLC_COLORS = {
  null: '',
  'Rise of the Giant':     'text-emerald-400',
  'The Bad Seed':          'text-green-400',
  'Fatal Falls':           'text-amber-400',
  'The Queen and the Sea': 'text-cyan-400',
  'Return to Castlevania': 'text-purple-400',
};

const DLC_BADGES = {
  'Rise of the Giant':     { label: 'RotG', bg: 'bg-emerald-900/40 border-emerald-500/30 text-emerald-300' },
  'The Bad Seed':          { label: 'Bad Seed', bg: 'bg-green-900/40 border-green-500/30 text-green-300' },
  'Fatal Falls':           { label: 'Fatal Falls', bg: 'bg-amber-900/40 border-amber-500/30 text-amber-300' },
  'The Queen and the Sea': { label: 'Queen & Sea', bg: 'bg-cyan-900/40 border-cyan-500/30 text-cyan-300' },
  'Return to Castlevania': { label: 'Castlevania', bg: 'bg-purple-900/40 border-purple-500/30 text-purple-300' },
};

function DlcBadge({ dlc }) {
  if (!dlc) return null;
  const b = DLC_BADGES[dlc];
  return (
    <span className={`text-xs px-1.5 py-0.5 rounded border ${b.bg} shrink-0`}>{b.label}</span>
  );
}

function createDCSave(name) {
  const bscEarned = {};
  BOSS_CELLS.forEach(c => { bscEarned[c.id] = false; });
  const runesFound = {};
  RUNES.forEach(r => { runesFound[r.id] = false; });
  const bossesDefeated = {};
  BOSSES.forEach(b => { bossesDefeated[b.id] = false; });
  const biomesVisited = {};
  BIOMES.forEach(b => { biomesVisited[b.id] = false; });

  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    bscEarned,
    runesFound,
    bossesDefeated,
    biomesVisited,
    notes: '',
    sessions: [],
    totalPlaytime: 0,
  };
}

// ── Boss Cell display ─────────────────────────────────────────────────────────
function BossCellRow({ save, onUpdateSave }) {
  const earned = BOSS_CELLS.filter(c => save.bscEarned?.[c.id]).length;

  const toggle = (id) => {
    onUpdateSave(s => ({ ...s, bscEarned: { ...s.bscEarned, [id]: !s.bscEarned?.[id] } }));
  };

  return (
    <div className="bg-black/40 rounded-xl border border-white/10 p-4">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-semibold text-gray-200 flex items-center gap-1.5">
          <Shield className="w-4 h-4 text-red-400" /> Boss Stem Cells
        </h3>
        <span className="text-sm font-bold text-red-400">{earned} / {BOSS_CELLS.length}</span>
      </div>
      <div className="flex gap-2 mb-3">
        {BOSS_CELLS.map((cell) => {
          const isEarned = save.bscEarned?.[cell.id];
          return (
            <button
              key={cell.id}
              onClick={() => toggle(cell.id)}
              title={cell.unlockCondition}
              className={`flex-1 h-12 rounded-lg border-2 font-bold text-lg transition-all ${
                isEarned
                  ? 'bg-red-600 border-red-400 text-white shadow-lg shadow-red-900/50'
                  : 'bg-black/30 border-white/20 text-gray-600 hover:border-red-500/50 hover:text-gray-400'
              }`}
            >
              {cell.number}
            </button>
          );
        })}
      </div>
      {earned > 0 && earned < 5 && (
        <p className="text-xs text-gray-500">
          Next: {BOSS_CELLS[earned]?.unlockCondition}
        </p>
      )}
      {earned === 5 && (
        <p className="text-xs text-emerald-400">All Boss Stem Cells earned — true ending unlocked!</p>
      )}
      {earned === 0 && (
        <p className="text-xs text-gray-600">Beat any final boss on 0 BSC to earn your first cell.</p>
      )}
    </div>
  );
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
function OverviewTab({ save, onUpdateSave }) {
  const bscEarned = BOSS_CELLS.filter(c => save.bscEarned?.[c.id]).length;
  const runesFound = RUNES.filter(r => save.runesFound?.[r.id]).length;
  const bossesDefeated = BOSSES.filter(b => save.bossesDefeated?.[b.id]).length;
  const biomesVisited = BIOMES.filter(b => save.biomesVisited?.[b.id]).length;

  return (
    <div className="space-y-4">
      <BossCellRow save={save} onUpdateSave={onUpdateSave} />

      {/* Stats grid */}
      <div className="grid grid-cols-2 gap-3">
        {[
          { label: 'Runes', value: `${runesFound}/${RUNES.length}`, pct: runesFound / RUNES.length, color: 'from-yellow-600 to-yellow-400' },
          { label: 'Bosses', value: `${bossesDefeated}/${BOSSES.length}`, pct: bossesDefeated / BOSSES.length, color: 'from-red-600 to-red-400' },
          { label: 'Biomes', value: `${biomesVisited}/${BIOMES.length}`, pct: biomesVisited / BIOMES.length, color: 'from-blue-600 to-blue-400' },
          { label: 'Boss Cells', value: `${bscEarned}/5`, pct: bscEarned / 5, color: 'from-red-700 to-red-500' },
        ].map(stat => (
          <div key={stat.label} className="bg-black/40 rounded-xl border border-white/10 p-3">
            <div className="text-xs text-gray-400 mb-1">{stat.label}</div>
            <div className="text-lg font-bold text-white mb-2">{stat.value}</div>
            <div className="h-1.5 bg-black/30 rounded-full overflow-hidden">
              <div
                className={`h-full bg-gradient-to-r ${stat.color} rounded-full transition-all`}
                style={{ width: `${(stat.pct || 0) * 100}%` }}
              />
            </div>
          </div>
        ))}
      </div>

      {/* Notes */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <label className="text-xs text-gray-400 block mb-2">Run Notes</label>
        <textarea
          rows={4}
          placeholder="Build notes, BSC goals, routes you're trying, blueprints to hunt..."
          value={save.notes || ''}
          onChange={e => onUpdateSave(s => ({ ...s, notes: e.target.value }))}
          className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none resize-none text-gray-200 placeholder-gray-600"
        />
      </div>
    </div>
  );
}

// ── Runes Tab ─────────────────────────────────────────────────────────────────
function RunesTab({ save, onUpdateSave }) {
  const found = RUNES.filter(r => save.runesFound?.[r.id]).length;

  const toggle = (id) => {
    onUpdateSave(s => ({ ...s, runesFound: { ...s.runesFound, [id]: !s.runesFound?.[id] } }));
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-400">Permanent movement abilities — carry across all runs</p>
        <span className="text-sm font-bold text-yellow-400">{found}/{RUNES.length}</span>
      </div>
      {RUNES.map(rune => {
        const isFound = save.runesFound?.[rune.id];
        return (
          <button
            key={rune.id}
            onClick={() => toggle(rune.id)}
            className={`w-full text-left p-4 rounded-xl border transition-colors ${
              isFound
                ? 'bg-yellow-900/20 border-yellow-500/30'
                : 'bg-black/40 border-white/10 hover:bg-white/5'
            }`}
          >
            <div className="flex items-start gap-3">
              <div className="mt-0.5 shrink-0">
                {isFound
                  ? <CheckCircle className="w-5 h-5 text-yellow-400" />
                  : <Circle className="w-5 h-5 text-gray-600" />
                }
              </div>
              <div className="flex-1 min-w-0">
                <div className={`font-semibold text-sm ${isFound ? 'text-yellow-300' : 'text-gray-100'}`}>
                  {rune.name}
                </div>
                <div className="text-xs text-gray-500 mt-0.5">
                  📍 {rune.location} · dropped by {rune.guardian}
                </div>
                <div className="text-xs text-gray-400 mt-1">{rune.unlocks}</div>
              </div>
            </div>
          </button>
        );
      })}
    </div>
  );
}

// ── Bosses Tab ────────────────────────────────────────────────────────────────
function BossesTab({ save, onUpdateSave }) {
  const defeated = BOSSES.filter(b => save.bossesDefeated?.[b.id]).length;
  const tiers = [1, 2, 3, 4, 5];
  const tierLabels = { 1: 'Boss 1', 2: 'Boss 2', 3: 'Boss 3', 4: 'Final Boss', 5: 'Secret Boss' };

  const toggle = (id) => {
    onUpdateSave(s => ({ ...s, bossesDefeated: { ...s.bossesDefeated, [id]: !s.bossesDefeated?.[id] } }));
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-400">Track first defeats across all routes and DLC</p>
        <span className="text-sm font-bold text-red-400">{defeated}/{BOSSES.length}</span>
      </div>
      {tiers.map(tier => {
        const tierBosses = BOSSES.filter(b => b.tier === tier);
        if (!tierBosses.length) return null;
        return (
          <div key={tier}>
            <h4 className="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <Skull className="w-3.5 h-3.5" /> {tierLabels[tier]}
            </h4>
            <div className="space-y-2">
              {tierBosses.map(boss => {
                const isDefeated = save.bossesDefeated?.[boss.id];
                return (
                  <button
                    key={boss.id}
                    onClick={() => toggle(boss.id)}
                    className={`w-full text-left p-3 rounded-xl border transition-colors ${
                      isDefeated
                        ? 'bg-red-900/20 border-red-500/30'
                        : 'bg-black/40 border-white/10 hover:bg-white/5'
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      <div className="mt-0.5 shrink-0">
                        {isDefeated
                          ? <CheckCircle className="w-4 h-4 text-red-400" />
                          : <Circle className="w-4 h-4 text-gray-600" />
                        }
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className={`font-semibold text-sm ${isDefeated ? 'text-red-300' : 'text-gray-100'}`}>
                            {boss.name}
                          </span>
                          <DlcBadge dlc={boss.dlc} />
                        </div>
                        <div className="text-xs text-gray-500 mt-0.5">📍 {boss.location}</div>
                        {boss.note && <div className="text-xs text-gray-400 mt-1">{boss.note}</div>}
                      </div>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── Biomes Tab ────────────────────────────────────────────────────────────────
function BiomesTab({ save, onUpdateSave }) {
  const [expanded, setExpanded] = useState(() => {
    const obj = {};
    SECTIONS.forEach(s => { obj[s] = true; });
    return obj;
  });

  const visited = BIOMES.filter(b => save.biomesVisited?.[b.id]).length;

  const toggle = (id) => {
    onUpdateSave(s => ({ ...s, biomesVisited: { ...s.biomesVisited, [id]: !s.biomesVisited?.[id] } }));
  };

  const toggleSection = (section) => {
    setExpanded(e => ({ ...e, [section]: !e[section] }));
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-gray-400">Track first visits across all routes and DLC</p>
        <span className="text-sm font-bold text-blue-400">{visited}/{BIOMES.length}</span>
      </div>
      {SECTIONS.map(section => {
        const sectionBiomes = BIOMES.filter(b => b.section === section);
        if (!sectionBiomes.length) return null;
        const sectionVisited = sectionBiomes.filter(b => save.biomesVisited?.[b.id]).length;
        const isBossSection = section.startsWith('Boss') || section === 'Final';

        return (
          <div key={section} className="bg-black/40 rounded-xl border border-white/10 overflow-hidden">
            <button
              onClick={() => toggleSection(section)}
              className="w-full flex items-center gap-2 px-4 py-3 hover:bg-white/5 text-left"
            >
              {isBossSection
                ? <Skull className="w-3.5 h-3.5 text-red-400 shrink-0" />
                : <Map className="w-3.5 h-3.5 text-blue-400 shrink-0" />
              }
              <span className={`font-semibold text-sm flex-1 ${isBossSection ? 'text-red-300' : 'text-gray-200'}`}>
                {section}
              </span>
              <span className="text-xs text-gray-500">{sectionVisited}/{sectionBiomes.length}</span>
              {expanded[section]
                ? <ChevronDown className="w-4 h-4 text-gray-600" />
                : <ChevronRight className="w-4 h-4 text-gray-600" />
              }
            </button>

            {expanded[section] && (
              <div className="border-t border-white/5 divide-y divide-white/5">
                {sectionBiomes.map(biome => {
                  const isVisited = save.biomesVisited?.[biome.id];
                  return (
                    <button
                      key={biome.id}
                      onClick={() => toggle(biome.id)}
                      className={`w-full text-left px-4 py-3 flex items-start gap-3 transition-colors ${
                        isVisited ? 'bg-blue-900/10' : 'hover:bg-white/5'
                      }`}
                    >
                      <div className="mt-0.5 shrink-0">
                        {isVisited
                          ? <CheckCircle className="w-4 h-4 text-blue-400" />
                          : <Circle className="w-4 h-4 text-gray-600" />
                        }
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className={`text-sm ${isVisited ? 'text-blue-300' : 'text-gray-200'}`}>
                            {biome.name}
                          </span>
                          <DlcBadge dlc={biome.dlc} />
                        </div>
                        {biome.note && (
                          <div className="flex items-start gap-1 mt-0.5">
                            <Info className="w-3 h-3 text-gray-600 mt-0.5 shrink-0" />
                            <span className="text-xs text-gray-500">{biome.note}</span>
                          </div>
                        )}
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ── Main Tracker ──────────────────────────────────────────────────────────────
const TABS = [
  { id: 'overview', label: 'Overview', icon: <Shield className="w-3.5 h-3.5" /> },
  { id: 'bosses',   label: 'Bosses',   icon: <Skull className="w-3.5 h-3.5" /> },
  { id: 'biomes',   label: 'Biomes',   icon: <Map className="w-3.5 h-3.5" /> },
  { id: 'runes',    label: 'Runes',    icon: <Zap className="w-3.5 h-3.5" /> },
];

export default function DeadCellsTracker({ game, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  const migratedSave = currentSave ? {
    ...currentSave,
    sessions: currentSave.sessions || [],
    totalPlaytime: currentSave.totalPlaytime ?? 0,
    bscEarned: currentSave.bscEarned || {},
    runesFound: currentSave.runesFound || {},
    bossesDefeated: currentSave.bossesDefeated || {},
    biomesVisited: currentSave.biomesVisited || {},
  } : null;

  const updateCurrentSave = useCallback((updater) => {
    const updated = typeof updater === 'function' ? updater(migratedSave) : updater;
    const newSaves = saves.map(s => s.id === updated.id ? updated : s);
    onUpdateGame({ ...game, saves: newSaves });
  }, [migratedSave, saves, game, onUpdateGame]);

  const createSave = () => {
    if (!newSaveName.trim()) return;
    const save = createDCSave(newSaveName.trim());
    onUpdateGame({ ...game, saves: [...saves, save], currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-950 via-red-950/20 to-black text-white">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-black/70 backdrop-blur border-b border-white/10 px-4 py-3">
        <div className="max-w-2xl mx-auto flex items-center gap-3 flex-wrap">
          <button onClick={onBack} className="p-2 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <span className="text-xl">⚔️</span>
          <span className="font-bold">Dead Cells</span>

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

          <button
            onClick={() => setShowNewSave(v => !v)}
            className="ml-auto flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white/10 hover:bg-white/20 text-sm"
          >
            + New File
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
            <h3 className="font-semibold text-sm">New Tracker File</h3>
            <input
              type="text"
              placeholder="Name (e.g. 'Main File', 'BSC 5 Run')"
              value={newSaveName}
              onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && createSave()}
              className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none"
              autoFocus
            />
            <div className="flex gap-2">
              <button onClick={createSave} className="px-4 py-2 bg-red-700 hover:bg-red-600 rounded-lg text-sm font-medium">Create</button>
              <button onClick={() => setShowNewSave(false)} className="px-3 py-2 bg-white/10 rounded-lg text-sm">Cancel</button>
            </div>
          </div>
        )}

        {!migratedSave ? (
          <div className="text-center py-20 text-gray-500">
            <div className="text-5xl mb-4">⚔️</div>
            <div className="text-lg mb-2 text-gray-300">No tracker file yet</div>
            <p className="text-sm mb-4">Track {BOSSES.length} bosses, {BIOMES.length} biomes, {RUNES.length} runes, and 5 Boss Stem Cells</p>
            <button onClick={() => setShowNewSave(true)} className="px-4 py-2 bg-red-700 rounded-lg text-sm">Start Tracking</button>
          </div>
        ) : (
          <>
            {/* Tabs */}
            <div className="flex gap-1 border-b border-white/10 pb-1">
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

            {activeTab === 'overview' && <OverviewTab save={migratedSave} onUpdateSave={updateCurrentSave} />}
            {activeTab === 'bosses'   && <BossesTab   save={migratedSave} onUpdateSave={updateCurrentSave} />}
            {activeTab === 'biomes'   && <BiomesTab   save={migratedSave} onUpdateSave={updateCurrentSave} />}
            {activeTab === 'runes'    && <RunesTab     save={migratedSave} onUpdateSave={updateCurrentSave} />}
          </>
        )}
      </div>
    </div>
  );
}
