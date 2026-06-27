import React, { useState, useEffect, useRef } from 'react';
import { createRun } from '../../utils/factories.js';
import { formatDuration } from '../../utils/format.js';
import { WEAPONS } from '../../data/hadesWeapons.js';
import { KEEPSAKES } from '../../data/hadesKeepsakes.js';
import { BOONS_BY_GOD, GODS } from '../../data/hadesBoons.js';
import { X, Search } from 'lucide-react';

const GOD_COLORS = {
  Zeus:      { off: 'border-yellow-600/40 text-yellow-500 bg-yellow-900/10',  on: 'bg-yellow-500 border-yellow-400 text-white' },
  Poseidon:  { off: 'border-blue-600/40 text-blue-500 bg-blue-900/10',        on: 'bg-blue-500 border-blue-400 text-white' },
  Athena:    { off: 'border-cyan-600/40 text-cyan-500 bg-cyan-900/10',        on: 'bg-cyan-500 border-cyan-400 text-white' },
  Aphrodite: { off: 'border-pink-600/40 text-pink-500 bg-pink-900/10',        on: 'bg-pink-500 border-pink-400 text-white' },
  Artemis:   { off: 'border-green-600/40 text-green-500 bg-green-900/10',     on: 'bg-green-500 border-green-400 text-white' },
  Ares:      { off: 'border-red-600/40 text-red-500 bg-red-900/10',           on: 'bg-red-500 border-red-400 text-white' },
  Dionysus:  { off: 'border-purple-600/40 text-purple-500 bg-purple-900/10',  on: 'bg-purple-500 border-purple-400 text-white' },
  Hermes:    { off: 'border-amber-600/40 text-amber-500 bg-amber-900/10',     on: 'bg-amber-500 border-amber-400 text-white' },
  Demeter:   { off: 'border-slate-500/40 text-slate-400 bg-slate-900/10',     on: 'bg-slate-500 border-slate-400 text-white' },
  Chaos:     { off: 'border-gray-600/40 text-gray-500 bg-gray-900/20',        on: 'bg-gray-600 border-gray-500 text-white' },
};

const DEATH_LOCATIONS = [
  { id: 'tartarus',   label: 'Tartarus',   icon: '💀' },
  { id: 'asphodel',   label: 'Asphodel',   icon: '🔥' },
  { id: 'elysium',    label: 'Elysium',    icon: '⚡' },
  { id: 'styx',       label: 'Styx',       icon: '🐍' },
  { id: 'final-boss', label: 'Final Boss', icon: '👑' },
];

// Short weapon name for buttons
function shortWeaponName(name) {
  const shorts = {
    'Stygian Blade': 'Blade',
    'Eternal Spear': 'Spear',
    'Shield of Chaos': 'Shield',
    'Heart-Seeking Bow': 'Bow',
    'Twin Fists': 'Fists',
    'Adamant Rail': 'Rail',
  };
  return shorts[name] || name;
}

