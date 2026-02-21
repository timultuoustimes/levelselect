import React, { useState, useEffect, useRef } from 'react';
import { Play, Pause, Trophy, Skull, X } from 'lucide-react';
import { STARTING_SPELLS, RUN_SPELLS } from '../../data/loneRuinData.js';

const ALL_SPELLS = [...STARTING_SPELLS, ...RUN_SPELLS];

function formatTime(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

export default function LoneRuinRunView({ run, onEnd, onCancel }) {
  const [elapsed, setElapsed] = useState(run.accumulatedTime || 0);
  const [paused, setPaused] = useState(false);
  const [spellInput, setSpellInput] = useState('');
  const [showSpellSuggestions, setShowSpellSuggestions] = useState(false);
  const [runData, setRunData] = useState(run);
  const intervalRef = useRef(null);

  useEffect(() => {
    if (!paused) {
      intervalRef.current = setInterval(() => setElapsed(e => e + 1), 1000);
    }
    return () => clearInterval(intervalRef.current);
  }, [paused]);

  const update = (field, value) =>
    setRunData(prev => ({ ...prev, [field]: value }));

  const addSpell = (spellName) => {
    const name = spellName.trim();
    if (!name || runData.spellsAcquired.includes(name)) return;
    update('spellsAcquired', [...runData.spellsAcquired, name]);
    setSpellInput('');
    setShowSpellSuggestions(false);
  };

  const removeSpell = (spell) =>
    update('spellsAcquired', runData.spellsAcquired.filter(s => s !== spell));

  const handleEnd = (outcome) => {
    onEnd({
      ...runData,
      outcome,
      duration: elapsed,
      endTime: new Date().toISOString(),
    });
  };

  const suggestions = spellInput.length > 0
    ? ALL_SPELLS.filter(s =>
        s.name.toLowerCase().includes(spellInput.toLowerCase()) &&
        !runData.spellsAcquired.includes(s.name)
      )
    : [];

  const startingSpellData = STARTING_SPELLS.find(s => s.name === runData.startingSpell);

  return (
    <div className="min-h-screen bg-gradient-to-b from-indigo-950 via-purple-950 to-black text-white p-4">
      <div className="max-w-3xl mx-auto space-y-4">

        {/* Timer bar */}
        <div className="card p-4 text-center border-purple-500/50">
          <div className="text-5xl font-mono font-bold text-purple-300 mb-3">
            {formatTime(elapsed)}
          </div>
          <div className="flex justify-center gap-3">
            <button
              onClick={() => setPaused(p => !p)}
              className="btn-secondary gap-2 flex items-center"
            >
              {paused ? <Play size={16} /> : <Pause size={16} />}
              {paused ? 'Resume' : 'Pause'}
            </button>
            <button
              onClick={() => handleEnd('victory')}
              className="bg-green-600 hover:bg-green-700 text-white font-semibold px-4 py-2 rounded-lg flex items-center gap-2"
            >
              <Trophy size={16} /> Victory
            </button>
            <button
              onClick={() => handleEnd('defeated')}
              className="bg-red-600 hover:bg-red-700 text-white font-semibold px-4 py-2 rounded-lg flex items-center gap-2"
            >
              <Skull size={16} /> Defeated
            </button>
            <button
              onClick={onCancel}
              className="bg-gray-700 hover:bg-gray-600 text-white px-3 py-2 rounded-lg flex items-center gap-2"
            >
              <X size={16} /> Cancel
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">

          {/* Loadout info */}
          <div className="card p-4 space-y-3">
            <h3 className="font-bold text-purple-300 text-sm uppercase tracking-wide">Loadout</h3>

            {startingSpellData && (
              <div className="bg-purple-900/30 rounded-lg p-3 flex items-center gap-3">
                <span className="text-3xl">{startingSpellData.icon}</span>
                <div>
                  <div className="font-semibold">{startingSpellData.name}</div>
                  <div className="text-xs text-gray-400">{startingSpellData.description}</div>
                </div>
              </div>
            )}

            <div className="grid grid-cols-2 gap-2 text-sm">
              <div className="bg-black/30 rounded p-2">
                <div className="text-gray-400 text-xs">Mode</div>
                <div className="font-semibold">{runData.mode}</div>
              </div>
              <div className="bg-black/30 rounded p-2">
                <div className="text-gray-400 text-xs">Difficulty</div>
                <div className="font-semibold">{runData.difficulty}</div>
              </div>
            </div>

            {/* Floor/Wave reached */}
            {runData.mode === 'Campaign' ? (
              <div>
                <label className="text-gray-400 text-xs block mb-1">Floor Reached (1–21)</label>
                <input
                  type="number"
                  min="1"
                  max="21"
                  value={runData.floorReached || ''}
                  onChange={e => update('floorReached', parseInt(e.target.value) || null)}
                  placeholder="e.g. 14"
                  className="input-field w-full text-sm"
                />
              </div>
            ) : (
              <div>
                <label className="text-gray-400 text-xs block mb-1">Waves Survived</label>
                <input
                  type="number"
                  min="1"
                  value={runData.wavesReached || ''}
                  onChange={e => update('wavesReached', parseInt(e.target.value) || null)}
                  placeholder="e.g. 8"
                  className="input-field w-full text-sm"
                />
              </div>
            )}
          </div>

          {/* Spells acquired during run */}
          <div className="card p-4 space-y-3">
            <h3 className="font-bold text-purple-300 text-sm uppercase tracking-wide">
              Spells Acquired
              <span className="text-gray-400 font-normal ml-2">({runData.spellsAcquired.length})</span>
            </h3>

            <div className="relative">
              <input
                type="text"
                value={spellInput}
                onChange={e => { setSpellInput(e.target.value); setShowSpellSuggestions(true); }}
                onKeyDown={e => { if (e.key === 'Enter') addSpell(spellInput); }}
                onFocus={() => setShowSpellSuggestions(true)}
                onBlur={() => setTimeout(() => setShowSpellSuggestions(false), 150)}
                placeholder="Add spell (or type name)…"
                className="input-field w-full text-sm"
              />
              {showSpellSuggestions && suggestions.length > 0 && (
                <div className="absolute z-10 w-full mt-1 bg-gray-900 border border-purple-500/40 rounded-lg overflow-hidden shadow-xl">
                  {suggestions.map(s => (
                    <button
                      key={s.id}
                      onMouseDown={() => addSpell(s.name)}
                      className="w-full text-left px-3 py-2 hover:bg-purple-900/40 flex items-center gap-2 text-sm"
                    >
                      <span>{s.icon}</span>
                      <span className="font-medium">{s.name}</span>
                      <span className="text-gray-500 text-xs ml-auto capitalize">{s.type}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>

            <div className="space-y-1 max-h-48 overflow-y-auto">
              {runData.spellsAcquired.length === 0 ? (
                <p className="text-gray-500 text-sm text-center py-4">No spells added yet</p>
              ) : (
                runData.spellsAcquired.map(spellName => {
                  const data = ALL_SPELLS.find(s => s.name === spellName);
                  return (
                    <div key={spellName} className="flex items-center gap-2 bg-purple-900/20 rounded px-3 py-2">
                      <span>{data?.icon || '✨'}</span>
                      <span className="flex-1 text-sm font-medium">{spellName}</span>
                      <button
                        onClick={() => removeSpell(spellName)}
                        className="text-gray-500 hover:text-red-400 text-xs"
                      >
                        ✕
                      </button>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        </div>

        {/* Notes */}
        <div className="card p-4">
          <h3 className="font-bold text-purple-300 text-sm uppercase tracking-wide mb-2">Notes</h3>
          <textarea
            value={runData.notes}
            onChange={e => update('notes', e.target.value)}
            placeholder="Strategy, synergies, what went wrong…"
            rows={3}
            className="input-field w-full text-sm resize-none"
          />
        </div>
      </div>
    </div>
  );
}
