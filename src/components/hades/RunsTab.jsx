import React, { useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { formatDuration, formatDate, winRate } from '../../utils/format.js';
import { WEAPONS } from '../../data/hadesWeapons.js';

const WEAPON_ICONS = {
  'Stygian Blade': '⚔️',
  'Eternal Spear': '🔱',
  'Shield of Chaos': '🛡️',
  'Heart-Seeking Bow': '🏹',
  'Twin Fists': '🥊',
  'Adamant Rail': '🔫',
};

const DEATH_LOCATION_LABELS = {
  tartarus: 'Tartarus',
  asphodel: 'Asphodel',
  elysium: 'Elysium',
  styx: 'Styx',
  'final-boss': 'Final Boss',
};

const DEATH_LOCATION_COLORS = {
  tartarus:    'bg-slate-700/60 text-slate-300',
  asphodel:    'bg-orange-700/60 text-orange-300',
  elysium:     'bg-blue-700/60 text-blue-300',
  styx:        'bg-purple-700/60 text-purple-300',
  'final-boss':'bg-red-700/60 text-red-300',
};

// Derive god list from a run — supports both quick-log (run.gods) and legacy detailed boons
function runGods(run) {
  if (run.gods?.length > 0) return run.gods;
  return [...new Set((run.boons || []).map(b => b.god))];
}

function RunRow({ run, expanded, onToggle }) {
  const gods = runGods(run);
  const isVictory = run.outcome === 'victory';
  const isDefeated = run.outcome === 'defeated';

  return (
    <div className={`rounded-lg border overflow-hidden transition-colors ${
      isVictory ? 'border-green-500/20 bg-green-900/5'
      : isDefeated ? 'border-red-500/20 bg-red-900/5'
      : 'border-white/10 bg-black/20'
    }`}>
      {/* Compact row */}
      <button
        onClick={onToggle}
        className="w-full text-left flex items-center gap-3 px-3 py-2.5 hover:bg-white/5 transition-colors min-h-[48px]"
      >
        <span className="text-base shrink-0">{WEAPON_ICONS[run.weapon] || '⚔️'}</span>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm font-medium text-gray-200 truncate">
              {run.weapon || 'Unknown'}{run.aspect ? ` · ${run.aspect}` : ''}
            </span>
            {run.heatLevel > 0 && (
              <span className="text-[10px] text-orange-400 bg-orange-900/30 border border-orange-700/30 rounded px-1.5 py-0.5">
                🔥 {run.heatLevel}
              </span>
            )}
            {isDefeated && run.deathLocation && (
              <span className={`text-[10px] rounded px-1.5 py-0.5 ${DEATH_LOCATION_COLORS[run.deathLocation] || 'bg-gray-700 text-gray-300'}`}>
                ✝ {DEATH_LOCATION_LABELS[run.deathLocation]}
              </span>
            )}
          </div>
          {gods.length > 0 && (
            <div className="text-[10px] text-gray-500 mt-0.5 truncate">
              {gods.join(' · ')}
            </div>
          )}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <div className="text-right">
            <div className={`text-xs font-medium ${isVictory ? 'text-green-400' : isDefeated ? 'text-red-400' : 'text-gray-500'}`}>
              {isVictory ? '🏆' : isDefeated ? '💀' : '✕'}
            </div>
            <div className="text-[10px] text-gray-600">{formatDuration(run.duration)}</div>
          </div>
          {expanded
            ? <ChevronDown className="w-3.5 h-3.5 text-gray-600 shrink-0" />
            : <ChevronRight className="w-3.5 h-3.5 text-gray-600 shrink-0" />
          }
        </div>
      </button>

      {/* Expanded detail */}
      {expanded && (
        <div className="px-3 pb-3 pt-1 border-t border-white/5 space-y-2 text-xs">
          <div className="text-gray-600">{formatDate(run.endTime)}</div>

          {run.keepsake && (
            <div><span className="text-gray-500">Keepsake:</span> <span className="text-gray-300">{run.keepsake}</span></div>
          )}

          {run.hammerUpgrades?.length > 0 && (
            <div>
              <span className="text-gray-500">Hammers:</span>{' '}
              <span className="text-amber-300">{run.hammerUpgrades.join(', ')}</span>
            </div>
          )}

          {run.boons?.length > 0 && (
            <div>
              <div className="text-gray-500 mb-1">Boons ({run.boons.length}):</div>
              <div className="flex flex-wrap gap-1">
                {run.boons.map((b, i) => (
                  <span key={i} className={`px-1.5 py-0.5 rounded ${slotColor(b.slot)}`}>
                    {b.name}
                  </span>
                ))}
              </div>
            </div>
          )}

          {run.notes && (
            <div className="text-gray-400 italic">"{run.notes}"</div>
          )}
        </div>
      )}
    </div>
  );
}

function AnalyticsSection({ runs }) {
  const [open, setOpen] = useState(false);
  if (runs.length < 3) return null;

  const victories = runs.filter(r => r.outcome === 'victory');
  const defeats = runs.filter(r => r.outcome === 'defeated');

  // Weapon performance
  const weaponStats = {};
  runs.forEach(run => {
    const k = run.weapon || 'Unknown';
    if (!weaponStats[k]) weaponStats[k] = { total: 0, victories: 0 };
    weaponStats[k].total++;
    if (run.outcome === 'victory') weaponStats[k].victories++;
  });
  const sortedWeapons = Object.entries(weaponStats)
    .map(([w, s]) => ({ weapon: w, ...s, rate: winRate(s.victories, s.total) }))
    .sort((a, b) => b.rate - a.rate);

  // Death locations
  const locationStats = {};
  defeats.forEach(r => {
    if (r.deathLocation) {
      locationStats[r.deathLocation] = (locationStats[r.deathLocation] || 0) + 1;
    }
  });
  const sortedLocations = Object.entries(locationStats)
    .map(([loc, count]) => ({ loc, count, pct: Math.round((count / defeats.length) * 100) }))
    .sort((a, b) => b.count - a.count);

  // God presence in victories
  const godFreq = {};
  victories.forEach(run => {
    runGods(run).forEach(g => { godFreq[g] = (godFreq[g] || 0) + 1; });
  });
  const sortedGods = Object.entries(godFreq)
    .map(([g, c]) => ({ god: g, count: c, pct: Math.round((c / Math.max(victories.length, 1)) * 100) }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 6);

  return (
    <div className="bg-black/40 rounded-xl border border-white/10 overflow-hidden">
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center justify-between px-4 py-3 hover:bg-white/5 transition-colors text-left"
      >
        <span className="text-sm font-semibold text-gray-300">Analytics</span>
        {open ? <ChevronDown className="w-4 h-4 text-gray-500" /> : <ChevronRight className="w-4 h-4 text-gray-500" />}
      </button>

      {open && (
        <div className="px-4 pb-4 space-y-5 border-t border-white/5">
          {/* Weapon performance */}
          <div>
            <div className="text-xs text-gray-500 uppercase tracking-wider mb-2 mt-3">Weapon win rates</div>
            <div className="space-y-2">
              {sortedWeapons.map(w => (
                <div key={w.weapon}>
                  <div className="flex items-center justify-between mb-1 text-xs">
                    <span className="text-gray-300">{WEAPON_ICONS[w.weapon] || '⚔️'} {w.weapon}</span>
                    <span className={w.rate >= 50 ? 'text-green-400' : w.rate >= 25 ? 'text-amber-400' : 'text-red-400'}>
                      {w.rate}% <span className="text-gray-600">({w.victories}/{w.total})</span>
                    </span>
                  </div>
                  <div className="h-1.5 bg-black/30 rounded-full overflow-hidden">
                    <div className={`h-full rounded-full ${w.rate >= 50 ? 'bg-green-500' : w.rate >= 25 ? 'bg-amber-500' : 'bg-red-500'}`}
                      style={{ width: `${w.rate}%` }} />
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Death locations */}
          {sortedLocations.length > 0 && (
            <div>
              <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">Where defeats happen</div>
              <div className="space-y-1.5">
                {sortedLocations.map(({ loc, count, pct }) => (
                  <div key={loc} className="flex items-center gap-2 text-xs">
                    <span className={`w-20 text-right shrink-0 ${DEATH_LOCATION_COLORS[loc]?.replace('bg-', '').replace('/60', '') || 'text-gray-400'}`}>
                      {DEATH_LOCATION_LABELS[loc]}
                    </span>
                    <div className="flex-1 h-2 bg-black/30 rounded-full overflow-hidden">
                      <div className={`h-full rounded-full ${DEATH_LOCATION_COLORS[loc] || 'bg-gray-500'}`}
                        style={{ width: `${pct}%` }} />
                    </div>
                    <span className="text-gray-500 w-12">{count}× ({pct}%)</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Gods in victories */}
          {sortedGods.length > 0 && (
            <div>
              <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">Gods in victories</div>
              <div className="space-y-1.5">
                {sortedGods.map(g => (
                  <div key={g.god} className="flex items-center gap-2 text-xs">
                    <span className="w-20 text-right text-gray-400 shrink-0">{g.god}</span>
                    <div className="flex-1 h-2 bg-black/30 rounded-full overflow-hidden">
                      <div className="h-full bg-purple-500 rounded-full" style={{ width: `${g.pct}%` }} />
                    </div>
                    <span className="text-gray-500 w-12">{g.pct}%</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default function RunsTab({ save }) {
  const runs = save?.runs || [];
  const [outcomeFilter, setOutcomeFilter] = useState('all');
  const [weaponFilter, setWeaponFilter] = useState('all');
  const [expandedId, setExpandedId] = useState(null);

  const victories = runs.filter(r => r.outcome === 'victory');
  const runTime = runs.reduce((sum, r) => sum + (r.duration || 0), 0);
  const sessionTime = (save?.sessions || []).reduce((sum, s) => sum + (s.duration || 0), 0);
  const totalTime = runTime + sessionTime;

  const weapons = [...new Set(runs.map(r => r.weapon).filter(Boolean))];

  const filtered = [...runs]
    .reverse()
    .filter(r => {
      if (outcomeFilter === 'victory' && r.outcome !== 'victory') return false;
      if (outcomeFilter === 'defeated' && r.outcome !== 'defeated') return false;
      if (weaponFilter !== 'all' && r.weapon !== weaponFilter) return false;
      return true;
    });

  if (runs.length === 0) {
    return (
      <div className="card p-12 text-center">
        <div className="text-5xl mb-4 opacity-50">🗡️</div>
        <h2 className="text-xl font-bold mb-2">No runs yet</h2>
        <p className="text-gray-400">Start your first escape attempt to begin tracking.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Summary stats */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="stat-box bg-purple-900/20 border border-purple-500/20 rounded-xl">
          <div className="text-2xl font-bold">{runs.length}</div>
          <div className="text-xs text-gray-400">Total Runs</div>
        </div>
        <div className="stat-box bg-green-900/20 border border-green-500/20 rounded-xl">
          <div className="text-2xl font-bold text-green-400">{victories.length}</div>
          <div className="text-xs text-gray-400">{winRate(victories.length, runs.length)}% Win Rate</div>
        </div>
        <div className="stat-box bg-red-900/20 border border-red-500/20 rounded-xl">
          <div className="text-2xl font-bold text-red-400">
            {runs.filter(r => r.outcome === 'defeated').length}
          </div>
          <div className="text-xs text-gray-400">Defeats</div>
        </div>
        <div className="stat-box bg-amber-900/20 border border-amber-500/20 rounded-xl">
          <div className="text-2xl font-bold text-amber-400">{formatDuration(totalTime)}</div>
          <div className="text-xs text-gray-400">Total Time</div>
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-2 flex-wrap">
        <div className="flex gap-1">
          {[['all', 'All'], ['victory', '🏆 Victories'], ['defeated', '💀 Defeats']].map(([v, l]) => (
            <button key={v} onClick={() => setOutcomeFilter(v)}
              className={`text-xs px-2.5 py-1.5 rounded-lg ${outcomeFilter === v ? 'tab-button-active' : 'tab-button-inactive'}`}>
              {l}
            </button>
          ))}
        </div>
        {weapons.length > 1 && (
          <div className="flex gap-1 overflow-x-auto scroll-smooth-ios">
            <button onClick={() => setWeaponFilter('all')}
              className={`text-xs px-2.5 py-1.5 rounded-lg whitespace-nowrap ${weaponFilter === 'all' ? 'tab-button-active' : 'tab-button-inactive'}`}>
              All weapons
            </button>
            {weapons.map(w => (
              <button key={w} onClick={() => setWeaponFilter(w)}
                className={`text-xs px-2.5 py-1.5 rounded-lg whitespace-nowrap ${weaponFilter === w ? 'tab-button-active' : 'tab-button-inactive'}`}>
                {WEAPON_ICONS[w] || '⚔️'} {w.split(' ')[0]}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Run list */}
      <div className="space-y-1.5">
        {filtered.length === 0 ? (
          <div className="text-center text-gray-500 text-sm py-8">No runs match this filter.</div>
        ) : filtered.map(run => (
          <RunRow
            key={run.id}
            run={run}
            expanded={expandedId === run.id}
            onToggle={() => setExpandedId(id => id === run.id ? null : run.id)}
          />
        ))}
      </div>

      {/* Analytics (collapses when not enough data) */}
      <AnalyticsSection runs={runs} />
    </div>
  );
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
  };
  return colors[slot] || 'bg-gray-800 text-gray-400';
}
