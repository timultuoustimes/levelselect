import React, { useState } from 'react';
import { MIRROR_CATEGORIES } from '../../data/hadesMirror.js';
import { Search } from 'lucide-react';

export default function MirrorTab({ save, updateSave }) {
  const [search, setSearch] = useState('');
  const [filterCategory, setFilterCategory] = useState('all');

  const mirror = save?.mirrorUpgrades || {};

  // Total ranks purchased vs possible
  const allUpgrades = MIRROR_CATEGORIES.flatMap(c => c.upgrades);
  const totalPurchased = allUpgrades.reduce((sum, u) => {
    const state = mirror[u.id];
    return sum + (state?.rank || 0);
  }, 0);
  const totalPossible = allUpgrades.reduce((sum, u) => sum + u.maxRank, 0);

  const setUpgradeRank = (upgradeId, rank) => {
    updateSave(s => ({
      ...s,
      mirrorUpgrades: {
        ...s.mirrorUpgrades,
        [upgradeId]: {
          ...(s.mirrorUpgrades?.[upgradeId] || {}),
          rank,
        },
      },
    }));
  };

  const toggleAltMode = (upgradeId) => {
    updateSave(s => {
      const current = s.mirrorUpgrades?.[upgradeId] || {};
      return {
        ...s,
        mirrorUpgrades: {
          ...s.mirrorUpgrades,
          [upgradeId]: {
            ...current,
            useAlt: !current.useAlt,
            rank: 0, // Reset rank when switching modes
          },
        },
      };
    });
  };

  const filteredCategories = MIRROR_CATEGORIES
    .filter(cat => filterCategory === 'all' || cat.id === filterCategory)
    .map(cat => ({
      ...cat,
      upgrades: cat.upgrades.filter(u => {
        if (!search) return true;
        const q = search.toLowerCase();
        return (
          u.name.toLowerCase().includes(q) ||
          (u.altName && u.altName.toLowerCase().includes(q)) ||
          u.description.toLowerCase().includes(q)
        );
      }),
    }))
    .filter(cat => cat.upgrades.length > 0);

  return (
    <div className="space-y-4">
      {/* Progress */}
      <div className="card p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm font-medium">🪞 Mirror Ranks Purchased</span>
          <span className="text-sm text-purple-400 font-bold">
            {totalPurchased} / {totalPossible}
          </span>
        </div>
        <div className="h-2 bg-black/30 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-purple-600 to-purple-400 rounded-full transition-all duration-300"
            style={{ width: `${(totalPurchased / totalPossible) * 100}%` }}
          />
        </div>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
        <input
          type="text"
          placeholder="Search upgrades..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="input-field pl-10"
        />
      </div>

      {/* Category filter */}
      <div className="flex gap-1 overflow-x-auto scroll-smooth-ios">
        <button
          onClick={() => setFilterCategory('all')}
          className={filterCategory === 'all' ? 'tab-button-active text-xs' : 'tab-button-inactive text-xs'}
        >
          All
        </button>
        {MIRROR_CATEGORIES.map(cat => (
          <button
            key={cat.id}
            onClick={() => setFilterCategory(cat.id)}
            className={`${filterCategory === cat.id ? 'tab-button-active' : 'tab-button-inactive'} text-xs whitespace-nowrap`}
          >
            {cat.icon} {cat.name}
          </button>
        ))}
      </div>

      {/* Upgrade cards by category */}
      {filteredCategories.map(cat => (
        <div key={cat.id} className="card p-4">
          <h3 className="font-semibold mb-3 flex items-center gap-2">
            <span>{cat.icon}</span>
            {cat.name}
          </h3>
          <div className="space-y-3">
            {cat.upgrades.map(upgrade => {
              const state = mirror[upgrade.id] || { rank: 0, useAlt: false };
              const useAlt = state.useAlt && upgrade.altName;
              const activeName = useAlt ? upgrade.altName : upgrade.name;
              const activeMaxRank = useAlt ? upgrade.altMaxRank : upgrade.maxRank;

              return (
                <div
                  key={upgrade.id}
                  className={`p-3 rounded-lg border transition-colors ${
                    state.rank > 0
                      ? 'border-purple-500/30 bg-purple-900/10'
                      : 'border-white/5 bg-black/20'
                  }`}
                >
                  {/* Header row */}
                  <div className="flex items-start justify-between gap-2 mb-2">
                    <div className="min-w-0">
                      <div className={`text-sm font-medium ${state.rank > 0 ? 'text-white' : 'text-gray-400'}`}>
                        {activeName}
                      </div>
                      <div className="text-xs text-gray-500 mt-0.5 leading-snug">
                        {upgrade.description}
                      </div>
                    </div>

                    {/* Alt toggle (only show if upgrade has an alt) */}
                    {upgrade.altName && (
                      <button
                        onClick={() => toggleAltMode(upgrade.id)}
                        className={`flex-shrink-0 text-xs px-2 py-1 rounded border transition-colors min-h-[32px] ${
                          useAlt
                            ? 'border-amber-500/50 bg-amber-900/20 text-amber-400'
                            : 'border-white/10 bg-black/20 text-gray-500 hover:text-gray-300'
                        }`}
                        title={useAlt ? `Switch to: ${upgrade.name}` : `Switch to: ${upgrade.altName}`}
                      >
                        {useAlt ? '★ Alt' : 'Alt'}
                      </button>
                    )}
                  </div>

                  {/* Alt name label when active */}
                  {useAlt && (
                    <div className="text-xs text-amber-400/70 mb-2">
                      Using: <span className="font-medium text-amber-400">{upgrade.altName}</span>
                      {' '}instead of {upgrade.name}
                    </div>
                  )}

                  {/* Rank pips */}
                  <div className="flex items-center gap-1 flex-wrap">
                    {Array.from({ length: activeMaxRank }, (_, i) => i + 1).map(r => (
                      <button
                        key={r}
                        onClick={() => setUpgradeRank(upgrade.id, state.rank === r ? r - 1 : r)}
                        className={`w-6 h-6 rounded transition-colors min-h-0 min-w-0 border text-xs font-bold ${
                          r <= state.rank
                            ? useAlt
                              ? 'bg-amber-600 border-amber-500 text-white'
                              : 'bg-purple-600 border-purple-500 text-white'
                            : 'border-gray-600 bg-black/30 text-gray-600 hover:border-gray-400'
                        }`}
                        title={`Rank ${r}`}
                      >
                        {r}
                      </button>
                    ))}
                    {state.rank > 0 && (
                      <span className="text-xs text-gray-500 ml-1">
                        Rank {state.rank}/{activeMaxRank}
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}
