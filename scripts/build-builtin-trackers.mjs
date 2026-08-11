// Builds native/LevelSelect/LevelSelect/Resources/builtin-trackers.json from
// the web app's data modules, using the web's own conversion functions where
// they exist (checklist/Dead Cells) and faithful mappings for the bespoke
// games (Messenger / Citizen Sleeper / Mina). Item ids are chosen to match
// the legacy save-state keys exactly so imported progress lights up.
//
// Run from the repo root:  node scripts/build-builtin-trackers.mjs

import { checklistToStructuredSchema } from '../src/utils/structuredFactory.js';
import {
  BLAZING_CHROME_CONFIG, SAYONARA_CONFIG, CAST_N_CHILL_CONFIG,
  HITMAN_CONFIG, UNDER_THE_ISLAND_CONFIG,
} from '../src/data/checklistGameData.js';
import { buildDeadCellsStructuredSchema } from '../src/data/deadCellsData.js';
import { HOLLOW_KNIGHT_CONFIG } from '../src/data/hollowKnightData.js';
import * as messenger from '../src/data/messengerData.js';
import * as sleeper from '../src/data/citizenSleeperData.js';
import * as mina from '../src/data/minaData.js';
import fs from 'fs';

const item = (id, name, extra = {}) => ({ id, name, ...extra });
const cat = (id, name, items, extra = {}) => ({ id, name, items, ...extra });
const schema = categories => ({ schemaVersion: 1, categories });

// ── The Messenger ───────────────────────────────────────────────────────────
function messengerSchema() {
  const levels = messenger.LEVELS.map(l => item(l.id, l.name, {
    description: l.boss ? `Boss: ${l.boss}` : undefined,
    ...(l.powerSeals > 0 ? { maxRank: l.powerSeals, rankNames: null } : {}),
    tags: [`part:${l.part}`],
  }));
  return schema([
    cat('msgr-levels', 'Levels & Power Seals', levels, { type: 'sequence',
      description: 'Rank = Power Seals found in that level.' }),
    cat('msgr-notes', 'Music Notes', messenger.MUSIC_NOTES.map(n =>
      item(n.id, n.name, { location: n.location, description: n.description }))),
    cat('msgr-phobekins', 'Phobekins', messenger.PHOBEKINS.map(p =>
      item(p.id, p.name, { location: p.location, description: p.description }))),
    cat('msgr-upgrades', 'Shop & Upgrades', messenger.SHOP_UPGRADES.map(u =>
      item(u.id, u.name, { description: u.description }))),
  ]);
}

// ── Citizen Sleeper ─────────────────────────────────────────────────────────
function sleeperSchema() {
  const cats = [];
  for (const q of sleeper.QUESTLINES) {
    const items = [];
    for (const d of q.drives ?? []) {
      items.push(item(d.id, d.name ?? d.label ?? d.text ?? d.id,
        { description: d.description ?? d.how }));
    }
    for (const c of q.clocks ?? []) {
      items.push(item(c.id, c.name ?? c.label ?? c.text ?? c.id,
        { description: c.description ?? c.how }));
    }
    if (items.length) {
      cats.push(cat(`csq-${q.id}`, `${q.npc}${q.role ? ` — ${q.role}` : ''}`, items,
        q.missable ? { description: 'Missable questline.' } : {}));
    }
  }
  cats.push(cat('cs-endings', 'Endings', sleeper.ALL_ENDINGS.map(e =>
    item(e.id, e.name, { description: e.description, location: e.source }))));
  return schema(cats);
}

