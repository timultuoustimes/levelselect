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
  hasRanks: true,
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
    { id: 'cnc-1',  name: 'Goldenfork River — The Fork',          items: [] },
    { id: 'cnc-2',  name: 'Goldenfork River — Beaver Dam',         items: [] },
    { id: 'cnc-3',  name: 'Goldenfork River — The Mistwood',       items: [] },
    { id: 'cnc-4',  name: 'Fawnmirror Lake — Underwater Meadow',   items: [] },
    { id: 'cnc-5',  name: 'Fawnmirror Lake — Picnic Point',        items: [] },
    { id: 'cnc-6',  name: "Fawnmirror Lake — Fisherman's Rest",    items: [] },
    { id: 'cnc-7',  name: 'Grizzlyridge River — The Rapids',       items: [] },
    { id: 'cnc-8',  name: 'Grizzlyridge River — Eagles Nest',      items: [] },
    { id: 'cnc-9',  name: 'Icewater Sea — Watchers Point',         items: [] },
    { id: 'cnc-10', name: 'Icewater Sea — Craggy Reef',            items: [] },
    { id: 'cnc-11', name: 'Icewater Sea — Safety Cove',            items: [] },
    { id: 'cnc-12', name: 'Old Wreck Bay — Divers Drop',           items: [] },
    { id: 'cnc-13', name: 'Old Wreck Bay — Seals Rest',            items: [] },
    { id: 'cnc-14', name: 'Autumnwood — Shallows Edge',            items: [] },
    { id: 'cnc-15', name: 'Autumnwood — Otter Cove',               items: [] },
    { id: 'cnc-16', name: 'Lake Hunkerdown — Frostbite Flats',     items: [] },
  ],
};

