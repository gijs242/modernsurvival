// Procedural soldier, weapon and equipment models.
import * as THREE from 'three';
import { boxGeo } from './world.js';

let T = null;
const M = {};
export function initModels(textures) {
  T = textures;
  M.gunmetal = new THREE.MeshStandardMaterial({ color: 0x2b2d30, roughness: 0.42, metalness: 0.85, roughnessMap: T.gunRough });
  M.polymer = new THREE.MeshStandardMaterial({ color: 0x1c1d1f, roughness: 0.72, metalness: 0.1 });
  M.tan = new THREE.MeshStandardMaterial({ color: 0x8c7a5a, roughness: 0.7, metalness: 0.05 });
  M.olive = new THREE.MeshStandardMaterial({ color: 0x4b5038, roughness: 0.7, metalness: 0.05 });
  M.wood = new THREE.MeshStandardMaterial({ color: 0x5a3a22, roughness: 0.6 });
  M.glass = new THREE.MeshStandardMaterial({ color: 0x0a1a24, roughness: 0.05, metalness: 1, emissive: 0x112233, emissiveIntensity: 0.4 });
  M.red = new THREE.MeshStandardMaterial({ color: 0x220000, emissive: 0xff2010, emissiveIntensity: 3 });
  M.brass = new THREE.MeshStandardMaterial({ color: 0xc8a050, roughness: 0.3, metalness: 1 });
  M.skin = new THREE.MeshStandardMaterial({ color: 0xa8806a, roughness: 0.65 });
  M.glove = new THREE.MeshStandardMaterial({ color: 0x2a2a26, roughness: 0.8, normalMap: T.fabricN });
  M.boot = new THREE.MeshStandardMaterial({ color: 0x241f1a, roughness: 0.75 });
  M.flash = new THREE.SpriteMaterial({ map: T.flash, color: 0xffd8a0, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, toneMapped: false });
  return M;
}

const box = (mat, w, h, d, x = 0, y = 0, z = 0) => { const m = new THREE.Mesh(boxGeo(w, h, d, 0), mat); m.position.set(x, y, z); return m; };
const cyl = (mat, r, len, x = 0, y = 0, z = 0, seg = 12) => { const m = new THREE.Mesh(new THREE.CylinderGeometry(r, r, len, seg).rotateX(Math.PI / 2), mat); m.position.set(x, y, z); return m; };

