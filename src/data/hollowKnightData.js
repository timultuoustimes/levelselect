// Hollow Knight tracker config — Phase 2 full dataset.
//
// Structured schema: see docs/structured-tracker-schema.md
//
// A mix of hand-authored items (named bosses, charms, spells, etc.) and
// programmatically generated collectibles (grubs, whispering roots, and
// the four relic types) — because tracking "grub #14 in Deepnest" works
// just fine without a hand-authored location string for every single one,
// and these can be spelled out later if the in-game feel demands it.
//
// Knowledge caveat: authored from memory, so some specifics (charm notch
// costs, a few boss names) may need correction. Locations for generated
// collectibles are area-level only. The idea is to have a real working
// tracker you can use in-game immediately — fix anything wrong as you
// go, or regenerate the whole thing with the Phase 3 AI generator later.
//
// Content scope: base game + all 4 free content packs
// (Hidden Dreams, The Grimm Troupe, Lifeblood, Godmaster) — everything
// included in the Switch 2 Edition. Content unique to a specific pack is
// tagged with `dlc:hidden-dreams`, `dlc:grimm-troupe`, `dlc:lifeblood`,
// or `dlc:godmaster` so you can see where things come from.

// ─── Helpers ─────────────────────────────────────────────────────────────────

const times = (n, fn) => Array.from({ length: n }, (_, i) => fn(i));

// Per-area distribution of the 46 grubs across Hallownest.
const GRUB_AREAS = [
  { key: 'crossroads', area: 'Forgotten Crossroads', count: 6 },
  { key: 'greenpath',  area: 'Greenpath',            count: 5 },
  { key: 'fungal',     area: 'Fungal Wastes',        count: 5 },
  { key: 'fog',        area: 'Fog Canyon',           count: 2 },
  { key: 'city',       area: 'City of Tears',        count: 4 },
  { key: 'crystal',    area: 'Crystal Peak',         count: 7 },
  { key: 'deepnest',   area: 'Deepnest',             count: 5 },
  { key: 'waterways',  area: 'Royal Waterways',      count: 4 },
  { key: 'kingdom',    area: "Kingdom's Edge",       count: 4 },
  { key: 'basin',      area: 'Ancient Basin',        count: 2 },
  { key: 'cliffs',     area: 'Howling Cliffs',       count: 1 },
  { key: 'resting',    area: 'Resting Grounds',      count: 1 },
]; // total: 46

const makeGrubs = () => {
  const out = [];
  for (const { key, area, count } of GRUB_AREAS) {
    for (let i = 1; i <= count; i++) {
      out.push({
        id: `grub-${key}-${i}`,
        name: `Grub — ${area} ${i} of ${count}`,
        location: area,
      });
    }
  }
  return out;
};

// Per-area distribution of the 20 Whispering Roots. Approximate — area
// counts from memory and may need correction after a full playthrough.
const ROOT_AREAS = [
  { key: 'crossroads', area: 'Forgotten Crossroads', count: 1 },
  { key: 'greenpath',  area: 'Greenpath',            count: 2 },
  { key: 'fungal',     area: 'Fungal Wastes',        count: 3 },
  { key: 'gardens',    area: "Queen's Gardens",      count: 2 },
  { key: 'city',       area: 'City of Tears',        count: 1 },
  { key: 'deepnest',   area: 'Deepnest',             count: 2 },
  { key: 'kingdom',    area: "Kingdom's Edge",       count: 2 },
  { key: 'crystal',    area: 'Crystal Peak',         count: 2 },
  { key: 'resting',    area: 'Resting Grounds',      count: 1 },
  { key: 'cliffs',     area: 'Howling Cliffs',       count: 1 },
  { key: 'basin',      area: 'Ancient Basin',        count: 1 },
  { key: 'waterways',  area: 'Royal Waterways',      count: 1 },
  { key: 'kings-pass', area: "King's Pass",          count: 1 },
]; // total: 20

const makeRoots = () => {
  const out = [];
  for (const { key, area, count } of ROOT_AREAS) {
    for (let i = 1; i <= count; i++) {
      out.push({
        id: `root-${key}-${i}`,
        name: count > 1 ? `Whispering Root — ${area} ${i} of ${count}` : `Whispering Root — ${area}`,
        location: area,
      });
    }
  }
  return out;
};

