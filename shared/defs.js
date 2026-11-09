// Shared game definitions (used by both the server simulation and the browser client).

export const WEAPONS = {
  pistol: {
    id: 'pistol', name: 'Kestrel 9mm', cls: 'Sidearm', dmg: 30, rpm: 420, auto: false, mag: 15, reserve: Infinity,
    reload: 1.3, spread: 0.010, adsSpread: 0.002, bloom: 0.012, recoil: 1.1, pellets: 1, headMult: 2.2,
    falloff: [18, 45, 0.6], zoom: 1.2, moveMul: 1.0, snd: 'pistol',
  },
  smg: {
    id: 'smg', name: 'Wasp SMG', cls: 'Submachine gun', dmg: 24, rpm: 880, auto: true, mag: 32, reserve: 224,
    reload: 1.9, spread: 0.022, adsSpread: 0.006, bloom: 0.006, recoil: 0.55, pellets: 1, headMult: 1.8,
    falloff: [14, 35, 0.5], zoom: 1.25, moveMul: 1.0, snd: 'smg',
  },
  shotgun: {
    id: 'shotgun', name: 'Breacher 12G', cls: 'Shotgun', dmg: 22, rpm: 78, auto: false, mag: 7, reserve: 49,
    reload: 2.6, spread: 0.075, adsSpread: 0.055, bloom: 0.0, recoil: 3.2, pellets: 9, headMult: 1.4,
    falloff: [7, 22, 0.2], zoom: 1.15, moveMul: 0.96, snd: 'shotgun',
  },
  ar: {
    id: 'ar', name: 'Ranger AR', cls: 'Assault rifle', dmg: 36, rpm: 680, auto: true, mag: 30, reserve: 210,
    reload: 2.2, spread: 0.016, adsSpread: 0.0025, bloom: 0.005, recoil: 0.8, pellets: 1, headMult: 2.0,
    falloff: [30, 70, 0.7], zoom: 1.45, moveMul: 0.95, snd: 'ar',
  },
  dmr: {
    id: 'dmr', name: 'Longbow DMR', cls: 'Marksman rifle', dmg: 110, rpm: 190, auto: false, mag: 10, reserve: 70,
    reload: 2.6, spread: 0.03, adsSpread: 0.0004, bloom: 0.02, recoil: 2.4, pellets: 1, headMult: 2.5,
    falloff: [60, 120, 0.85], zoom: 3.2, moveMul: 0.92, snd: 'dmr',
  },
  lmg: {
    id: 'lmg', name: 'Bulwark LMG', cls: 'Light machine gun', dmg: 40, rpm: 760, auto: true, mag: 100, reserve: 300,
    reload: 4.6, spread: 0.024, adsSpread: 0.006, bloom: 0.004, recoil: 0.75, pellets: 1, headMult: 1.8,
    falloff: [35, 80, 0.75], zoom: 1.4, moveMul: 0.85, snd: 'lmg',
  },
  launcher: {
    id: 'launcher', name: 'Ravager RL', cls: 'Rocket launcher', dmg: 0, rpm: 40, auto: false, mag: 1, reserve: 7,
    reload: 3.0, spread: 0.01, adsSpread: 0.001, bloom: 0, recoil: 4.0, pellets: 0, headMult: 1, rocket: true,
    falloff: [999, 999, 1], zoom: 1.3, moveMul: 0.85, snd: 'launcher',
  },
};

export const ENEMIES = {
  grunt:      { name: 'Militia',      hp: 70,   speed: 3.3, dmg: 5,  rpm: 300, burst: [2, 4], pause: [0.8, 1.8], range: 24, acc: 0.30, reward: 50,  scale: 1.0,  headMult: 1 },
  rifleman:   { name: 'Rifleman',     hp: 105,  speed: 3.1, dmg: 8,  rpm: 520, burst: [3, 5], pause: [0.7, 1.5], range: 38, acc: 0.36, reward: 75,  scale: 1.0,  headMult: 1 },
  shotgunner: { name: 'Breacher',     hp: 140,  speed: 4.0, dmg: 20, rpm: 60,  burst: [1, 1], pause: [0.9, 1.3], range: 10, acc: 0.65, reward: 80,  scale: 1.04, headMult: 1 },
  rusher:     { name: 'Rusher',       hp: 60,   speed: 6.2, dmg: 24, melee: true, range: 1.7, acc: 1, reward: 60, scale: 0.97, headMult: 1 },
  heavy:      { name: 'Heavy Gunner', hp: 1600, speed: 1.9, dmg: 7,  rpm: 700, burst: [10, 18], pause: [1.0, 1.8], range: 32, acc: 0.30, reward: 500, scale: 1.28, headMult: 0.6 },
};

