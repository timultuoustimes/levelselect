// Generic lightweight roguelike config - used for GoNNER, Cursed to Golf, etc.
// Each game defines its own loadout fields

// GoNNER has 4 procedural worlds (Cave, Robot, Shooty, Death) — NOT named stages.
// Each world is procedurally generated; there are no fixed named levels to track.
// World bosses: Fatty Bats (Cave), Gureddo (Robot), The Snakes (Shooty), ??? (Death/final boss).
export const GONNERS_CONFIG = {
  name: 'GoNNER',
  icon: '💀',
  color: 'from-red-900 via-gray-900 to-black',
  accent: 'red',
  loadoutFields: [
    {
      id: 'head',
      label: 'Head',
      type: 'text',
      placeholder: 'e.g. Default, Sally...',
    },
    {
      id: 'body',
      label: 'Body',
      type: 'text',
      placeholder: 'e.g. Default...',
    },
    {
      id: 'weapon',
      label: 'Weapon',
      type: 'text',
      placeholder: 'e.g. Gun, Arm...',
    },
    {
      id: 'buddy',
      label: 'Buddy',
      type: 'select',
      options: ['None', 'Sally'],
    },
  ],
  outcomes: ['victory', 'death', 'abandoned'],
};

// Cursed to Golf: 18 holes total across 4 biomes (randomly selected from a pool of 70+).
// Holes-per-biome breakdown is not fixed — the 18 played each run are drawn from the pool.
// Caddies (The Scotsman, The Explorer, The Forgotten, The Greenskeeper) are BOSS ENCOUNTERS,
// not collectibles. They are legendary phantoms fought as multi-phase golf challenges at the
// end of each biome. There are also regular boss holes within each biome.
export const CURSED_TO_GOLF_CONFIG = {
  name: 'Cursed to Golf',
  icon: '⛳',
  color: 'from-green-900 via-gray-900 to-black',
  accent: 'green',
  loadoutFields: [
    {
      id: 'clubs',
      label: 'Starting Clubs',
      type: 'text',
      placeholder: 'e.g. Driver, Iron, Wedge...',
    },
    {
      id: 'cards',
      label: 'Hole-in-One Cards',
      type: 'text',
      placeholder: 'Cards carried into run...',
    },
    {
      id: 'hole',
      label: 'Furthest Hole Reached',
      type: 'text',
      placeholder: 'e.g. Hole 4, Boss Hole...',
    },
  ],
  outcomes: ['escaped', 'death', 'abandoned'],
};
