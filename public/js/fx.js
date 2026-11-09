// Particles, tracers, decals, explosions, shell casings.
import * as THREE from 'three';
import { raycastWorld } from '/shared/map.js';

export class FX {
  constructor(scene, T) {
    this.scene = scene; this.T = T;
    // sprite pool
    this.parts = [];
    for (let i = 0; i < 360; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: T.smoke, transparent: true, depthWrite: false }));
      s.visible = false; s.userData = { life: 0 }; scene.add(s); this.parts.push(s);
    }
    this.pi = 0;
    // tracers
    this.tracers = [];
    const tg = new THREE.BoxGeometry(1, 1, 1).translate(0, 0, 0.5);
    for (let i = 0; i < 80; i++) {
      const m = new THREE.Mesh(tg, new THREE.MeshBasicMaterial({ color: 0xffd9a0, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }));
      m.visible = false; m.userData = { life: 0 }; scene.add(m); this.tracers.push(m);
    }
    this.ti = 0;
    // decals
    this.decals = [];
    const dg = new THREE.PlaneGeometry(1, 1);
    const mk = (map) => new THREE.MeshStandardMaterial({ map, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, roughness: 0.9 });
    this.decalMats = { hole: mk(T.hole), scorch: mk(T.scorch), blood: mk(T.blood) };
    for (let i = 0; i < 220; i++) { const m = new THREE.Mesh(dg, this.decalMats.hole); m.visible = false; m.receiveShadow = true; scene.add(m); this.decals.push(m); }
    this.di = 0;
    // casings
    this.casings = [];
    const cg = new THREE.CylinderGeometry(0.006, 0.006, 0.03, 6).rotateZ(Math.PI / 2);
    const cm = new THREE.MeshStandardMaterial({ color: 0xc8a050, roughness: 0.3, metalness: 1 });
    for (let i = 0; i < 40; i++) { const m = new THREE.Mesh(cg, cm); m.visible = false; m.userData = { v: new THREE.Vector3(), life: 0, spin: new THREE.Vector3() }; scene.add(m); this.casings.push(m); }
    this.ci = 0;
    // explosion lights
    this.lights = [];
    for (let i = 0; i < 3; i++) { const l = new THREE.PointLight(0xff9a40, 0, 30, 1.6); scene.add(l); this.lights.push({ l, life: 0 }); }
    this.li = 0;
    this.debris = [];
    const dbg = new THREE.BoxGeometry(0.08, 0.08, 0.08), dbm = new THREE.MeshStandardMaterial({ color: 0x3a3631, roughness: 1 });
    for (let i = 0; i < 60; i++) { const m = new THREE.Mesh(dbg, dbm); m.visible = false; m.castShadow = true; m.userData = { v: new THREE.Vector3(), life: 0 }; scene.add(m); this.debris.push(m); }
    this.dbi = 0;
    this.shake = 0;
  }

  sprite(o) {
    const s = this.parts[this.pi = (this.pi + 1) % this.parts.length], m = s.material;
    m.map = o.map || this.T.smoke; m.color.set(o.color ?? 0xffffff);
    m.blending = o.add ? THREE.AdditiveBlending : THREE.NormalBlending;
    m.toneMapped = !o.add; m.rotation = Math.random() * 6.28; m.needsUpdate = true;
    s.position.copy(o.pos);
    const u = s.userData;
    u.v = o.vel ? o.vel.clone() : new THREE.Vector3();
    u.life = u.max = o.life; u.s0 = o.size; u.s1 = o.grow ?? o.size; u.a = o.alpha ?? 1; u.g = o.grav ?? 0; u.drag = o.drag ?? 1.5; u.spin = (Math.random() - 0.5) * (o.spin ?? 1);
    s.scale.setScalar(o.size); m.opacity = u.a; s.visible = true;
    return s;
  }

  tracer(from, to, color = 0xffd9a0, width = 0.022, speed = 380) {
    const t = this.tracers[this.ti = (this.ti + 1) % this.tracers.length];
    const dir = to.clone().sub(from), len = dir.length();
    if (len < 0.5) return;
    dir.divideScalar(len);
    t.position.copy(from); t.lookAt(to);
    t.material.color.set(color);
    const seg = Math.min(len, 4 + Math.random() * 3);
    t.scale.set(width, width, seg);
    Object.assign(t.userData, { from: from.clone(), dir, len, seg, d: 0, speed, life: 1 });
    t.material.opacity = 0.9; t.visible = true;
  }

  decal(pos, normal, kind = 'hole', size = 0.09) {
    const d = this.decals[this.di = (this.di + 1) % this.decals.length];
    d.material = this.decalMats[kind];
    d.position.copy(pos).addScaledVector(normal, 0.012);
    d.lookAt(pos.clone().add(normal));
    d.rotateZ(Math.random() * 6.28);
    d.scale.setScalar(size * (0.8 + Math.random() * 0.4));
    d.visible = true;
  }

  impact(pos, normal, surface = 'concrete') {
    const n = normal;
    const dust = surface === 'metal' ? 0x6a6560 : surface === 'wood' ? 0x8a6a48 : surface === 'ground' ? 0x8a7a64 : 0xa09a90;
    for (let i = 0; i < 2; i++) this.sprite({ pos, vel: n.clone().multiplyScalar(0.8 + Math.random()).add(new THREE.Vector3((Math.random() - 0.5) * 0.6, Math.random() * 0.5, (Math.random() - 0.5) * 0.6)), size: 0.12, grow: 0.6 + Math.random() * 0.4, life: 0.7 + Math.random() * 0.5, color: dust, alpha: 0.55 });
    const sparks = surface === 'metal' ? 6 : 3;
    for (let i = 0; i < sparks; i++) {
      const v = n.clone().multiplyScalar(2 + Math.random() * 4).add(new THREE.Vector3((Math.random() - 0.5) * 5, Math.random() * 3, (Math.random() - 0.5) * 5));
      this.sprite({ pos, vel: v, size: 0.05, grow: 0.01, life: 0.15 + Math.random() * 0.2, color: 0xffb060, add: true, map: this.T.glow, grav: 9, drag: 0.5 });
    }
    this.decal(pos, n, 'hole', surface === 'ground' ? 0.12 : 0.08);
  }

  blood(pos, dir, head) {
    const n = head ? 6 : 3;
    for (let i = 0; i < n; i++) {
      const v = dir.clone().multiplyScalar(1 + Math.random() * 2).add(new THREE.Vector3((Math.random() - 0.5) * 1.5, Math.random() * 1.2, (Math.random() - 0.5) * 1.5));
      this.sprite({ pos, vel: v, size: 0.1, grow: head ? 0.55 : 0.4, life: 0.35 + Math.random() * 0.3, color: 0x6a0a06, alpha: 0.85, grav: 4 });
    }
    // splatter on the ground / wall behind
    const h = raycastWorld(pos.x, pos.y, pos.z, dir.x + (Math.random() - 0.5) * 0.3, dir.y - 0.4, dir.z + (Math.random() - 0.5) * 0.3, 4);
    if (h.t < 4) {
      const p = pos.clone().add(new THREE.Vector3(dir.x, dir.y - 0.4, dir.z).normalize().multiplyScalar(h.t));
      this.decal(p, new THREE.Vector3(h.nx, h.ny, h.nz), 'blood', 0.5 + Math.random() * 0.5);
    }
  }

  muzzleSmoke(pos, dir) {
    this.sprite({ pos, vel: dir.clone().multiplyScalar(1.2).add(new THREE.Vector3(0, 0.4, 0)), size: 0.05, grow: 0.35, life: 0.5, color: 0xbbbbbb, alpha: 0.2 });
  }

  explosion(pos, r = 6) {
    const s = r / 6;
    const lt = this.lights[this.li = (this.li + 1) % this.lights.length];
    lt.l.position.copy(pos).add(new THREE.Vector3(0, 1, 0)); lt.l.intensity = 900 * s; lt.life = 0.35;
    // flash + fireball
    this.sprite({ pos: pos.clone().add(new THREE.Vector3(0, 0.5, 0)), size: 2 * s, grow: 7 * s, life: 0.18, color: 0xfff0c0, add: true, map: this.T.glow });
    for (let i = 0; i < 14; i++) {
      const v = new THREE.Vector3((Math.random() - 0.5) * 9, Math.random() * 7 + 1, (Math.random() - 0.5) * 9).multiplyScalar(s);
      this.sprite({ pos: pos.clone().add(new THREE.Vector3(0, 0.4, 0)), vel: v, size: 1.0 * s, grow: 3.2 * s, life: 0.35 + Math.random() * 0.3, color: i % 2 ? 0xff8a30 : 0xffb050, add: true, drag: 3.5 });
    }
    // smoke column
    for (let i = 0; i < 16; i++) {
      const v = new THREE.Vector3((Math.random() - 0.5) * 4, Math.random() * 3 + 0.8, (Math.random() - 0.5) * 4).multiplyScalar(s);
      this.sprite({ pos: pos.clone().add(new THREE.Vector3((Math.random() - 0.5) * 2, 0.5 + Math.random(), (Math.random() - 0.5) * 2)), vel: v, size: 2 * s, grow: (6 + Math.random() * 4) * s, life: 2.5 + Math.random() * 2.5, color: i % 3 ? 0x3d3a36 : 0x5a554e, alpha: 0.75, drag: 1.2 });
    }
    // dust ring
    for (let i = 0; i < 12; i++) {
      const a = i / 12 * Math.PI * 2;
      this.sprite({ pos: pos.clone().setY(0.4), vel: new THREE.Vector3(Math.cos(a) * 9 * s, 0.4, Math.sin(a) * 9 * s), size: 1.2 * s, grow: 4 * s, life: 1.4, color: 0x9a8a72, alpha: 0.5, drag: 2.5 });
    }
    // sparks & debris
    for (let i = 0; i < 18; i++) {
      const v = new THREE.Vector3((Math.random() - 0.5) * 22, Math.random() * 16, (Math.random() - 0.5) * 22);
      this.sprite({ pos: pos.clone().add(new THREE.Vector3(0, 0.5, 0)), vel: v, size: 0.12, grow: 0.04, life: 0.5 + Math.random() * 0.8, color: 0xffa040, add: true, map: this.T.glow, grav: 14, drag: 0.4 });
    }
    for (let i = 0; i < 10; i++) {
      const d = this.debris[this.dbi = (this.dbi + 1) % this.debris.length];
      d.position.copy(pos).add(new THREE.Vector3(0, 0.4, 0));
      d.userData.v.set((Math.random() - 0.5) * 14, 5 + Math.random() * 10, (Math.random() - 0.5) * 14);
      d.userData.life = 3; d.visible = true; d.scale.setScalar(0.5 + Math.random() * 1.5);
    }
    if (pos.y < 1.2) this.decal(new THREE.Vector3(pos.x, 0.02, pos.z), new THREE.Vector3(0, 1, 0), 'scorch', r * 0.9);
  }

  casing(pos, vel) {
    const c = this.casings[this.ci = (this.ci + 1) % this.casings.length];
    c.position.copy(pos); c.userData.v.copy(vel); c.userData.life = 1.6; c.visible = true;
    c.userData.spin.set(Math.random() * 30, Math.random() * 30, Math.random() * 30);
  }

  update(dt, camera) {
    for (const s of this.parts) {
      const u = s.userData;
      if (!s.visible) continue;
      u.life -= dt;
      if (u.life <= 0) { s.visible = false; continue; }
      const k = 1 - u.life / u.max;
      u.v.multiplyScalar(Math.max(0, 1 - u.drag * dt)); u.v.y -= u.g * dt;
      s.position.addScaledVector(u.v, dt);
      if (s.position.y < 0.02) { s.position.y = 0.02; u.v.y *= -0.3; }
      s.scale.setScalar(u.s0 + (u.s1 - u.s0) * (1 - (1 - k) * (1 - k)));
      s.material.opacity = u.a * (1 - k) * Math.min(1, k * 20 + 0.2);
      s.material.rotation += u.spin * dt;
    }
    for (const t of this.tracers) {
      const u = t.userData;
      if (!t.visible) continue;
      u.d += u.speed * dt;
      if (u.d > u.len) { t.visible = false; continue; }
      t.position.copy(u.from).addScaledVector(u.dir, Math.max(0, u.d - u.seg));
      t.scale.z = Math.min(u.seg, u.d, u.len - Math.max(0, u.d - u.seg));
    }
    for (const c of this.casings) {
      if (!c.visible) continue;
      const u = c.userData;
      u.life -= dt;
      if (u.life <= 0) { c.visible = false; continue; }
      u.v.y -= 9.8 * dt;
      c.position.addScaledVector(u.v, dt);
      if (c.position.y < 0.01) { c.position.y = 0.01; u.v.multiplyScalar(0.4); u.v.y = Math.abs(u.v.y) * 0.5; u.spin.multiplyScalar(0.5); }
      c.rotation.x += u.spin.x * dt; c.rotation.y += u.spin.y * dt; c.rotation.z += u.spin.z * dt;
    }
    for (const d of this.debris) {
      if (!d.visible) continue;
      const u = d.userData;
      u.life -= dt; if (u.life <= 0) { d.visible = false; continue; }
      u.v.y -= 15 * dt; d.position.addScaledVector(u.v, dt);
      if (d.position.y < 0.04) { d.position.y = 0.04; u.v.multiplyScalar(0.3); u.v.y = Math.abs(u.v.y) * 0.3; }
      d.rotation.x += u.v.length() * dt; d.rotation.z += u.v.x * dt;
    }
    for (const l of this.lights) { if (l.life > 0) { l.life -= dt; l.l.intensity = Math.max(0, l.l.intensity * Math.pow(0.0005, dt)); if (l.life <= 0) l.l.intensity = 0; } }
    this.shake = Math.max(0, this.shake - dt * 2.2);
  }
}