export default function RunView({ save, onEndRun, onCancelRun, onStartRun, initialRun }) {
  const [phase, setPhase] = useState(initialRun ? 'active' : 'setup');
  const [run, setRun] = useState(() => initialRun || createRun());
  const [elapsed, setElapsed] = useState(() =>
    initialRun?.startTime
      ? Math.floor((Date.now() - new Date(initialRun.startTime).getTime()) / 1000)
      : 0
  );
  const [showBoonPicker, setShowBoonPicker] = useState(false);
  const [showHammerPicker, setShowHammerPicker] = useState(false);
  const [boonGod, setBoonGod] = useState('');
  const [boonSearch, setBoonSearch] = useState('');
  const timerRef = useRef(null);

  useEffect(() => {
    if (phase !== 'active') return;
    timerRef.current = setInterval(() => setElapsed(e => e + 1), 1000);
    return () => clearInterval(timerRef.current);
  }, [phase]);

  const selectedWeapon = WEAPONS.find(w => w.name === run.weapon);
  const availableAspects = selectedWeapon?.aspects || [];
  const availableHammers = selectedWeapon?.hammerUpgrades || [];
  const unlockedKeepsakes = (save?.keepsakes || []).filter(k => k.unlocked);
  const allKeepsakes = unlockedKeepsakes.length > 0 ? unlockedKeepsakes : KEEPSAKES;

  const handleStartRun = () => {
    const newRun = { ...run, startTime: new Date().toISOString() };
    setRun(newRun);
    setElapsed(0);
    onStartRun?.(newRun);
    setPhase('active');
  };

  const toggleGod = (god) => setRun(prev => ({
    ...prev,
    gods: prev.gods.includes(god) ? prev.gods.filter(g => g !== god) : [...prev.gods, god],
  }));

  const addBoon = (god, name, slot) => {
    setRun(prev => ({ ...prev, boons: [...prev.boons, { god, name, slot }] }));
    setBoonSearch('');
  };
  const removeBoon = (idx) => setRun(prev => ({ ...prev, boons: prev.boons.filter((_, i) => i !== idx) }));
  const addHammer = (h) => {
    if (!run.hammerUpgrades.includes(h)) setRun(prev => ({ ...prev, hammerUpgrades: [...prev.hammerUpgrades, h] }));
  };
  const removeHammer = (h) => setRun(prev => ({ ...prev, hammerUpgrades: prev.hammerUpgrades.filter(x => x !== h) }));

  const handleSaveRun = () => {
    clearInterval(timerRef.current);
    onEndRun({ ...run, endTime: new Date().toISOString(), duration: elapsed });
  };

  const getFilteredBoons = () => {
    if (!boonGod) return [];
    const godBoons = BOONS_BY_GOD[boonGod];
    if (!godBoons) return [];
    const result = [];
    if (boonGod === 'Chaos') {
      (godBoons.blessings || []).forEach(name => result.push({ name, slot: 'blessing', god: boonGod }));
      (godBoons.curses || []).forEach(name => result.push({ name, slot: 'curse', god: boonGod }));
    } else {
      ['attack', 'special', 'cast', 'dash', 'call', 'other', 'legendary'].forEach(slot =>
        (godBoons[slot] || []).forEach(name => result.push({ name, slot, god: boonGod }))
      );
    }
    return boonSearch ? result.filter(b => b.name.toLowerCase().includes(boonSearch.toLowerCase())) : result;
  };
  const collectedNames = new Set(run.boons.map(b => `${b.god}:${b.name}`));

  // ── Setup ────────────────────────────────────────────────────────────────
  if (phase === 'setup') {
    return (
      <div className="min-h-screen bg-gradient-to-b from-slate-900 via-purple-900/30 to-slate-900 safe-area-bottom">
        <div className="max-w-lg mx-auto px-4 py-6 space-y-5">
          <div className="flex items-center justify-between">
            <h2 className="text-xl font-bold">New Run</h2>
            <button onClick={onCancelRun} className="text-gray-500 hover:text-white text-sm">Cancel</button>
          </div>

          {/* Weapon grid */}
          <div>
            <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">Weapon</div>
            <div className="grid grid-cols-3 gap-2">
              {WEAPONS.map(w => (
                <button
                  key={w.id}
                  onClick={() => setRun(prev => ({ ...prev, weapon: w.name, aspect: '', hammerUpgrades: [] }))}
                  className={`flex flex-col items-center gap-1.5 p-3 rounded-xl border text-sm transition-colors ${
                    run.weapon === w.name
                      ? 'border-purple-500 bg-purple-900/30 text-white'
                      : 'border-white/10 bg-black/20 text-gray-400 hover:border-white/30 hover:text-gray-200'
                  }`}
                >
                  <span className="text-2xl">{w.icon}</span>
                  <span className="text-[11px] text-center leading-tight">{shortWeaponName(w.name)}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Aspect chips */}
          {availableAspects.length > 0 && (
            <div>
              <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">Aspect</div>
              <div className="flex flex-wrap gap-1.5">
                {availableAspects.map(a => (
                  <button
                    key={a.id}
                    onClick={() => setRun(prev => ({ ...prev, aspect: prev.aspect === a.name ? '' : a.name }))}
                    className={`px-3 py-1.5 rounded-lg border text-sm transition-colors ${
                      run.aspect === a.name
                        ? 'border-purple-500 bg-purple-900/30 text-white'
                        : 'border-white/10 bg-black/20 text-gray-400 hover:border-white/30'
                    }`}
                  >
                    {a.name}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Heat + Keepsake */}
          <div className="flex items-end gap-3">
            <div>
              <div className="text-xs text-gray-500 uppercase tracking-wider mb-1">Heat</div>
              <input
                type="number" min="0" max="64" value={run.heatLevel}
                onChange={e => setRun(prev => ({ ...prev, heatLevel: parseInt(e.target.value) || 0 }))}
                className="input-field w-20 text-center"
              />
            </div>
            <div className="flex-1">
              <div className="text-xs text-gray-500 uppercase tracking-wider mb-1">Keepsake</div>
              <select value={run.keepsake} onChange={e => setRun(prev => ({ ...prev, keepsake: e.target.value }))} className="input-field">
                <option value="">None / Skip</option>
                {allKeepsakes.map(k => <option key={k.id} value={k.name}>{k.name}</option>)}
              </select>
            </div>
          </div>

          <button onClick={handleStartRun} className="btn-primary w-full py-3 text-base">
            🗡️ Start Run
          </button>
        </div>
      </div>
    );
  }

  // ── Ending ────────────────────────────────────────────────────────────────
  if (phase === 'ending') {
    return (
      <div className="min-h-screen bg-gradient-to-b from-slate-900 via-purple-900/30 to-slate-900 safe-area-bottom">
        <div className="max-w-lg mx-auto px-4 py-6 space-y-5">
          <div>
            <h2 className="text-xl font-bold">How did it go?</h2>
            <p className="text-sm text-gray-500 mt-0.5">Run time: {formatDuration(elapsed)}</p>
          </div>

          {/* Outcome */}
          {!run.outcome ? (
            <div className="grid grid-cols-3 gap-3">
              {[
                { id: 'victory',  label: '🏆 Victory',  cls: 'border-green-500 bg-green-900/20 text-green-300 hover:bg-green-900/40' },
                { id: 'defeated', label: '💀 Defeated',  cls: 'border-red-500/50 bg-red-900/20 text-red-300 hover:bg-red-900/40' },
                { id: 'abandoned',label: '🚪 Abandoned', cls: 'border-gray-600/50 bg-gray-900/20 text-gray-400 hover:bg-gray-900/40' },
              ].map(o => (
                <button key={o.id}
                  onClick={() => setRun(prev => ({ ...prev, outcome: o.id }))}
                  className={`py-4 rounded-xl border text-sm font-medium transition-colors ${o.cls}`}
                >
                  {o.label}
                </button>
              ))}
            </div>
          ) : (
            <div className="flex items-center gap-2 p-3 bg-black/20 rounded-lg border border-white/10">
              <span className={`text-sm font-medium ${run.outcome === 'victory' ? 'text-green-400' : run.outcome === 'defeated' ? 'text-red-400' : 'text-gray-400'}`}>
                {run.outcome === 'victory' ? '🏆 Victory' : run.outcome === 'defeated' ? '💀 Defeated' : '🚪 Abandoned'}
              </span>
              <button
                onClick={() => setRun(prev => ({ ...prev, outcome: null, deathLocation: null }))}
                className="text-gray-600 hover:text-gray-400 text-xs ml-auto"
              >
                Change
              </button>
            </div>
          )}

          {/* Death location */}
          {run.outcome === 'defeated' && (
            <div>
              <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">Where did you fall?</div>
              <div className="grid grid-cols-3 gap-2 sm:grid-cols-5">
                {DEATH_LOCATIONS.map(loc => (
                  <button
                    key={loc.id}
                    onClick={() => setRun(prev => ({ ...prev, deathLocation: prev.deathLocation === loc.id ? null : loc.id }))}
                    className={`flex flex-col items-center gap-1 py-3 rounded-xl border text-xs transition-colors ${
                      run.deathLocation === loc.id
                        ? 'border-red-500 bg-red-900/30 text-red-300'
                        : 'border-white/10 bg-black/20 text-gray-400 hover:border-white/30'
                    }`}
                  >
                    <span className="text-lg">{loc.icon}</span>
                    <span>{loc.label}</span>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Notes */}
          <div>
            <div className="text-xs text-gray-500 uppercase tracking-wider mb-1">Notes (optional)</div>
            <textarea
              rows={3}
              value={run.notes}
              onChange={e => setRun(prev => ({ ...prev, notes: e.target.value }))}
              placeholder="What happened? Build notes, synergies..."
              className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none resize-none text-gray-200 placeholder-gray-600"
            />
          </div>

          <div className="flex gap-2">
            <button onClick={() => setPhase('active')} className="btn-secondary flex-1">← Back</button>
            <button
              onClick={handleSaveRun}
              disabled={!run.outcome}
              className={`flex-1 py-3 rounded-xl text-sm font-semibold transition-colors ${
                run.outcome ? 'btn-primary' : 'bg-gray-800 text-gray-500 cursor-not-allowed'
              }`}
            >
              Save Run
            </button>
          </div>
        </div>
      </div>
    );
  }

  // ── Active ────────────────────────────────────────────────────────────────
  return (
    <div className="min-h-screen bg-gradient-to-b from-red-900/20 via-purple-900/30 to-slate-900 safe-area-bottom">
      {/* Sticky header */}
      <div className="sticky top-0 z-10 bg-black/80 backdrop-blur border-b border-red-500/20 safe-area-top">
        <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between gap-4">
          <div>
            <div className="text-3xl font-mono font-bold tabular-nums text-white">{formatDuration(elapsed)}</div>
            <div className="text-xs text-gray-500">
              {run.weapon || 'No weapon'}
              {run.aspect ? ` · ${run.aspect}` : ''}
              {run.heatLevel > 0 ? ` · Heat ${run.heatLevel}` : ''}
            </div>
          </div>
          <button onClick={() => setPhase('ending')} className="btn-danger text-sm shrink-0">End Run</button>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 py-4 space-y-4">
        {/* God chips */}
        <div className="card p-4">
          <div className="text-xs text-gray-500 uppercase tracking-wider mb-3">Gods Seen</div>
          <div className="flex flex-wrap gap-2">
            {GODS.map(god => {
              const active = run.gods.includes(god);
              const colors = GOD_COLORS[god] || { off: 'border-gray-600/40 text-gray-500', on: 'bg-gray-600 border-gray-500 text-white' };
              return (
                <button
                  key={god}
                  onClick={() => toggleGod(god)}
                  className={`px-3 py-1.5 rounded-full border text-xs font-medium transition-colors ${active ? colors.on : colors.off}`}
                >
                  {god}
                </button>
              );
            })}
          </div>
        </div>

        {/* Hammers */}
        {run.weapon && (
          <div className="card p-4">
            <div className="flex items-center justify-between mb-2">
              <div className="text-xs text-gray-500 uppercase tracking-wider">🔨 Hammers</div>
              <button
                onClick={() => setShowHammerPicker(!showHammerPicker)}
                className="text-xs text-purple-400 hover:text-purple-300"
              >
                {showHammerPicker ? 'Done' : '+ Add'}
              </button>
            </div>
            {run.hammerUpgrades.length > 0 && (
              <div className="flex flex-wrap gap-1.5 mb-2">
                {run.hammerUpgrades.map(h => (
                  <span key={h} className="inline-flex items-center gap-1 text-xs bg-amber-900/30 text-amber-300 border border-amber-700/30 px-2 py-1 rounded-full">
                    {h}
                    <button onClick={() => removeHammer(h)} className="hover:text-white ml-0.5">×</button>
                  </span>
                ))}
              </div>
            )}
            {showHammerPicker && (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-1 max-h-40 overflow-y-auto">
                {availableHammers.filter(h => !run.hammerUpgrades.includes(h)).map(h => (
                  <button key={h} onClick={() => addHammer(h)}
                    className="text-left text-xs px-2 py-1.5 rounded hover:bg-white/10 text-gray-400 min-h-[32px]"
                  >
                    + {h}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Boons (optional detailed tracking) */}
        <div className="card p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="text-xs text-gray-500 uppercase tracking-wider">
              Boons
              <span className="normal-case font-normal text-gray-600 ml-1">(optional)</span>
              {run.boons.length > 0 && <span className="ml-1 text-purple-400">{run.boons.length}</span>}
            </div>
            <button
              onClick={() => setShowBoonPicker(!showBoonPicker)}
              className="text-xs text-purple-400 hover:text-purple-300"
            >
              {showBoonPicker ? 'Done' : '+ Add'}
            </button>
          </div>

          {showBoonPicker && (
            <div className="mb-3 border border-purple-500/20 rounded-lg p-3 bg-black/30">
              <div className="flex flex-wrap gap-1 mb-2">
                {GODS.map(god => (
                  <button key={god} onClick={() => { setBoonGod(god); setBoonSearch(''); }}
                    className={`text-xs px-2 py-1 rounded min-h-[28px] ${boonGod === god ? 'bg-purple-600 text-white' : 'bg-white/5 text-gray-400 hover:bg-white/10'}`}
                  >
                    {god}
                  </button>
                ))}
              </div>
              {boonGod && (
                <>
                  <div className="relative mb-2">
                    <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3 h-3 text-gray-500" />
                    <input type="text" placeholder={`Search ${boonGod}...`} value={boonSearch}
                      onChange={e => setBoonSearch(e.target.value)}
                      className="input-field pl-7 text-xs py-1.5" autoFocus
                    />
                  </div>
                  <div className="max-h-48 overflow-y-auto space-y-0.5">
                    {getFilteredBoons().map(b => {
                      const isCollected = collectedNames.has(`${b.god}:${b.name}`);
                      return (
                        <button key={`${b.god}-${b.name}`}
                          onClick={() => !isCollected && addBoon(b.god, b.name, b.slot)}
                          disabled={isCollected}
                          className={`w-full text-left flex items-center justify-between px-2 py-1.5 rounded text-xs min-h-[32px] ${
                            isCollected ? 'text-gray-600 cursor-not-allowed' : 'text-gray-300 hover:bg-purple-600/20'
                          }`}
                        >
                          <span>{isCollected ? '✓ ' : ''}{b.name}</span>
                          <span className={`text-[10px] px-1 py-0.5 rounded ${slotColor(b.slot)}`}>{b.slot}</span>
                        </button>
                      );
                    })}
                  </div>
                </>
              )}
            </div>
          )}

          {run.boons.length > 0 && (
            <div className="space-y-1 max-h-48 overflow-y-auto">
              {groupBoonsByGod(run.boons).map(([god, boons]) => (
                <div key={god} className="mb-1.5">
                  <div className="text-[10px] text-purple-400 font-medium mb-0.5">{god}</div>
                  {boons.map((boon, idx) => {
                    const globalIdx = run.boons.findIndex(b => b.god === boon.god && b.name === boon.name);
                    return (
                      <div key={`${boon.name}-${idx}`} className="flex items-center justify-between pl-2 py-0.5 text-xs">
                        <span className="text-gray-300">{boon.name}</span>
                        <button onClick={() => removeBoon(globalIdx)} className="text-gray-600 hover:text-red-400 p-1">
                          <X className="w-3 h-3" />
                        </button>
                      </div>
                    );
                  })}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Notes */}
        <div className="card p-4">
          <div className="text-xs text-gray-500 uppercase tracking-wider mb-1">Notes</div>
          <textarea
            rows={3}
            value={run.notes}
            onChange={e => setRun(prev => ({ ...prev, notes: e.target.value }))}
            placeholder="Strategy, synergies, what to try..."
            className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none resize-none text-gray-200 placeholder-gray-600"
          />
        </div>
      </div>
    </div>
  );
}

function groupBoonsByGod(boons) {
  const grouped = {};
  boons.forEach(b => {
    if (!grouped[b.god]) grouped[b.god] = [];
    grouped[b.god].push(b);
  });
  return Object.entries(grouped);
}

function slotColor(slot) {
  const colors = {
    attack: 'bg-red-900/40 text-red-300',
    special: 'bg-blue-900/40 text-blue-300',
    cast: 'bg-green-900/40 text-green-300',
    dash: 'bg-cyan-900/40 text-cyan-300',
    call: 'bg-yellow-900/40 text-yellow-300',
    other: 'bg-gray-800 text-gray-400',
    legendary: 'bg-amber-900/40 text-amber-300',
    blessing: 'bg-emerald-900/40 text-emerald-300',
    curse: 'bg-red-900/40 text-red-300',
  };
  return colors[slot] || 'bg-gray-800 text-gray-400';
}
