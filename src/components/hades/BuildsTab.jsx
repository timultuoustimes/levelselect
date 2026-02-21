import React, { useState } from 'react';
import { formatDuration, formatDate } from '../../utils/format.js';
import { ChevronDown, ChevronRight } from 'lucide-react';

export default function BuildsTab({ save }) {
  const [expandedRun, setExpandedRun] = useState(null);
  const [filterWeapon, setFilterWeapon] = useState('all');

  const runs = save?.runs || [];
  const victories = runs.filter(r => r.outcome === 'victory');

  // Group by weapon
  const byWeapon = {};
  victories.forEach(run => {
    const key = run.weapon || 'Unknown';
    if (!byWeapon[key]) byWeapon[key] = [];
    byWeapon[key].push(run);
  });

  const weaponKeys = Object.keys(byWeapon).sort();

  if (victories.length === 0) {
    return (
      <div className="card p-12 text-center">
        <div className="text-5xl mb-4 opacity-50">🏆</div>
        <h2 className="text-xl font-bold mb-2">No victories yet</h2>
        <p className="text-gray-400">
          Complete a successful escape to see your winning builds here.
        </p>
      </div>
    );
  }

  const displayedWeapons = filterWeapon === 'all' ? weaponKeys : weaponKeys.filter(w => w === filterWeapon);

  return (
    <div className="space-y-4">
      {/* Filter */}
      {weaponKeys.length > 1 && (
        <div className="flex gap-1 overflow-x-auto scroll-smooth-ios">
          <button
            onClick={() => setFilterWeapon('all')}
            className={filterWeapon === 'all' ? 'tab-button-active text-xs' : 'tab-button-inactive text-xs'}
          >
            All ({victories.length})
          </button>
          {weaponKeys.map(w => (
            <button
              key={w}
              onClick={() => setFilterWeapon(w)}
              className={`${filterWeapon === w ? 'tab-button-active' : 'tab-button-inactive'} text-xs whitespace-nowrap`}
            >
              {w} ({byWeapon[w].length})
            </button>
          ))}
        </div>
      )}

      {displayedWeapons.map(weapon => (
        <div key={weapon} className="card p-4">
          <h3 className="font-semibold mb-3 flex items-center gap-2">
            <span className="text-lg">{getWeaponIcon(weapon)}</span>
            {weapon}
            <span className="text-xs text-gray-500 font-normal">
              {byWeapon[weapon].length} {byWeapon[weapon].length === 1 ? 'victory' : 'victories'}
            </span>
          </h3>

          <div className="space-y-2">
            {byWeapon[weapon].map(run => {
              const isExpanded = expandedRun === run.id;
              return (
                <div key={run.id} className="border border-green-500/20 rounded-lg overflow-hidden">
                  <button
                    onClick={() => setExpandedRun(isExpanded ? null : run.id)}
                    className="w-full flex items-center justify-between p-3 hover:bg-green-900/10 min-h-[44px]"
                  >
                    <div className="flex items-center gap-2 text-sm min-w-0">
                      <span>{isExpanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}</span>
                      <span className="truncate font-medium">{run.aspect || 'No Aspect'}</span>
                      {run.keepsake && <span className="text-gray-500 truncate hidden sm:inline">· {run.keepsake}</span>}
                      {run.heatLevel > 0 && <span className="text-orange-400">🔥{run.heatLevel}</span>}
                    </div>
                    <div className="text-xs text-gray-500 flex-shrink-0 ml-2">
                      {formatDuration(run.duration)} · {formatDate(run.endTime)}
                    </div>
                  </button>

                  {isExpanded && (
                    <div className="px-3 pb-3 border-t border-green-500/10 pt-3 space-y-3">
                      {/* Loadout */}
                      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
                        <div>
                          <span className="text-gray-500">Aspect:</span>{' '}
                          <span className="text-white">{run.aspect || '—'}</span>
                        </div>
                        <div>
                          <span className="text-gray-500">Keepsake:</span>{' '}
                          <span className="text-white">{run.keepsake || '—'}</span>
                        </div>
                        <div>
                          <span className="text-gray-500">Heat:</span>{' '}
                          <span className="text-white">{run.heatLevel || 0}</span>
                        </div>
                        <div>
                          <span className="text-gray-500">Boons:</span>{' '}
                          <span className="text-white">{run.boons?.length || 0}</span>
                        </div>
                      </div>

                      {/* Hammer upgrades */}
                      {run.hammerUpgrades?.length > 0 && (
                        <div>
                          <div className="text-xs text-gray-500 mb-1">🔨 Hammer Upgrades</div>
                          <div className="flex flex-wrap gap-1">
                            {run.hammerUpgrades.map((u, i) => (
                              <span key={i} className="text-xs bg-amber-900/30 text-amber-300 px-2 py-0.5 rounded">
                                {u}
                              </span>
                            ))}
                          </div>
                        </div>
                      )}

                      {/* Boons by god */}
                      {run.boons?.length > 0 && (
                        <div>
                          <div className="text-xs text-gray-500 mb-1">Boons</div>
                          <BoonsByGod boons={run.boons} />
                        </div>
                      )}

                      {/* Notes */}
                      {run.notes && (
                        <div>
                          <div className="text-xs text-gray-500 mb-1">Notes</div>
                          <p className="text-sm text-gray-300 bg-black/30 rounded p-2">
                            {run.notes}
                          </p>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

function BoonsByGod({ boons }) {
  const grouped = {};
  boons.forEach(b => {
    const god = b.god || 'Unknown';
    if (!grouped[god]) grouped[god] = [];
    grouped[god].push(b.name);
  });

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
      {Object.entries(grouped).map(([god, names]) => (
        <div key={god} className="text-xs">
          <span className="text-purple-300 font-medium">{god}:</span>{' '}
          <span className="text-gray-300">{names.join(', ')}</span>
        </div>
      ))}
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