// =========================================================================
// Weapons. Built along -Z (barrel forward), origin at the grip. Returns group
// with userData.muzzle (Object3D), userData.mag (mesh), userData.eject (Object3D).
// =========================================================================
export function buildWeapon(id) {
  const g = new THREE.Group();
  const muzzle = new THREE.Object3D(), eject = new THREE.Object3D();
  let mag;
  const gm = M.gunmetal, pm = M.polymer;
  switch (id) {
    case 'pistol':
      g.add(box(gm, 0.034, 0.036, 0.2, 0, 0.055, -0.06));        // slide
      g.add(box(pm, 0.032, 0.03, 0.17, 0, 0.026, -0.05));        // frame
      g.add(box(pm, 0.03, 0.11, 0.045, 0, -0.03, 0.02)).rotation.x = 0.25;
      mag = box(gm, 0.024, 0.06, 0.035, 0, -0.06, 0.03);
      g.add(box(gm, 0.006, 0.012, 0.006, 0, 0.078, -0.15), box(gm, 0.014, 0.01, 0.006, 0, 0.078, 0.03));
      muzzle.position.set(0, 0.055, -0.17); eject.position.set(0.02, 0.06, -0.03);
      break;
    case 'smg':
      g.add(box(pm, 0.05, 0.07, 0.34, 0, 0.04, -0.1));
      g.add(cyl(gm, 0.014, 0.12, 0, 0.05, -0.32));
      g.add(box(pm, 0.035, 0.1, 0.045, 0, -0.04, 0.0)).rotation.x = 0.2;
      g.add(box(gm, 0.02, 0.02, 0.24, 0, 0.085, -0.12));
      g.add(box(pm, 0.04, 0.05, 0.18, 0, 0.03, 0.17));            // stock
      g.add(box(gm, 0.03, 0.035, 0.05, 0, 0.11, -0.05), box(M.glass, 0.022, 0.022, 0.005, 0, 0.11, -0.075));
      mag = box(gm, 0.026, 0.16, 0.035, 0, -0.06, -0.12); mag.rotation.x = 0.05;
      muzzle.position.set(0, 0.05, -0.39); eject.position.set(0.03, 0.06, -0.06);
      break;
    case 'shotgun':
      g.add(box(gm, 0.05, 0.07, 0.3, 0, 0.04, -0.05));
      g.add(cyl(gm, 0.016, 0.6, 0, 0.065, -0.45));
      g.add(cyl(gm, 0.014, 0.5, 0, 0.032, -0.42));
      const pump = box(pm, 0.055, 0.05, 0.18, 0, 0.032, -0.4); g.add(pump); g.userData.pump = pump;
      g.add(box(pm, 0.035, 0.1, 0.045, 0, -0.04, 0.05)).rotation.x = 0.2;
      g.add(box(M.wood, 0.045, 0.08, 0.3, 0, 0.0, 0.25));
      mag = box(gm, 0.02, 0.02, 0.06, 0, 0.0, -0.05); mag.visible = false;
      muzzle.position.set(0, 0.065, -0.76); eject.position.set(0.03, 0.06, -0.08);
      break;
    case 'ar': case 'dmr': {
      const furn = id === 'dmr' ? M.tan : pm;
      g.add(box(gm, 0.05, 0.065, 0.3, 0, 0.045, -0.06));                 // receiver
      g.add(box(furn, 0.055, 0.06, 0.26, 0, 0.045, -0.33));              // handguard
      g.add(cyl(gm, 0.012, id === 'dmr' ? 0.36 : 0.2, 0, 0.05, id === 'dmr' ? -0.6 : -0.54));
      g.add(box(gm, 0.024, 0.02, 0.06, 0, 0.05, id === 'dmr' ? -0.78 : -0.64)); // muzzle device
      g.add(box(furn, 0.035, 0.1, 0.045, 0, -0.03, 0.03)).rotation.x = 0.25;
      g.add(box(furn, 0.045, 0.08, 0.22, 0, 0.03, 0.2));                 // stock
      g.add(box(gm, 0.022, 0.012, 0.36, 0, 0.083, -0.15));               // rail
      if (id === 'dmr') {
        g.add(cyl(gm, 0.024, 0.28, 0, 0.12, -0.1, 16), cyl(gm, 0.03, 0.06, 0, 0.12, -0.27, 16), cyl(gm, 0.028, 0.05, 0, 0.12, 0.05, 16));
        g.add(box(gm, 0.02, 0.04, 0.02, 0, 0.098, -0.18), box(gm, 0.02, 0.04, 0.02, 0, 0.098, -0.03));
        mag = box(gm, 0.03, 0.09, 0.07, 0, -0.03, -0.1);
        muzzle.position.set(0, 0.05, -0.82);
      } else {
        g.add(box(gm, 0.04, 0.045, 0.07, 0, 0.11, -0.06), box(M.glass, 0.028, 0.028, 0.004, 0, 0.115, -0.096));
        g.add(box(M.red, 0.004, 0.004, 0.002, 0, 0.118, -0.03));
        mag = box(gm, 0.028, 0.15, 0.06, 0, -0.06, -0.1); mag.rotation.x = 0.18;
        muzzle.position.set(0, 0.05, -0.68);
      }
      eject.position.set(0.03, 0.06, -0.05);
      break;
    }
    case 'lmg':
      g.add(box(gm, 0.07, 0.1, 0.4, 0, 0.05, -0.05));
      g.add(box(pm, 0.07, 0.07, 0.25, 0, 0.04, -0.38));
      g.add(cyl(gm, 0.016, 0.42, 0, 0.055, -0.68));
      g.add(box(M.olive, 0.12, 0.12, 0.13, 0.0, -0.06, -0.1));        // box mag
      g.add(box(pm, 0.035, 0.1, 0.045, 0, -0.04, 0.12)).rotation.x = 0.25;
      g.add(box(pm, 0.05, 0.1, 0.24, 0, 0.03, 0.3));
      g.add(box(gm, 0.012, 0.18, 0.012, 0.02, -0.05, -0.62), box(gm, 0.012, 0.18, 0.012, -0.02, -0.05, -0.62));
      g.add(box(gm, 0.04, 0.045, 0.07, 0, 0.13, -0.06));
      mag = box(gm, 0.12, 0.02, 0.13, 0, -0.13, -0.1); mag.visible = false;
      muzzle.position.set(0, 0.055, -0.9); eject.position.set(0.04, 0.06, -0.05);
      break;
    case 'launcher':
      g.add(cyl(M.olive, 0.055, 1.0, 0, 0.08, -0.15, 16));
      g.add(cyl(gm, 0.06, 0.06, 0, 0.08, -0.65, 16), cyl(gm, 0.06, 0.06, 0, 0.08, 0.35, 16));
      g.add(box(pm, 0.035, 0.1, 0.045, 0, -0.02, 0.0)).rotation.x = 0.2;
      g.add(box(pm, 0.035, 0.1, 0.045, 0, -0.02, -0.3));
      g.add(box(gm, 0.04, 0.06, 0.1, -0.07, 0.12, -0.1));
      mag = new THREE.Mesh(new THREE.ConeGeometry(0.05, 0.16, 12).rotateX(-Math.PI / 2), M.olive); mag.position.set(0, 0.08, -0.72);
      muzzle.position.set(0, 0.08, -0.7); eject.position.set(0, 0.08, 0.4);
      break;
    case 'knife':
      g.add(box(M.boot, 0.025, 0.03, 0.12, 0, 0, 0.0));
      g.add(box(M.gunmetal, 0.006, 0.035, 0.18, 0, 0.004, -0.15));
      break;
    case 'designator':
      g.add(box(pm, 0.12, 0.08, 0.16, 0, 0.04, -0.05), cyl(gm, 0.03, 0.08, 0.03, 0.05, -0.16), cyl(gm, 0.03, 0.08, -0.03, 0.05, -0.16));
      g.add(box(M.red, 0.01, 0.01, 0.01, 0.045, 0.085, -0.02));
      muzzle.position.set(0, 0.05, -0.2);
      break;
  }
  if (mag) g.add(mag);
  g.add(muzzle, eject);
  g.userData.muzzle = muzzle; g.userData.mag = mag; g.userData.eject = eject;
  if (mag) g.userData.magPos = mag.position.clone();
  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return g;
}