export const HITMAN_CONFIG = {
  name: 'Hitman: World of Assassination',
  icon: '🎯',
  color: 'from-red-950 via-gray-900 to-black',
  accent: 'red',
  description: 'Stealth assassination sandbox',
  chapters: [

    // ── HITMAN 1 — Main Campaign ───────────────────────────────────────────────
    { id: 'h1-1',  name: 'H1 — ICA Facility: The Final Test (Prologue)',       items: [] },
    { id: 'h1-2',  name: 'H1 — Paris: The Showstopper',                        items: [] },
    { id: 'h1-3',  name: 'H1 — Sapienza: World of Tomorrow',                   items: [] },
    { id: 'h1-4',  name: 'H1 — Marrakesh: A Gilded Cage',                      items: [] },
    { id: 'h1-5',  name: 'H1 — Bangkok: Club 27',                              items: [] },
    { id: 'h1-6',  name: 'H1 — Colorado: Freedom Fighters',                    items: [] },
    { id: 'h1-7',  name: 'H1 — Hokkaido: Situs Inversus',                      items: [] },

    // ── HITMAN 1 — Bonus Missions ──────────────────────────────────────────────
    { id: 'h1-b1', name: 'H1 Bonus — Sapienza: The Icon',                      items: [] },
    { id: 'h1-b2', name: 'H1 Bonus — Sapienza: Landslide',                     items: [] },
    { id: 'h1-b3', name: 'H1 Bonus — Marrakesh: A House Built on Sand',        items: [] },
    { id: 'h1-b4', name: 'H1 Bonus — Paris: Holiday Hoarders',                 items: [] },

    // ── HITMAN 2 — Main Campaign ───────────────────────────────────────────────
    { id: 'h2-1',  name: "H2 — Hawke's Bay: Nightcall",                        items: [] },
    { id: 'h2-2',  name: 'H2 — Miami: The Finish Line',                        items: [] },
    { id: 'h2-3',  name: 'H2 — Santa Fortuna: Three-Headed Serpent',           items: [] },
    { id: 'h2-4',  name: 'H2 — Mumbai: Chasing a Ghost',                       items: [] },
    { id: 'h2-5',  name: 'H2 — Whittleton Creek: Another Life',                items: [] },
    { id: 'h2-6',  name: "H2 — Isle of Sgàil: The Ark Society",                items: [] },

    // ── HITMAN 2 — Expansion Locations (included in Signature Edition) ─────────
    { id: 'h2-7',  name: 'H2 Expansion — New York: Golden Handshake',          items: [] },
    { id: 'h2-8',  name: 'H2 Expansion — Haven Island: The Last Resort',       items: [] },

    // ── HITMAN 2 — Special Assignments (included in Signature Edition) ─────────
    { id: 'h2-sa1', name: 'H2 Special — Santa Fortuna: Embrace of the Serpent', items: [] },
    { id: 'h2-sa2', name: 'H2 Special — Mumbai: Illusions of Grandeur',         items: [] },
    { id: 'h2-sa3', name: 'H2 Special — Miami: A Silver Tongue',                items: [] },
    { id: 'h2-sa4', name: 'H2 Special — Whittleton Creek: A Bitter Pill',       items: [] },

    // ── HITMAN 3 — Main Campaign ───────────────────────────────────────────────
    { id: 'h3-1',  name: 'H3 — Dubai: On Top of the World',                    items: [] },
    { id: 'h3-2',  name: 'H3 — Dartmoor: Death in the Family',                 items: [] },
    { id: 'h3-3',  name: 'H3 — Berlin: Apex Predator',                         items: [] },
    { id: 'h3-4',  name: 'H3 — Chongqing: End of an Era',                      items: [] },
    { id: 'h3-5',  name: 'H3 — Mendoza: The Farewell',                         items: [] },
    { id: 'h3-6',  name: 'H3 — Carpathian Mountains: Untouchable',             items: [] },
    { id: 'h3-7',  name: 'H3 — Ambrose Island: Shadows in the Water',          items: [] },

    // ── Achievements ──────────────────────────────────────────────────────────

    // Prologue
    { id: 'ha-1',  name: '🏆 The Result of Previous Training — Complete Freeform Training',       items: [] },
    { id: 'ha-2',  name: '🏆 Cleared for Field Duty — Complete The Final Test',                   items: [] },
    { id: 'ha-3',  name: '🏆 Silent Assassin — Complete The Final Test with Silent Assassin rating', items: [] },
    { id: 'ha-4',  name: '🏆 Seizing the Opportunity — Complete a Mission Story in The Final Test', items: [] },
    { id: 'ha-5',  name: '🏆 Training Escalated — Complete Level 5 of an Escalation in ICA Facility', items: [] },

    // Hitman 1 — Story Completions
    { id: 'ha-6',  name: '🏆 When No One Else Dares — Complete The Showstopper',                  items: [] },
    { id: 'ha-7',  name: '🏆 Die By the Sword — Complete World of Tomorrow',                      items: [] },
    { id: 'ha-8',  name: '🏆 Too Big to Fail — Complete A Gilded Cage',                           items: [] },
    { id: 'ha-9',  name: '🏆 Shining Bright — Complete Club 27',                                  items: [] },
    { id: 'ha-10', name: '🏆 Guerrilla Warfare — Complete Freedom Fighters',                      items: [] },
    { id: 'ha-11', name: '🏆 A Long Time Coming — Complete Situs Inversus',                       items: [] },

    // Hitman 1 — Mastery Level 20
    { id: 'ha-12', name: '🏆 City of Light — Reach Paris Mastery Level 20',                       items: [] },
    { id: 'ha-13', name: '🏆 Amalfi Pearl — Reach Sapienza Mastery Level 20',                     items: [] },
    { id: 'ha-14', name: '🏆 Ancient Marrakesh — Reach Marrakesh Mastery Level 20',               items: [] },
    { id: 'ha-15', name: '🏆 One Night in Bangkok — Reach Bangkok Mastery Level 20',              items: [] },
    { id: 'ha-16', name: '🏆 Mission Complete — Reach Colorado Mastery Level 20',                 items: [] },
    { id: 'ha-17', name: '🏆 Sayōnara — Reach Hokkaido Mastery Level 20',                         items: [] },

    // Hitman 1 — Bonus Mission Challenges
    { id: 'ha-18', name: '🏆 Perfectionist — Complete Suit Only & Silent Assassin on The Icon, Landslide, or A House Built on Sand', items: [] },

    // Hitman 2 — Sniper Assassin
    { id: 'ha-19', name: '🏆 Silent Sniper — Complete The Last Yardbird as Silent Assassin',      items: [] },
    { id: 'ha-20', name: '🏆 Hawkeye — Complete The Pen and the Sword as Silent Assassin',        items: [] },
    { id: 'ha-21', name: '🏆 Pure Poetry — Complete all The Pen and the Sword challenges',        items: [] },
    { id: 'ha-22', name: '🏆 Seven Figures — Score above 1,000,000 on The Pen and the Sword',     items: [] },
    { id: 'ha-23', name: '🏆 Never Knew What Hit Them — Complete Crime and Punishment as Silent Assassin', items: [] },
    { id: 'ha-24', name: '🏆 Capital Punishment — Complete all Crime and Punishment challenges',  items: [] },
    { id: 'ha-25', name: '🏆 In a League of Their Own — Score above 1,000,000 on Crime and Punishment', items: [] },

    // Hitman 3 — Story & Location Mastery
    { id: 'ha-26', name: '🏆 Death From Above — Complete On Top of the World (Dubai)',            items: [] },
    { id: 'ha-27', name: '🏆 Reach Dubai Mastery Level 20',                                       items: [] },
    { id: 'ha-28', name: '🏆 Complete Death in the Family (Dartmoor)',                            items: [] },
    { id: 'ha-29', name: '🏆 Reach Dartmoor Mastery Level 20',                                    items: [] },
    { id: 'ha-30', name: '🏆 Complete Apex Predator (Berlin)',                                    items: [] },
    { id: 'ha-31', name: '🏆 Reach Berlin Mastery Level 20',                                      items: [] },
    { id: 'ha-32', name: '🏆 Complete End of an Era (Chongqing)',                                 items: [] },
    { id: 'ha-33', name: '🏆 Reach Chongqing Mastery Level 20',                                   items: [] },
    { id: 'ha-34', name: '🏆 Complete The Farewell (Mendoza)',                                    items: [] },
    { id: 'ha-35', name: '🏆 Reach Mendoza Mastery Level 20',                                     items: [] },
    { id: 'ha-36', name: '🏆 Complete Untouchable (Carpathian Mountains)',                        items: [] },

    // Hitman 3 — Shortcut / Challenge achievements
    { id: 'ha-37', name: '🏆 Shortcut Killer — Find and unlock 15 shortcuts',                    items: [] },
    { id: 'ha-38', name: '🏆 Well-Rounded — Complete a Playstyle from each category',            items: [] },

    // Contracts Mode
    { id: 'ha-39', name: '🏆 The Creative Assassin — Complete the Contract Creation Tutorial',   items: [] },
    { id: 'ha-40', name: '🏆 A New Profile — Complete a Featured Contract',                      items: [] },
    { id: 'ha-41', name: '🏆 Top of the Class — Beat the highest leaderboard score on a Contract', items: [] },

  ],
};

