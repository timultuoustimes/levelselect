import React from 'react';
import { STARTING_SPELLS } from '../../data/loneRuinData.js';

function formatTime(seconds) {
  if (!seconds) return '0:00';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${String(s).padStart(2, '0')}s`;
  return `${s}s`;
}

export default function LoneRuinOverview({ save }) {
  const runs = save.runs || [];
  const victories = runs.filter(r => r.outcome === 'victory');
  const totalTime = runs.reduce((acc, r) => acc + (r.duration || 0), 0);
  const winRate = runs.length > 0 ? Math.round((victories.length / runs.length) * 100) : 0;
  const campaignRuns = runs.filter(r => r.mode === 'Campaign');
  const bestFloor = campaignRuns.length > 0
    ? Math.max(...campaignRuns.map(r => r.floorReached || 0))
    : null;

  return (
    <div className="space-y-6">
      {/* Stats row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div className="card p-4 text-center bg-purple-900/20">
          <div className="text-3xl font-bold text-purple-300">{runs.length}</div>
          <div className="text-xs text-gray-400 mt-1">Total Runs</div>
        </div>
        <div className="card p-4 text-center bg-green-900/20">
          <div className="text-3xl font-bold text-green-400">{victories.length}</div>
          <div className="text-xs text-gray-400 mt-1">Victories</div>
        </div>
        <div className="card p-4 text-center bg-blue-900/20">
          <div className="text-3xl font-bold text-blue-400">{winRate}%</div>
          <div className="text-xs text-gray-400 mt-1">Win Rate</div>
        </div>
        <div className="card p-4 text-center bg-indigo-900/20">
          <div className="text-3xl font-bold text-indigo-400">
            {bestFloor != null ? `F${bestFloor}` : '—'}
          </div>
          <div className="text-xs text-gray-400 mt-1">Best Floor</div>
        </div>
      </div>

      {/* Playtime */}
      <div className="card p-4 flex items-center gap-3">
        <span className="text-2xl">⏱️</span>
        <div>
          <div className="font-semibold">Total Playtime</div>
          <div className="text-gray-400 text-sm">{formatTime(totalTime)}</div>
        </div>
      </div>

      {/* Recent runs */}
      <div className="card p-4">
        <h3 className="font-bold mb-3">Recent Runs</h3>
        {runs.length === 0 ? (
          <p className="text-gray-500 text-center py-6">No runs yet. Start a run to begin tracking!</p>
        ) : (
          <div className="space-y-2">
            {[...runs].reverse().slice(0, 8).map(run => {
              const spellData = STARTING_SPELLS.find(s => s.name === run.startingSpell);
              return (
                <div key={run.id} className="flex items-center gap-3 bg-black/30 rounded-lg px-3 py-2">
                  <span className="text-xl w-7 text-center">{spellData?.icon || '✨'}</span>
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-sm">{run.startingSpell || 'Unknown Spell'}</div>
                    <div className="text-xs text-gray-400">
                      {run.mode} · {run.difficulty}
                      {run.mode === 'Campaign' && run.floorReached ? ` · Floor ${run.floorReached}` : ''}
                      {run.mode === 'Survival' && run.wavesReached ? ` · ${run.wavesReached} waves` : ''}
                      {run.spellsAcquired?.length > 0 ? ` · ${run.spellsAcquired.length} spells` : ''}
                    </div>
                  </div>
                  <div className="text-xs text-gray-500">{formatTime(run.duration)}</div>
                  <span className={`px-2 py-0.5 rounded text-xs font-semibold ${
                    run.outcome === 'victory' ? 'bg-green-600' : 'bg-red-700'
                  }`}>
                    {run.outcome === 'victory' ? '✓ Win' : '✗ Loss'}
                  </span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
