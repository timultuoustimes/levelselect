const generateId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

export function createChecklistSave(name, config) {
  return {
    id: generateId(),
    name,
    createdAt: new Date().toISOString(),
    lastPlayedAt: new Date().toISOString(),
    // Chapter completion: { chapterId: boolean }
    chapterCompleted: {},
    // Sub-item completion: { itemId: boolean }
    itemCompleted: {},
    // Session history: [{ id, startTime, endTime, duration, notes }]
    sessions: [],
    activeSession: null,
    // Total elapsed across all sessions
    totalPlaytime: 0,
    notes: '',
    // User-edited chapter list (null = use config.chapters; array = override)
    customChapters: null,
  };
}