// Generic numbered collectible, used for relics where exact locations
// aren't authored individually. You can edit these later to add rooms.
const makeNumbered = (prefix, displayName, count, defaultLocation) =>
  times(count, i => ({
    id: `${prefix}-${i + 1}`,
    name: `${displayName} #${i + 1}`,
    ...(defaultLocation ? { location: defaultLocation } : {}),
  }));

// ─── Config ──────────────────────────────────────────────────────────────────

export const HOLLOW_KNIGHT_CONFIG = {
  name: 'Hollow Knight',
  icon: '🗡️',
  color: 'from-slate-900 via-blue-950 to-black',
  accent: 'slate',
  description: 'Metroidvania soulslike by Team Cherry',
  structuredData: {
    schemaVersion: 1,
    generatedAt: '2026-04-11T00:00:00Z',
    generatedBy: 'user',
    sources: [{
      type: 'user',
      title: 'Hand-authored Phase 2 dataset (all 4 content packs included)',
    }],

    categories: [
      // ─── story: dreamers ───────────────────────────────────────────────
      {
        id: 'dreamers',
        name: 'Dreamers',
        description: 'The three ancient sages whose seals keep the Black Egg bound.',
        type: 'checklist',
        items: [
          { id: 'dreamer-lurien',  name: 'Lurien the Watcher',
            location: "City of Tears (Watcher's Spire)",
            source: 'Defeat the Watcher Knights' },
          { id: 'dreamer-monomon', name: 'Monomon the Teacher',
            location: "Fog Canyon (Teacher's Archives)",
            source: 'Defeat Uumuu' },
          { id: 'dreamer-herrah',  name: 'Herrah the Beast',
            location: 'Deepnest (Distant Village)',
            source: "Reach the Beast's Den past Nosk's lair" },
        ],
      },

      // ─── main bosses ───────────────────────────────────────────────────
      {
        id: 'main-bosses',
        name: 'Main Bosses',
        description: 'Bosses on the main path to the base ending.',
        type: 'checklist',
        items: [
          { id: 'boss-false-knight',    name: 'False Knight',
            location: 'Forgotten Crossroads' },
          { id: 'boss-hornet-1',        name: 'Hornet Protector',
            location: 'Greenpath',
            source: 'Unlocks Mothwing Cloak progression' },
          { id: 'boss-mantis-lords',    name: 'Mantis Lords',
            location: 'Mantis Village (Fungal Wastes)' },
          { id: 'boss-soul-master',     name: 'Soul Master',
            location: 'Soul Sanctum (City of Tears)' },
          { id: 'boss-broken-vessel',   name: 'Broken Vessel',
            location: 'Ancient Basin',
            source: 'Unlocks Monarch Wings' },
          { id: 'boss-watcher-knights', name: 'Watcher Knights',
            location: "Watcher's Spire (City of Tears)",
            source: 'Required to kill Lurien' },
          { id: 'boss-uumuu',           name: 'Uumuu',
            location: "Teacher's Archives (Fog Canyon)",
            source: 'Required to kill Monomon' },
          { id: 'boss-dung-defender',   name: 'Dung Defender',
            location: 'Royal Waterways' },
          { id: 'boss-collector',       name: 'The Collector',
            location: 'Tower of Love (City of Tears)',
            description: 'Releases trapped grubs when defeated.' },
          { id: 'boss-hollow-knight',   name: 'The Hollow Knight',
            location: 'Temple of the Black Egg',
            description: 'Final boss of the base ending.' },
        ],
      },

      // ─── optional bosses ───────────────────────────────────────────────
      {
        id: 'optional-bosses',
        name: 'Optional Bosses',
        description: 'Not required for an ending, but part of 100% / 112%.',
        type: 'checklist',
        items: [
          { id: 'boss-gruz-mother',      name: 'Gruz Mother',
            location: 'Forgotten Crossroads' },
          { id: 'boss-vengefly-king',    name: 'Vengefly King',
            location: 'Greenpath' },
          { id: 'boss-brooding-mawlek',  name: 'Brooding Mawlek',
            location: 'Forgotten Crossroads (Ancestral Mound side)' },
          { id: 'boss-crystal-guardian', name: 'Crystal Guardian',
            location: 'Crystal Peak' },
          { id: 'boss-enraged-guardian', name: 'Enraged Guardian',
            location: 'Crystal Peak',
            description: 'Empowered rematch in the same room.' },
          { id: 'boss-nosk',             name: 'Nosk',
            location: 'Deepnest',
            missable: true,
            description: "Not available after Nosk's lair collapses." },
          { id: 'boss-flukemarm',        name: 'Flukemarm',
            location: 'Royal Waterways' },
          { id: 'boss-traitor-lord',     name: 'Traitor Lord',
            location: "Queen's Gardens" },
          { id: 'boss-hornet-2',         name: 'Hornet Sentinel',
            location: "Kingdom's Edge" },
          { id: 'boss-god-tamer',        name: 'God Tamer',
            location: 'Colosseum of Fools',
            source: 'Clear Trial of the Fool' },
          { id: 'boss-zote',             name: 'Zote the Mighty',
            location: 'Colosseum of Fools / multiple encounters',
            description: 'Fought across several encounters throughout Hallownest.' },
        ],
      },

      // ─── warrior dreams (essence ghost fights) ─────────────────────────
      {
        id: 'warrior-dreams',
        name: 'Warrior Dreams',
        description: 'Ghost warriors of Hallownest — defeat for dream essence. Requires the Dream Nail.',
        type: 'checklist',
        items: [
          { id: 'dream-elder-hu', name: 'Elder Hu',
            location: 'Resting Grounds',
            hideUntilDiscovered: true },
          { id: 'dream-gorb',     name: 'Gorb',
            location: 'Howling Cliffs',
            hideUntilDiscovered: true },
          { id: 'dream-marmu',    name: 'Marmu',
            location: "Queen's Gardens",
            hideUntilDiscovered: true },
          { id: 'dream-no-eyes',  name: 'No Eyes',
            location: 'Greenpath',
            hideUntilDiscovered: true },
          { id: 'dream-xero',     name: 'Xero',
            location: 'Resting Grounds',
            hideUntilDiscovered: true },
          { id: 'dream-galien',   name: 'Galien',
            location: 'Deepnest',
            hideUntilDiscovered: true },
          { id: 'dream-markoth',  name: 'Markoth',
            location: "Kingdom's Edge",
            hideUntilDiscovered: true },
        ],
      },

      // ─── upgraded dream forms ──────────────────────────────────────────
      {
        id: 'dream-bosses',
        name: 'Dream Bosses',
        description: 'Harder dream-nail variants of major bosses. Require the Awoken Dream Nail.',
        type: 'checklist',
        items: [
          { id: 'dream-failed-champion', name: 'Failed Champion',
            location: 'Forgotten Crossroads (False Knight arena)',
            source: "Dream Nail False Knight's corpse",
            hideUntilDiscovered: true },
          { id: 'dream-soul-tyrant',     name: 'Soul Tyrant',
            location: 'Soul Sanctum (City of Tears)',
            source: 'Dream Nail the Soul Master',
            hideUntilDiscovered: true },
          { id: 'dream-lost-kin',        name: 'Lost Kin',
            location: 'Ancient Basin',
            source: 'Dream Nail the Broken Vessel',
            hideUntilDiscovered: true },
          { id: 'dream-white-defender',  name: 'White Defender',
            location: "Dung Defender's hideaway (Royal Waterways)",
            source: 'Dream Nail the sleeping Dung Defender',
            tags: ['dlc:hidden-dreams'],
            hideUntilDiscovered: true },
          { id: 'dream-grey-prince-zote', name: 'Grey Prince Zote',
            location: "Bretta's house (Dirtmouth)",
            source: "Dream Nail Bretta's dreamed Zote",
            tags: ['dlc:hidden-dreams'],
            hideUntilDiscovered: true },
        ],
      },

      // ─── DLC-exclusive bosses ──────────────────────────────────────────
      {
        id: 'dlc-bosses',
        name: 'DLC-Exclusive Bosses',
        description: 'Bosses added by the free content packs.',
        type: 'checklist',
        items: [
          { id: 'boss-troupe-grimm',    name: 'Troupe Master Grimm',
            location: 'Dirtmouth (Grimm Troupe tent)',
            source: 'Light the Nightmare Lantern and complete the ritual',
            tags: ['dlc:grimm-troupe'] },
          { id: 'boss-nightmare-king',  name: 'Nightmare King Grimm',
            location: 'Grimm Troupe tent (dream)',
            source: 'Dream Nail the troupe master after defeating him',
            missable: true,
            tags: ['dlc:grimm-troupe', 'route-exclusive'],
            description: 'Only available on the "summon the troupe" route — not the "banish" route.' },
          { id: 'boss-hive-knight',     name: 'Hive Knight',
            location: 'The Hive (Kingdom\'s Edge)',
            tags: ['dlc:lifeblood'] },
        ],
      },

      // ─── godhome-exclusive bosses ──────────────────────────────────────
      {
        id: 'godhome-bosses',
        name: 'Godhome-Exclusive Bosses',
        description: 'Boss variants and final encounters found only in Godhome.',
        type: 'checklist',
        tags: ['dlc:godmaster'],
        items: [
          { id: 'boss-sisters-of-battle', name: 'Sisters of Battle',
            location: 'Godhome (Pantheon of the Artist)',
            description: 'Full-power rematch with all three Mantis Lords.',
            hideUntilDiscovered: true },
          { id: 'boss-winged-nosk',       name: 'Winged Nosk',
            location: 'Godhome',
            description: "A Godhome-exclusive variant of Nosk's fight.",
            hideUntilDiscovered: true },
          { id: 'boss-pure-vessel',       name: 'Pure Vessel',
            location: 'Godhome (Pantheon of Hallownest)',
            description: 'The Hollow Knight at its unshackled peak.',
            hideUntilDiscovered: true },
          { id: 'boss-absolute-radiance', name: 'Absolute Radiance',
            location: 'Godhome (Pantheon of Hallownest)',
            description: 'Final encounter of Pantheon 5. Unlocks the "Embrace the Void" ending.',
            hideUntilDiscovered: true },
        ],
      },

      // ─── colosseum of fools ────────────────────────────────────────────
      {
        id: 'colosseum',
        name: 'Colosseum of Fools',
        description: 'Three trials in the arena at the top of Kingdom\'s Edge.',
        type: 'checklist',
        items: [
          { id: 'colo-warrior',   name: 'Trial of the Warrior',
            location: 'Colosseum of Fools',
            metadata: { geoCost: 100 } },
          { id: 'colo-conqueror', name: 'Trial of the Conqueror',
            location: 'Colosseum of Fools',
            metadata: { geoCost: 450 } },
          { id: 'colo-fool',      name: 'Trial of the Fool',
            location: 'Colosseum of Fools',
            metadata: { geoCost: 800 },
            description: 'The hardest trial. Clearing unlocks God Tamer.' },
        ],
      },

      // ─── pantheons (godmaster) ─────────────────────────────────────────
      {
        id: 'pantheons',
        name: 'Pantheons',
        description: 'The five boss rushes of Godhome. Each must be cleared without dying.',
        type: 'checklist',
        tags: ['dlc:godmaster'],
        items: [
          { id: 'pantheon-master',     name: 'Pantheon of the Master',
            description: 'Boss rush focused on the earliest fights.' },
          { id: 'pantheon-artist',     name: 'Pantheon of the Artist',
            description: 'Includes the Sisters of Battle and other mid-game upgrades.' },
          { id: 'pantheon-sage',       name: 'Pantheon of the Sage',
            description: 'Deeper challenges including Enraged Guardian and Collector.' },
          { id: 'pantheon-knight',     name: 'Pantheon of the Knight',
            description: "Top-tier fights culminating in Pure Vessel.",
            hideUntilDiscovered: true },
          { id: 'pantheon-hallownest', name: 'Pantheon of Hallownest',
            description: 'All 42 bosses back-to-back, ending with Absolute Radiance.',
            hideUntilDiscovered: true },
        ],
      },

      // ─── nail upgrades ─────────────────────────────────────────────────
      {
        id: 'nail-upgrades',
        name: 'Nail Upgrades',
        description: 'Upgraded at the Nailsmith with pale ore + geo.',
        type: 'leveled',
        items: [{
          id: 'nail',
          name: 'Nail',
          maxRank: 4,
          rankNames: ['Old Nail', 'Sharpened Nail', 'Channelled Nail', 'Coiled Nail', 'Pure Nail'],
        }],
      },

      // ─── nail arts ─────────────────────────────────────────────────────
      {
        id: 'nail-arts',
        name: 'Nail Arts',
        description: 'Three techniques taught by the Great Nailmasters.',
        type: 'checklist',
        items: [
          { id: 'art-cyclone-slash', name: 'Cyclone Slash',
            source: 'Nailmaster Mato',
            location: 'Howling Cliffs' },
          { id: 'art-dash-slash',    name: 'Dash Slash',
            source: 'Nailmaster Oro',
            location: "Kingdom's Edge" },
          { id: 'art-great-slash',   name: 'Great Slash',
            source: 'Nailmaster Sheo',
            location: 'Greenpath' },
        ],
      },

      // ─── spells ────────────────────────────────────────────────────────
      {
        id: 'spells',
        name: 'Spells',
        description: 'Each spell has a base and an upgraded form.',
        type: 'leveled',
        items: [
          { id: 'spell-fireball',
            name: 'Vengeful Spirit → Shade Soul',
            maxRank: 2,
            rankNames: ['Not acquired', 'Vengeful Spirit', 'Shade Soul'],
            location: 'Forgotten Crossroads / Soul Sanctum' },
          { id: 'spell-quake',
            name: 'Desolate Dive → Descending Dark',
            maxRank: 2,
            rankNames: ['Not acquired', 'Desolate Dive', 'Descending Dark'],
            location: 'Soul Sanctum / Crystal Peak' },
          { id: 'spell-scream',
            name: 'Howling Wraiths → Abyss Shriek',
            maxRank: 2,
            rankNames: ['Not acquired', 'Howling Wraiths', 'Abyss Shriek'],
            location: "Howling Cliffs / The Abyss" },
        ],
      },

      // ─── mask shards (16 = 4 extra masks) ──────────────────────────────
      {
        id: 'mask-shards',
        name: 'Mask Shards',
        description: '16 shards in total — 4 per extra mask, for a max of 9 masks.',
        type: 'collectibles',
        items: [
          { id: 'mask-1',  name: 'Mask Shard #1',  location: 'Dirtmouth (Sly shop)',
            metadata: { acquired: 'purchase' } },
          { id: 'mask-2',  name: 'Mask Shard #2',  location: 'Dirtmouth (Sly shop)',
            metadata: { acquired: 'purchase' } },
          { id: 'mask-3',  name: 'Mask Shard #3',  location: 'Dirtmouth (Sly shop, after Shopkeeper\'s Key)',
            metadata: { acquired: 'purchase' } },
          { id: 'mask-4',  name: 'Mask Shard #4',  location: 'Dirtmouth (Sly shop, after Shopkeeper\'s Key)',
            metadata: { acquired: 'purchase' } },
          { id: 'mask-5',  name: 'Mask Shard #5',  location: "King's Pass (breakable wall)" },
          { id: 'mask-6',  name: 'Mask Shard #6',  location: 'Forgotten Crossroads (Brooding Mawlek reward)' },
          { id: 'mask-7',  name: 'Mask Shard #7',  location: 'Forgotten Crossroads (Grub reward — Grubfather)' },
          { id: 'mask-8',  name: 'Mask Shard #8',  location: 'Greenpath' },
          { id: 'mask-9',  name: 'Mask Shard #9',  location: 'Fungal Wastes' },
          { id: 'mask-10', name: 'Mask Shard #10', location: "Queen's Station / Fungal Wastes" },
          { id: 'mask-11', name: 'Mask Shard #11', location: 'Deepnest' },
          { id: 'mask-12', name: 'Mask Shard #12', location: 'Crystal Peak (Enraged Guardian area)' },
          { id: 'mask-13', name: 'Mask Shard #13', location: 'Royal Waterways' },
          { id: 'mask-14', name: 'Mask Shard #14', location: "Kingdom's Edge" },
          { id: 'mask-15', name: 'Mask Shard #15', location: 'Hallownest (Grubfather reward)' },
          { id: 'mask-16', name: 'Mask Shard #16', location: 'Hallownest (Seer reward — essence)' },
        ],
      },

      // ─── vessel fragments (9 = 3 extra soul vessels) ───────────────────
      {
        id: 'vessel-fragments',
        name: 'Vessel Fragments',
        description: '9 fragments in total — 3 per extra soul vessel.',
        type: 'collectibles',
        items: [
          { id: 'vessel-1', name: 'Vessel Fragment #1', location: 'Dirtmouth (Sly shop)',
            metadata: { acquired: 'purchase' } },
          { id: 'vessel-2', name: 'Vessel Fragment #2', location: 'Dirtmouth (Sly shop, after Shopkeeper\'s Key)',
            metadata: { acquired: 'purchase' } },
          { id: 'vessel-3', name: 'Vessel Fragment #3', location: 'Greenpath' },
          { id: 'vessel-4', name: 'Vessel Fragment #4', location: 'Forgotten Crossroads (Soul Totem area)' },
          { id: 'vessel-5', name: 'Vessel Fragment #5', location: "Queen's Gardens" },
          { id: 'vessel-6', name: 'Vessel Fragment #6', location: "Kingdom's Edge" },
          { id: 'vessel-7', name: 'Vessel Fragment #7', location: 'Deepnest' },
          { id: 'vessel-8', name: 'Vessel Fragment #8', location: 'Hallownest (Seer reward — essence)' },
          { id: 'vessel-9', name: 'Vessel Fragment #9', location: 'Ancient Basin' },
        ],
      },

      // ─── charms (~40 of the ~45 in the game) ───────────────────────────
      {
        id: 'charms',
        name: 'Charms',
        description: 'Equippable charms of Hallownest. Notch costs in metadata — some may need correction.',
        type: 'collectibles',
        items: [
          { id: 'charm-wayward-compass',   name: 'Wayward Compass',
            location: 'Forgotten Crossroads', source: 'Purchased from Iselda',
            metadata: { notchCost: 1 } },
          { id: 'charm-gathering-swarm',   name: 'Gathering Swarm',
            location: 'Forgotten Crossroads', source: 'Purchased from Salubra',
            metadata: { notchCost: 1 } },
          { id: 'charm-stalwart-shell',    name: 'Stalwart Shell',
            location: 'Forgotten Crossroads', source: 'Purchased from Sly',
            metadata: { notchCost: 2 } },
          { id: 'charm-soul-catcher',      name: 'Soul Catcher',
            location: 'Ancestral Mound', metadata: { notchCost: 2 } },
          { id: 'charm-shaman-stone',      name: 'Shaman Stone',
            location: 'Resting Grounds', source: 'Purchased from Salubra reward path',
            metadata: { notchCost: 3 } },
          { id: 'charm-soul-eater',        name: 'Soul Eater',
            location: 'Resting Grounds', metadata: { notchCost: 4 } },
          { id: 'charm-dashmaster',        name: 'Dashmaster',
            location: 'Fungal Wastes', metadata: { notchCost: 2 } },
          { id: 'charm-sprintmaster',      name: 'Sprintmaster',
            location: 'City of Tears (Sly)', metadata: { notchCost: 1 } },
          { id: 'charm-grubsong',          name: 'Grubsong',
            location: 'Forgotten Crossroads (Grubfather)', source: 'Rescue 10 grubs',
            metadata: { notchCost: 1 } },
          { id: 'charm-grubberflys-elegy', name: "Grubberfly's Elegy",
            location: 'Grubfather', source: 'Rescue all 46 grubs',
            metadata: { notchCost: 3 } },
          { id: 'charm-fragile-heart',     name: 'Fragile Heart',
            location: "Leg Eater (Fungal Wastes)", source: 'Can be upgraded to Unbreakable Heart at Divine (Grimm Troupe)',
            metadata: { notchCost: 2 } },
          { id: 'charm-fragile-greed',     name: 'Fragile Greed',
            location: 'Leg Eater (Fungal Wastes)',
            metadata: { notchCost: 2 } },
          { id: 'charm-fragile-strength',  name: 'Fragile Strength',
            location: 'Leg Eater (Fungal Wastes)',
            metadata: { notchCost: 3 } },
          { id: 'charm-spell-twister',     name: 'Spell Twister',
            location: 'Soul Sanctum (City of Tears)', metadata: { notchCost: 2 } },
          { id: 'charm-steady-body',       name: 'Steady Body',
            location: 'City of Tears (Sly)', metadata: { notchCost: 1 } },
          { id: 'charm-heavy-blow',        name: 'Heavy Blow',
            location: 'City of Tears (Sly, after Shopkeeper\'s Key)',
            metadata: { notchCost: 2 } },
          { id: 'charm-quick-slash',       name: 'Quick Slash',
            location: "Kingdom's Edge", metadata: { notchCost: 3 } },
          { id: 'charm-longnail',          name: 'Longnail',
            location: 'Fungal Wastes (Sly)', metadata: { notchCost: 2 } },
          { id: 'charm-mark-of-pride',     name: 'Mark of Pride',
            location: 'Mantis Village', source: 'Reward from Mantis Lords',
            metadata: { notchCost: 3 } },
          { id: 'charm-fury-of-the-fallen', name: 'Fury of the Fallen',
            location: "King's Pass", metadata: { notchCost: 2 } },
          { id: 'charm-thorns-of-agony',   name: 'Thorns of Agony',
            location: 'Greenpath', metadata: { notchCost: 1 } },
          { id: 'charm-baldur-shell',      name: 'Baldur Shell',
            location: 'Howling Cliffs', metadata: { notchCost: 2 } },
          { id: 'charm-flukenest',         name: 'Flukenest',
            location: 'Royal Waterways', source: 'Defeat Flukemarm',
            metadata: { notchCost: 3 } },
          { id: 'charm-defenders-crest',   name: "Defender's Crest",
            location: 'Royal Waterways', source: 'Defeat Dung Defender',
            metadata: { notchCost: 1 } },
          { id: 'charm-glowing-womb',      name: 'Glowing Womb',
            location: 'Forgotten Crossroads', metadata: { notchCost: 2 } },
          { id: 'charm-quick-focus',       name: 'Quick Focus',
            location: 'Resting Grounds (Salubra)', metadata: { notchCost: 3 } },
          { id: 'charm-deep-focus',        name: 'Deep Focus',
            location: 'Crystal Peak', metadata: { notchCost: 4 } },
          { id: 'charm-lifeblood-heart',   name: 'Lifeblood Heart',
            location: 'Greenpath', metadata: { notchCost: 2 } },
          { id: 'charm-lifeblood-core',    name: 'Lifeblood Core',
            location: 'Ancient Basin (hidden)', metadata: { notchCost: 3 } },
          { id: 'charm-jonis-blessing',    name: "Joni's Blessing",
            location: "Howling Cliffs (Joni's Repose)", metadata: { notchCost: 4 } },
          { id: 'charm-hiveblood',         name: 'Hiveblood',
            location: 'The Hive', source: 'Defeat Hive Knight',
            tags: ['dlc:lifeblood'], metadata: { notchCost: 3 } },
          { id: 'charm-spore-shroom',      name: 'Spore Shroom',
            location: 'Fungal Wastes', metadata: { notchCost: 1 } },
          { id: 'charm-sharp-shadow',      name: 'Sharp Shadow',
            location: 'Deepnest', metadata: { notchCost: 2 } },
          { id: 'charm-shape-of-unn',      name: 'Shape of Unn',
            location: 'Greenpath (Lake of Unn)', metadata: { notchCost: 2 } },
          { id: 'charm-nailmasters-glory', name: "Nailmaster's Glory",
            source: 'Learn all three Nail Arts', metadata: { notchCost: 1 } },
          { id: 'charm-weaversong',        name: 'Weaversong',
            location: "Weavers' Den (Deepnest)", metadata: { notchCost: 2 } },
          { id: 'charm-dream-wielder',     name: 'Dream Wielder',
            location: 'Resting Grounds (Seer)', source: 'Seer reward for essence',
            metadata: { notchCost: 1 } },
          { id: 'charm-dreamshield',       name: 'Dreamshield',
            location: 'Resting Grounds', metadata: { notchCost: 3 } },
          { id: 'charm-grimmchild',        name: 'Grimmchild',
            location: 'Howling Cliffs (Grimm Troupe tent)',
            source: 'Begin the Grimm Troupe ritual',
            missable: true,
            tags: ['dlc:grimm-troupe', 'route-exclusive'],
            metadata: { notchCost: 2 } },
          { id: 'charm-carefree-melody',   name: 'Carefree Melody',
            location: 'Dirtmouth (Nymm)',
            source: 'Banish the Grimm Troupe via Nightmare Lantern destruction',
            missable: true,
            tags: ['dlc:grimm-troupe', 'route-exclusive'],
            metadata: { notchCost: 3 } },
          { id: 'charm-kingsoul',          name: 'Kingsoul → Void Heart',
            location: 'White Palace + The Abyss',
            description: 'Assemble from Queen Fragment + King Fragment, then awakens to Void Heart at the Birthplace. Notch cost drops to 0.',
            metadata: { notchCost: 5, upgradedNotchCost: 0 },
            hideUntilDiscovered: true },
        ],
      },

      // ─── pale ore ──────────────────────────────────────────────────────
      {
        id: 'pale-ore',
        name: 'Pale Ore',
        description: '6 pieces total — enough to fully upgrade the Nail (with one to spare for Nailsmith quest outcomes).',
        type: 'collectibles',
        items: [
          { id: 'ore-1', name: 'Pale Ore #1', location: 'Crystal Peak (roll machine path)' },
          { id: 'ore-2', name: 'Pale Ore #2', location: 'Ancient Basin (hidden room)' },
          { id: 'ore-3', name: 'Pale Ore #3', location: "Deepnest (near Nosk's lair)" },
          { id: 'ore-4', name: 'Pale Ore #4', location: 'Resting Grounds (Seer — essence reward)' },
          { id: 'ore-5', name: 'Pale Ore #5', location: 'Colosseum of Fools (Trial of the Conqueror reward)' },
          { id: 'ore-6', name: 'Pale Ore #6', location: 'Grubfather (rescue 31+ grubs)' },
        ],
      },

      // ─── grubs (46, programmatically generated per area) ───────────────
      {
        id: 'grubs',
        name: 'Grubs',
        description: '46 grubs sealed in jars throughout Hallownest. Free them for rewards from the Grubfather.',
        type: 'collectibles',
        items: makeGrubs(),
      },

      // ─── whispering roots (20, programmatically generated per area) ────
      {
        id: 'whispering-roots',
        name: 'Whispering Roots',
        description: 'Dream Nail into each root to release essence. Area counts are approximate from memory.',
        type: 'collectibles',
        items: makeRoots(),
      },

      // ─── relics: hallownest seals (17) ─────────────────────────────────
      {
        id: 'hallownest-seals',
        name: 'Hallownest Seals',
        description: 'Sell to Relic Seeker Lemm, or keep for Dream Nail essence.',
        type: 'collectibles',
        items: makeNumbered('seal', 'Hallownest Seal', 17, 'Various'),
      },

      // ─── relics: king's idols (8) ──────────────────────────────────────
      {
        id: 'kings-idols',
        name: "King's Idols",
        description: "Relics depicting the Pale King. 8 total throughout Hallownest.",
        type: 'collectibles',
        items: makeNumbered('idol', "King's Idol", 8, 'Various'),
      },

      // ─── relics: arcane eggs (4) ───────────────────────────────────────
      {
        id: 'arcane-eggs',
        name: 'Arcane Eggs',
        description: 'Mysterious eggs worth a fortune to Lemm. Only 4 in the game.',
        type: 'collectibles',
        items: makeNumbered('egg', 'Arcane Egg', 4, 'Various'),
      },

      // ─── relics: wanderer's journals (14) ──────────────────────────────
      {
        id: 'wanderers-journals',
        name: "Wanderer's Journals",
        description: 'The most common relic. 14 scattered across Hallownest.',
        type: 'collectibles',
        items: makeNumbered('journal', "Wanderer's Journal", 14, 'Various'),
      },

      // ─── endings (sequence, spoiler-hidden) ────────────────────────────
      {
        id: 'endings',
        name: 'Endings',
        description: 'Ending names and descriptions are hidden until you reach them, or hit Reveal.',
        type: 'sequence',
        items: [
          { id: 'ending-hollow-knight',
            name: 'The Hollow Knight',
            description: 'The default ending — defeat The Hollow Knight without Void Heart equipped.',
            hideUntilDiscovered: true },
          { id: 'ending-sealed-siblings',
            name: 'Sealed Siblings',
            description: 'Acquire Void Heart, then defeat The Hollow Knight.',
            hideUntilDiscovered: true },
          { id: 'ending-dream-no-more',
            name: 'Dream No More',
            description: 'Acquire Void Heart and the Awoken Dream Nail, enter the dream, defeat The Radiance.',
            hideUntilDiscovered: true },
          { id: 'ending-embrace-the-void',
            name: 'Embrace the Void',
            description: 'Complete Pantheon of Hallownest in Godhome — defeat Absolute Radiance.',
            tags: ['dlc:godmaster'],
            hideUntilDiscovered: true },
        ],
      },
    ],

    estimatedHours: 40,
    completionNotes: '112% completion requires all charms including the Grimm Troupe route-exclusive pair, plus the Godmaster pantheons. Source content: base game + Hidden Dreams + The Grimm Troupe + Lifeblood + Godmaster (all included in the Switch 2 Edition).',
    tags: ['metroidvania', 'soulslike', 'indie', 'team-cherry'],
  },
};
