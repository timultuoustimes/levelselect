import React, { useState, useEffect, useRef, useCallback } from 'react';
import { createRun } from '../../utils/factories.js';
import { formatDuration } from '../../utils/format.js';
import { WEAPONS } from '../../data/hadesWeapons.js';
import { KEEPSAKES } from '../../data/hadesKeepsakes.js';
import { BOONS_BY_GOD, GODS } from '../../data/hadesBoons.js';
import { Pause, Play, X, Search } from 'lucide-react';

export default function RunView({ save, onEndRun, onCancelRun }) {
  const [run, setRun] = useState(() => createRun());
  const [isPaused, setIsPaused] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [boonGod, setBoonGod] = useState('');
  const [boonSearch, setBoonSearch] = useState('');
  const [showBoonPicker, setShowBoonPicker] = useState(false);
  const [showHammerPicker, setShowHammerPicker] = useState(false);
  const [confirmEnd, setConfirmEnd] = useState(null); // 'victory' | 'defeated' | null
  const timerRef = useRef(null);
  const startTimeRef = useRef(Date.now());

  // Timer logic
  useEffect(() => {
    if (isPaused) {
      clearInterval(timerRef.current);
      return;
    }

    startTimeRef.current = Date.now();
    timerRef.current = setInterval(() => {
      setElapsed(prev => prev + 1);
    }, 1000);

    return () => clearInterval(timerRef.current);
  }, [isPaused]);

  const togglePause = () => setIsPaused(p => !p);

  // Get weapon data for current selection
  const selectedWeapon = WEAPONS.find(w => w.name === run.weapon);
  const availableAspects = selectedWeapon?.aspects || [];
  const availableHammers = selectedWeapon?.hammerUpgrades || [];

  // Get unlocked keepsakes
  const unlockedKeepsakes = (save?.keepsakes || []).filter(k => k.unlocked);
  const allKeepsakes = unlockedKeepsakes.length > 0 ? unlockedKeepsakes : KEEPSAKES;

  // End run
  const handleEnd = (outcome) => {
    clearInterval(timerRef.current);
    const completedRun = {
      ...run,
      endTime: new Date().toISOString(),
      outcome,
      duration: elapsed,
    };
    onEndRun(completedRun);
  };

  // Cancel run
  const handleCancel = () => {
    clearInterval(timerRef.current);
    onCancelRun();
  };

  // Add boon
  const addBoon = (god, name, slot) => {
    setRun(prev => ({
      ...prev,
      boons: [...prev.boons, { god, name, slot }],
    }));
    setBoonSearch('');
  };

  // Remove boon
  const removeBoon = (index) => {
    setRun(prev => ({
      ...prev,
      boons: prev.boons.filter((_, i) => i !== index),
    }));
  };

  // Add hammer
  const addHammer = (name) => {
    if (run.hammerUpgrades.includes(name)) return;
    setRun(prev => ({
      ...prev,
      hammerUpgrades: [...prev.hammerUpgrades, name],
    }));
  };

  // Remove hammer
  const removeHammer = (name) => {
    setRun(prev => ({
      ...prev,
      hammerUpgrades: prev.hammerUpgrades.filter(h => h !== name),
    }));
  };

  // Get searchable boons
  const getFilteredBoons = () => {
    if (!boonGod) return [];
    const godBoons = BOONS_BY_GOD[boonGod];
    if (!godBoons) return [];

    const allSlotBoons = [];
    const slots = ['attack', 'special', 'cast', 'dash', 'call', 'other', 'legendary'];

    // Handle Chaos separately
    if (boonGod === 'Chaos') {
      (godBoons.blessings || []).forEach(name => {
        allSlotBoons.push({ name, slot: 'blessing', god: boonGod });
      });
      (godBoons.curses || []).forEach(name => {
        allSlotBoons.push({ name, slot: 'curse', god: boonGod });
      });
    } else {
      slots.forEach(slot => {
        (godBoons[slot] || []).forEach(name => {
          allSlotBoons.push({ name, slot, god: boonGod });
        });
      });
    }

    // Filter by search
    if (boonSearch) {
      return allSlotBoons.filter(b =>
        b.name.toLowerCase().includes(boonSearch.toLowerCase())
      );
    }
    return allSlotBoons;
  };

  // Already collected boon names (to grey them out)
  const collectedNames = new Set(run.boons.map(b => `${b.god}:${b.name}`));

  return (
    <div className="min-h-screen bg-gradient-to-b from-red-900/30 via-purple-900/40 to-black safe-area-bottom">
      {/* Timer Header */}
      <div className="sticky top-0 z-10 bg-black/80 backdrop-blur border-b border-red-500/20">
        <div className="max-w-7xl mx-auto px-4 py-3">
          {/* Timer */}
          <div className="text-center mb-3">
            <div className={`text-4xl sm:text-5xl font-mono font-bold tabular-nums ${isPaused ? 'text-gray-500' : 'text-white'}`}>
              {formatDuration(elapsed)}
            </div>
            {isPaused && <div className="text-xs text-yellow-400 mt-1">PAUSED</div>}
          </div>

          {/* Action buttons */}
          <div className="flex gap-2 justify-center flex-wrap">
            <button onClick={togglePause} className="btn-secondary text-sm gap-1.5">
              {isPaused ? <Play className="w-4 h-4" /> : <Pause className="w-4 h-4" />}
              {isPaused ? 'Resume' : 'Pause'}
            </button>

            {confirmEnd === 'victory' ? (
              <div className="flex gap-2">
                <button onClick={() => handleEnd('victory')} className="btn-success text-sm">
                  Confirm Victory
                </button>
                <button onClick={() => setConfirmEnd(null)} className="btn-secondary text-sm">
                  Cancel
                </button>
              </div>
            ) : confirmEnd === 'defeated' ? (
              <div className="flex gap-2">
                <button onClick={() => handleEnd('defeated')} className="btn-danger text-sm">
                  Confirm Defeat
                </button>
                <button onClick={() => setConfirmEnd(null)} className="btn-secondary text-sm">
                  Cancel
                </button>
              </div>
            ) : (
              <>
                <button onClick={() => setConfirmEnd('victory')} className="btn-success text-sm">
                  🏆 Victory
                </button>
                <button onClick={() => setConfirmEnd('defeated')} className="btn-danger text-sm">
                  💀 Defeated
                </button>
                <button onClick={handleCancel} className="btn-secondary text-sm text-gray-400">
                  Cancel
                </button>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Run Content */}
      <div className="max-w-7xl mx-auto px-4 py-4">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {/* Left: Loadout */}
          <div className="space-y-4">
            <div className="card p-4">
              <h3 className="font-semibold mb-3">Loadout</h3>
              <div className="space-y-3">
                {/* Weapon */}
                <div>
                  <label className="text-xs text-gray-500 mb-1 block">Weapon</label>
                  <select
                    value={run.weapon}
                    onChange={e => setRun(prev => ({ ...prev, weapon: e.target.value, aspect: '', hammerUpgrades: [] }))}
                    className="input-field"
                  >
                    <option value="">Select weapon...</option>
                    {WEAPONS.map(w => (
                      <option key={w.id} value={w.name}>{w.icon} {w.name}</option>
                    ))}
                  </select>
                </div>

                {/* Aspect */}
                {run.weapon && (
                  <div>
                    <label className="text-xs text-gray-500 mb-1 block">Aspect</label>
                    <select
                      value={run.aspect}
                      onChange={e => setRun(prev => ({ ...prev, aspect: e.target.value }))}
                      className="input-field"
                    >
                      <option value="">Select aspect...</option>
                      {availableAspects.map(a => (
                        <option key={a.id} value={a.name}>{a.name}</option>
                      ))}
                    </select>
                  </div>
                )}

                {/* Keepsake */}
                <div>
                  <label className="text-xs text-gray-500 mb-1 block">Keepsake</label>
                  <select
                    value={run.keepsake}
                    onChange={e => setRun(prev => ({ ...prev, keepsake: e.target.value }))}
                    className="input-field"
                  >
                    <option value="">Select keepsake...</option>
                    {allKeepsakes.map(k => (
                      <option key={k.id} value={k.name}>{k.name} ({k.source})</option>
                    ))}
                  </select>
                </div>

                {/* Heat Level */}
                <div>
                  <label className="text-xs text-gray-500 mb-1 block">Heat Level</label>
                  <input
                    type="number"
                    min="0"
                    max="64"
                    value={run.heatLevel}
                    onChange={e => setRun(prev => ({ ...prev, heatLevel: parseInt(e.target.value) || 0 }))}
                    className="input-field w-24"
                  />
                </div>
              </div>
            </div>

            {/* Hammer Upgrades */}
            {run.weapon && (
              <div className="card p-4">
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-semibold">🔨 Hammer Upgrades</h3>
                  <button
                    onClick={() => setShowHammerPicker(!showHammerPicker)}
                    className="btn-secondary text-xs"
                  >
                    {showHammerPicker ? 'Close' : '+ Add'}
                  </button>
                </div>

                {/* Selected hammers */}
                {run.hammerUpgrades.length > 0 && (
                  <div className="flex flex-wrap gap-1.5 mb-3">
                    {run.hammerUpgrades.map(h => (
                      <span
                        key={h}
                        className="inline-flex items-center gap-1 text-xs bg-amber-900/30 text-amber-300 px-2 py-1 rounded"
                      >
                        {h}
                        <button onClick={() => removeHammer(h)} className="hover:text-white ml-1">×</button>
                      </span>
                    ))}
                  </div>
                )}

                {/* Picker */}
                {showHammerPicker && (
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-1 max-h-48 overflow-y-auto scroll-smooth-ios">
                    {availableHammers.map(h => {
                      const selected = run.hammerUpgrades.includes(h);
                      return (
                        <button
                          key={h}
                          onClick={() => selected ? removeHammer(h) : addHammer(h)}
                          className={`text-left text-xs px-2 py-1.5 rounded min-h-[36px] ${
                            selected
                              ? 'bg-amber-600/30 text-amber-300'
                              : 'hover:bg-white/10 text-gray-400'
                          }`}
                        >
                          {selected ? '✓ ' : ''}{h}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            )}

            {/* Notes */}
            <div className="card p-4">
              <h3 className="font-semibold mb-2">📝 Notes</h3>
              <textarea
                value={run.notes}
                onChange={e => setRun(prev => ({ ...prev, notes: e.target.value }))}
                placeholder="Strategy notes, synergies, what went wrong..."
                className="input-field h-24 resize-none"
              />
            </div>
          </div>

          {/* Right: Boons */}
          <div className="card p-4">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-semibold">
                Boons <span className="text-gray-500 text-sm font-normal">({run.boons.length})</span>
              </h3>
              <button
                onClick={() => setShowBoonPicker(!showBoonPicker)}
                className="btn-primary text-xs"
              >
                {showBoonPicker ? 'Close' : '+ Add Boon'}
              </button>
            </div>

            {/* Boon Picker */}
            {showBoonPicker && (
              <div className="mb-4 border border-purple-500/20 rounded-lg p-3 bg-black/30">
                {/* God selector */}
                <div className="flex flex-wrap gap-1 mb-2">
                  {GODS.map(god => (
                    <button
                      key={god}
                      onClick={() => { setBoonGod(god); setBoonSearch(''); }}
                      className={`text-xs px-2 py-1 rounded min-h-[32px] ${
                        boonGod === god
                          ? 'bg-purple-600 text-white'
                          : 'bg-white/5 text-gray-400 hover:bg-white/10'
                      }`}
                    >
                      {god}
                    </button>
                  ))}
                </div>

                {boonGod && (
                  <>
                    {/* Search within god */}
                    <div className="relative mb-2">
                      <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3 h-3 text-gray-500" />
                      <input
                        type="text"
                        placeholder={`Search ${boonGod} boons...`}
                        value={boonSearch}
                        onChange={e => setBoonSearch(e.target.value)}
                        className="input-field pl-7 text-sm py-1.5 min-h-[36px]"
                        autoFocus
                      />
                    </div>

                    {/* Boon list */}
                    <div className="max-h-60 overflow-y-auto scroll-smooth-ios space-y-0.5">
                      {getFilteredBoons().map(b => {
                        const isCollected = collectedNames.has(`${b.god}:${b.name}`);
                        return (
                          <button
                            key={`${b.god}-${b.name}`}
                            onClick={() => !isCollected && addBoon(b.god, b.name, b.slot)}
                            disabled={isCollected}
                            className={`w-full text-left flex items-center justify-between px-2 py-1.5 rounded text-xs min-h-[36px] ${
                              isCollected
                                ? 'text-gray-600 cursor-not-allowed'
                                : 'text-gray-300 hover:bg-purple-600/20'
                            }`}
                          >
                            <span>{isCollected ? '✓ ' : ''}{b.name}</span>
                            <span className={`text-[10px] px-1.5 py-0.5 rounded ${slotColor(b.slot)}`}>
                              {b.slot}
                            </span>
                          </button>
                        );
                      })}
                    </div>
                  </>
                )}
              </div>
            )}

            {/* Collected Boons */}
            {run.boons.length === 0 ? (
              <p className="text-gray-500 text-sm text-center py-4">
                No boons collected yet. Tap "+ Add Boon" to start tracking.
              </p>
            ) : (
              <div className="space-y-1 max-h-96 overflow-y-auto scroll-smooth-ios">
                {/* Group by god */}
                {groupBoonsByGod(run.boons).map(([god, boons]) => (
                  <div key={god} className="mb-2">
                    <div className="text-xs text-purple-400 font-medium mb-1">{god}</div>
                    {boons.map((boon, idx) => {
                      const globalIdx = run.boons.findIndex(
                        b => b.god === boon.god && b.name === boon.name
                      );
                      return (
                        <div
                          key={`${boon.name}-${idx}`}
                          className="flex items-center justify-between pl-3 py-1 text-sm"
                        >
                          <span className="flex items-center gap-2">
                            <span className="text-gray-300">{boon.name}</span>
                            <span className={`text-[10px] px-1.5 py-0.5 rounded ${slotColor(boon.slot)}`}>
                              {boon.slot}
                            </span>
                          </span>
                          <button
                            onClick={() => removeBoon(globalIdx)}
                            className="text-gray-500 hover:text-red-400 p-1 min-h-[32px] min-w-[32px] flex items-center justify-center"
                          >
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
    duo: 'bg-purple-900/40 text-purple-300',
    blessing: 'bg-emerald-900/40 text-emerald-300',
    curse: 'bg-red-900/40 text-red-300',
  };
  return colors[slot] || 'bg-gray-800 text-gray-400';
}