// =========================================================================
// First-person viewmodel: arms + weapon
// =========================================================================
export function buildViewmodel(id, sleeveMat) {
  const root = new THREE.Group();
  const gun = buildWeapon(id === 'designator' ? 'designator' : id);
  root.add(gun);
  const sleeve = sleeveMat;
  // right hand on grip
  const rArm = new THREE.Group();
  rArm.add(box(M.glove, 0.05, 0.07, 0.09, 0, -0.02, 0.03));
  rArm.add(box(sleeve, 0.08, 0.08, 0.36, 0.0, -0.06, 0.24));
  rArm.position.set(0.012, -0.02, 0.04); rArm.rotation.set(0.35, 0.1, 0);
  // left hand on handguard
  const lArm = new THREE.Group();
  lArm.add(box(M.glove, 0.06, 0.05, 0.1, 0, -0.01, 0));
  lArm.add(box(sleeve, 0.08, 0.08, 0.38, -0.05, -0.05, 0.2));
  const lz = { pistol: 0.01, smg: -0.22, shotgun: -0.4, ar: -0.33, dmr: -0.36, lmg: -0.38, launcher: -0.3, designator: -0.08 }[id] ?? -0.3;
  lArm.position.set(id === 'pistol' ? -0.025 : -0.03, id === 'pistol' ? -0.03 : 0.0, lz);
  lArm.rotation.set(0.25, -0.5, 0.3);
  if (id === 'pistol') lArm.rotation.set(0.35, -0.2, 0.1);
  root.add(rArm, lArm);
  if (gun.userData.pump) lArm.userData.pump = true;
  root.userData = { gun, lArm, rArm, lArmBase: lArm.position.clone(), muzzle: gun.userData.muzzle, mag: gun.userData.mag, magPos: gun.userData.magPos, eject: gun.userData.eject, pump: gun.userData.pump };
  root.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.frustumCulled = false; } });
  return root;
}

