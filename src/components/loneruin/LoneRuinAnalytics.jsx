import React, { useState } from 'react';
import { STARTING_SPELLS } from '../../data/loneRuinData.js';

function formatTime(seconds) {
  if (!seconds) return '—';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}m ${String(s).padStart(2, '0')}s`;
}

export default function LoneRuinAnalytics({ save }) {
  const [filter, setFilter] = useState('All'); // 'All' | 'Campaign' | 'Survival'
  const runs = (save.runs || []).filter(r => filter === 'All' || r.mode === filter);

  // Per-starting-spell stats
  const spellStats = STARTING_SPELLS.map(spell => {
    const spellRuns = runs.filter(r => r.startingSpell === spell.name);
    const wins = spellRuns.filter(r => r.outcome === 'victory');
    const winRate = spellRuns.length > 0 ? Math.round((wins.length / spellRuns.length) * 100) : null;
    const avgFloor = spellRuns.filter(r => r.floorReached).length > 0
      ? Math.round(spellRuns.filter(r => r.floorReached).reduce((a, r) => a + r.floorReached, 0) / spellRuns.filter(r => r.floorReached).length)
      : null;
    return { ...spell, runs: spellRuns.length, wins: wins.length, winRate, avgFloor };
  })
    .filter(s => s.runs > 0)
    .sort((a, b) => (b.winRate ?? -1) - (a.winRate ?? -1));

  // Most commonly picked up mid-run spells
  const midRunCounts = {};
  runs.forEach(run => {
    (run.spellsAcquired || []).forEach(spell => {
      midRunCounts[spell] = (midRunCounts[spell] || 0) + 1;
    });
  });
  const topMidRun = Object.entries(midRunCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5);

  // Best floor records (Campaign only)
  const campaignVictories = (save.runs || []).filter(r => r.outcome === 'victory' && r.mode === 'Campaign');

  return (
    <div className="space-y-6">
      {/* Mode filter */}
      <div className="flex gap-2">
        {['All', 'Campaign', 'Survival'].map(m => (
          <button
            key={m}
            onClick={() => setFilter(m)}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              filter === m
                ? 'bg-purple-600 text-white'
                : 'bg-black/30 text-gray-400 hover:bg-purple-900/30'
            }`}
          >
            {m}
          </button>
        ))}
      </div>

      {runs.length === 0 ? (
        <div className="card p-8 text-center text-gray-500">
          No runs to analyze yet.
        </div>
      ) : (
        <>
          {/* Starting spell performance */}
          <div className="card p-4">
            <h3 className="font-bold mb-4">Starting Spell Performance</h3>
            {spellStats.length === 0 ? (
              <p className="text-gray-500 text-sm">No spell data yet.</p>
            ) : (
              <div className="space-y-3">
                {spellStats.map(spell => (
                  <div key={spell.id}>
                    <div className="flex items-center gap-2 mb-1">
                      <span className="text-xl w-7 text-center">{spell.icon}</span>
                      <span className="font-medium flex-1">{spell.name}</span>
                      <span className="text-xs text-gray-400">
                        {spell.wins}/{spell.runs} wins
                        {spell.avgFloor && filter !== 'Survival' ? ` · avg floor ${spell.avgFloor}` : ''}
                      </span>
                      <span className={`text-sm font-bold w-12 text-right ${
                        spell.winRate >= 60 ? 'text-green-400' :
                        spell.winRate >= 30 ? 'text-yellow-400' : 'text-red-400'
                      }`}>
                        {spell.winRate}%
                      </span>
                    </div>
                    <div className="h-2 bg-black/40 rounded-full overflow-hidden">
                      <div
                        className={`h-full rounded-full transition-all ${
                          spell.winRate >= 60 ? 'bg-green-500' :
                          spell.winRate >= 30 ? 'bg-yellow-500' : 'bg-red-500'
                        }`}
                        style={{ width: `${spell.winRate}%` }}
                      />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Most picked up mid-run spells */}
          {topMidRun.length > 0 && (
            <div className="card p-4">
              <h3 className="font-bold mb-3">Most Acquired Mid-Run</h3>
              <div className="space-y-2">
                {topMidRun.map(([spell, count]) => (
                  <div key={spell} className="flex items-center justify-between bg-black/30 rounded px-3 py-2 text-sm">
                    <span>{spell}</span>
                    <span className="text-purple-400 font-semibold">{count}×</span>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Campaign victories */}
          {campaignVictories.length > 0 && filter !== 'Survival' && (
            <div className="card p-4">
              <h3 className="font-bold mb-3">Winning Builds</h3>
              <div className="space-y-2">
                {[...campaignVictories].reverse().slice(0, 5).map(run => {
                  const spellData = STARTING_SPELLS.find(s => s.name === run.startingSpell);
                  return (
                    <div key={run.id} className="bg-green-900/20 border border-green-800/30 rounded-lg px-3 py-2">
                      <div className="flex items-center gap-2">
                        <span>{spellData?.icon || '✨'}</span>
                        <span className="font-medium text-sm">{run.startingSpell}</span>
                        {run.spellsAcquired?.length > 0 && (
                          <span className="text-gray-400 text-xs">+ {run.spellsAcquired.join(', ')}</span>
                        )}
                      </div>
                      {run.notes && (
                        <div className="text-xs text-gray-400 mt-1 ml-6">{run.notes}</div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
