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
  { id: 'blizzard', name: 'Blizzard', icon: '❄️', description: 'Slows enemies in an area. Excellent boss tool.' },
  { id: 'grenade', name: 'Grenade', icon: '💣', description: 'Lobbed explosive. Good area denial.' },
  { id: 'nova', name: 'Nova', icon: '✨', description: 'Expanding ring of energy.' },
];

export const DIFFICULTIES = ['Easy', 'Normal', 'Hard'];
export const MODES = ['Campaign', 'Survival'];
