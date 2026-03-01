// Dead Cells — Bosses, biomes, runes, and Boss Cell progression
// Base game + Rise of the Giant (free) + The Bad Seed + Fatal Falls + The Queen and the Sea + Return to Castlevania

export const BOSS_CELLS = [
  {
    id: 'bsc1',
    number: 1,
    unlockCondition: 'Beat Hand of the King / Queen / Dracula Final Form with 0 BSC active',
  },
  {
    id: 'bsc2',
    number: 2,
    unlockCondition: 'Beat final boss with 1 BSC active',
  },
  {
    id: 'bsc3',
    number: 3,
    unlockCondition: 'Beat final boss with 2 BSC active',
  },
  {
    id: 'bsc4',
    number: 4,
    unlockCondition: 'Beat final boss with 3 BSC active',
  },
  {
    id: 'bsc5',
    number: 5,
    unlockCondition: 'Beat The Giant (Rise of the Giant DLC) with 4 BSC active',
    note: 'Unlocks the True Final Boss and true ending.',
  },
];

export const RUNES = [
  {
    id: 'vine',
    name: 'Vine Rune',
    location: 'Promenade of the Condemned',
    guardian: 'Elite Undead Archer',
    unlocks: 'Grow climbing vines from green blobs. Unlocks Toxic Sewers access.',
  },
  {
    id: 'teleportation',
    name: 'Teleportation Rune',
    location: 'Toxic Sewers',
    guardian: 'Elite Undead Slasher',
    unlocks: 'Use teleportation monoliths throughout the map. Unlocks Ossuary and Forgotten Sepulcher.',
  },
  {
    id: 'ram',
    name: 'Ram Rune',
    location: 'Ossuary',
    guardian: 'Elite Slasher',
    unlocks: 'Smash through orange-glyphed floors. Unlocks Ancient Sewers and underground sections.',
  },
  {
    id: 'spider',
    name: 'Spider Rune',
    location: 'Slumbering Sanctuary',
    guardian: 'Elite Caster',
    unlocks: 'Climb walls. Unlocks Graveyard, Prison Depths, and many shortcuts.',
  },
  {
    id: 'challenger',
    name: "Challenger's Rune",
    location: 'Black Bridge',
    guardian: 'The Concierge (boss drop)',
    unlocks: "Unlocks Daily Challenge mode door in Prisoners' Quarters.",
  },
  {
    id: 'explorer',
    name: "Explorer's Rune",
    location: 'Forgotten Sepulcher',
    guardian: 'Two Dark Trackers',
    unlocks: 'Auto-reveals the full map and all points of interest (scrolls, merchants).',
  },
  {
    id: 'homunculus',
    name: 'Homunculus Rune',
    location: 'Throne Room',
    guardian: 'Hand of the King (boss drop)',
    unlocks: 'Detach your head to fly and reach hidden areas. Unlocks Cavern (Rise of the Giant).',
  },
  {
    id: 'customization',
    name: 'Customization Rune',
    location: 'Ramparts',
    guardian: 'Elite Zombie or Elite Archer',
    unlocks: 'Unlocks Custom Mode (Speed Run, One Hit One Kill, outfit options, etc.).',
  },
];

