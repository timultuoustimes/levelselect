// Complete Hades boon database extracted from HadesTracker + Hades Wiki
// Each boon has: name, slot (attack/special/cast/dash/call/other/legendary), god

export const GODS = [
  'Zeus', 'Poseidon', 'Athena', 'Aphrodite', 'Artemis',
  'Ares', 'Dionysus', 'Hermes', 'Demeter', 'Chaos',
];

export const BOON_SLOTS = ['attack', 'special', 'cast', 'dash', 'call', 'other', 'legendary'];

export const BOONS_BY_GOD = {
  Zeus: {
    attack: ['Lightning Strike'],
    special: ['Thunder Flourish'],
    cast: ['Electric Shot', 'Thunder Flare'],
    dash: ['Thunder Dash'],
    call: ["Zeus' Aid"],
    other: [
      'Billowing Strength', 'Lightning Reflexes', "Heaven's Vengeance",
      'Clouded Judgement', 'High Voltage', 'Double Strike',
      'Storm Lightning', 'Static Discharge',
    ],
    legendary: ['Splitting Bolt'],
  },
  Poseidon: {
    attack: ['Tempest Strike'],
    special: ['Tempest Flourish'],
    cast: ['Flood Shot', 'Flood Flare'],
    dash: ['Tidal Dash'],
    call: ["Poseidon's Aid"],
    other: [
      'Boiling Point', 'Hydraulic Might', 'Sunken Treasure',
      "Ocean's Bounty", "Typhoon's Fury", 'Wave Pounding',
      'Rip Current', 'Breaking Wave', 'Razor Shoals',
    ],
    legendary: ['Second Wave', 'Huge Catch'],
  },
  Athena: {
    attack: ['Divine Strike'],
    special: ['Divine Flourish'],
    cast: ['Phalanx Shot', 'Phalanx Flare'],
    dash: ['Divine Dash'],
    call: ["Athena's Aid"],
    other: [
      'Holy Shield', 'Bronze Skin', 'Deathless Stand',
      'Last Stand', 'Proud Bearing', 'Sure Footing',
      'Blinding Flash', 'Brilliant Riposte',
    ],
    legendary: ['Divine Protection'],
  },
  Aphrodite: {
    attack: ['Heartbreak Strike'],
    special: ['Heartbreak Flourish'],
    cast: ['Crush Shot', 'Passion Flare'],
    dash: ['Passion Dash'],
    call: ["Aphrodite's Aid"],
    other: [
      'Dying Lament', 'Wave of Despair', 'Life Affirmation',
      'Different League', 'Empty Inside', 'Broken Resolve',
      'Blown Kiss', 'Sweet Surrender',
    ],
    legendary: ['Unhealthy Fixation'],
  },
  Artemis: {
    attack: ['Deadly Strike'],
    special: ['Deadly Flourish'],
    cast: ['True Shot', "Hunter's Flare"],
    dash: ['Hunter Dash'],
    call: ["Artemis' Aid"],
    other: [
      'Pressure Points', 'Exit Wounds', 'Clean Kill',
      'Support Fire', 'Hide Breaker', 'Hunter Instinct',
      "Hunter's Mark",
    ],
    legendary: ['Fully Loaded'],
  },
  Ares: {
    attack: ['Curse of Agony'],
    special: ['Curse of Pain'],
    cast: ['Slicing Shot', 'Slicing Flare'],
    dash: ['Blade Dash'],
    call: ["Ares' Aid"],
    other: [
      'Curse of Vengeance', 'Urge to Kill', 'Blood Frenzy',
      'Battle Rage', 'Black Metal', 'Engulfing Vortex',
      'Dire Misfortune', 'Impending Doom',
    ],
    legendary: ['Vicious Cycle'],
  },
  Dionysus: {
    attack: ['Drunken Strike'],
    special: ['Drunken Flourish'],
    cast: ['Trippy Shot', 'Trippy Flare'],
    dash: ['Drunken Dash'],
    call: ["Dionysus' Aid"],
    other: [
      'Premium Vintage', 'After Party', 'Strong Drink',
      'Positive Outlook', 'High Tolerance', 'Bad Influence',
      'Numbing Sensation', 'Peer Pressure',
    ],
    legendary: ['Black Out'],
  },
  Hermes: {
    // Hermes doesn't follow the normal slot system
    attack: [],
    special: [],
    cast: [],
    dash: [],
    call: [],
    other: [
      'Quick Reload', 'Auto Reload', 'Greatest Reflex',
      'Side Hustle', 'Greater Evasion', 'Swift Flourish',
      'Second Wind', 'Swift Strike', 'Greater Haste',
      'Flurry Cast', 'Quick Favor', 'Quick Recovery',
      'Hyper Sprint', 'Rush Delivery',
    ],
    legendary: ['Greater Recall', 'Bad News'],
  },
  Demeter: {
    attack: ['Frost Strike'],
    special: ['Frost Flourish'],
    cast: ['Crystal Beam', 'Icy Flare'],
    dash: ['Mistral Dash'],
    call: ["Demeter's Aid"],
    other: [
      'Snow Burst', 'Frozen Touch', 'Rare Crop',
      'Nourished Soul', 'Ravenous Will', 'Glacial Glare',
      'Arctic Blast', 'Killing Freeze',
    ],
    legendary: ['Winter Harvest'],
  },
  Chaos: {
    attack: [],
    special: [],
    cast: [],
    dash: [],
    call: [],
    other: [],
    legendary: [],
    blessings: [
      'Affluence', 'Ambush', 'Assault', 'Defiance',
      'Eclipse', 'Favor', 'Flourish', 'Grasp',
      'Lunge', 'Shot', 'Soul', 'Strike',
    ],
    curses: [
      'Abyssal', 'Addled', 'Atrophic', 'Caustic',
      'Enshrouded', 'Excruciating', 'Flayed', 'Halting',
      'Maimed', 'Pauper', 'Roiling', 'Slippery', 'Slothful',
    ],
  },
};

