import React, { useState } from 'react';
import { Search, Heart } from 'lucide-react';

export default function KeepsakesTab({ save, updateSave }) {
  const [search, setSearch] = useState('');

  const keepsakes = save?.keepsakes || [];
  const companions = save?.companions || [];
  const unlockedKeepsakes = keepsakes.filter(k => k.unlocked).length;
  const unlockedCompanions = companions.filter(c => c.unlocked).length;

  const filteredKeepsakes = keepsakes.filter(k =>
    k.name.toLowerCase().includes(search.toLowerCase()) ||
    k.source.toLowerCase().includes(search.toLowerCase())
  );

  const filteredCompanions = companions.filter(c =>
    c.name.toLowerCase().includes(search.toLowerCase()) ||
    c.source.toLowerCase().includes(search.toLowerCase())
  );

  const toggleKeepsake = (id) => {
    updateSave(s => ({
      ...s,
      keepsakes: s.keepsakes.map(k =>
        k.id === id
          ? { ...k, unlocked: !k.unlocked, rank: k.unlocked ? 0 : 1 }
          : k
      ),
    }));
  };

  const setKeepsakeRank = (id, rank) => {
    updateSave(s => ({
      ...s,
      keepsakes: s.keepsakes.map(k =>
        k.id === id ? { ...k, rank, unlocked: rank > 0 } : k
      ),
    }));
  };

  const toggleCompanion = (id) => {
    updateSave(s => ({
      ...s,
      companions: s.companions.map(c =>
        c.id === id ? { ...c, unlocked: !c.unlocked } : c
      ),
    }));
  };

  return (
    <div className="space-y-4">
      {/* Progress */}
      <div className="grid grid-cols-2 gap-3">
        <div className="card p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium">Keepsakes</span>
            <span className="text-sm text-pink-400 font-bold">{unlockedKeepsakes}/{keepsakes.length}</span>
          </div>
          <div className="h-2 bg-black/30 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-pink-600 to-pink-400 rounded-full transition-all duration-300"
              style={{ width: `${(unlockedKeepsakes / keepsakes.length) * 100}%` }}
            />
          </div>
        </div>
        <div className="card p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium">Companions</span>
            <span className="text-sm text-amber-400 font-bold">{unlockedCompanions}/{companions.length}</span>
          </div>
          <div className="h-2 bg-black/30 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-amber-600 to-amber-400 rounded-full transition-all duration-300"
              style={{ width: `${(unlockedCompanions / companions.length) * 100}%` }}
            />
          </div>
        </div>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500" />
        <input
          type="text"
          placeholder="Search keepsakes..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="input-field pl-10"
        />
      </div>

      {/* Keepsakes */}
      <div className="card p-4">
        <h3 className="font-semibold mb-3">💎 Keepsakes</h3>
        <div className="space-y-2">
          {filteredKeepsakes.map(k => (
            <div
              key={k.id}
              className={`flex items-center justify-between p-3 rounded-lg border transition-colors ${
                k.unlocked
                  ? 'border-pink-500/20 bg-pink-900/10'
                  : 'border-white/5 bg-black/20'
              }`}
            >
              <button
                onClick={() => toggleKeepsake(k.id)}
                className="flex items-center gap-3 min-w-0 text-left min-h-[44px]"
              >
                <div className={`w-6 h-6 rounded flex items-center justify-center flex-shrink-0 border ${
                  k.unlocked
                    ? 'bg-pink-600 border-pink-500 text-white'
                    : 'border-gray-600 text-transparent'
                }`}>
                  ✓
                </div>
                <div className="min-w-0">
                  <div className={`text-sm font-medium ${k.unlocked ? 'text-white' : 'text-gray-400'}`}>
                    {k.name}
                  </div>
                  <div className="text-xs text-gray-500">
                    From {k.source} · {k.effect}
                  </div>
                </div>
              </button>

              {/* Hearts (rank) */}
              {k.unlocked && (
                <div className="flex gap-1 flex-shrink-0 ml-2">
                  {[1, 2, 3].map(r => (
                    <button
                      key={r}
                      onClick={() => setKeepsakeRank(k.id, r === k.rank ? r - 1 : r)}
                      className="min-h-0 min-w-0 p-0.5"
                      title={`Rank ${r}`}
                    >
                      <Heart
                        className={`w-4 h-4 transition-colors ${
                          r <= k.rank
                            ? 'fill-pink-500 text-pink-500'
                            : 'text-gray-600'
                        }`}
                      />
                    </button>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Companions */}
      <div className="card p-4">
        <h3 className="font-semibold mb-3">🏺 Companions</h3>
        <div className="space-y-2">
          {filteredCompanions.map(c => (
            <button
              key={c.id}
              onClick={() => toggleCompanion(c.id)}
              className={`w-full flex items-center gap-3 p-3 rounded-lg border transition-colors text-left min-h-[44px] ${
                c.unlocked
                  ? 'border-amber-500/20 bg-amber-900/10'
                  : 'border-white/5 bg-black/20'
              }`}
            >
              <div className={`w-6 h-6 rounded flex items-center justify-center flex-shrink-0 border ${
                c.unlocked
                  ? 'bg-amber-600 border-amber-500 text-white'
                  : 'border-gray-600 text-transparent'
              }`}>
                ✓
              </div>
              <div className="min-w-0">
                <div className={`text-sm font-medium ${c.unlocked ? 'text-white' : 'text-gray-400'}`}>
                  {c.name}
                </div>
                <div className="text-xs text-gray-500">
                  From {c.source} · {c.effect}
                </div>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
