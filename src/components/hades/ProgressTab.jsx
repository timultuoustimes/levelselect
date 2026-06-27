import React, { useState } from 'react';
import { ChevronDown, ChevronRight, Heart } from 'lucide-react';
import { MIRROR_CATEGORIES } from '../../data/hadesMirror.js';

// ─── Collapsible section wrapper ─────────────────────────────────────────────

function Section({ title, defaultOpen = true, badge, children }) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="bg-black/40 rounded-xl border border-white/10 overflow-hidden">
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center justify-between px-4 py-3 hover:bg-white/5 transition-colors text-left"
      >
        <div className="flex items-center gap-2">
          {open ? <ChevronDown className="w-4 h-4 text-gray-500" /> : <ChevronRight className="w-4 h-4 text-gray-500" />}
          <span className="font-semibold text-sm text-gray-200">{title}</span>
        </div>
        {badge && <span className="text-xs font-bold text-purple-400">{badge}</span>}
      </button>
      {open && <div className="border-t border-white/5">{children}</div>}
    </div>
  );
}

// ─── Aspects ─────────────────────────────────────────────────────────────────

function AspectsSection({ save, updateSave }) {
  const aspects = save?.weaponAspects || [];
  const completed = aspects.filter(a => a.unlocked).length;

  const grouped = {};
  aspects.forEach(a => {
    if (!grouped[a.weapon]) grouped[a.weapon] = [];
    grouped[a.weapon].push(a);
  });

  const toggleUnlock = (id) => {
    updateSave(s => ({
      ...s,
      weaponAspects: s.weaponAspects.map(a =>
        a.id === id ? { ...a, unlocked: !a.unlocked, rank: a.unlocked ? 0 : 1 } : a
      ),
    }));
  };

  const setRank = (id, rank) => {
    updateSave(s => ({
      ...s,
      weaponAspects: s.weaponAspects.map(a =>
        a.id === id ? { ...a, rank, unlocked: rank > 0 } : a
      ),
    }));
  };

  return (
    <Section title="Weapons & Aspects" badge={`${completed}/24`}>
      <div className="p-4 space-y-4">
        {Object.entries(grouped).map(([weapon, weaponAspects]) => (
          <div key={weapon}>
            <div className="text-xs text-gray-500 uppercase tracking-wider mb-2 flex items-center gap-1.5">
              <span>{weaponIcon(weapon)}</span> {weapon}
            </div>
            <div className="space-y-1.5">
              {weaponAspects.map(aspect => (
                <div key={aspect.id} className={`flex items-center justify-between p-2.5 rounded-lg border transition-colors ${
                  aspect.unlocked ? 'border-purple-500/20 bg-purple-900/10' : 'border-white/5 bg-black/20'
                }`}>
                  <button onClick={() => toggleUnlock(aspect.id)}
                    className="flex items-center gap-2.5 min-w-0 text-left min-h-[36px]"
                  >
                    <div className={`w-5 h-5 rounded flex items-center justify-center shrink-0 border text-[10px] ${
                      aspect.unlocked ? 'bg-purple-600 border-purple-500 text-white' : 'border-gray-600 text-transparent'
                    }`}>✓</div>
                    <div className="min-w-0">
                      <div className={`text-sm ${aspect.unlocked ? 'text-white' : 'text-gray-400'}`}>{aspect.name}</div>
                      <div className="text-[10px] text-gray-600 truncate">{aspect.description}</div>
                    </div>
                  </button>
                  {aspect.unlocked && (
                    <div className="flex gap-1 shrink-0 ml-2">
                      {[1,2,3,4,5].map(r => (
                        <button key={r} onClick={() => setRank(aspect.id, r)}
                          className={`w-3.5 h-3.5 rounded-full min-h-0 min-w-0 ${r <= aspect.rank ? 'bg-purple-500' : 'bg-gray-700 hover:bg-gray-600'}`}
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
    </Section>
  );
}

// ─── Keepsakes & Companions ──────────────────────────────────────────────────

function KeepsakesSection({ save, updateSave }) {
  const keepsakes = save?.keepsakes || [];
  const companions = save?.companions || [];
  const unlockedK = keepsakes.filter(k => k.unlocked).length;
  const unlockedC = companions.filter(c => c.unlocked).length;

  const toggleKeepsake = (id) => updateSave(s => ({
    ...s,
    keepsakes: s.keepsakes.map(k => k.id === id ? { ...k, unlocked: !k.unlocked, rank: k.unlocked ? 0 : 1 } : k),
  }));

  const setKeepsakeRank = (id, rank) => updateSave(s => ({
    ...s,
    keepsakes: s.keepsakes.map(k => k.id === id ? { ...k, rank, unlocked: rank > 0 } : k),
  }));

  const toggleCompanion = (id) => updateSave(s => ({
    ...s,
    companions: s.companions.map(c => c.id === id ? { ...c, unlocked: !c.unlocked } : c),
  }));

  return (
    <Section
      title="Keepsakes & Companions"
      badge={`${unlockedK}/${keepsakes.length} · ${unlockedC}/${companions.length}`}
    >
      <div className="p-4 space-y-4">
        <div>
          <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">💎 Keepsakes</div>
          <div className="space-y-1.5">
            {keepsakes.map(k => (
              <div key={k.id} className={`flex items-center justify-between p-2.5 rounded-lg border transition-colors ${
                k.unlocked ? 'border-pink-500/20 bg-pink-900/10' : 'border-white/5 bg-black/20'
              }`}>
                <button onClick={() => toggleKeepsake(k.id)}
                  className="flex items-center gap-2.5 min-w-0 text-left min-h-[36px]"
                >
                  <div className={`w-5 h-5 rounded flex items-center justify-center shrink-0 border text-[10px] ${
                    k.unlocked ? 'bg-pink-600 border-pink-500 text-white' : 'border-gray-600 text-transparent'
                  }`}>✓</div>
                  <div className="min-w-0">
                    <div className={`text-sm ${k.unlocked ? 'text-white' : 'text-gray-400'}`}>{k.name}</div>
                    <div className="text-[10px] text-gray-600">From {k.source}</div>
                  </div>
                </button>
                {k.unlocked && (
                  <div className="flex gap-0.5 shrink-0 ml-2">
                    {[1,2,3].map(r => (
                      <button key={r} onClick={() => setKeepsakeRank(k.id, r === k.rank ? r - 1 : r)}
                        className="p-0.5 min-h-0 min-w-0"
                      >
                        <Heart className={`w-3.5 h-3.5 ${r <= k.rank ? 'fill-pink-500 text-pink-500' : 'text-gray-600'}`} />
                      </button>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>

        <div>
          <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">🏺 Companions</div>
          <div className="space-y-1.5">
            {companions.map(c => (
              <button key={c.id} onClick={() => toggleCompanion(c.id)}
                className={`w-full flex items-center gap-2.5 p-2.5 rounded-lg border transition-colors text-left min-h-[36px] ${
                  c.unlocked ? 'border-amber-500/20 bg-amber-900/10' : 'border-white/5 bg-black/20'
                }`}
              >
                <div className={`w-5 h-5 rounded flex items-center justify-center shrink-0 border text-[10px] ${
                  c.unlocked ? 'bg-amber-600 border-amber-500 text-white' : 'border-gray-600 text-transparent'
                }`}>✓</div>
                <div className="min-w-0">
                  <div className={`text-sm ${c.unlocked ? 'text-white' : 'text-gray-400'}`}>{c.name}</div>
                  <div className="text-[10px] text-gray-600">From {c.source}</div>
                </div>
              </button>
            ))}
          </div>
        </div>
      </div>
    </Section>
  );
}

// ─── Mirror of Night ─────────────────────────────────────────────────────────

function MirrorSection({ save, updateSave }) {
  const mirror = save?.mirrorUpgrades || {};
  const allUpgrades = MIRROR_CATEGORIES.flatMap(c => c.upgrades);
  const totalPurchased = allUpgrades.reduce((sum, u) => sum + (mirror[u.id]?.rank || 0), 0);
  const totalPossible = allUpgrades.reduce((sum, u) => sum + u.maxRank, 0);

  const setUpgradeRank = (id, rank) => updateSave(s => ({
    ...s,
    mirrorUpgrades: { ...s.mirrorUpgrades, [id]: { ...(s.mirrorUpgrades?.[id] || {}), rank } },
  }));

  const toggleAltMode = (id) => updateSave(s => {
    const cur = s.mirrorUpgrades?.[id] || {};
    return { ...s, mirrorUpgrades: { ...s.mirrorUpgrades, [id]: { ...cur, useAlt: !cur.useAlt, rank: 0 } } };
  });

  return (
    <Section title="Mirror of Night" badge={`${totalPurchased}/${totalPossible}`}>
      <div className="p-4 space-y-4">
        {MIRROR_CATEGORIES.map(cat => (
          <div key={cat.id}>
            <div className="text-xs text-gray-500 uppercase tracking-wider mb-2">{cat.icon} {cat.name}</div>
            <div className="space-y-2">
              {cat.upgrades.map(upgrade => {
                const state = mirror[upgrade.id] || { rank: 0, useAlt: false };
                const useAlt = state.useAlt && upgrade.altName;
                const activeName = useAlt ? upgrade.altName : upgrade.name;
                const activeMaxRank = useAlt ? upgrade.altMaxRank : upgrade.maxRank;

                return (
                  <div key={upgrade.id} className={`p-2.5 rounded-lg border ${state.rank > 0 ? 'border-purple-500/20 bg-purple-900/10' : 'border-white/5 bg-black/20'}`}>
                    <div className="flex items-start justify-between gap-2 mb-2">
                      <div className="min-w-0">
                        <div className={`text-sm font-medium ${state.rank > 0 ? 'text-white' : 'text-gray-400'}`}>{activeName}</div>
                        <div className="text-[10px] text-gray-600 leading-snug mt-0.5">{upgrade.description}</div>
                      </div>
                      {upgrade.altName && (
                        <button onClick={() => toggleAltMode(upgrade.id)}
                          className={`shrink-0 text-[10px] px-1.5 py-0.5 rounded border min-h-0 ${
                            useAlt ? 'border-amber-500/50 bg-amber-900/20 text-amber-400' : 'border-white/10 text-gray-600 hover:text-gray-400'
                          }`}
                        >Alt</button>
                      )}
                    </div>
                    <div className="flex items-center gap-1 flex-wrap">
                      {Array.from({ length: activeMaxRank }, (_, i) => i + 1).map(r => (
                        <button key={r}
                          onClick={() => setUpgradeRank(upgrade.id, state.rank === r ? r - 1 : r)}
                          className={`w-5 h-5 rounded text-[10px] font-bold border min-h-0 min-w-0 ${
                            r <= state.rank
                              ? useAlt ? 'bg-amber-600 border-amber-500 text-white' : 'bg-purple-600 border-purple-500 text-white'
                              : 'border-gray-600 bg-black/30 text-gray-600 hover:border-gray-400'
                          }`}
                          title={`Rank ${r}`}
                        >{r}</button>
                      ))}
                      {state.rank > 0 && (
                        <span className="text-[10px] text-gray-600 ml-1">{state.rank}/{activeMaxRank}</span>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </Section>
  );
}

// ─── Main ────────────────────────────────────────────────────────────────────

export default function ProgressTab({ save, updateSave }) {
  const handleNotesChange = (e) => {
    updateSave(s => ({ ...s, notes: e.target.value }));
  };

  return (
    <div className="space-y-4">
      <AspectsSection save={save} updateSave={updateSave} />
      <KeepsakesSection save={save} updateSave={updateSave} />
      <MirrorSection save={save} updateSave={updateSave} />

      {/* Run notes */}
      <div className="bg-black/40 rounded-xl border border-white/10 p-4">
        <label className="text-xs text-gray-500 uppercase tracking-wider block mb-2">Notes</label>
        <textarea
          rows={4}
          placeholder="Build goals, current heat target, things to try next run..."
          value={save?.notes || ''}
          onChange={handleNotesChange}
          className="w-full bg-black/50 border border-white/10 rounded-lg px-3 py-2 text-sm focus:outline-none resize-none text-gray-200 placeholder-gray-600"
        />
      </div>
    </div>
  );
}

function weaponIcon(weapon) {
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