// Tier = which boss slot (1 = first boss, 2 = second, 3 = third, 4 = final, 5 = secret)
export const BOSSES = [
  // ── Base Game ─────────────────────────────────────────────────────────────
  { id: 'concierge',   name: 'The Concierge',   location: 'Black Bridge',        tier: 1, dlc: null,                      note: "Drops Challenger's Rune on first defeat." },
  { id: 'conjunc',     name: 'Conjunctivius',   location: 'Insufferable Crypt',   tier: 2, dlc: null,                      note: 'Access via Ancient Sewers.' },
  { id: 'timekeeper',  name: 'The Time Keeper', location: 'Clock Room',           tier: 3, dlc: null },
  { id: 'hotk',        name: 'Hand of the King', location: 'Throne Room',         tier: 4, dlc: null,                      note: "Drops Homunculus Rune and BSC 1–4 (one per run at the correct difficulty)." },

  // ── Rise of the Giant (Free DLC) ──────────────────────────────────────────
  { id: 'giant',       name: 'The Giant',        location: "Guardian's Haven",    tier: 4, dlc: 'Rise of the Giant',        note: 'Requires 4 BSC active. Drops BSC 5.' },
  { id: 'true-boss',   name: 'True Final Boss',  location: 'True Ending Area',    tier: 5, dlc: 'Rise of the Giant',        note: 'Requires 5 BSC. Spoiler boss — the true ending of the game.' },

  // ── The Bad Seed ──────────────────────────────────────────────────────────
  { id: 'mama-tick',   name: 'Mama Tick',        location: 'Nest',                tier: 1, dlc: 'The Bad Seed',             note: 'Alternate Boss 1 reached via Dilapidated Arboretum.' },

  // ── Fatal Falls ───────────────────────────────────────────────────────────
  { id: 'scarecrow',   name: 'The Scarecrow',    location: 'Mausoleum',           tier: 2, dlc: 'Fatal Falls',              note: 'Alternate Boss 2 reached via Fractured Shrines.' },

  // ── The Queen and the Sea ─────────────────────────────────────────────────
  { id: 'servants',    name: 'The Servants',     location: 'Lighthouse',          tier: 3, dlc: 'The Queen and the Sea',    note: 'Calliope, Euterpe & Kleio. Fight through the lighthouse. Last Servant defeated drops their weapon.' },
  { id: 'queen',       name: 'The Queen',        location: 'The Crown',           tier: 4, dlc: 'The Queen and the Sea',    note: "Alternate final boss. Drops Queen's Rapier. Counts for BSC acquisition." },

  // ── Return to Castlevania ─────────────────────────────────────────────────
  { id: 'death',       name: 'Death',            location: 'Defiled Necropolis',  tier: 2, dlc: 'Return to Castlevania',   note: 'Alternate Boss 2 on the Castlevania path.' },
  { id: 'dracula',     name: 'Dracula',          location: "Master's Keep",       tier: 3, dlc: 'Return to Castlevania' },
  { id: 'dracula-f',   name: 'Dracula — Final Form', location: "Master's Keep",  tier: 4, dlc: 'Return to Castlevania',   note: 'Alternate final boss. Counts for BSC acquisition.' },
];

