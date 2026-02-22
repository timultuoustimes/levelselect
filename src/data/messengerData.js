// The Messenger - complete collectibles and progression data

export const LEVELS = [
  // Part 1 (8-bit linear)
  { id: 'lvl-1',  name: 'Wingsuit',           part: 1, boss: 'Wingsuit Boss',          powerSeals: 4 },
  { id: 'lvl-2',  name: 'Ninja Village',       part: 1, boss: 'Wingsuit',               powerSeals: 4 },
  { id: 'lvl-3',  name: 'Autumn Hills',        part: 1, boss: 'Wingsuit',               powerSeals: 4 },
  { id: 'lvl-4',  name: 'Catacombs',           part: 1, boss: 'Necromancer / Ruxxtin',  powerSeals: 5 },
  { id: 'lvl-5',  name: 'Bamboo Creek',        part: 1, boss: null,                     powerSeals: 4 },
  { id: 'lvl-6',  name: 'Searing Crags',       part: 1, boss: 'Colos & Suses',          powerSeals: 5 },
  { id: 'lvl-7',  name: 'Glacial Peak',        part: 1, boss: null,                     powerSeals: 3 },
  { id: 'lvl-8',  name: 'Tower of Time',       part: 1, boss: 'Clockwork Concierge',    powerSeals: 3 },
  { id: 'lvl-9',  name: 'Cloud Ruins',         part: 1, boss: null,                     powerSeals: 4 },
  { id: 'lvl-10', name: 'Underworld',          part: 1, boss: 'Demon King',             powerSeals: 5 },
  // Part 2 (16-bit metroidvania)
  { id: 'lvl-11', name: 'Forlorn Temple',      part: 2, boss: 'Phantom',                powerSeals: 4 },
  { id: 'lvl-12', name: 'Corrupted Future',    part: 2, boss: 'Abomination',            powerSeals: 5 },
  { id: 'lvl-13', name: 'Music Box',           part: 2, boss: 'Phantom (Final)',        powerSeals: 0 },
  // DLC
  { id: 'lvl-dlc-1', name: 'Howling Grotto (Picnic Panic)', part: 3, boss: 'Butterfly Matriarch', powerSeals: 7, dlc: true },
  { id: 'lvl-dlc-2', name: 'Sunken Shrine (Picnic Panic)',  part: 3, boss: 'Guardian Gods',       powerSeals: 7, dlc: true },
];

export const MUSIC_NOTES = [
  { id: 'note-1', name: 'Key of Hope',     location: 'Autumn Hills',     description: 'In a 16-bit time rift at the bottom of a tall room with a large tree.' },
  { id: 'note-2', name: 'Key of Strength', location: 'Searing Crags',    description: 'Deliver the Power Thistle from Colos & Suses\'s flowerbed (8-bit) to the 8-bit era colossi.' },
  { id: 'note-3', name: 'Key of Love',     location: 'Sunken Shrine',    description: 'Obtain Sun Crest and Moon Crest from within the shrine and place on the locked door.' },
  { id: 'note-4', name: 'Key of Chaos',    location: 'Underworld',       description: 'Found in the Underworld after defeating the Demon King.' },
  { id: 'note-5', name: 'Key of Symbiosis', location: 'Tower of Time HQ', description: 'Gifted by the Clockwork Concierge after clearing the Tower of Time.' },
  { id: 'note-6', name: 'Key of Courage',  location: 'Corrupted Future', description: 'Collect all 4 Phobekins → clear Forlorn Temple → use Demon Crown on portal → traverse Corrupted Future.' },
  // Pre-placed
  { id: 'note-7', name: 'Key of Adventure', location: 'Tower of Time HQ (pre-placed)', description: 'Already on the wall. Obtained by a previous Messenger.' },
  { id: 'note-8', name: 'Key of Revenge',   location: 'Tower of Time HQ (pre-placed)', description: 'Already on the wall. Obtained by a previous Messenger.' },
];