// =========================================================================
// Soldiers. Model faces +Z, feet at y=0, ~1.8 m tall before scale.
// =========================================================================
const STYLES = {
  grunt:      { camo: 'camoDesert', vest: 0x5b5240, helmet: 'cap', face: 'scarf', scarf: 0x6a5a44, gun: 'ar' },
  rifleman:   { camo: 'camoWood', vest: 0x3f4430, helmet: 'helmet', face: 'skin', gun: 'ar' },
  shotgunner: { camo: 'camoBlack', vest: 0x222226, helmet: 'helmet', face: 'balaclava', gun: 'shotgun' },
  rusher:     { camo: 'camoRed', vest: 0x2d1d18, helmet: 'none', face: 'balaclava', scarf: 0x7a1010, gun: 'knife' },
  heavy:      { camo: 'camoBlack', vest: 0x1b1d20, helmet: 'jugg', face: 'visor', gun: 'lmg', heavy: true },
  friendly:   { camo: 'camoUrban', vest: 0x3a3e44, helmet: 'helmet', face: 'skin', gun: 'ar', friendly: true },
};
const matCache = {};
function fabric(key) {
  if (!matCache[key]) matCache[key] = new THREE.MeshStandardMaterial({ map: T[key], normalMap: T.fabricN, roughness: 0.95 });
  return matCache[key];
}
function solid(c, rough = 0.8, metal = 0) {
  const k = c + '_' + rough + '_' + metal;
  if (!matCache[k]) matCache[k] = new THREE.MeshStandardMaterial({ color: c, roughness: rough, metalness: metal, normalMap: T.fabricN });
  return matCache[k];
}

