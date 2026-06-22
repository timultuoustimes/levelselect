// Mina the Hollower — Tracker Data
// Yacht Club Games (2026) · Tenebrous Isle Metroidvania

export const REGIONS = [
  {
    id: 'ossex',
    name: 'Ossex City',
    icon: '🏙️',
    hub: true,
    sparkGenerator: false,
    boss: null,
    description: 'Central hub. Shops, NPCs, the Trinket Chest, and the Emporium.',
  },
  {
    id: 'queensbury',
    name: 'Queensbury Crypt',
    icon: '⚰️',
    hub: false,
    sparkGenerator: true,
    boss: 'The Duchess of Queensbury',
    description: 'First dungeon. Contains the Ancestral Chamber (secret boss: Midden).',
  },
  {
    id: 'nox-bayou',
    name: "Nox's Bayou",
    icon: '🌿',
    hub: false,
    sparkGenerator: true,
    boss: "Nox's Beast",
    description: 'Hazardous swamp reached by boat from Ossex. Noxious water and hostile flora.',
  },
  {
    id: 'bone-beach',
    name: 'Bone Beach',
    icon: '🦴',
    hub: false,
    sparkGenerator: true,
    boss: 'Mined Mind',
    description: 'Mining town built inside a gargantuan creature carcass. Bones are currency.',
  },
  {
    id: 'kindlewood',
    name: 'Kindlewood',
    icon: '🌲',
    hub: false,
    sparkGenerator: false,
    boss: 'Madd House',
    description: 'Dense forest gating the path to Septemburg.',
  },
  {
    id: 'septemburg',
    name: 'Septemburg',
    icon: '🏚️',
    hub: false,
    sparkGenerator: true,
    boss: null,
    description: 'Reached through Kindlewood.',
  },
  {
    id: 'astral-orrery',
    name: 'Astral Orrery',
    icon: '⭐',
    hub: false,
    sparkGenerator: true,
    boss: 'Orrery Warden',
    description: 'Celestial-themed clockwork region.',
  },
  {
    id: 'coltrane-peak',
    name: 'Coltrane Peak',
    icon: '⛰️',
    hub: false,
    sparkGenerator: true,
    boss: 'Frozen Horror',
    description: 'Icy mountain peak. Requires 10,000 Bones train donation. Secret boss: Mirren.',
  },
];

export const STORY_BOSSES = [
  {
    id: 'nether-kraken',
    name: 'Nether Kraken',
    area: 'Prologue — Ship Deck',
    reward: 'Uranium Bracelet',
    note: 'Scripted intro — survive the arm slams, Kraken retreats when ship crashes.',
  },
  {
    id: 'hulk-trooper',
    name: 'Hulk Trooper',
    area: 'Prologue Shore',
    reward: null,
    note: 'Mini-boss on the shore before reaching Ossex City.',
  },
  {
    id: 'thorne-1',
    name: 'Thorne (Round 1)',
    area: 'Early Game',
    reward: null,
    note: 'First proper boss after the shipwreck.',
  },
  {
    id: 'duchess',
    name: 'The Duchess of Queensbury',
    area: 'Queensbury Crypt',
    reward: null,
    note: 'Gate boss for the first Spark Generator.',
  },
  {
    id: 'nox-beast',
    name: "Nox's Beast",
    area: "Nox's Bayou",
    reward: null,
    note: 'Gate boss for the Swampy Generator.',
  },
  {
    id: 'madd-house',
    name: 'Madd House',
    area: 'Kindlewood',
    reward: null,
    note: 'Gate boss — clears the path to Septemburg.',
  },
  {
    id: 'mined-mind',
    name: 'Mined Mind',
    area: 'Bone Beach',
    reward: null,
    note: 'Gate boss for the Shoreline Generator.',
  },
  {
    id: 'orrery-warden',
    name: 'Orrery Warden',
    area: 'Astral Orrery',
    reward: null,
    note: 'Gate boss for the Astral Generator.',
  },
  {
    id: 'frozen-horror',
    name: 'Frozen Horror',
    area: 'Coltrane Peak',
    reward: null,
    note: 'Gate boss for the Coltrane Generator.',
  },
  {
    id: 'thorne-2',
    name: 'Thorne (Round 2)',
    area: 'Mid-game',
    reward: null,
    note: 'Thorne returns.',
  },
  {
    id: 'thorne-3',
    name: 'Thorne (Round 3)',
    area: 'Endgame',
    reward: null,
    note: 'Final confrontation.',
  },
];

export const SECRET_BOSSES = [
  {
    id: 'midden',
    name: 'Midden',
    area: 'Queensbury Crypt — Ancestral Chamber',
    renegade: false,
    reward: 'Fly Bait Trinket',
    how: 'Enter through the door requiring 2 Plasma Vials, then insult him to trigger the fight.',
  },
  {
    id: 'thalassion',
    name: 'Thalassion',
    area: 'Backwaters',
    renegade: false,
    reward: null,
    how: 'Catch all 15 fish using the fishing rod from Irwin & Durwin, then cross the watery area to the right.',
  },
  {
    id: 'dark-deluxy',
    name: 'Dark Deluxy',
    area: 'Unknown',
    renegade: false,
    reward: null,
    how: 'Specific trigger required — consult a guide.',
  },
  {
    id: 'mirren',
    name: 'Mirren',
    area: 'Coltrane Peak — Underlab',
    renegade: false,
    reward: null,
    how: 'Dig under the ice from the Underlab.',
  },
  {
    id: 'armand',
    name: 'Armand',
    area: 'Unknown',
    renegade: true,
    reward: null,
    how: 'One of five Renegades. Defeat all five for the Renegade Roundup reward.',
  },
  {
    id: 'maxi',
    name: 'Maxi',
    area: 'Unknown',
    renegade: true,
    reward: null,
    how: 'Renegade.',
  },
  {
    id: 'willis',
    name: 'Willis',
    area: 'Unknown',
    renegade: true,
    reward: null,
    how: 'Renegade.',
  },
  {
    id: 'dugin',
    name: 'Dugin',
    area: 'Unknown',
    renegade: true,
    reward: null,
    how: 'Renegade.',
  },
  {
    id: 'evra',
    name: 'Evra the Undying',
    area: 'Unknown',
    renegade: true,
    reward: null,
    how: 'Renegade — hardest secret boss. Rides an undead steed. Requires multiple movement abilities to reach.',
  },
];

