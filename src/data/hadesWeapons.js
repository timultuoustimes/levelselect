// Weapons, aspects, and Daedalus hammer upgrades

export const WEAPONS = [
  {
    id: 'stygian-blade',
    name: 'Stygian Blade',
    icon: '⚔️',
    aspects: [
      { id: 'blade-zagreus', name: 'Aspect of Zagreus', description: '+5% Attack/Special damage per rank' },
      { id: 'blade-nemesis', name: 'Aspect of Nemesis', description: 'Next 3 Strikes deal +30% Crit' },
      { id: 'blade-poseidon', name: 'Aspect of Poseidon', description: 'Special dislodges Cast from foes' },
      { id: 'blade-arthur', name: 'Aspect of Arthur', description: 'Hallowed Ground aura, +50 max HP' },
    ],
    hammerUpgrades: [
      'Breaching Slash', 'Cruel Thrust', 'Cursed Slash', 'Dash Nova',
      'Double Edge', 'Double Nova', 'Flurry Slash', 'Hoarding Slash',
      'Piercing Wave', 'Shadow Slash', 'Super Nova', 'World Splitter',
      'Greater Consecration',
    ],
  },
  {
    id: 'eternal-spear',
    name: 'Eternal Spear',
    icon: '🔱',
    aspects: [
      { id: 'spear-zagreus', name: 'Aspect of Zagreus', description: '+10% Spin Attack charge speed per rank' },
      { id: 'spear-achilles', name: 'Aspect of Achilles', description: 'After Special, +150% damage for 4 strikes' },
      { id: 'spear-hades', name: 'Aspect of Hades', description: 'Punishing Sweep on Spin Attack' },
      { id: 'spear-guan-yu', name: 'Aspect of Guan Yu', description: 'Serpent Slash heals, -70% max HP' },
    ],
    hammerUpgrades: [
      'Breaching Skewer', 'Chain Skewer', 'Charged Skewer', 'Exploding Launcher',
      'Extending Jab', 'Flaring Spin', 'Flurry Jab', 'Massive Spin',
      'Quick Spin', 'Serrated Point', 'Triple Jab', 'Vicious Skewer',
      'Winged Serpent',
    ],
  },
  {
    id: 'shield-of-chaos',
    name: 'Shield of Chaos',
    icon: '🛡️',
    aspects: [
      { id: 'shield-zagreus', name: 'Aspect of Zagreus', description: '+10% damage per rank' },
      { id: 'shield-chaos', name: 'Aspect of Chaos', description: 'Bull Rush hits grant bonus damage' },
      { id: 'shield-zeus', name: 'Aspect of Zeus', description: '+4 shields per Special rank' },
      { id: 'shield-beowulf', name: 'Aspect of Beowulf', description: 'Dragon Rush loads Cast' },
    ],
    hammerUpgrades: [
      'Breaching Rush', 'Charged Flight', 'Charged Shot', 'Dashing Flight',
      'Dashing Wallop', 'Dread Flight', 'Empowering Flight', 'Explosive Return',
      'Ferocious Guard', 'Minotaur Rush', 'Pulverizing Blow', 'Sudden Rush',
      'Unyielding Defense',
    ],
  },
  {
    id: 'heart-seeking-bow',
    name: 'Heart-Seeking Bow',
    icon: '🏹',
    aspects: [
      { id: 'bow-zagreus', name: 'Aspect of Zagreus', description: '+10% Attack charge speed per rank' },
      { id: 'bow-chiron', name: 'Aspect of Chiron', description: 'Special seeks last Attack target' },
      { id: 'bow-hera', name: 'Aspect of Hera', description: 'Load Cast into Power Shot' },
      { id: 'bow-rama', name: 'Aspect of Rama', description: 'Shared Suffering triple shot' },
    ],
    hammerUpgrades: [
      'Chain Shot', 'Charged Volley', 'Concentrated Volley', 'Explosive Shot',
      'Flurry Shot', 'Perfect Shot', 'Piercing Volley', 'Point-Blank Shot',
      'Relentless Volley', 'Sniper Shot', 'Triple Shot', 'Twin Shot',
      'Repulse Shot',
    ],
  },
  {
    id: 'twin-fists',
    name: 'Twin Fists',
    icon: '🥊',
    aspects: [
      { id: 'fists-zagreus', name: 'Aspect of Zagreus', description: '+15% dodge chance per rank' },
      { id: 'fists-talos', name: 'Aspect of Talos', description: 'Special pulls foes, +40% damage' },
      { id: 'fists-demeter', name: 'Aspect of Demeter', description: 'Dash-Upper hits 12x' },
      { id: 'fists-gilgamesh', name: 'Aspect of Gilgamesh', description: 'Maim debuff, Enkidu Rush' },
    ],
    hammerUpgrades: [
      'Breaching Cross', 'Colossus Knuckle', 'Concentrated Knuckle', 'Draining Cutter',
      'Explosive Upper', 'Flying Cutter', 'Heavy Knuckle', 'Kinetic Launcher',
      'Long Knuckle', 'Quake Cutter', 'Rolling Knuckle', 'Rush Kick',
      'Rending Claws',
    ],
  },
  {
    id: 'adamant-rail',
    name: 'Adamant Rail',
    icon: '🔫',
    aspects: [
      { id: 'rail-zagreus', name: 'Aspect of Zagreus', description: '+12% Ammo capacity per rank' },
      { id: 'rail-eris', name: 'Aspect of Eris', description: 'Absorb Special blast for +75% damage' },
      { id: 'rail-hestia', name: 'Aspect of Hestia', description: 'Manual reload empowers next shot' },
      { id: 'rail-lucifer', name: 'Aspect of Lucifer', description: 'Hellfire laser beam mode' },
    ],
    hammerUpgrades: [
      'Cluster Bomb', 'Delta Chamber', 'Explosive Fire', 'Flurry Fire',
      'Hazard Bomb', 'Piercing Fire', 'Ricochet Fire', 'Rocket Bomb',
      'Seeking Fire', 'Spread Fire', 'Targeting System', 'Triple Bomb',
      'Concentrated Beam', 'Eternal Chamber', 'Flash Fire',
      'Greater Inferno', 'Triple Beam',
    ],
  },
];

// Flat list of all aspects for easy lookup
export const ALL_ASPECTS = WEAPONS.flatMap(w =>
  w.aspects.map(a => ({ ...a, weapon: w.name, weaponId: w.id, weaponIcon: w.icon }))
);
