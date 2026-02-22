import React, { useState, useCallback } from 'react';
import {
  ArrowLeft, Plus, ChevronDown, CheckCircle, Circle, Music, Star,
  Zap, ShoppingBag, Map, BookOpen, ChevronRight
} from 'lucide-react';
import {
  LEVELS, MUSIC_NOTES, PHOBEKINS, SHOP_UPGRADES,
  TOTAL_POWER_SEALS_MAIN, TOTAL_POWER_SEALS_DLC
} from '../../data/messengerData.js';

const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

function createMessengerSave(name) {
  const levelData = {};
  LEVELS.forEach(l => {
    levelData[l.id] = { cleared: false, powerSeals: 0 };
  });
  const collected = {};
  [...MUSIC_NOTES, ...PHOBEKINS, ...SHOP_UPGRADES].forEach(item => {
    collected[item.id] = false;
  });
  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    levelData,
    collected,
    notes: '',
  };
}

// ── Levels Tab ─────────────────────────────────────────────────────────────────
function LevelsTab({ save, onUpdateSave }) {
  const mainLevels = LEVELS.filter(l => !l.dlc);
  const dlcLevels = LEVELS.filter(l => l.dlc);

  const toggleLevel = (id) => {
    onUpdateSave(s => ({
      ...s,
      levelData: { ...s.levelData, [id]: { ...s.levelData?.[id], cleared: !s.levelData?.[id]?.cleared } }
    }));
  };

  const setSeals = (id, count, max) => {
    const val = Math.min(max, Math.max(0, count));
    onUpdateSave(s => ({
      ...s,
      levelData: { ...s.levelData, [id]: { ...s.levelData?.[id], powerSeals: val } }
    }));
  };

  const renderSection = (levels, title) => (
    <div>
      <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2 px-1">{title}</h3>
      <div className="space-y-2">
        {levels.map(level => {
          const data = save.levelData?.[level.id] || {};
          const sealsMax = level.powerSeals || 0;
          const sealsCount = data.powerSeals || 0;
          const sealsComplete = sealsMax > 0 && sealsCount >= sealsMax;
          return (
            <div key={level.id} className={`bg-black/40 rounded-xl border p-3 ${data.cleared ? 'border-green-500/30' : 'border-white/10'}`}>
              <div className="flex items-center gap-3">
                <button onClick={() => toggleLevel(level.id)} className="shrink-0">
                  {data.cleared
                    ? <CheckCircle className="w-5 h-5 text-green-400" />
                    : <Circle className="w-5 h-5 text-gray-600" />
                  }
                </button>
                <div className="flex-1 min-w-0">
                  <div className={`font-medium text-sm ${data.cleared ? 'line-through text-gray-500' : 'text-gray-100'}`}>
                    {level.name}
                  </div>
                  {level.boss && <div className="text-xs text-gray-500">Boss: {level.boss}</div>}
                </div>
                {/* Power seals counter */}
                {sealsMax > 0 && (
                  <div className="flex items-center gap-1.5 shrink-0">
                    <span className={`text-xs ${sealsComplete ? 'text-green-400' : 'text-gray-400'}`}>
                      🔷 {sealsCount}/{sealsMax}
                    </span>
                    <button
                      onClick={() => setSeals(level.id, sealsCount - 1, sealsMax)}
                      className="w-6 h-6 text-xs rounded bg-white/10 hover:bg-white/20 flex items-center justify-center"
                    >−</button>
                    <button
                      onClick={() => setSeals(level.id, sealsCount + 1, sealsMax)}
                      className="w-6 h-6 text-xs rounded bg-white/10 hover:bg-white/20 flex items-center justify-center"
                    >+</button>
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );

  return (
    <div className="space-y-5">
      {renderSection(mainLevels.filter(l => l.part === 1), 'Part 1 — 8-bit Linear')}
      {renderSection(mainLevels.filter(l => l.part === 2), 'Part 2 — 16-bit Metroidvania')}
      {renderSection(dlcLevels, 'DLC — Picnic Panic (Free)')}
    </div>
  );
}

// ── Collectibles Tab ──────────────────────────────────────────────────────────
function CollectiblesTab({ save, onUpdateSave }) {
  const toggle = (id) => {
    onUpdateSave(s => ({ ...s, collected: { ...s.collected, [id]: !s.collected?.[id] } }));
  };

  const totalSeals = LEVELS.filter(l => !l.dlc).reduce((sum, l) => sum + (l.powerSeals || 0), 0);
  const collectedSeals = Object.values(save.levelData || {})
    .reduce((sum, d) => sum + (d.powerSeals || 0), 0);

  const Section = ({ title, icon, items, keyField = 'location', valueField = 'description' }) => {
    const count = items.filter(i => save.collected?.[i.id]).length;
    return (
      <div>
        <div className="flex items-center justify-between mb-2 px-1">
          <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wider flex items-center gap-1.5">
            {icon}{title}
          </h3>
          <span className="text-xs text-gray-400">{count}/{items.length}</span>
        </div>
        <div className="space-y-2">
          {items.map(item => (
            <button
              key={item.id}
              onClick={() => toggle(item.id)}
              className={`w-full text-left p-3 rounded-xl border transition-colors ${save.collected?.[item.id] ? 'bg-green-900/20 border-green-500/20 opacity-70' : 'bg-black/40 border-white/10 hover:bg-white/5'}`}
            >
              <div className="flex items-start gap-2.5">
                <div className="mt-0.5 shrink-0">
                  {save.collected?.[item.id] ? <CheckCircle className="w-4 h-4 text-green-400" /> : <Circle className="w-4 h-4 text-gray-600" />}
                </div>
                <div>
                  <div className={`font-medium text-sm ${save.collected?.[item.id] ? 'line-through text-gray-500' : 'text-gray-100'}`}>
                    {item.name}
                    {item.cost && item.category === 'shop' && (
                      <span className="ml-2 text-xs text-gray-500 font-normal no-underline">
                        {item.cost === 'story' ? '(story)' : item.cost === 'seal' ? '(45 seals)' : `(${item.cost} shards)`}
                      </span>
                    )}
                  </div>
                  <div className="text-xs text-gray-500 mt-0.5">{item[keyField]}</div>
                  <div className="text-xs text-gray-600 mt-0.5">{item[valueField]}</div>
                </div>
              </div>
            </button>
          ))}
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-6">
      {/* Power Seals summary */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <div className="flex justify-between items-center mb-2">
          <h3 className="text-sm font-semibold text-gray-200">🔷 Power Seals</h3>
          <span className={`text-sm font-bold ${collectedSeals >= TOTAL_POWER_SEALS_MAIN ? 'text-green-400' : 'text-gray-300'}`}>
            {collectedSeals} / {TOTAL_POWER_SEALS_MAIN}
          </span>
        </div>
        <div className="h-2 bg-black/30 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-blue-600 to-blue-400 rounded-full transition-all"
            style={{ width: `${Math.min(100, (collectedSeals / TOTAL_POWER_SEALS_MAIN) * 100)}%` }}
          />
        </div>
        <p className="text-xs text-gray-500 mt-2">Track per-level in the Levels tab. Collect all 45 to unlock Windmill Shuriken.</p>
      </div>

      <Section title="Music Notes / Keys" icon={<Music className="w-3.5 h-3.5" />} items={MUSIC_NOTES} keyField="location" valueField="description" />
      <Section title="Phobekins" icon={<Star className="w-3.5 h-3.5" />} items={PHOBEKINS} keyField="location" valueField="description" />
      <Section title="Shop Upgrades" icon={<ShoppingBag className="w-3.5 h-3.5" />} items={SHOP_UPGRADES} keyField="category" valueField="description" />
    </div>
  );
}

// ── Overview Tab ──────────────────────────────────────────────────────────────
function OverviewTab({ save }) {
  const clearedLevels = Object.values(save.levelData || {}).filter(d => d.cleared).length;
  const totalLevels = LEVELS.length;
  const totalSeals = LEVELS.filter(l => !l.dlc).reduce((sum, l) => sum + (l.powerSeals || 0), 0);
  const collectedSeals = Object.values(save.levelData || {}).reduce((sum, d) => sum + (d.powerSeals || 0), 0);
  const collectedNotes = MUSIC_NOTES.filter(n => save.collected?.[n.id]).length;
  const collectedPhobekins = PHOBEKINS.filter(p => save.collected?.[p.id]).length;
  const collectedUpgrades = SHOP_UPGRADES.filter(u => save.collected?.[u.id]).length;

  const stats = [
    { label: 'Levels Cleared', value: `${clearedLevels}/${totalLevels}`, pct: clearedLevels/totalLevels, color: 'from-purple-600 to-purple-400' },
    { label: 'Power Seals', value: `${collectedSeals}/${totalSeals}`, pct: collectedSeals/totalSeals, color: 'from-blue-600 to-blue-400' },
    { label: 'Music Notes', value: `${collectedNotes}/${MUSIC_NOTES.length}`, pct: collectedNotes/MUSIC_NOTES.length, color: 'from-yellow-600 to-yellow-400' },
    { label: 'Phobekins', value: `${collectedPhobekins}/${PHOBEKINS.length}`, pct: collectedPhobekins/PHOBEKINS.length, color: 'from-green-600 to-green-400' },
    { label: 'Shop Upgrades', value: `${collectedUpgrades}/${SHOP_UPGRADES.length}`, pct: collectedUpgrades/SHOP_UPGRADES.length, color: 'from-orange-600 to-orange-400' },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {stats.map(stat => (
          <div key={stat.label} className="bg-black/40 rounded-xl border border-white/10 p-3">
            <div className="text-xs text-gray-400 mb-1">{stat.label}</div>
            <div className="text-lg font-bold text-white mb-2">{stat.value}</div>
            <div className="h-1.5 bg-black/30 rounded-full overflow-hidden">
              <div className={`h-full bg-gradient-to-r ${stat.color} rounded-full transition-all`} style={{ width: `${(stat.pct || 0) * 100}%` }} />
            </div>
          </div>
        ))}
      </div>

      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <h3 className="text-sm font-semibold text-gray-300 mb-3">Quick Tips</h3>
        <ul className="text-xs text-gray-500 space-y-1.5">
          <li>→ <span className="text-gray-400">Part 1</span>: Linear 8-bit — collect Power Seals as you go</li>
          <li>→ <span className="text-gray-400">Part 2</span>: Metroidvania — backtrack with new abilities to collect notes</li>
          <li>→ Collect all <span className="text-yellow-400">4 Phobekins</span> before attempting Forlorn Temple</li>
          <li>→ All <span className="text-blue-400">45 Power Seals</span> unlock the Windmill Shuriken</li>
          <li>→ <span className="text-green-400">Key of Strength</span>: deliver Power Thistle between 8-bit eras</li>
        </ul>
      </div>
    </div>
  );
}

// ── Main Tracker ──────────────────────────────────────────────────────────────
const TABS = [
  { id: 'overview',     label: 'Overview',     icon: <BookOpen className="w-3.5 h-3.5" /> },
  { id: 'levels',       label: 'Levels',        icon: <Map className="w-3.5 h-3.5" /> },
  { id: 'collectibles', label: 'Collectibles',  icon: <Star className="w-3.5 h-3.5" /> },
];

export default function MessengerTracker({ game, onBack, onUpdateGame }) {
  const [activeTab, setActiveTab] = useState('overview');
  const [showNewSave, setShowNewSave] = useState(false);
  const [newSaveName, setNewSaveName] = useState('');
  const [showSaveDropdown, setShowSaveDropdown] = useState(false);

  const saves = game.saves || [];
  const currentSave = saves.find(s => s.id === game.currentSaveId) || saves[0];

  const updateCurrentSave = useCallback((updater) => {
    const updated = typeof updater === 'function' ? updater(currentSave) : updater;
    const newSaves = saves.map(s => s.id === updated.id ? updated : s);
    onUpdateGame({ ...game, saves: newSaves });
  }, [currentSave, saves, game, onUpdateGame]);

  const createSave = () => {
    if (!newSaveName.trim()) return;
    const save = createMessengerSave(newSaveName.trim());
    onUpdateGame({ ...game, saves: [...saves, save], currentSaveId: save.id });
    setNewSaveName('');
    setShowNewSave(false);
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-slate-800 to-black text-white">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-black/70 backdrop-blur border-b border-white/10 px-4 py-3">
        <div className="max-w-2xl mx-auto flex items-center gap-3 flex-wrap">
          <button onClick={onBack} className="p-2 rounded-lg hover:bg-white/10 text-gray-400 hover:text-white">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <span className="text-xl">📜</span>
          <span className="font-bold">The Messenger</span>

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
            <Plus className="w-3.5 h-3.5" /> New Save
          </button>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-4 space-y-4">
        {showNewSave && (
          <div className="flex gap-2">
            <input type="text" placeholder="Save name..." value={newSaveName}
              onChange={e => setNewSaveName(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && createSave()}
              className="flex-1 bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none" autoFocus />
            <button onClick={createSave} className="px-3 py-2 bg-purple-600 rounded-lg text-sm">Create</button>
            <button onClick={() => setShowNewSave(false)} className="px-3 py-2 bg-white/10 rounded-lg text-sm">Cancel</button>
          </div>
        )}

        {!currentSave ? (
          <div className="text-center py-20 text-gray-500">
            <div className="text-5xl mb-4">📜</div>
            <div className="text-lg mb-2 text-gray-300">No saves yet</div>
            <p className="text-sm mb-4">Track levels, 45 power seals, music notes, phobekins & shop upgrades</p>
            <button onClick={() => setShowNewSave(true)} className="px-4 py-2 bg-purple-600 rounded-lg text-sm">Create Save</button>
          </div>
        ) : (
          <>
            <div className="flex gap-1 border-b border-white/10 pb-1">
              {TABS.map(tab => (
                <button key={tab.id} onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-1.5 px-3 py-2 rounded-t-lg text-sm font-medium transition-colors ${activeTab === tab.id ? 'text-white bg-white/10' : 'text-gray-400 hover:text-white hover:bg-white/5'}`}>
                  {tab.icon}{tab.label}
                </button>
              ))}
            </div>

            {activeTab === 'overview' && <OverviewTab save={currentSave} />}
            {activeTab === 'levels' && <LevelsTab save={currentSave} onUpdateSave={updateCurrentSave} />}
            {activeTab === 'collectibles' && <CollectiblesTab save={currentSave} onUpdateSave={updateCurrentSave} />}
          </>
        )}
      </div>
    </div>
  );
}