// ── Mina the Hollower ───────────────────────────────────────────────────────
function minaSchema() {
  return schema([
    cat('mina-bosses', 'Story Bosses', mina.STORY_BOSSES.map(b =>
      item(b.id, b.name, { location: b.area, description: b.note ?? b.how })),
      { type: 'sequence' }),
    cat('mina-secret', 'Secret Bosses', mina.SECRET_BOSSES.map(b =>
      item(b.id, b.name, { location: b.area, description: b.how }))),
    cat('mina-quests', 'Quests', mina.QUESTS.map(q =>
      item(q.id, q.name, { location: q.area,
        description: q.reward ? `Reward: ${q.reward}` : undefined }))),
    cat('mina-joule', 'Joule Boxes', mina.JOULE_BOXES.map(j =>
      item(j.id, j.label))),
    cat('mina-trinkets', 'Trinkets by Region', mina.TRINKET_REGIONS.map(r =>
      item(r.id, r.name, { maxRank: r.max })),
      { description: `Rank = trinkets found (of ${mina.TOTAL_TRINKETS} total).` }),
  ]);
}

// ── Assemble ────────────────────────────────────────────────────────────────
// igdbIds resolved from the local library export when present (gitignored file;
// falls back to the known ids so the script also runs on a fresh clone).
const KNOWN_IGDB = {
  'sayonara-wild-hearts': [113107], 'cast-n-chill': [330638], hitman: [338082],
  'under-the-island': [151501], 'dead-cells': [26855], 'hollow-knight': [14593],
  messenger: [], 'citizen-sleeper': [], 'mina-the-hollower': [], 'blazing-chrome': [],
};
try {
  const lib = JSON.parse(fs.readFileSync(
    'native/LevelSelect/LevelSelect/Resources/legacy-import.json', 'utf8')).library;
  for (const g of lib) {
    const tt = g.trackerType;
    if (tt && KNOWN_IGDB[tt] !== undefined) {
      const id = parseInt(g.igdbId, 10);
      if (!isNaN(id) && !KNOWN_IGDB[tt].includes(id)) KNOWN_IGDB[tt].push(id);
    }
  }
} catch { /* fresh clone — fall back to known ids */ }

const entries = [
  { key: 'blazing-chrome', name: 'Blazing Chrome', structuredData: checklistToStructuredSchema(BLAZING_CHROME_CONFIG) },
  { key: 'sayonara-wild-hearts', name: 'Sayonara Wild Hearts', structuredData: checklistToStructuredSchema(SAYONARA_CONFIG) },
  { key: 'cast-n-chill', name: 'Cast n Chill', structuredData: checklistToStructuredSchema(CAST_N_CHILL_CONFIG) },
  { key: 'hitman', name: 'Hitman World of Assassination', structuredData: checklistToStructuredSchema(HITMAN_CONFIG) },
  { key: 'under-the-island', name: 'Under the Island', structuredData: checklistToStructuredSchema(UNDER_THE_ISLAND_CONFIG) },
  { key: 'dead-cells', name: 'Dead Cells', structuredData: buildDeadCellsStructuredSchema() },
  { key: 'hollow-knight', name: 'Hollow Knight', structuredData: HOLLOW_KNIGHT_CONFIG.structuredData },
  { key: 'messenger', name: 'The Messenger', structuredData: messengerSchema() },
  { key: 'citizen-sleeper', name: 'Citizen Sleeper', structuredData: sleeperSchema() },
  { key: 'mina-the-hollower', name: 'Mina the Hollower', structuredData: minaSchema() },
].map(e => ({ ...e, igdbIds: KNOWN_IGDB[e.key] ?? [] }));

for (const e of entries) {
  if (!e.structuredData.schemaVersion) e.structuredData.schemaVersion = 1;
  const cats = e.structuredData.categories ?? [];
  const n = cats.reduce((s, c) => s + (c.items?.length ?? 0), 0);
  console.log(`${e.key.padEnd(22)} igdb=${JSON.stringify(e.igdbIds).padEnd(12)} cats=${String(cats.length).padStart(2)} items=${n}`);
}

fs.writeFileSync(
  'native/LevelSelect/LevelSelect/Resources/builtin-trackers.json',
  JSON.stringify(entries));
console.log('\nwrote builtin-trackers.json');
