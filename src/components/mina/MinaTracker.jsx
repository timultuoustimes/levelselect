import React, { useState, useCallback } from 'react';
import { ArrowLeft, Plus, ChevronDown, CheckCircle, Circle, Zap, BookOpen, Package, Skull } from 'lucide-react';
import SessionPanel from '../shared/SessionPanel.jsx';
import {
  REGIONS, STORY_BOSSES, SECRET_BOSSES,
  TRINKET_REGIONS, TOTAL_TRINKETS, JOULE_BOXES, QUESTS,
} from '../../data/minaData.js';

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

const QUEST_TYPE_LABELS = {
  race: '🏁 Race',
  minigame: '🎮 Minigame',
  collection: '📦 Collection',
  challenge: '⚔️ Challenge',
  quest: '💬 Quest',
  shop: '🛒 Shop',
};

function createMinaSave(name) {
  const bossesDefeated = {};
  STORY_BOSSES.forEach(b => { bossesDefeated[b.id] = false; });

  const secretBossesDefeated = {};
  SECRET_BOSSES.forEach(b => { secretBossesDefeated[b.id] = false; });

  const trinketCounts = {};
  TRINKET_REGIONS.forEach(r => { trinketCounts[r.id] = 0; });

  const jouleBoxes = {};
  JOULE_BOXES.forEach(j => { jouleBoxes[j.id] = false; });

  const questsCompleted = {};
  QUESTS.forEach(q => { questsCompleted[q.id] = false; });

  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    bossesDefeated,
    secretBossesDefeated,
    trinketCounts,
    jouleBoxes,
    healthRosesExtra: 0,
    sparkContainersExtra: 0,
    questsCompleted,
    sessions: [],
    activeSession: null,
    lastPlayedAt: null,
    notes: '',
  };
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
function OverviewTab({ save }) {
  const bossCount      = STORY_BOSSES.filter(b => save.bossesDefeated?.[b.id]).length;
  const secretCount    = SECRET_BOSSES.filter(b => save.secretBossesDefeated?.[b.id]).length;
  const trinketTotal   = Object.values(save.trinketCounts || {}).reduce((s, n) => s + n, 0);
  const jouleCount     = JOULE_BOXES.filter(j => save.jouleBoxes?.[j.id]).length;
  const questCount     = QUESTS.filter(q => save.questsCompleted?.[q.id]).length;
  // Count spark generators as restored when their area boss is defeated
  const SPARK_BOSS_IDS = new Set(['duchess', 'nox-beast', 'mined-mind', 'orrery-warden', 'frozen-horror']);
  const sparksRestored = Object.entries(save.bossesDefeated || {})
    .filter(([id, done]) => done && SPARK_BOSS_IDS.has(id)).length +
    // Septemburg boss unknown — leave a gap so the count stays accurate as data improves
    0;

  const stats = [
    { label: 'Spark Generators',   value: `${sparksRestored}/6`,                 pct: sparksRestored / 6,           color: 'from-yellow-600 to-yellow-400' },
    { label: 'Story Bosses',       value: `${bossCount}/${STORY_BOSSES.length}`, pct: bossCount / STORY_BOSSES.length, color: 'from-purple-600 to-purple-400' },
    { label: 'Trinkets',           value: `${trinketTotal}/${TOTAL_TRINKETS}`,   pct: trinketTotal / TOTAL_TRINKETS, color: 'from-blue-600 to-blue-400'   },
    { label: 'Secret Bosses',      value: `${secretCount}/${SECRET_BOSSES.length}`, pct: secretCount / SECRET_BOSSES.length, color: 'from-red-600 to-red-400' },
    { label: 'Joule Boxes',        value: `${jouleCount}/${JOULE_BOXES.length}`, pct: jouleCount / JOULE_BOXES.length, color: 'from-cyan-600 to-cyan-400'  },
    { label: 'Quests / Minigames', value: `${questCount}/${QUESTS.length}`,      pct: questCount / QUESTS.length,    color: 'from-green-600 to-green-400' },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {stats.map(stat => (
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

      {/* Regions grid */}
      <div>
        <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 px-1">Tenebrous Isle</h3>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          {REGIONS.map(region => {
            const bossId = STORY_BOSSES.find(b => b.area === region.name)?.id;
            const bossDefeated = bossId ? save.bossesDefeated?.[bossId] : null;
            return (
              <div key={region.id} className={`p-2.5 rounded-xl border text-sm ${
                region.hub ? 'border-indigo-500/30 bg-indigo-900/10' :
                bossDefeated ? 'border-green-500/30 bg-green-900/10' : 'border-white/10 bg-black/30'
              }`}>
                <div className="text-base mb-0.5">{region.icon}</div>
                <div className="font-medium text-xs text-gray-200 leading-tight">{region.name}</div>
                {region.sparkGenerator && (
                  <div className={`text-xs mt-1 flex items-center gap-1 ${bossDefeated ? 'text-yellow-400' : 'text-gray-600'}`}>
                    <Zap className="w-3 h-3" />
                    <span>{bossDefeated ? 'Restored' : 'Failing'}</span>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Notes */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <label className="text-xs text-gray-400 block mb-2">Notes</label>
        <textarea
          rows={3}
          placeholder="Route notes, what to tackle next..."
          value={save.notes || ''}
          readOnly
          className="w-full bg-transparent text-sm text-gray-300 placeholder-gray-600 resize-none focus:outline-none"
        />
      </div>
    </div>
  );
}

// ── World Tab ─────────────────────────────────────────────────────────────────
function WorldTab({ save, onUpdateSave }) {
  const toggleBoss = (id) => {
    onUpdateSave(s => ({ ...s, bossesDefeated: { ...s.bossesDefeated, [id]: !s.bossesDefeated?.[id] } }));
  };

  return (
    <div className="space-y-5">
      {/* Regions + their generator bosses */}
      <div>
        <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 px-1">Regions & Spark Generators</h3>
        <div className="space-y-2">
          {REGIONS.map(region => {
            const bossId = STORY_BOSSES.find(b => b.area === region.name)?.id;
            const bossDefeated = bossId ? !!save.bossesDefeated?.[bossId] : null;
            return (
              <div key={region.id} className={`rounded-xl border p-3 ${
                region.hub ? 'border-indigo-500/20 bg-indigo-900/10' :
                bossDefeated ? 'border-green-500/20 bg-green-900/10' : 'border-white/10 bg-black/30'
              }`}>
                <div className="flex items-center gap-2.5">
                  <span className="text-lg shrink-0">{region.icon}</span>
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-sm text-gray-100">{region.name}</div>
                    <div className="text-xs text-gray-500">{region.description}</div>
                  </div>
                  {region.sparkGenerator && bossId && (
                    <button
                      onClick={() => toggleBoss(bossId)}
                      className="shrink-0 flex items-center gap-1.5"
                    >
                      <Zap className={`w-4 h-4 ${bossDefeated ? 'text-yellow-400' : 'text-gray-600'}`} />
                    </button>
                  )}
                </div>
                {region.boss && (
                  <button
                    onClick={() => bossId && toggleBoss(bossId)}
                    className="mt-2 w-full flex items-center gap-2 text-left hover:bg-white/5 rounded-lg px-1.5 py-1"
                  >
                    {bossDefeated
                      ? <CheckCircle className="w-4 h-4 text-green-400 shrink-0" />
                      : <Circle className="w-4 h-4 text-gray-600 shrink-0" />
                    }
                    <span className={`text-sm ${bossDefeated ? 'line-through text-gray-500' : 'text-gray-200'}`}>
                      {region.boss}
                    </span>
                    {region.sparkGenerator && (
                      <Zap className={`w-3 h-3 ml-auto ${bossDefeated ? 'text-yellow-400' : 'text-gray-600'}`} />
                    )}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Other story bosses (not tied to a region card above) */}
      <div>
        <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 px-1">Other Story Bosses</h3>
        <div className="space-y-1.5">
          {STORY_BOSSES.filter(b => !REGIONS.some(r => r.name === b.area)).map(boss => (
            <button
              key={boss.id}
              onClick={() => toggleBoss(boss.id)}
              className="w-full flex items-start gap-2.5 text-left hover:bg-white/5 rounded-xl p-3 border border-white/5 bg-black/30"
            >
              {save.bossesDefeated?.[boss.id]
                ? <CheckCircle className="w-5 h-5 text-green-400 shrink-0 mt-0.5" />
                : <Circle className="w-5 h-5 text-gray-600 shrink-0 mt-0.5" />
              }
              <div>
                <div className={`text-sm font-medium ${save.bossesDefeated?.[boss.id] ? 'line-through text-gray-500' : 'text-gray-100'}`}>
                  {boss.name}
                </div>
                <div className="text-xs text-gray-500">{boss.area}{boss.reward ? ` · Reward: ${boss.reward}` : ''}</div>
                {boss.note && <div className="text-xs text-gray-600 mt-0.5">{boss.note}</div>}
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* Notes */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <label className="text-xs text-gray-400 block mb-2">Notes</label>
        <textarea
          rows={3}
          placeholder="Route order, what to tackle next..."
          value={save.notes || ''}
          onChange={e => onUpdateSave(s => ({ ...s, notes: e.target.value }))}
          className="w-full bg-black/30 border border-white/10 rounded-lg px-3 py-2 text-sm text-gray-200 placeholder-gray-600 resize-none focus:outline-none"
        />
      </div>
    </div>
  );
}

// ── Collectibles Tab ──────────────────────────────────────────────────────────
function CollectiblesTab({ save, onUpdateSave }) {
  const trinketTotal = Object.values(save.trinketCounts || {}).reduce((s, n) => s + n, 0);
  const jouleCount   = JOULE_BOXES.filter(j => save.jouleBoxes?.[j.id]).length;

  const setTrinketCount = (regionId, val, max) => {
    const clamped = Math.max(0, Math.min(max, val));
    onUpdateSave(s => ({ ...s, trinketCounts: { ...s.trinketCounts, [regionId]: clamped } }));
  };

  const toggleJoule = (id) => {
    onUpdateSave(s => ({ ...s, jouleBoxes: { ...s.jouleBoxes, [id]: !s.jouleBoxes?.[id] } }));
  };

  return (
    <div className="space-y-5">
      {/* Trinkets */}
      <div>
        <div className="flex items-center justify-between mb-2 px-1">
          <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Trinkets</h3>
          <span className={`text-sm font-bold ${trinketTotal >= TOTAL_TRINKETS ? 'text-blue-400' : 'text-gray-300'}`}>
            {trinketTotal} / {TOTAL_TRINKETS}
          </span>
        </div>
        <div className="h-2 bg-black/30 rounded-full overflow-hidden mb-3">
          <div
            className="h-full bg-gradient-to-r from-blue-600 to-blue-400 rounded-full transition-all"
            style={{ width: `${(trinketTotal / TOTAL_TRINKETS) * 100}%` }}
          />
        </div>
        <div className="space-y-2">
          {TRINKET_REGIONS.map(region => {
            const count = save.trinketCounts?.[region.id] || 0;
            const done = count >= region.max;
            return (
              <div key={region.id} className={`flex items-center gap-3 rounded-xl border px-3 py-2.5 ${done ? 'border-blue-500/20 bg-blue-900/10' : 'border-white/10 bg-black/20'}`}>
                <span className={`text-sm flex-1 ${done ? 'text-gray-400' : 'text-gray-200'}`}>{region.name}</span>
                <div className="flex items-center gap-1.5 shrink-0">
                  <span className={`text-xs w-10 text-right ${done ? 'text-blue-400 font-semibold' : 'text-gray-400'}`}>{count}/{region.max}</span>
                  <button
                    onClick={() => setTrinketCount(region.id, count - 1, region.max)}
                    className="w-6 h-6 text-xs rounded bg-white/10 hover:bg-white/20 flex items-center justify-center"
                  >−</button>
                  <button
                    onClick={() => setTrinketCount(region.id, count + 1, region.max)}
                    className="w-6 h-6 text-xs rounded bg-white/10 hover:bg-white/20 flex items-center justify-center"
                  >+</button>
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Joule Boxes */}
      <div>
        <div className="flex items-center justify-between mb-2 px-1">
          <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Joule Boxes</h3>
          <span className={`text-sm font-bold ${jouleCount >= JOULE_BOXES.length ? 'text-cyan-400' : 'text-gray-300'}`}>
            {jouleCount} / {JOULE_BOXES.length}
          </span>
        </div>
        <div className="space-y-1.5">
          {JOULE_BOXES.map(jb => (
            <button
              key={jb.id}
              onClick={() => toggleJoule(jb.id)}
              className={`w-full flex items-center gap-2.5 text-left px-3 py-2.5 rounded-xl border transition-colors ${
                save.jouleBoxes?.[jb.id]
                  ? 'bg-cyan-900/20 border-cyan-500/20 opacity-70'
                  : 'bg-black/30 border-white/10 hover:bg-white/5'
              }`}
            >
              {save.jouleBoxes?.[jb.id]
                ? <CheckCircle className="w-4 h-4 text-cyan-400 shrink-0" />
                : <Circle className="w-4 h-4 text-gray-600 shrink-0" />
              }
              <span className={`text-sm ${save.jouleBoxes?.[jb.id] ? 'line-through text-gray-500' : 'text-gray-200'}`}>
                {jb.label}
              </span>
              <span className={`ml-auto text-xs ${jb.via === 'shop' ? 'text-amber-500/70' : 'text-gray-600'}`}>
                {jb.via === 'shop' ? 'shop' : 'explore'}
              </span>
            </button>
          ))}
        </div>
      </div>

      {/* Other upgrades */}
      <div>
        <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 px-1">Other Upgrades</h3>
        <div className="bg-black/40 rounded-xl border border-white/10 p-4 space-y-4">
          {[
            { key: 'healthRosesExtra',     label: '🌹 Health Roses (extras found)', note: 'Start with 8; extras from bosses & vendors' },
            { key: 'sparkContainersExtra', label: '⚡ Spark Containers (extras found)', note: 'Increases energy capacity' },
          ].map(({ key, label, note }) => (
            <div key={key}>
              <div className="flex items-center justify-between mb-1">
                <span className="text-sm text-gray-200">{label}</span>
                <div className="flex items-center gap-1.5">
                  <button
                    onClick={() => onUpdateSave(s => ({ ...s, [key]: Math.max(0, (s[key] || 0) - 1) }))}
                    className="w-7 h-7 text-sm rounded bg-white/10 hover:bg-white/20 flex items-center justify-center"
                  >−</button>
                  <span className="text-lg font-mono font-bold text-white w-8 text-center">
                    {save[key] || 0}
                  </span>
                  <button
                    onClick={() => onUpdateSave(s => ({ ...s, [key]: (s[key] || 0) + 1 }))}
                    className="w-7 h-7 text-sm rounded bg-white/10 hover:bg-white/20 flex items-center justify-center"
                  >+</button>
                </div>
              </div>
              <p className="text-xs text-gray-600">{note}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Secrets & Quests Tab ──────────────────────────────────────────────────────
function SecretsTab({ save, onUpdateSave }) {
  const secretCount = SECRET_BOSSES.filter(b => save.secretBossesDefeated?.[b.id]).length;
  const questCount  = QUESTS.filter(q => save.questsCompleted?.[q.id]).length;
  const renegadeCount = SECRET_BOSSES.filter(b => b.renegade && save.secretBossesDefeated?.[b.id]).length;

  const toggleSecret = (id) => {
    onUpdateSave(s => ({ ...s, secretBossesDefeated: { ...s.secretBossesDefeated, [id]: !s.secretBossesDefeated?.[id] } }));
  };

  const toggleQuest = (id) => {
    onUpdateSave(s => ({ ...s, questsCompleted: { ...s.questsCompleted, [id]: !s.questsCompleted?.[id] } }));
  };

  return (
    <div className="space-y-5">
      {/* Secret bosses */}
      <div>
        <div className="flex items-center justify-between mb-2 px-1">
          <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Secret Bosses</h3>
          <span className="text-sm font-bold text-gray-300">{secretCount}/{SECRET_BOSSES.length}</span>
        </div>
        {/* Renegade tracker */}
        {renegadeCount > 0 && (
          <div className={`mb-2 px-3 py-2 rounded-lg text-xs flex items-center gap-2 ${renegadeCount === 5 ? 'bg-green-900/30 border border-green-500/30 text-green-300' : 'bg-orange-900/20 border border-orange-500/20 text-orange-300'}`}>
            <Skull className="w-3.5 h-3.5 shrink-0" />
            Renegades: {renegadeCount}/5{renegadeCount === 5 ? ' — Renegade Roundup unlocked!' : ''}
          </div>
        )}
        <div className="space-y-2">
          {SECRET_BOSSES.map(boss => (
            <button
              key={boss.id}
              onClick={() => toggleSecret(boss.id)}
              className={`w-full text-left rounded-xl border p-3 transition-colors ${
                save.secretBossesDefeated?.[boss.id]
                  ? 'bg-red-900/20 border-red-500/20 opacity-70'
                  : 'bg-black/30 border-white/10 hover:bg-white/5'
              }`}
            >
              <div className="flex items-start gap-2.5">
                <div className="mt-0.5 shrink-0">
                  {save.secretBossesDefeated?.[boss.id]
                    ? <CheckCircle className="w-4 h-4 text-red-400" />
                    : <Circle className="w-4 h-4 text-gray-600" />
                  }
                </div>
                <div className="flex-1 min-w-0">
                  <div className={`text-sm font-medium ${save.secretBossesDefeated?.[boss.id] ? 'line-through text-gray-500' : 'text-gray-100'}`}>
                    {boss.name}
                    {boss.renegade && <span className="ml-1.5 text-xs text-orange-400 font-normal no-underline">Renegade</span>}
                  </div>
                  <div className="text-xs text-gray-500 mt-0.5">{boss.area}</div>
                  <div className="text-xs text-gray-600 mt-0.5">{boss.how}</div>
                  {boss.reward && <div className="text-xs text-amber-500/70 mt-0.5">Reward: {boss.reward}</div>}
                </div>
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* Quests */}
      <div>
        <div className="flex items-center justify-between mb-2 px-1">
          <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider">Quests & Minigames</h3>
          <span className="text-sm font-bold text-gray-300">{questCount}/{QUESTS.length}</span>
        </div>
        <div className="space-y-1.5">
          {QUESTS.map(quest => (
            <button
              key={quest.id}
              onClick={() => toggleQuest(quest.id)}
              className={`w-full text-left flex items-start gap-2.5 px-3 py-2.5 rounded-xl border transition-colors ${
                save.questsCompleted?.[quest.id]
                  ? 'bg-green-900/20 border-green-500/20 opacity-70'
                  : 'bg-black/30 border-white/10 hover:bg-white/5'
              }`}
            >
              <div className="mt-0.5 shrink-0">
                {save.questsCompleted?.[quest.id]
                  ? <CheckCircle className="w-4 h-4 text-green-400" />
                  : <Circle className="w-4 h-4 text-gray-600" />
                }
              </div>
              <div className="flex-1 min-w-0">
                <div className={`text-sm font-medium ${save.questsCompleted?.[quest.id] ? 'line-through text-gray-500' : 'text-gray-100'}`}>
                  {quest.name}
                </div>
                <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                  <span className="text-xs text-gray-500">{QUEST_TYPE_LABELS[quest.type]}</span>
                  <span className="text-xs text-gray-600">{quest.area}</span>
                </div>
                {quest.reward && <div className="text-xs text-amber-500/70 mt-0.5">Reward: {quest.reward}</div>}
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Main Tracker ──────────────────────────────────────────────────────────────
const TABS = [
  { id: 'overview',    label: 'Overview',   icon: <BookOpen className="w-3.5 h-3.5" /> },
  { id: 'world',       label: 'World',      icon: <Zap className="w-3.5 h-3.5" /> },
  { id: 'collectibles', label: 'Items',     icon: <Package className="w-3.5 h-3.5" /> },
  { id: 'secrets',     label: 'Secrets',    icon: <Skull className="w-3.5 h-3.5" /> },
];

export default function MinaTracker({ game, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab]       = useState('overview');
  const [showNewSave, setShowNewSave]   = useState(false);
  const [newSaveName, setNewSaveName]   = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  const saves       = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  const updateCurrentSave = useCallback((updater) => {
    if (!currentSave) return;
    const updated = typeof updater === 'function' ? updater(currentSave) : updater;
    onUpdateGame({ ...game, saves: saves.map(s => s.id === updated.id ? updated : s) });
  }, [currentSave, saves, game, onUpdateGame]);

  const createSave = () => {
    const name = newSaveName.trim() || `Playthrough ${saves.length + 1}`;
    const save = createMinaSave(name);
    onUpdateGame({ ...game, saves: [...saves, save], currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  const totalPlaytime = (currentSave?.sessions || []).reduce((s, session) => s + (session.duration || 0), 0);

  if (saves.length === 0) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-slate-900 via-violet-950/40 to-slate-900 flex items-center justify-center p-4">
        <div className="card p-8 max-w-md w-full text-center">
          <div className="text-5xl mb-4">🕯️</div>
          <h1 className="text-2xl font-bold mb-2">Mina the Hollower</h1>
          <p className="text-gray-400 mb-6">
            Track your progress through Tenebrous Isle — Spark Generators, bosses, trinkets, and secrets.
          </p>
          <input
            type="text"
            placeholder="Playthrough name"
            value={newSaveName}
            onChange={e => setNewSaveName(e.target.value)}
            onKeyDown={e => e.key === 'Enter' && createSave()}
            className="input-field mb-3"
            autoFocus
          />
          <button onClick={createSave} className="btn-primary w-full">Start Tracking</button>
          <button onClick={onBack} className="btn-secondary w-full mt-2">← Back to Library</button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-violet-950/30 to-slate-900 safe-area-bottom">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-slate-900/90 backdrop-blur border-b border-violet-500/20 safe-area-top">
        <div className="max-w-2xl mx-auto px-4 py-3">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-3">
              <button onClick={onBack} className="text-gray-400 hover:text-white p-1 min-h-[44px] min-w-[44px] flex items-center justify-center">
                <ArrowLeft className="w-5 h-5" />
              </button>
              <div>
                <h1 className="text-lg font-bold">🕯️ Mina the Hollower</h1>
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
                        <button key={s.id} onClick={() => { onUpdateGame({ ...game, currentSaveId: s.id }); setShowSaveDropdown(false); }}
                          className={`w-full text-left px-3 py-2 rounded text-sm min-h-[44px] ${
                            s.id === currentSave?.id ? 'bg-violet-600 text-white' : 'hover:bg-white/10 text-gray-300'
                          }`}
                        >{s.name}</button>
                      ))}
                      <hr className="border-violet-500/20 my-1" />
                      <button
                        onClick={() => { setShowSaveDropdown(false); setShowNewSave(true); }}
                        className="w-full text-left px-3 py-2 rounded text-sm text-violet-400 hover:bg-white/10 min-h-[44px] flex items-center gap-2"
                      >
                        <Plus className="w-4 h-4" /> New Playthrough
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>

          {/* Tabs */}
          <div className="flex gap-1 overflow-x-auto scroll-smooth-ios -mx-4 px-4">
            {TABS.map(tab => (
              <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                className={`${activeTab === tab.id ? 'tab-button-active' : 'tab-button-inactive'} whitespace-nowrap text-sm flex items-center gap-1.5`}
              >
                {tab.icon}{tab.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Session Panel */}
      <SessionPanel
        game={game}
        totalPlaytime={totalPlaytime}
        sessions={currentSave?.sessions || []}
        onUpdateGame={onUpdateGame}
        onSessionStart={({ id, startTime }) => updateCurrentSave(s => ({
          ...s,
          activeSession: { id, startTime, endTime: null, duration: 0 },
          lastPlayedAt: startTime,
        }))}
        onAddSession={(session) => updateCurrentSave(s => ({
          ...s,
          sessions: [...(s.sessions || []), session],
          activeSession: null,
          lastPlayedAt: session.endTime,
        }))}
        onDeleteSession={(id) => updateCurrentSave(s => ({
          ...s,
          sessions: (s.sessions || []).filter(sess => sess.id !== id),
        }))}
        onUpdateSession={(updated) => updateCurrentSave(s => ({
          ...s,
          sessions: (s.sessions || []).map(sess => sess.id === updated.id ? updated : sess),
        }))}
      />

      {/* Tab content */}
      <div className="max-w-2xl mx-auto px-4 py-4">
        {activeTab === 'overview'     && <OverviewTab save={currentSave} />}
        {activeTab === 'world'        && <WorldTab save={currentSave} onUpdateSave={updateCurrentSave} />}
        {activeTab === 'collectibles' && <CollectiblesTab save={currentSave} onUpdateSave={updateCurrentSave} />}
        {activeTab === 'secrets'      && <SecretsTab save={currentSave} onUpdateSave={updateCurrentSave} />}
      </div>

      {/* New save modal */}
      {showNewSave && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
          onClick={() => setShowNewSave(false)}
        >
          <div className="card p-6 w-full max-w-md" onClick={e => e.stopPropagation()}>
            <h2 className="text-lg font-bold mb-4">New Playthrough</h2>
            <input
              type="text"
              placeholder="Playthrough name"
              value={newSaveName}
              onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && createSave()}
              className="input-field mb-3"
              autoFocus
            />
            <button onClick={createSave} className="btn-primary w-full">Create</button>
          </div>
        </div>
      )}
    </div>
  );
}