export function buildSoldier(type, gunId) {
  const st = STYLES[type] || STYLES.grunt;
  const cloth = fabric(st.camo), vest = solid(st.vest, 0.85), hel = solid(st.heavy ? 0x2a2c2e : 0x4a4b3c, 0.6, st.heavy ? 0.5 : 0.1);
  const root = new THREE.Group();
  const body = new THREE.Group(); root.add(body);                  // tilts for death animation
  const hips = new THREE.Group(); hips.position.y = 0.95; body.add(hips);
  const bulk = st.heavy ? 1.35 : 1;

  hips.add(box(cloth, 0.34 * bulk, 0.16, 0.22 * bulk, 0, 0, 0));
  const legs = [];
  for (const s of [-1, 1]) {
    const thigh = new THREE.Group(); thigh.position.set(0.1 * s * bulk, 0, 0);
    thigh.add(box(cloth, 0.15 * bulk, 0.48, 0.17 * bulk, 0, -0.24, 0));
    if (st.heavy) thigh.add(box(hel, 0.17 * bulk, 0.3, 0.06, 0, -0.2, 0.1));
    const knee = new THREE.Group(); knee.position.y = -0.47;
    knee.add(box(cloth, 0.13 * bulk, 0.44, 0.15 * bulk, 0, -0.22, 0));
    knee.add(box(solid(0x2b2a26, 0.7), 0.15 * bulk, 0.1, 0.06, 0, -0.03, 0.08));    // knee pad
    knee.add(box(M.boot, 0.13 * bulk, 0.1, 0.27, 0, -0.43, 0.05));
    thigh.add(knee); hips.add(thigh);
    legs.push({ thigh, knee });
  }

  const torso = new THREE.Group(); torso.position.y = 0.06; hips.add(torso);
  torso.add(box(cloth, 0.38 * bulk, 0.52, 0.22 * bulk, 0, 0.27, 0));
  torso.add(box(vest, 0.42 * bulk, 0.4, 0.27 * bulk, 0, 0.3, 0));
  if (!st.heavy) for (let k = -1; k <= 1; k++) torso.add(box(vest, 0.09, 0.11, 0.05, k * 0.11, 0.2, 0.15));   // mag pouches
  else {
    torso.add(box(hel, 0.5 * bulk, 0.45, 0.06, 0, 0.32, 0.2), box(hel, 0.5 * bulk, 0.45, 0.06, 0, 0.32, -0.2));
    torso.add(box(hel, 0.2, 0.14, 0.32, 0.33 * bulk, 0.5, 0), box(hel, 0.2, 0.14, 0.32, -0.33 * bulk, 0.5, 0));   // shoulder plates
  }
  if (st.friendly) torso.add(box(solid(0x2f6fd8, 0.6), 0.155, 0.06, 0.155, 0.27, 0.42, 0));   // blue armband
  torso.add(box(vest, 0.3, 0.35, 0.12, 0, 0.3, -0.18));              // backpack

  const neck = new THREE.Group(); neck.position.y = 0.56; torso.add(neck);
  const head = new THREE.Group(); head.position.y = 0.12; neck.add(head);
  const faceMat = st.face === 'balaclava' ? solid(0x1a1a1a, 0.95) : M.skin;
  head.add(new THREE.Mesh(new THREE.SphereGeometry(0.115, 14, 10).scale(0.9, 1.08, 1), faceMat));
  if (st.face === 'scarf' || st.scarf) head.add(box(solid(st.scarf, 0.95), 0.2, 0.09, 0.2, 0, -0.07, 0.02));
  if (st.face === 'skin') head.add(box(solid(0x111111, 0.2, 0.6), 0.17, 0.035, 0.04, 0, 0.02, 0.1));   // glasses
  if (st.face === 'balaclava') head.add(box(solid(0x0a0a0a, 0.3), 0.13, 0.03, 0.03, 0, 0.025, 0.105));
  if (st.helmet === 'helmet') {
    const h = new THREE.Mesh(new THREE.SphereGeometry(0.14, 16, 10, 0, Math.PI * 2, 0, Math.PI * 0.55), hel); h.position.y = 0.025; head.add(h);
    head.add(box(solid(0x111111, 0.4), 0.08, 0.04, 0.05, 0, 0.1, 0.11));   // NVG mount
  } else if (st.helmet === 'cap') {
    const h = new THREE.Mesh(new THREE.SphereGeometry(0.125, 14, 8, 0, Math.PI * 2, 0, Math.PI * 0.45), cloth); h.position.y = 0.03; head.add(h);
    head.add(box(cloth, 0.16, 0.015, 0.1, 0, 0.065, 0.12));
  } else if (st.helmet === 'jugg') {
    const h = new THREE.Mesh(new THREE.SphereGeometry(0.17, 16, 12), hel); h.scale.set(1, 1.05, 1.05); head.add(h);
    head.add(box(M.glass, 0.2, 0.06, 0.05, 0, 0.02, 0.15));
  }

  // arms in an aiming pose (or running pose for the rusher)
  const arms = [];
  for (const s of [-1, 1]) {
    const sh = new THREE.Group(); sh.position.set(0.24 * s * bulk, 0.5, 0);
    sh.add(box(cloth, 0.12 * bulk, 0.3, 0.12 * bulk, 0, -0.14, 0));
    const el = new THREE.Group(); el.position.y = -0.28;
    el.add(box(cloth, 0.1 * bulk, 0.28, 0.1 * bulk, 0, -0.13, 0));
    el.add(box(M.glove, 0.09, 0.09, 0.1, 0, -0.29, 0));
    sh.add(el); torso.add(sh);
    arms.push({ sh, el });
  }
  let gun = null, muzzle = null;
  const gid = gunId || st.gun;
  if (gid === 'knife') {
    arms[0].sh.rotation.x = -0.4; arms[1].sh.rotation.x = 0.3; arms[1].el.rotation.x = -1.2;
    const k = buildWeapon('knife'); k.position.set(0, -0.3, 0.05); k.rotation.x = -1.4; arms[1].el.add(k);
  } else {
    gun = buildWeapon(gid);
    gun.scale.setScalar(1.15);
    gun.position.set(0.05 * bulk, 0.33, 0.3);
    torso.add(gun);
    muzzle = gun.userData.muzzle;
    // right arm to grip, left to handguard
    arms[1].sh.rotation.set(-1.0, 0, -0.25); arms[1].el.rotation.set(-0.9, 0, 0);
    arms[0].sh.rotation.set(-1.2, 0, 0.5); arms[0].el.rotation.set(-0.5, 0, 0);
    gun.rotation.y = Math.PI;   // weapon model points -Z, soldier faces +Z
  }
  const flash = new THREE.Sprite(M.flash); flash.scale.setScalar(0.5); flash.visible = false;
  if (muzzle) muzzle.add(flash);

  root.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  root.userData = { body, hips, torso, legs, arms, head, neck, flash, muzzle, phase: Math.random() * 6, knife: gid === 'knife' };
  return root;
}