// Trinkets grouped by region (60 total)
// Regional distribution based on available guides. Totals to 60.
export const TRINKET_REGIONS = [
  { id: 'ossex',       name: 'Ossex City & Sub-areas', max: 15 },
  { id: 'queensbury',  name: 'Queensbury Crypt',        max: 6  },
  { id: 'nox',         name: "Nox's Bayou",             max: 6  },
  { id: 'boneBeach',   name: 'Bone Beach',              max: 6  },
  { id: 'kindlewood',  name: 'Kindlewood / Septemburg', max: 8  },
  { id: 'astral',      name: 'Astral Orrery',           max: 5  },
  { id: 'coltrane',    name: 'Coltrane Peak',           max: 5  },
  { id: 'eastern',     name: 'Eastern Heath',           max: 4  },
  { id: 'southern',    name: 'Southern Outskirts',      max: 2  },
  { id: 'other',       name: 'Merchants & Quests',      max: 3  },
];
export const TOTAL_TRINKETS = 60;

// 8 Joule Boxes (upgrade energy/ammo capacity): 3 from Ossex Emporium, 5 from exploration
export const JOULE_BOXES = [
  { id: 'jb-shop-1', label: 'Emporium — Purchase 1', via: 'shop' },
  { id: 'jb-shop-2', label: 'Emporium — Purchase 2', via: 'shop' },
  { id: 'jb-shop-3', label: 'Emporium — Purchase 3', via: 'shop' },
  { id: 'jb-world-1', label: 'Exploration Find #1', via: 'explore' },
  { id: 'jb-world-2', label: 'Exploration Find #2', via: 'explore' },
  { id: 'jb-world-3', label: 'Exploration Find #3', via: 'explore' },
  { id: 'jb-world-4', label: 'Exploration Find #4', via: 'explore' },
  { id: 'jb-world-5', label: 'Exploration Find #5', via: 'explore' },
];

// Quests, minigames, and challenge activities (23 total)
export const QUESTS = [
  // Poppit Shops (3)
  { id: 'poppit-1',   name: 'Poppit Stop #1',          type: 'shop',      area: 'Eastern Heath',             npc: 'Poppit',          reward: 'Wisp Trinket'           },
  { id: 'poppit-2',   name: 'Poppit Stop #2',          type: 'shop',      area: 'Western Wilds',             npc: 'Poppit',          reward: 'Wisp Trinket'           },
  { id: 'poppit-3',   name: 'Poppit Stop #3',          type: 'shop',      area: 'Southern Outskirts',        npc: 'Poppit',          reward: 'Wisp Trinket'           },
  { id: 'dance-poppit', name: 'Dance with Poppit',     type: 'quest',     area: 'Poppit Stops',              npc: 'Poppit',          reward: null                     },
  // Racing (Blaise)
  { id: 'race-1',     name: 'Race #1',                 type: 'race',      area: 'Ossex',                     npc: 'Blaise',          reward: null                     },
  { id: 'race-2',     name: 'Race #2',                 type: 'race',      area: 'Overworld',                 npc: 'Blaise',          reward: null                     },
  { id: 'race-3',     name: 'Race #3',                 type: 'race',      area: 'Overworld',                 npc: 'Blaise',          reward: null                     },
  // Minigames
  { id: 'ring-dive',  name: 'Ring Dive',               type: 'minigame',  area: 'Unknown',                   npc: null,              reward: null                     },
  { id: 'wrecker',    name: 'Wrecker',                 type: 'minigame',  area: 'Unknown',                   npc: null,              reward: null                     },
  // Fishing
  { id: 'fishing',    name: 'Fishing (all 15 catches)', type: 'collection', area: 'Backwaters',              npc: 'Irwin & Durwin',  reward: 'Unlocks Thalassion boss' },
  // NPC Challenges
  { id: 'choppe-shoppe', name: 'Choppe Shoppe Challenge', type: 'challenge', area: 'Eastern Heath',          npc: null,              reward: 'Chain Capacitor Trinket' },
  { id: 'music-hall',    name: 'Music Hall Sequence',  type: 'challenge', area: 'Ossex',                     npc: null,              reward: 'Pneumatic Armlet Trinket' },
  { id: 'southern-duo',  name: 'Southern Outskirts Duo', type: 'quest',   area: 'Southern Outskirts',        npc: null,              reward: 'Lace Glove Trinket'     },
  // Renegades (5 secret bosses as a meta-quest)
  { id: 'renegades',  name: 'Renegade Roundup (all 5)', type: 'collection', area: 'Various',                 npc: null,              reward: 'Trinket Bag + Spark Container + Health Rose + Gilded Rod' },
  // Train donation
  { id: 'train-donation', name: 'Iron Steed Donation (10,000 Bones)', type: 'quest', area: 'Ossex',          npc: null,              reward: 'Unlocks Coltrane Peak access' },
  // Iron Steed challenge
  { id: 'iron-steed', name: 'Iron Steed Run (6 screens)',  type: 'challenge', area: 'Overworld',              npc: null,              reward: null                     },
];
