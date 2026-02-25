// The Messenger - complete collectibles and progression data
//
// Part 1 Power Seals per level (total 45 in main game):
//   Ninja Village: 1, Autumn Hills: 4, Catacombs: 3, Bamboo Creek: 3,
//   Howling Grotto: 3, Quillshroom Marsh: 3, Searing Crags: 3, Glacial Peak: 3,
//   Tower of Time: 3, Cloud Ruins: 4, Underworld: 4
//   Part-2-only areas: Sunken Shrine: 3, Riviere Turquoise: 3,
//   Elemental Skylands: 3, Forlorn Temple: 2, Corrupted Future: 0, Music Box: 0
//   Running total: 1+4+3+3+3+3+3+3+3+4+4+3+3+3+2+0+0 = 45

export const LEVELS = [
  // ── Part 1 (8-bit linear, 11 stages in order) ────────────────────────────
  // NOTE: "Wingsuit" in the original data is not a real stage — the Wingsuit
  // is a story item obtained before Ninja Village, not a named level.
  // The first real level is Ninja Village (lvl-2 in the old IDs).
  // IDs lvl-1 through lvl-10 are preserved to avoid breaking existing save data;
  // lvl-1 is retired (was the erroneous "Wingsuit" stub).
  { id: 'lvl-2',  name: 'Ninja Village',      part: 1, boss: null,                  powerSeals: 1 },
  // boss fix: was 'Wingsuit' (wrong) — Ninja Village has no boss fight
  // powerSeals fix: was 4, correct count is 1 (only accessible in 16-bit)

  { id: 'lvl-3',  name: 'Autumn Hills',       part: 1, boss: 'Leaf Monster',        powerSeals: 4 },
  // boss fix: was 'Wingsuit' (wrong) — correct boss is the Leaf Monster

  { id: 'lvl-4',  name: 'Catacombs',          part: 1, boss: 'Ruxxtin',             powerSeals: 3 },
  // boss fix: was 'Necromancer / Ruxxtin' — official name is just 'Ruxxtin'
  // powerSeals fix: was 5, correct count is 3

  { id: 'lvl-5',  name: 'Bamboo Creek',       part: 1, boss: null,                  powerSeals: 3 },
  // powerSeals fix: was 4, correct count is 3

  // ── NEW levels (were missing from original data) ──────────────────────────
  { id: 'lvl-howling-grotto',    name: 'Howling Grotto',    part: 1, boss: 'Golem',           powerSeals: 3 },
  { id: 'lvl-quillshroom-marsh', name: 'Quillshroom Marsh', part: 1, boss: 'Queen of Quills',  powerSeals: 3 },

  { id: 'lvl-6',  name: 'Searing Crags',      part: 1, boss: 'Colos & Suses',       powerSeals: 3 },
  // powerSeals fix: was 5, correct count is 3

  { id: 'lvl-7',  name: 'Glacial Peak',       part: 1, boss: null,                  powerSeals: 3 },
  // no changes needed (boss correctly null, powerSeals correctly 3)

  { id: 'lvl-8',  name: 'Tower of Time',      part: 1, boss: 'Timekeeper',          powerSeals: 3 },
  // boss fix: was 'Clockwork Concierge' (wrong — that is the Elemental Skylands
  // boss in Part 2). The Tower of Time Part 1 boss is 'Timekeeper'.

  { id: 'lvl-9',  name: 'Cloud Ruins',        part: 1, boss: 'Sky Serpent',         powerSeals: 4 },
  // boss fix: was null — Cloud Ruins ends with the Sky Serpent boss fight

  { id: 'lvl-10', name: 'Underworld',         part: 1, boss: "Barma'thazel",        powerSeals: 4 },
  // boss fix: was 'Demon King' (wrong — Demon King is the Forlorn Temple boss
  // in Part 2). The Underworld Part 1 boss is Barma'thazel (the Demon General).
  // powerSeals fix: was 5, correct count is 4

  // ── Part 2 (16-bit metroidvania — revisit + new areas) ───────────────────
  // Part 2 also has Power Seals in areas revisited from Part 1 (already counted
  // above per area). The entries below are for the Part-2-exclusive locations.

  { id: 'lvl-sunken-shrine',      name: 'Sunken Shrine',      part: 2, boss: null,                   powerSeals: 3 },
  { id: 'lvl-riviere-turquoise',  name: 'Riviere Turquoise',  part: 2, boss: 'Butterfly Matriarch',   powerSeals: 3 },
  { id: 'lvl-elemental-skylands', name: 'Elemental Skylands', part: 2, boss: 'Clockwork Concierge',   powerSeals: 3 },

  { id: 'lvl-11', name: 'Forlorn Temple',     part: 2, boss: 'Demon King',           powerSeals: 2 },
  // boss fix: was 'Phantom' (wrong — Demon King is the Forlorn Temple boss).
  // powerSeals fix: was 4, correct count is 2 (seals #44 and #45)

  { id: 'lvl-12', name: 'Corrupted Future',   part: 2, boss: null,                   powerSeals: 0 },
  // boss fix: was 'Abomination' (invented name — Corrupted Future is linear
  // with no traditional boss fight; it leads directly to the Music Box).
  // powerSeals fix: was 5, correct count is 0

  { id: 'lvl-13', name: 'Music Box',          part: 2, boss: 'Phantom',              powerSeals: 0 },
  // boss fix: was 'Phantom (Final)' — the boss's name is simply 'Phantom'
  // (he is the true final boss of the game, fought inside the Music Box)

  // ── DLC — Picnic Panic ───────────────────────────────────────────────────
  // NOTE: The original DLC entries were wrong. They reused main-game area names
  // ("Howling Grotto", "Sunken Shrine") which are main-game locations.
  // Picnic Panic has four distinct tropical-themed areas, not remixes of
  // existing areas. Bosses and collectibles are DLC-specific.
  // Picnic Panic has 14 collectibles (skulls/totems) rather than Power Seals —
  // these are tracked separately and not counted in the 45-seal main-game total.
  { id: 'lvl-dlc-1', name: 'Open Sea',        part: 3, boss: 'Octo',                  powerSeals: 0, dlc: true },
  { id: 'lvl-dlc-2', name: 'Voodkin Shore',   part: 3, boss: 'Voodkin Totem Pole',    powerSeals: 0, dlc: true },
  { id: 'lvl-dlc-3', name: 'Fire Mountain',   part: 3, boss: 'Shadow Messenger',      powerSeals: 0, dlc: true },
  { id: 'lvl-dlc-4', name: 'Voodoo Heart',    part: 3, boss: "Barma'thething",        powerSeals: 0, dlc: true },
  // Barma'thething = Barma'thazel fused with the Dark Messenger (final DLC boss)
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
