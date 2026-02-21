import React from 'react';
import { formatDuration, formatRelativeDate, winRate } from '../../utils/format.js';

export default function OverviewTab({ save }) {
  const runs = save?.runs || [];
  const victories = runs.filter(r => r.outcome === 'victory');
  const totalTime = runs.reduce((sum, r) => sum + (r.duration || 0), 0);

  // Recent runs (latest 10)
  const recentRuns = [...runs].reverse().slice(0, 10);

  if (runs.length === 0) {
    return (
      <div className="card p-12 text-center">
        <div className="text-5xl mb-4 opacity-50">🗡️</div>
        <h2 className="text-xl font-bold mb-2">No runs yet</h2>
        <p className="text-gray-400">
          Start your first escape attempt to begin tracking.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Stat boxes */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="stat-box bg-purple-900/20 border border-purple-500/20 rounded-xl">
          <div className="text-2xl font-bold">{runs.length}</div>
          <div className="text-xs text-gray-400">Total Runs</div>
        </div>
        <div className="stat-box bg-green-900/20 border border-green-500/20 rounded-xl">
          <div className="text-2xl font-bold text-green-400">{victories.length}</div>
          <div className="text-xs text-gray-400">Victories</div>
        </div>
        <div className="stat-box bg-blue-900/20 border border-blue-500/20 rounded-xl">
          <div className="text-2xl font-bold text-blue-400">
            {winRate(victories.length, runs.length)}%
          </div>
          <div className="text-xs text-gray-400">Win Rate</div>
        </div>
        <div className="stat-box bg-amber-900/20 border border-amber-500/20 rounded-xl">
          <div className="text-2xl font-bold text-amber-400">
            {formatDuration(totalTime)}
          </div>
          <div className="text-xs text-gray-400">Total Time</div>
        </div>
      </div>

      {/* Recent Runs */}
      <div className="card p-4">
        <h3 className="font-semibold mb-3">Recent Runs</h3>
        <div className="space-y-2">
          {recentRuns.map(run => (
            <div
              key={run.id}
              className={`flex items-center justify-between p-3 rounded-lg ${
                run.outcome === 'victory'
                  ? 'bg-green-900/10 border border-green-500/20'
                  : 'bg-red-900/10 border border-red-500/20'
              }`}
            >
              <div className="flex items-center gap-3 min-w-0">
                <span className={`text-lg ${run.outcome === 'victory' ? '' : 'grayscale opacity-60'}`}>
                  {getWeaponIcon(run.weapon)}
                </span>
                <div className="min-w-0">
                  <div className="font-medium text-sm truncate">
                    {run.weapon || 'Unknown'}{run.aspect ? ` — ${run.aspect}` : ''}
                  </div>
                  <div className="text-xs text-gray-500 flex items-center gap-2 flex-wrap">
                    {run.keepsake && <span>{run.keepsake}</span>}
                    {run.heatLevel > 0 && <span>🔥 {run.heatLevel}</span>}
                    <span>{run.boons?.length || 0} boons</span>
                  </div>
                </div>
              </div>
              <div className="text-right flex-shrink-0 ml-2">
                <div className={`text-sm font-medium ${
                  run.outcome === 'victory' ? 'text-green-400' : 'text-red-400'
                }`}>
                  {run.outcome === 'victory' ? '🏆 Victory' : '💀 Defeated'}
                </div>
                <div className="text-xs text-gray-500">
                  {formatDuration(run.duration)} · {formatRelativeDate(run.endTime)}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function getWeaponIcon(weapon) {
  const icons = {
    'Stygian Blade': '⚔️',
    'Eternal Spear': '🔱',
    'Shield of Chaos': '🛡️',
    'Heart-Seeking Bow': '🏹',
    'Twin Fists': '🥊',
    'Adamant Rail': '🔫',
  };
  return icons[weapon] || '⚔️';
}
