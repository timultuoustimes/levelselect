import { WEAPONS, ALL_ASPECTS } from '../data/hadesWeapons.js';
import { KEEPSAKES, COMPANIONS } from '../data/hadesKeepsakes.js';
import { ALL_MIRROR_UPGRADES } from '../data/hadesMirror.js';
import { generateId } from './format.js';

// Create a new Hades save file with all tracking initialized
export function createHadesSave(name) {
  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    lastPlayedAt: new Date().toISOString(),

    // Weapon aspects: unlocked status + rank (0-5)
    weaponAspects: ALL_ASPECTS.map(a => ({
      id: a.id,
      weapon: a.weapon,
      weaponId: a.weaponId,
      name: a.name,
      description: a.description,
      unlocked: a.name.includes('Zagreus'), // Zagreus aspects start unlocked
      rank: a.name.includes('Zagreus') ? 1 : 0,
      maxRank: 5,
    })),

    // Keepsakes: unlocked + rank (0 = not owned, 1-3 hearts)
    keepsakes: KEEPSAKES.map(k => ({
      ...k,
      unlocked: false,
      rank: 0, // 0 = not owned, 1-3 = hearts
      maxRank: 3,
    })),

    // Companions: unlocked status
    companions: COMPANIONS.map(c => ({
      ...c,
      unlocked: false,
    })),

    // Mirror of Night: keyed by upgrade id, each has rank + useAlt flag
    mirrorUpgrades: {},

    // Run history
    runs: [],

    // Active run (null when no run is active)
    activeRun: null,
  };
}

// Migrate an existing save to add any missing fields
export function migrateSave(save) {
  const migrated = { ...save };

  // Add mirrorUpgrades if missing (existing saves)
  if (!migrated.mirrorUpgrades) {
    migrated.mirrorUpgrades = {};
  }

  // Add session tracking fields if missing
  if (!migrated.sessions) migrated.sessions = [];
  if (migrated.notes === undefined) migrated.notes = '';

  return migrated;
}

// Create a new run object
export function createRun(weapon, aspect, keepsake, heatLevel) {
  return {
    id: generateId(),
    startTime: new Date().toISOString(),
    endTime: null,
    weapon: weapon || '',
    aspect: aspect || '',
    keepsake: keepsake || '',
    heatLevel: heatLevel || 0,
    boons: [],          // [{ god, name, slot }]
    hammerUpgrades: [],  // [string]
    notes: '',
    outcome: null,       // 'victory' | 'defeated'
    duration: 0,         // seconds
    pausedAt: null,      // timestamp when paused
    accumulatedTime: 0,  // seconds accumulated before current timer segment
  };
}

// Create a new game entry for the library
export function createGameEntry({ name, igdbId, platforms, status, complexity, summary }) {
  return {
    id: generateId(),
    name,
    igdbId: igdbId || null,
    platforms: platforms || [],
    status: status || 'backlog',
    complexity: complexity || 'simple', // 'simple' | 'standard' | 'detailed'
    summary: summary || '',
    coverColor: null,
    coverImageId: null,     // IGDB image_id for cover art
    coverUrl: null,         // fallback manual URL
    franchise: null,        // franchise/series name
    firstReleaseDate: null, // release year from IGDB
    yearPlayed: null,       // legacy: single year (kept for backward compat)
    playPeriods: [],        // [{ id, startMonth, startYear, endMonth, endYear, ongoing, note }]
    igdbSlug: null,         // IGDB URL slug for linking to game page
    genres: [],             // e.g. ['Role-playing (RPG)', 'Hack and slash']
    themes: [],             // e.g. ['Action', 'Fantasy'] — includes roguelike etc.
    gameModes: [],          // e.g. ['Single player', 'Co-operative']
    playerPerspectives: [], // e.g. ['Third person', 'Bird view / Isometric']
    developers: [],         // company names
    publishers: [],         // company names
    saves: [],
    currentSaveId: null,
    addedAt: new Date().toISOString(),
    trackerType: null,
    userTags: [],
    notes: '',   // game-level freeform notes ("where I left off", current goals, etc.)
  };
}

// Migrate old yearPlayed integer → playPeriods array (called lazily in GamePage)
export function migratePlayPeriods(game) {
  if (Array.isArray(game.playPeriods) && game.playPeriods.length > 0) {
    return game.playPeriods;
  }
  if (game.yearPlayed) {
    return [{
      id: generateId(),
      startMonth: null,
      startYear: game.yearPlayed,
      endMonth: null,
      endYear: null,
      ongoing: false,
      platform: game.platforms?.[0] || null, // default to first platform
      note: '',
    }];
  }
  return [];
}