export const PHOBEKINS = [
  { id: 'phob-1', name: 'Claustro',  location: 'Bamboo Creek',    description: 'Found via wingsuit glide at the top of the tall waterfall. Glide to the far side to find a small opening.' },
  { id: 'phob-2', name: 'Acro',      location: 'Searing Crags',   description: 'Found in a hidden area within Searing Crags.' },
  { id: 'phob-3', name: 'Pyro',      location: 'Cloud Ruins',     description: 'Found in Cloud Ruins.' },
  { id: 'phob-4', name: 'Dextro',    location: 'Underworld',      description: 'Found in the Underworld.' },
];

export const SHOP_UPGRADES = [
  // Abilities
  { id: 'upg-1',  name: 'Wingsuit',             cost: 'story',  category: 'ability',   description: 'Allows gliding and riding air currents. Obtained in Wingsuit level.' },
  { id: 'upg-2',  name: 'Rope Dart',            cost: 'story',  category: 'ability',   description: 'Grapple and swing on lanterns. Obtained mid-game.' },
  { id: 'upg-3',  name: 'Lightfoot Tabi',       cost: 'story',  category: 'ability',   description: 'Run across liquid surfaces. Obtained in Sunken Shrine.' },
  { id: 'upg-4',  name: 'Fairy Bottle',         cost: 'story',  category: 'ability',   description: 'One-time auto-revive.' },
  { id: 'upg-5',  name: 'Magic Firefly',        cost: 'story',  category: 'ability',   description: 'Needed to traverse Corrupted Future.' },
  // Shop purchases
  { id: 'upg-6',  name: 'Ki Shuriken',          cost: 50,    category: 'shop',    description: 'Ranged attack — throw energy shurikens.' },
  { id: 'upg-7',  name: 'HP +1',                cost: 50,    category: 'shop',    description: 'Increase max health by 1.' },
  { id: 'upg-8',  name: 'Ki Refill Globe',      cost: 50,    category: 'shop',    description: 'Enemies sometimes drop Ki charge globes.' },
  { id: 'upg-9',  name: 'HP Refill Globe',      cost: 50,    category: 'shop',    description: 'Enemies sometimes drop HP globes.' },
  { id: 'upg-10', name: 'Ki +1 (pierce 1)',     cost: 250,   category: 'shop',    description: 'Ki charges +1, shurikens pierce 1 target.' },
  { id: 'upg-11', name: 'Ki +1 (pierce 2)',     cost: 350,   category: 'shop',    description: 'Ki charges +1, shurikens pierce 2 targets.' },
  { id: 'upg-12', name: 'Rift Map',             cost: 250,   category: 'shop',    description: 'Adds blue glow to rooms on Area Map where time rifts exist.' },
  { id: 'upg-13', name: 'Devil\'s Due',         cost: 100,   category: 'shop',    description: 'Quarble sticks around for 30s instead of 60s. Must die once to unlock.' },
  { id: 'upg-14', name: 'Attack Projectiles',   cost: 40,    category: 'shop',    description: 'Empower attacks to destroy enemy projectiles. Can cloudstep off them.' },
  { id: 'upg-15', name: 'Power of Resilience',  cost: 1000,  category: 'shop',    description: 'HP +1 (second upgrade tier).' },
  { id: 'upg-16', name: 'Aerobatics Warrior',   cost: 250,   category: 'shop',    description: 'Wingsuit attack — attack downward while gliding. Requires Wingsuit.' },
  { id: 'upg-17', name: 'Attack Boost',         cost: 2000,  category: 'shop',    description: 'Passive charge next attack for triple damage.' },
  { id: 'upg-18', name: 'Energy Shuriken',      cost: 'seal', category: 'shop',   description: 'Windmill Shuriken — unlock by collecting all 45 Power Seals.' },
];

// Total power seals in main game
export const TOTAL_POWER_SEALS_MAIN = 45;
export const TOTAL_POWER_SEALS_DLC = 14;