// Shop: three physical stations in the armory, each with its own catalogue.
// `after` = number of completed waves required before the item unlocks.
export const SHOP = [
  { id: 'w_smg',      cat: 'weapons',   name: 'Wasp SMG',        desc: 'Fast-firing, great up close',            price: 1000, after: 0, weapon: 'smg' },
  { id: 'w_shotgun',  cat: 'weapons',   name: 'Breacher 12G',    desc: 'Pump shotgun, devastating at short range', price: 1200, after: 0, weapon: 'shotgun' },
  { id: 'w_ar',       cat: 'weapons',   name: 'Ranger AR',       desc: 'Accurate all-round assault rifle',       price: 2200, after: 2, weapon: 'ar' },
  { id: 'w_dmr',      cat: 'weapons',   name: 'Longbow DMR',     desc: 'Scoped semi-auto, huge headshot damage', price: 3000, after: 6, weapon: 'dmr' },
  { id: 'w_lmg',      cat: 'weapons',   name: 'Bulwark LMG',     desc: '100-round belt of sustained fire',       price: 4500, after: 8, weapon: 'lmg' },
  { id: 'w_launcher', cat: 'weapons',   name: 'Ravager RL',      desc: 'High-explosive rockets',                 price: 5500, after: 10, weapon: 'launcher' },

  { id: 'e_ammo',     cat: 'equipment', name: 'Ammo Refill',     desc: 'Tops up reserve ammo for all weapons',   price: 350,  after: 0 },
  { id: 'e_frag',     cat: 'equipment', name: 'Frag Grenades x2', desc: 'Thrown with G, max 4',                  price: 400,  after: 0 },
  { id: 'e_armor',    cat: 'equipment', name: 'Body Armor',      desc: '100 armor that absorbs damage',          price: 800,  after: 2 },
  { id: 'e_mine',     cat: 'equipment', name: 'Proximity Mines x2', desc: 'Placed with 4, max 4',                price: 700,  after: 4 },
  { id: 'e_revive',   cat: 'equipment', name: 'Self-Revive Kit', desc: 'Get back up once when downed',           price: 1500, after: 4 },
  { id: 'e_harmor',   cat: 'equipment', name: 'Heavy Armor',     desc: '250 armor plate carrier',                price: 2000, after: 6 },
  { id: 'e_turret',   cat: 'equipment', name: 'Sentry Gun',      desc: 'Auto-turret, placed with 5, lasts 90s',  price: 2500, after: 6 },

  { id: 'a_strike',   cat: 'air',       name: 'Precision Airstrike', desc: 'Line of bombs on your marker (6)',   price: 2000, after: 4 },
  { id: 'a_drone',    cat: 'air',       name: 'Gunship Drone',   desc: 'Orbiting gunship for 45s (7)',           price: 4000, after: 8 },
  { id: 'a_carpet',   cat: 'air',       name: 'Carpet Bombing',  desc: 'Three bombing runs across the yard (6)', price: 6000, after: 12 },
];

export const CAT_NAMES = { weapons: 'WEAPON ARMORY', equipment: 'EQUIPMENT ARMORY', air: 'AIR SUPPORT ARMORY' };

export const COMBO_NAMES = [null, null, 'DOUBLE KILL', 'TRIPLE KILL', 'MULTI KILL', 'RAMPAGE', 'UNSTOPPABLE', 'MASSACRE'];

export const START_MONEY = 500;
export const MAX_FRAGS = 4;
export const MAX_MINES = 4;

export function waveBonus(wave) { return 250 + 50 * wave; }

export function damageAt(w, dist) {
  const [a, b, m] = w.falloff;
  if (dist <= a) return w.dmg;
  if (dist >= b) return w.dmg * m;
  return w.dmg * (1 - (1 - m) * (dist - a) / (b - a));
}