export const UNDER_THE_ISLAND_CONFIG = {
  name: 'Under the Island',
  icon: '🏝️',
  color: 'from-teal-900 via-emerald-900 to-black',
  accent: 'teal',
  description: '2D action-adventure on Seashell Island',
  chapters: [
    { id: 'uti-1',  name: "Let's go! — Let's go on an adventure, trusty weapon in hand!",       items: [] },
    { id: 'uti-2',  name: 'Noodle Slurper — Ramen is life! Buy a bowl of ramen.',               items: [] },
    { id: 'uti-3',  name: 'Blast Off — It\'s time to go boom! Get the bombs from Betty.',       items: [] },
    { id: 'uti-4',  name: 'Hobby Cartographer — Uncover 25% of the map',                        items: [] },
    { id: 'uti-5',  name: "It's Tough Being A Star! — Collect the Ancient Gear Wheel (Secret)",   items: [] },
    { id: 'uti-6',  name: 'Cat Lover — Reunite all the kittens with the cat mom.',              items: [] },
    { id: 'uti-7',  name: 'Advanced Cartographer — Uncover 50% of the map',                     items: [] },
    { id: 'uti-8',  name: 'Epic Gamer — Play the Arcade Monkey minigame!',                      items: [] },
    { id: 'uti-9',  name: 'Looks Eaten... — Collect the Swallowed Gear Wheel (Secret)',           items: [] },
    { id: 'uti-10', name: 'Out Of The Little League — Upgrade the Hockey-Stick',                items: [] },
    { id: 'uti-11', name: 'Fluffy New Citizen — Build the Museum for a certain new friend!',    items: [] },
    { id: 'uti-12', name: "#1 Mum — No no! it's KEY-Rex (Secret)",                               items: [] },
    { id: 'uti-13', name: 'Post Woman — First class post! Deliver all letters.',                 items: [] },
    { id: 'uti-14', name: 'Dog Lover — Give a dog a treat and make friends.',                   items: [] },
    { id: 'uti-15', name: 'Eww, Slimy! — Collect the Trophy Gear Wheel (Secret)',                items: [] },
    { id: 'uti-16', name: "Quiz Champ — Unravel the mysteries of Torogami's questions!",        items: [] },
    { id: 'uti-17', name: 'Cat Karma Chameleon — A wise sage once said, "be nice to animals"', items: [] },
    { id: 'uti-18', name: 'Cereals with Additives — Collect the Icy Gear Wheel (Secret)',        items: [] },
    { id: 'uti-19', name: 'Fear Nekogami — Be mean to cats!',                                   items: [] },
    { id: 'uti-20', name: 'Public Transportation — Unlock all fast travel points!',             items: [] },
    { id: 'uti-21', name: 'Haunted Nonogram — Complete the haunted chicken coop minidungeon!',   items: [] },
    { id: 'uti-22', name: 'Masterful Adventurer — Save Seashell Island!',                       items: [] },
    { id: 'uti-23', name: "Made it into the Club — Find a way into the Moray Gang's hideout.", items: [] },
    { id: 'uti-24', name: 'Master Cartographer — Uncover 100% of the map',                      items: [] },
    { id: 'uti-25', name: 'Foolish Foes Flattened — Give the Moray duo a triple lesson in defeat!', items: [] },
    { id: 'uti-26', name: "Gone Fishin' — Catch all fish species.",                             items: [] },
    { id: 'uti-27', name: 'Belive in the Bamboo — Find all parts of the Bamboo-Goddess (Secret)', items: [] },
    { id: 'uti-28', name: 'Healthy Explorer — Reach the maximum number of life containers',     items: [] },
    { id: 'uti-29', name: 'Golf ala Monkey — Complete Coconut-Golf with just two hits!',        items: [] },
    { id: 'uti-30', name: 'Storyteller — Bear witness to the ancient legend!',                  items: [] },
    { id: 'uti-31', name: 'Monster Zoologist — Unlock all the pages of the Monster Encyclopaedia', items: [] },
    { id: 'uti-32', name: 'Snow Long — Finish the Snowboard Minigame in under 2 Minutes',       items: [] },
    { id: 'uti-33', name: 'Groovy! — Find all of the hidden music tapes',                       items: [] },
  ],
};