/** Animate a soldier. mv: moving 0/1, speed m/s, st: 0 move 1 aim 2 attack, dt seconds */
export function animateSoldier(s, dt, mv, speed, st, t) {
  const u = s.userData;
  u.phase += dt * (mv ? speed * 2.2 : 0);
  const ph = u.phase, a = mv ? 0.6 : 0;
  u.legBlend = (u.legBlend || 0) + ((mv ? 1 : 0) - (u.legBlend || 0)) * Math.min(1, dt * 8);
  const lb = u.legBlend;
  u.legs[0].thigh.rotation.x = Math.sin(ph) * a * lb;
  u.legs[1].thigh.rotation.x = -Math.sin(ph) * a * lb;
  u.legs[0].knee.rotation.x = Math.max(0, -Math.sin(ph + 1.2)) * 0.9 * lb;
  u.legs[1].knee.rotation.x = Math.max(0, Math.sin(ph + 1.2)) * 0.9 * lb;
  u.hips.position.y = 0.95 - Math.abs(Math.cos(ph)) * 0.04 * lb;
  u.torso.rotation.x = mv && u.knife ? 0.25 : mv ? 0.08 : 0.02;
  u.torso.rotation.y = Math.sin(ph) * 0.06 * lb;
  if (u.knife) {
    u.arms[0].sh.rotation.x = -Math.sin(ph) * 0.8 * lb - 0.2;
    u.arms[1].sh.rotation.x = st === 2 ? -2.2 : Math.sin(ph) * 0.8 * lb - 0.2;
  }
  // idle breathing
  u.neck.rotation.x = Math.sin(t * 1.3 + ph) * 0.02;
  if (u.flashT > 0) { u.flashT -= dt; u.flash.visible = u.flashT > 0; u.flash.material.rotation = Math.random() * 6; }
}

export function soldierMuzzleFlash(s) {
  const u = s.userData;
  if (!u.flash) return;
  u.flashT = 0.05; u.flash.visible = true; u.flash.scale.setScalar(0.35 + Math.random() * 0.3);
}

