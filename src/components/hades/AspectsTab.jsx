import React, { useState } from 'react';
import { Search } from 'lucide-react';

export default function AspectsTab({ save, updateSave }) {
  const [search, setSearch] = useState('');
  const [filterWeapon, setFilterWeapon] = useState('all');

  const aspects = save?.weaponAspects || [];
  const completed = aspects.filter(a => a.unlocked).length;

  const weapons = [...new Set(aspects.map(a => a.weapon))];

  const filtered = aspects.filter(a => {
    const matchesSearch =
      a.name.toLowerCase().includes(search.toLowerCase()) ||
      a.weapon.toLowerCase().includes(search.toLowerCase());
    const matchesWeapon = filterWeapon === 'all' || a.weapon === filterWeapon;
    return matchesSearch && matchesWeapon;
  });

  // Group by weapon
  const grouped = {};
  filtered.forEach(a => {
    if (!grouped[a.weapon]) grouped[a.weapon] = [];
    grouped[a.weapon].push(a);
  });

  const toggleUnlock = (aspectId) => {
    updateSave(s => ({
      ...s,
      weaponAspects: s.weaponAspects.map(a =>
        a.id === aspectId
          ? { ...a, unlocked: !a.unlocked, rank: a.unlocked ? 0 : 1 }
          : a
      ),
    }));
  };

  const setRank = (aspectId, rank) => {
    updateSave(s => ({
      ...s,
      weaponAspects: s.weaponAspects.map(a =>
        a.id === aspectId ? { ...a, rank, unlocked: rank > 0 } : a
      ),
    }));
  };

  return (
    <div className="space-y-4">
      {/* Progress */}
      <div className="card p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm font-medium">Aspects Unlocked</span>
          <span className="text-sm text-purple-400 font-bold">{completed}/24</span>
        </div>
        <div className="h-2 bg-black/30 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-purple-600 to-purple-400 rounded-full transition-all duration-300"
            style={{ width: `${(completed / 24) * 100}%` }}
          />
        </div>
      </div>

      {/* Search + Filter */}
      <div className="flex gap-2 flex-col sm:flex-row">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
          <input
            type="text"
            placeholder="Search aspects..."
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="input-field pl-10"
          />
        </div>
        <div className="flex gap-1 overflow-x-auto scroll-smooth-ios">
          <button
            onClick={() => setFilterWeapon('all')}
            className={filterWeapon === 'all' ? 'tab-button-active text-xs' : 'tab-button-inactive text-xs'}
          >
            All
          </button>
          {weapons.map(w => (
            <button
              key={w}
              onClick={() => setFilterWeapon(w)}
              className={`${filterWeapon === w ? 'tab-button-active' : 'tab-button-inactive'} text-xs whitespace-nowrap`}
            >
              {getWeaponIcon(w)} {w.split(' ')[0]}
            </button>
          ))}
        </div>
      </div>

      {/* Aspects List */}
      {Object.entries(grouped).map(([weapon, weaponAspects]) => (
        <div key={weapon} className="card p-4">
          <h3 className="font-semibold mb-3 flex items-center gap-2">
            <span className="text-lg">{getWeaponIcon(weapon)}</span>
            {weapon}
          </h3>
          <div className="space-y-2">
            {weaponAspects.map(aspect => (
              <div
                key={aspect.id}
                className={`flex items-center justify-between p-3 rounded-lg border transition-colors ${
                  aspect.unlocked
                    ? 'border-purple-500/30 bg-purple-900/10'
                    : 'border-white/5 bg-black/20'
                }`}
              >
                <button
                  onClick={() => toggleUnlock(aspect.id)}
                  className="flex items-center gap-3 min-w-0 text-left min-h-[44px]"
                >
                  <div className={`w-6 h-6 rounded flex items-center justify-center flex-shrink-0 border ${
                    aspect.unlocked
                      ? 'bg-purple-600 border-purple-500 text-white'
                      : 'border-gray-600 text-transparent'
                  }`}>
                    ✓
                  </div>
                  <div className="min-w-0">
                    <div className={`text-sm font-medium ${aspect.unlocked ? 'text-white' : 'text-gray-400'}`}>
                      {aspect.name}
                    </div>
                    <div className="text-xs text-gray-500 truncate">{aspect.description}</div>
                  </div>
                </button>

                {/* Rank pips */}
                {aspect.unlocked && (
                  <div className="flex gap-1 flex-shrink-0 ml-2">
                    {[1, 2, 3, 4, 5].map(r => (
                      <button
                        key={r}
                        onClick={() => setRank(aspect.id, r)}
                        className={`w-4 h-4 rounded-full transition-colors min-h-0 min-w-0 ${
                          r <= aspect.rank
                            ? 'bg-purple-500'
                            : 'bg-gray-700 hover:bg-gray-600'
                        }`}
                        title={`Rank ${r}`}
                      />
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
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
