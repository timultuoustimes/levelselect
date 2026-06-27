// Lone Ruin game data

export const STARTING_SPELLS = [
  {
    id: 'shards',
    name: 'Shards',
    icon: '💎',
    type: 'ranged',
    description: 'High fire rate basic projectile spell. Simple and effective.',
  },
  {
    id: 'fireball',
    name: 'Fireball',
    icon: '🔥',
    type: 'ranged',
    description: 'Slow but explosive. Deals AoE damage and knockback.',
  },
  {
    id: 'chain-lightning',
    name: 'Chain Lightning',
    icon: '⚡',
    type: 'ranged',
    description: 'Arcs through multiple enemies. Great crowd control.',
  },
  {
    id: 'scythe',
    name: 'Scythe',
    icon: '🌙',
    type: 'melee',
    description: 'Close-range melee spell. Powerful but puts you in harm\'s way.',
  },
  {
    id: 'barrage',
    name: 'Barrage',
    icon: '🌟',
    type: 'ranged',
    description: 'Multi-projectile ranged spell. Good spread damage.',
  },
  {
    id: 'pulse',
    name: 'Pulse',
    icon: '🔵',
    type: 'aoe',
    description: 'Area burst around the caster. Strong up close.',
  },
  {
    id: 'boomerang',
    name: 'Boomerang',
    icon: '🪃',
    type: 'ranged',
    description: 'Returns to you on flight path. Great for status effects builds.',
  },
  {
    id: 'rail',
    name: 'Rail',
    icon: '🔱',
    type: 'ranged',
    description: 'Piercing linear projectile. Hits enemies in a line.',
  },
];

// Additional spells that can be acquired during runs (not starting spells)
export const RUN_SPELLS = [
  { id: 'blizzard',      name: 'Blizzard',      icon: '❄️', description: 'Slows enemies in an area. Excellent boss tool.' },
  { id: 'grenade-toss', name: 'Grenade Toss',  icon: '💣', description: 'Lobbed explosive. Good area denial.' },
  { id: 'nova',          name: 'Nova',          icon: '✨', description: 'Expanding ring of energy.' },
  { id: 'black-hole',   name: 'Black Hole',    icon: '🌑', description: 'Pulls enemies toward a point. Strong crowd control.' },
  { id: 'barrier',      name: 'Barrier',       icon: '🧊', description: 'Place a wall of ice at cursor. Blocks enemies and projectiles.' },
  { id: 'berserk',      name: 'Berserk',       icon: '🔴', description: 'Refreshes all other cooldowns instantly on a timer. Speeds you up.' },
];

export const DIFFICULTIES = ['Easy', 'Normal', 'Hard'];
export const MODES = ['Campaign', 'Survival'];

// NOTE: Campaign floor count — sources conflict between 21 floors (3 bosses, every 7th floor)
// and 24 floors. Multiple reviews cite 21; leaving as a known discrepancy until confirmed in-game.
