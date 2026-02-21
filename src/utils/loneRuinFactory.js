import { generateId } from './format.js';

export function createLoneRuinSave(name) {
  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    lastPlayedAt: new Date().toISOString(),
    runs: [],
    activeRun: null,
  };
}

export function createLoneRuinRun({ startingSpell, mode, difficulty }) {
  return {
    id: generateId(),
    startTime: new Date().toISOString(),
    endTime: null,
    startingSpell: startingSpell || '',
    mode: mode || 'Campaign',          // 'Campaign' | 'Survival'
    difficulty: difficulty || 'Normal', // 'Easy' | 'Normal' | 'Hard'
    spellsAcquired: [],                 // [string] spell names picked up mid-run
    outcome: null,                      // 'victory' | 'defeated'
    floorReached: null,                 // 1–21 for Campaign, null for Survival
    wavesReached: null,                 // for Survival mode
    notes: '',
    duration: 0,
    pausedAt: null,
    accumulatedTime: 0,
  };
}