// Section groups the biomes for display. Tier for ordering within section.
export const BIOMES = [
  // ── Start ─────────────────────────────────────────────────────────────────
  { id: 'pq',              name: "Prisoners' Quarters",       section: 'Start',   dlc: null,                    note: 'Starting area for every run. Contains the Aspect vendor and BSC tube.' },

  // ── Early (after start, before Boss 1) ────────────────────────────────────
  { id: 'promenade',       name: 'Promenade of the Condemned', section: 'Early',  dlc: null,                    note: 'Contains Vine Rune.' },
  { id: 'toxic',           name: 'Toxic Sewers',               section: 'Early',  dlc: null,                    note: 'Requires Vine Rune. Contains Teleportation Rune.' },
  { id: 'corrupted',       name: 'Corrupted Prison',           section: 'Early',  dlc: null,                    note: 'Requires Teleportation Rune.' },
  { id: 'prison-depths',   name: 'Prison Depths',              section: 'Early',  dlc: null,                    note: 'Requires Spider Rune.' },
  { id: 'arboretum',       name: 'Dilapidated Arboretum',      section: 'Early',  dlc: 'The Bad Seed',           note: 'Requires Teleportation Rune. Alternate early path → Nest.' },

  // ── Boss 1 ────────────────────────────────────────────────────────────────
  { id: 'black-bridge',    name: 'Black Bridge',               section: 'Boss 1', dlc: null,                    note: 'The Concierge.' },
  { id: 'nest',            name: 'Nest',                       section: 'Boss 1', dlc: 'The Bad Seed',           note: 'Mama Tick. Alternate Boss 1 via Arboretum.' },

  // ── Mid (between Boss 1 and Boss 2) ───────────────────────────────────────
  { id: 'ossuary',         name: 'Ossuary',                    section: 'Mid',    dlc: null,                    note: 'Requires Teleportation Rune. Contains Ram Rune.' },
  { id: 'ancient-sewers',  name: 'Ancient Sewers',             section: 'Mid',    dlc: null,                    note: 'Requires Ram Rune.' },
  { id: 'ramparts',        name: 'Ramparts',                   section: 'Mid',    dlc: null,                    note: 'Contains Customization Rune.' },
  { id: 'graveyard',       name: 'Graveyard',                  section: 'Mid',    dlc: null,                    note: 'Requires Spider Rune.' },
  { id: 'morass',          name: 'Morass of the Banished',     section: 'Mid',    dlc: 'The Bad Seed',           note: 'Part of Bad Seed path after Nest.' },
  { id: 'fractured',       name: 'Fractured Shrines',          section: 'Mid',    dlc: 'Fatal Falls',            note: 'Alternate mid-game path.' },
  { id: 'outskirts',       name: "Castle's Outskirts",         section: 'Mid',    dlc: 'Return to Castlevania',  note: 'Access via Richter in Prisoners\' Quarters.' },

  // ── Boss 2 ────────────────────────────────────────────────────────────────
  { id: 'insufferable',    name: 'Insufferable Crypt',         section: 'Boss 2', dlc: null,                    note: 'Conjunctivius.' },
  { id: 'mausoleum',       name: 'Mausoleum',                  section: 'Boss 2', dlc: 'Fatal Falls',            note: 'The Scarecrow. Alternate Boss 2 via Fractured Shrines.' },
  { id: 'defiled',         name: 'Defiled Necropolis',         section: 'Boss 2', dlc: 'Return to Castlevania',  note: 'Death. Alternate Boss 2 on Castlevania path.' },

  // ── Late (between Boss 2 and Boss 3) ──────────────────────────────────────
  { id: 'slumbering',      name: 'Slumbering Sanctuary',       section: 'Late',   dlc: null,                    note: 'Contains Spider Rune. Access via Ancient Sewers → Insufferable Crypt.' },
  { id: 'clock-tower',     name: 'Clock Tower',                section: 'Late',   dlc: null },
  { id: 'sepulcher',       name: 'Forgotten Sepulcher',        section: 'Late',   dlc: null,                    note: 'Requires Teleportation Rune. Contains Explorer\'s Rune.' },
  { id: 'stilt',           name: 'Stilt Village',              section: 'Late',   dlc: null },
  { id: 'undying',         name: 'Undying Shores',             section: 'Late',   dlc: 'Fatal Falls',            note: 'Part of Fatal Falls path after Scarecrow.' },
  { id: 'shipwreck',       name: 'Infested Shipwreck',         section: 'Late',   dlc: 'The Queen and the Sea',  note: 'Alternate late-game path via Queen and the Sea DLC.' },
  { id: 'dc-castle',       name: "Dracula's Castle",           section: 'Late',   dlc: 'Return to Castlevania',  note: 'Collect 20 Castlevania outfits here.' },

  // ── Boss 3 ────────────────────────────────────────────────────────────────
  { id: 'clock-room',      name: 'Clock Room',                 section: 'Boss 3', dlc: null,                    note: 'The Time Keeper.' },
  { id: 'lighthouse',      name: 'Lighthouse',                 section: 'Boss 3', dlc: 'The Queen and the Sea',  note: 'The Servants — fight up the lighthouse.' },
  { id: 'masters-keep',    name: "Master's Keep",              section: 'Boss 3', dlc: 'Return to Castlevania',  note: 'Dracula (Boss 3), then Dracula Final Form (Boss 4).' },

  // ── End (between Boss 3 and Final Boss) ───────────────────────────────────
  { id: 'high-peak',       name: 'High Peak Castle',           section: 'End',    dlc: null },
  { id: 'distillery',      name: 'Distillery',                 section: 'End',    dlc: null },
  { id: 'cavern',          name: 'Cavern',                     section: 'End',    dlc: 'Rise of the Giant',      note: 'Requires Homunculus Rune.' },

  // ── Final Boss areas ──────────────────────────────────────────────────────
  { id: 'throne-room',     name: 'Throne Room',                section: 'Final',  dlc: null,                    note: 'Hand of the King. Drops Homunculus Rune + BSC 1–4.' },
  { id: 'the-crown',       name: 'The Crown',                  section: 'Final',  dlc: 'The Queen and the Sea',  note: 'The Queen. Alternate final boss.' },
  { id: 'guardians-haven', name: "Guardian's Haven",           section: 'Final',  dlc: 'Rise of the Giant',      note: 'The Giant — requires 4 BSC. Drops BSC 5.' },
  { id: 'true-ending',     name: 'True Ending Area',           section: 'Final',  dlc: 'Rise of the Giant',      note: 'Requires 5 BSC. True final boss and ending.' },

  // ── Special ───────────────────────────────────────────────────────────────
  { id: 'bank',            name: 'The Bank',                   section: 'Special', dlc: null,                   note: 'Appears randomly once you\'ve entered a final boss area. Replaces the next biome when a golden chest triggers it.' },
];

export const DLC_LIST = [
  { id: null,                    label: 'Base Game' },
  { id: 'Rise of the Giant',     label: 'Rise of the Giant (Free)' },
  { id: 'The Bad Seed',          label: 'The Bad Seed' },
  { id: 'Fatal Falls',           label: 'Fatal Falls' },
  { id: 'The Queen and the Sea', label: 'The Queen and the Sea' },
  { id: 'Return to Castlevania', label: 'Return to Castlevania' },
];

export const SECTIONS = ['Start', 'Early', 'Boss 1', 'Mid', 'Boss 2', 'Late', 'Boss 3', 'End', 'Final', 'Special'];
