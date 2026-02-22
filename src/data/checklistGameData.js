// Checklist game configs
// Each game has chapters/levels plus optional sub-items

export const BLAZING_CHROME_CONFIG = {
  name: 'Blazing Chrome',
  icon: '🔥',
  color: 'from-orange-900 via-gray-900 to-black',
  accent: 'orange',
  description: 'Run and gun co-op shooter',
  chapters: [
    { id: 'bc-1', name: 'Stage 1 — City Ruins', items: [] },
    { id: 'bc-2', name: 'Stage 2 — Highway', items: [] },
    { id: 'bc-3', name: 'Stage 3 — Aerial Battleship', items: [] },
    { id: 'bc-4', name: 'Stage 4 — Factory', items: [] },
    { id: 'bc-5', name: 'Stage 5 — Fortress', items: [] },
    { id: 'bc-6', name: 'Stage 6 — Final Stage', items: [] },
  ],
};

export const SAYONARA_CONFIG = {
  name: 'Sayonara Wild Hearts',
  icon: '🃏',
  color: 'from-purple-900 via-violet-900 to-black',
  accent: 'violet',
  description: 'Pop album video game',
  chapters: [
    { id: 'swh-1',  name: '1. Wild Hearts Never Die', items: [] },
    { id: 'swh-2',  name: '2. Magic Girl',            items: [] },
    { id: 'swh-3',  name: '3. Begin Again',           items: [] },
    { id: 'swh-4',  name: '4. Reverie',               items: [] },
    { id: 'swh-5',  name: '5. Heartbreak',            items: [] },
    { id: 'swh-6',  name: '6. Stereo Lovers',         items: [] },
    { id: 'swh-7',  name: '7. Parallel Universes',    items: [] },
    { id: 'swh-8',  name: '8. Sayonara Wild Heart',   items: [] },
    { id: 'swh-9',  name: '9. Clair de Lune',         items: [] },
    { id: 'swh-10', name: '10. Howling at the Moon',  items: [] },
    { id: 'swh-11', name: '11. Soft Dive',            items: [] },
    { id: 'swh-12', name: '12. Neon Jungle',          items: [] },
    { id: 'swh-13', name: '13. Holy Ward',            items: [] },
    { id: 'swh-14', name: '14. Crystalline',          items: [] },
    { id: 'swh-15', name: '15. Arcade Lover',         items: [] },
    { id: 'swh-16', name: '16. Fire',                 items: [] },
    { id: 'swh-17', name: '17. Last Kiss',            items: [] },
    { id: 'swh-18', name: '18. Wildfire',             items: [] },
    { id: 'swh-19', name: '19. Heart & Sword',        items: [] },
    { id: 'swh-20', name: '20. Wild Hearts Never Die (Reprise)', items: [] },
    { id: 'swh-21', name: '21. Sayonara Wild Hearts', items: [] },
  ],
};

export const CAST_N_CHILL_CONFIG = {
  name: 'Cast n Chill',
  icon: '🎣',
  color: 'from-cyan-900 via-teal-900 to-black',
  accent: 'cyan',
  description: 'Relaxing fishing game',
  chapters: [
    { id: 'cnc-1', name: 'Tutorial Pond', items: [] },
    { id: 'cnc-2', name: 'Sunny Lake', items: [] },
    { id: 'cnc-3', name: 'River Bend', items: [] },
    { id: 'cnc-4', name: 'Ocean Pier', items: [] },
    { id: 'cnc-5', name: 'Hidden Cove', items: [] },
    { id: 'cnc-6', name: 'Deep Sea', items: [] },
  ],
  note: 'Chapters may not be accurate — edit as needed once you play!',
};
