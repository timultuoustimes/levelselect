import React from 'react';
import { winRate } from '../../utils/format.js';

export default function AnalyticsTab({ save }) {
  const runs = save?.runs || [];

  if (runs.length === 0) {
    return (
      <div className="card p-12 text-center">
        <div className="text-5xl mb-4 opacity-50">📊</div>
        <h2 className="text-xl font-bold mb-2">No data yet</h2>
        <p className="text-gray-400">
          Complete some runs to see performance analytics.
        </p>
      </div>
    );
  }

  // Weapon stats
  const weaponStats = {};
  runs.forEach(run => {
    const key = run.weapon || 'Unknown';
    if (!weaponStats[key]) weaponStats[key] = { total: 0, victories: 0 };
    weaponStats[key].total++;
    if (run.outcome === 'victory') weaponStats[key].victories++;
  });

  const sortedWeapons = Object.entries(weaponStats)
    .map(([weapon, stats]) => ({
      weapon,
      ...stats,
      rate: winRate(stats.victories, stats.total),
    }))
    .sort((a, b) => b.rate - a.rate);

  // Aspect stats
  const aspectStats = {};
  runs.forEach(run => {
    if (!run.aspect) return;
    const key = run.aspect;
    if (!aspectStats[key]) aspectStats[key] = { total: 0, victories: 0, weapon: run.weapon };
    aspectStats[key].total++;
    if (run.outcome === 'victory') aspectStats[key].victories++;
  });

  const sortedAspects = Object.entries(aspectStats)
    .map(([aspect, stats]) => ({
      aspect,
      ...stats,
      rate: winRate(stats.victories, stats.total),
    }))
    .filter(a => a.total >= 2)
    .sort((a, b) => b.rate - a.rate);

  // Most picked boons (from victories)
  const victories = runs.filter(r => r.outcome === 'victory');
  const boonFreq = {};
  victories.forEach(run => {
    (run.boons || []).forEach(b => {
      const key = `${b.god}: ${b.name}`;
      boonFreq[key] = (boonFreq[key] || 0) + 1;
    });
  });

  const topBoons = Object.entries(boonFreq)
    .map(([boon, count]) => ({ boon, count, pct: Math.round((count / victories.length) * 100) }))
    .sort((a, b) => b.count - a.count)
    .slice(0, 10);

  // God frequency in victories
  const godFreq = {};
  victories.forEach(run => {
    const gods = new Set((run.boons || []).map(b => b.god));
    gods.forEach(g => {
      godFreq[g] = (godFreq[g] || 0) + 1;
    });
  });

  const sortedGods = Object.entries(godFreq)
    .map(([god, count]) => ({ god, count, pct: Math.round((count / Math.max(victories.length, 1)) * 100) }))
    .sort((a, b) => b.count - a.count);

  return (
    <div className="space-y-4">
      {/* Weapon Performance */}
      <div className="card p-4">
        <h3 className="font-semibold mb-3">⚔️ Weapon Performance</h3>
        <div className="space-y-3">
          {sortedWeapons.map(w => (
            <div key={w.weapon}>
              <div className="flex items-center justify-between mb-1">
                <span className="text-sm flex items-center gap-2">
                  <span>{getWeaponIcon(w.weapon)}</span>
                  {w.weapon}
                </span>
                <span className="text-sm">
                  <span className={w.rate >= 50 ? 'text-green-400' : w.rate >= 25 ? 'text-amber-400' : 'text-red-400'}>
                    {w.rate}%
                  </span>
                  <span className="text-gray-500 text-xs ml-1">
                    ({w.victories}/{w.total})
                  </span>
                </span>
              </div>
              <div className="h-2 bg-black/30 rounded-full overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all duration-300 ${
                    w.rate >= 50 ? 'bg-green-500' : w.rate >= 25 ? 'bg-amber-500' : 'bg-red-500'
                  }`}
                  style={{ width: `${w.rate}%` }}
                />
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Aspect Performance (only show if enough data) */}
      {sortedAspects.length > 0 && (
        <div className="card p-4">
          <h3 className="font-semibold mb-3">🔷 Aspect Win Rates</h3>
          <p className="text-xs text-gray-500 mb-3">Aspects with 2+ runs</p>
          <div className="space-y-3">
            {sortedAspects.map(a => (
              <div key={a.aspect}>
                <div className="flex items-center justify-between mb-1">
                  <span className="text-sm">{a.aspect}</span>
                  <span className="text-sm">
                    <span className={a.rate >= 50 ? 'text-green-400' : 'text-amber-400'}>
                      {a.rate}%
                    </span>
                    <span className="text-gray-500 text-xs ml-1">
                      ({a.victories}/{a.total})
                    </span>
                  </span>
                </div>
                <div className="h-1.5 bg-black/30 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-purple-500 rounded-full transition-all duration-300"
                    style={{ width: `${a.rate}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* God Preference (victories) */}
      {sortedGods.length > 0 && (
        <div className="card p-4">
          <h3 className="font-semibold mb-3">🏛️ God Presence in Victories</h3>
          <p className="text-xs text-gray-500 mb-3">How often each god's boons appear in winning runs</p>
          <div className="space-y-2">
            {sortedGods.map(g => (
              <div key={g.god} className="flex items-center gap-3">
                <span className="text-sm w-20 text-right">{g.god}</span>
                <div className="flex-1 h-2 bg-black/30 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-purple-500 rounded-full transition-all duration-300"
                    style={{ width: `${g.pct}%` }}
                  />
                </div>
                <span className="text-xs text-gray-400 w-12">{g.pct}%</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Top Boons in Victories */}
      {topBoons.length > 0 && (
        <div className="card p-4">
          <h3 className="font-semibold mb-3">⭐ Most Common Winning Boons</h3>
          <div className="space-y-1">
            {topBoons.map((b, i) => (
              <div key={b.boon} className="flex items-center justify-between py-1.5 text-sm">
                <span className="text-gray-300">
                  <span className="text-gray-500 w-5 inline-block">{i + 1}.</span> {b.boon}
                </span>
                <span className="text-gray-500 text-xs">
                  {b.count}× ({b.pct}%)
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
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
