// Generic lightweight roguelike config - used for GONNERS, Cursed to Golf, etc.
// Each game defines its own loadout fields

export const GONNERS_CONFIG = {
  name: 'GONNER',
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