// Duo boons - require boons from two specific gods
export const DUO_BOONS = [
  { name: 'Curse of Longing', gods: ['Ares', 'Aphrodite'] },
  { name: 'Heart Rend', gods: ['Artemis', 'Aphrodite'] },
  { name: 'Parting Shot', gods: ['Athena', 'Aphrodite'] },
  { name: 'Cold Embrace', gods: ['Demeter', 'Aphrodite'] },
  { name: 'Low Tolerance', gods: ['Dionysus', 'Aphrodite'] },
  { name: 'Sweet Nectar', gods: ['Poseidon', 'Aphrodite'] },
  { name: 'Smoldering Air', gods: ['Zeus', 'Aphrodite'] },
  { name: 'Hunting Blades', gods: ['Artemis', 'Ares'] },
  { name: 'Merciful End', gods: ['Athena', 'Ares'] },
  { name: 'Freezing Vortex', gods: ['Demeter', 'Ares'] },
  { name: 'Curse of Nausea', gods: ['Dionysus', 'Ares'] },
  { name: 'Curse of Drowning', gods: ['Poseidon', 'Ares'] },
  { name: 'Vengeful Mood', gods: ['Zeus', 'Ares'] },
  { name: 'Deadly Reversal', gods: ['Athena', 'Artemis'] },
  { name: 'Crystal Clarity', gods: ['Demeter', 'Artemis'] },
  { name: 'Splitting Headache', gods: ['Dionysus', 'Artemis'] },
  { name: 'Mirage Shot', gods: ['Poseidon', 'Artemis'] },
  { name: 'Lightning Rod', gods: ['Zeus', 'Artemis'] },
  { name: 'Stubborn Roots', gods: ['Demeter', 'Athena'] },
  { name: 'Calculated Risk', gods: ['Dionysus', 'Athena'] },
  { name: 'Unshakable Mettle', gods: ['Poseidon', 'Athena'] },
  { name: 'Lightning Phalanx', gods: ['Zeus', 'Athena'] },
  { name: 'Ice Wine', gods: ['Dionysus', 'Demeter'] },
  { name: 'Blizzard Shot', gods: ['Poseidon', 'Demeter'] },
  { name: 'Cold Fusion', gods: ['Zeus', 'Demeter'] },
  { name: 'Exclusive Access', gods: ['Poseidon', 'Dionysus'] },
  { name: 'Scintillating Feast', gods: ['Zeus', 'Dionysus'] },
  { name: 'Sea Storm', gods: ['Zeus', 'Poseidon'] },
];

// All boons in a flat searchable array
export const ALL_BOONS = (() => {
  const boons = [];
  for (const [god, slots] of Object.entries(BOONS_BY_GOD)) {
    for (const [slot, names] of Object.entries(slots)) {
      if (slot === 'blessings' || slot === 'curses') {
        for (const name of names) {
          boons.push({ god, name, slot: slot === 'blessings' ? 'blessing' : 'curse' });
        }
      } else {
        for (const name of names) {
          boons.push({ god, name, slot });
        }
      }
    }
  }
  for (const duo of DUO_BOONS) {
    boons.push({ god: duo.gods.join(' + '), name: duo.name, slot: 'duo' });
  }
  return boons;
})();
