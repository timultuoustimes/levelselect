import { generateId } from './format.js';

// Create a general tracker save file (used for any game without a dedicated tracker)
export function createGeneralSave(name) {
  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    lastPlayedAt: new Date().toISOString(),

    // Overall progress (0-100)
    progressPercent: 0,

    // Milestones the user defines themselves
    milestones: [],

    // Play sessions
    sessions: [],

    // Active session (null when not playing)
    activeSession: null,

    // Total playtime in seconds (sum of all sessions)
    totalPlaytime: 0,

    // User review
    rating: null,    // 1-5 or null
    review: '',

    // Notes (general freeform)
    notes: '',
  };
}

// Create a milestone
export function createMilestone(title) {
  return {
    id: generateId(),
    title,
    completed: false,
    completedAt: null,
  };
}

// Create a session
export function createSession() {
  return {
    id: generateId(),
    startTime: new Date().toISOString(),
    endTime: null,
    duration: 0,          // seconds
    pausedAt: null,
    accumulatedTime: 0,
    notes: '',
  };
}