// =========================================================================
// Equipment & support models
// =========================================================================
export function buildFrag() {
  const g = new THREE.Group();
  g.add(new THREE.Mesh(new THREE.SphereGeometry(0.05, 10, 8).scale(1, 1.2, 1), M.olive));
  g.add(box(M.gunmetal, 0.03, 0.03, 0.03, 0, 0.06, 0), box(M.gunmetal, 0.012, 0.06, 0.02, 0.025, 0.04, 0));
  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return g;
}
export function buildRocket() {
  const g = new THREE.Group();
  g.add(new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.5, 10).rotateX(Math.PI / 2), M.olive));
  const nose = new THREE.Mesh(new THREE.ConeGeometry(0.035, 0.14, 10).rotateX(Math.PI / 2), M.gunmetal); nose.position.z = 0.32; g.add(nose);
  const glow = new THREE.Sprite(new THREE.SpriteMaterial({ map: T.glow, color: 0xffa040, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }));
  glow.scale.setScalar(0.9); glow.position.z = -0.3; g.add(glow);
  return g;
}
export function buildMine() {
  const g = new THREE.Group();
  g.add(box(M.olive, 0.24, 0.12, 0.06, 0, 0.1, 0));
  g.add(box(M.gunmetal, 0.02, 0.1, 0.02, -0.08, 0.04, 0), box(M.gunmetal, 0.02, 0.1, 0.02, 0.08, 0.04, 0));
  const led = box(M.red, 0.015, 0.015, 0.01, 0.09, 0.15, 0.035); g.add(led); g.userData.led = led;
  return g;
}
export function buildTurret() {
  const g = new THREE.Group();
  for (let k = 0; k < 3; k++) { const leg = box(M.gunmetal, 0.04, 0.85, 0.04, 0, 0.4, 0); leg.rotation.set(0.35, 0, 0); const p = new THREE.Group(); p.rotation.y = k * 2.09; p.add(leg); leg.position.z = 0.15; g.add(p); }
  const head = new THREE.Group(); head.position.y = 0.95; g.add(head);
  head.add(box(M.olive, 0.3, 0.22, 0.4, 0, 0.08, 0), box(M.olive, 0.16, 0.16, 0.12, 0.2, 0.06, 0.05));
  head.add(cyl(M.gunmetal, 0.025, 0.6, 0, 0.12, 0.45));
  head.add(box(M.glass, 0.12, 0.08, 0.02, 0, 0.2, 0.18));
  const flash = new THREE.Sprite(M.flash); flash.position.set(0, 0.12, 0.8); flash.scale.setScalar(0.5); flash.visible = false; head.add(flash);
  g.userData = { head, flash };
  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return g;
}
export function buildJet() {
  const g = new THREE.Group(), m = new THREE.MeshStandardMaterial({ color: 0x6d747a, roughness: 0.5, metalness: 0.6 });
  g.add(new THREE.Mesh(new THREE.CylinderGeometry(0.7, 0.9, 14, 12).rotateX(Math.PI / 2), m));
  const nose = new THREE.Mesh(new THREE.ConeGeometry(0.7, 3, 12).rotateX(Math.PI / 2), m); nose.position.z = 8.5; g.add(nose);
  const wing = new THREE.Mesh(new THREE.BufferGeometry(), m);
  const shape = new THREE.Shape(); shape.moveTo(0, 3); shape.lineTo(6.5, -2); shape.lineTo(6.5, -3.2); shape.lineTo(0, -2.5); shape.lineTo(-6.5, -3.2); shape.lineTo(-6.5, -2); shape.closePath();
  wing.geometry = new THREE.ExtrudeGeometry(shape, { depth: 0.2, bevelEnabled: false }).rotateX(-Math.PI / 2); g.add(wing);
  const tail = box(m, 0.15, 2.4, 2.4, 0, 1.3, -5.6); g.add(tail);
  const canopy = new THREE.Mesh(new THREE.SphereGeometry(0.6, 12, 8).scale(1, 0.8, 2.4), M.glass); canopy.position.set(0, 0.6, 4.5); g.add(canopy);
  const burner = new THREE.Sprite(new THREE.SpriteMaterial({ map: T.glow, color: 0xff9a50, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false })); burner.scale.setScalar(3.5); burner.position.z = -7.6; g.add(burner);
  return g;
}
export function buildGunship() {
  const g = buildJet();
  g.scale.set(1.4, 1.4, 1.6);
  return g;
}

export { M as MATS };
