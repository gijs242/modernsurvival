// Authoritative game simulation. Runs in Node for multiplayer and directly in
// the browser for singleplayer. No DOM / Node APIs in here.
import { WEAPONS, ENEMIES, SHOP, START_MONEY, MAX_FRAGS, MAX_MINES, waveBonus, damageAt } from './defs.js';
import { BOXES, SPAWNS, PLAYER_SPAWNS, NAV, HALF, collideCircle, segmentBlocked, pointInBox, raycastWorld } from './map.js';

const rnd = (a, b) => a + Math.random() * (b - a);
const rint = (a, b) => Math.floor(rnd(a, b + 1));
const r2 = (v) => Math.round(v * 100) / 100;

export class Game {
  constructor() {
    this.players = new Map();
    this.events = [];
    this.nextId = 1;
    this.flow = new Int16Array(NAV.n * NAV.n);
    this.queue = new Int32Array(NAV.n * NAV.n);
    this.reset();
  }

  reset() {
    this.enemies = [];
    this.projectiles = [];
    this.mines = [];
    this.turrets = [];
    this.drones = [];
    this.strikes = [];
    this.wave = 0;            // current / last started wave
    this.cleared = 0;         // completed waves
    this.state = 'inter';     // inter | active | over
    this.timer = 15;
    this.spawnQueue = [];
    this.spawnT = 0;
    this.flowT = 0;
    this.time = 0;
    let i = 0;
    for (const p of this.players.values()) this.initPlayer(p, i++);
  }

  initPlayer(p, idx = 0) {
    const s = PLAYER_SPAWNS[idx % PLAYER_SPAWNS.length];
    Object.assign(p, {
      x: s.x, y: 0, z: s.z, yaw: 0, pitch: 0, cr: 0, hp: 100, armor: 0, money: START_MONEY,
      weapons: ['pistol'], cur: 'pistol', frags: 2, mines: 0, turrets: 0, selfRevive: 0, strikes: 0, drones: 0, carpets: 0,
      downed: false, dead: false, downT: 0, revP: 0, rev: 0, lastDmg: -99, kills: 0, heads: 0, earned: 0, downs: 0,
      combo: 0, comboT: 0, ready: false, flawless: true, tp: 1,
    });
  }

  addPlayer(id, name) {
    const p = { id, name: String(name || 'Soldier').slice(0, 16) };
    this.initPlayer(p, this.players.size);
    if (this.state === 'over') { /* joins the debrief, will play after restart */ }
    this.players.set(id, p);
    this.ev({ t: 'msg', text: `${p.name} joined` });
    return p;
  }

  removePlayer(id) {
    const p = this.players.get(id);
    if (!p) return;
    this.players.delete(id);
    this.ev({ t: 'msg', text: `${p.name} left` });
  }

  ev(e) { this.events.push(e); }
  unlocked(item) { return this.cleared >= item.after; }
  alivePlayers() { const a = []; for (const p of this.players.values()) if (!p.dead && !p.downed) a.push(p); return a; }

  // ------------------------------------------------------------------ input
  handle(id, m) {
    const p = this.players.get(id);
    if (!p || !m) return;
    switch (m.t) {
      case 'st':
        if (p.dead) break;
        if (p.tp) break;       // waiting for the client to acknowledge a teleport
        if (!p.downed) { p.x = +m.x || 0; p.y = +m.y || 0; p.z = +m.z || 0; p.cr = m.cr ? 1 : 0; }
        p.yaw = +m.yaw || 0; p.pitch = +m.pitch || 0;
        if (p.weapons.includes(m.cur)) p.cur = m.cur;
        p.rev = m.rev || 0;
        break;
      case 'tpok': p.tp = 0; break;
      case 'fire':
        if (p.downed || p.dead) break;
        this.ev({ t: 'tracer', k: 'p', pid: id, w: m.w, o: m.o, e: m.e });
        break;
      case 'hits': this.playerHits(p, m); break;
      case 'melee': {
        const e = this.enemies.find((e) => e.id === m.eid);
        if (e && !p.downed && !p.dead && Math.hypot(e.x - p.x, e.z - p.z) < 3.2) this.damageEnemy(e, 150, p, { melee: true });
        break;
      }
      case 'throw':
        if (p.downed || p.dead || p.frags <= 0) break;
        p.frags--;
        this.projectiles.push({ id: this.nextId++, k: 'frag', x: m.o[0], y: m.o[1], z: m.o[2], vx: m.v[0], vy: m.v[1], vz: m.v[2], fuse: 2.6, owner: id });
        break;
      case 'rocket':
        if (p.downed || p.dead || !p.weapons.includes('launcher')) break;
        this.projectiles.push({ id: this.nextId++, k: 'rocket', x: m.o[0], y: m.o[1], z: m.o[2], vx: m.d[0] * 55, vy: m.d[1] * 55, vz: m.d[2] * 55, fuse: 5, owner: id });
        break;
      case 'mine':
        if (p.downed || p.dead || p.mines <= 0) break;
        p.mines--;
        this.mines.push({ id: this.nextId++, x: p.x + Math.sin(p.yaw) * -1, z: p.z + Math.cos(p.yaw) * -1, y: p.y, arm: 1.2, owner: id });
        if (this.mines.length > 12) this.mines.shift();
        break;
      case 'turret':
        if (p.downed || p.dead || p.turrets <= 0) break;
        p.turrets--;
        {
          let tx = p.x - Math.sin(p.yaw) * 1.3, tz = p.z - Math.cos(p.yaw) * 1.3;
          [tx, tz] = collideCircle(tx, tz, 0.45, 0, 1.2, 0.1);
          this.turrets.push({ id: this.nextId++, x: tx, z: tz, yaw: p.yaw, life: 90, cd: 0, owner: id, fire: 0 });
        }
        break;
      case 'strike':
        if (p.downed || p.dead) break;
        if (m.k === 'carpet') {
          if (p.carpets <= 0) break;
          p.carpets--;
          for (let i = -1; i <= 1; i++) this.addStrike(i * 22 + rnd(-3, 3), rnd(-4, 4), 0, 3.5 + (i + 1) * 1.6, id, 9, 9);
          this.ev({ t: 'announce', text: 'CARPET BOMBING INBOUND', sub: `${p.name} called it in — take cover!`, snd: 'radio' });
        } else {
          if (p.strikes <= 0) break;
          p.strikes--;
          this.addStrike(+m.x, +m.z, Math.atan2(m.x - p.x, m.z - p.z) + Math.PI / 2, 3.2, id, 7, 6.5);
          this.ev({ t: 'announce', text: 'AIRSTRIKE INBOUND', sub: `Marked by ${p.name}`, snd: 'radio' });
        }
        break;
      case 'drone':
        if (p.downed || p.dead || p.drones <= 0) break;
        p.drones--;
        this.drones.push({ id: this.nextId++, a: Math.random() * 6.28, life: 45, cd: 1.5, owner: id, x: 0, y: 32, z: 0 });
        this.ev({ t: 'announce', text: 'GUNSHIP ON STATION', sub: `Called in by ${p.name}`, snd: 'radio' });
        break;
      case 'buy': this.buy(p, m.item); break;
      case 'ready':
        if (this.state === 'inter') {
          p.ready = true;
          let all = true;
          for (const q of this.players.values()) if (!q.ready) all = false;
          if (all && this.timer > 3) this.timer = 3;
        }
        break;
      case 'restart':
        if (this.state === 'over') { this.reset(); this.ev({ t: 'restart' }); }
        break;
    }
  }

  addStrike(x, z, ang, delay, owner, count, spacing) {
    this.strikes.push({ id: this.nextId++, x, z, ang, t: delay, n: 0, count, spacing, gap: 0, owner });
    this.ev({ t: 'strikeMark', x, z, ang, delay, len: count * spacing });
  }

  buy(p, itemId) {
    const it = SHOP.find((s) => s.id === itemId);
    if (!it || p.dead || p.downed) return;
    const fail = (why) => this.ev({ t: 'buy', to: p.id, ok: false, why });
    if (!this.unlocked(it)) return fail('Locked');
    if (p.money < it.price) return fail('Not enough cash');
    let grant = null;
    switch (it.id) {
      case 'e_ammo': grant = { ammo: true }; break;
      case 'e_frag': if (p.frags >= MAX_FRAGS) return fail('Grenades full'); p.frags = Math.min(MAX_FRAGS, p.frags + 2); break;
      case 'e_mine': if (p.mines >= MAX_MINES) return fail('Mines full'); p.mines = Math.min(MAX_MINES, p.mines + 2); break;
      case 'e_armor': if (p.armor >= 100) return fail('Armor already full'); p.armor = 100; break;
      case 'e_harmor': if (p.armor >= 250) return fail('Armor already full'); p.armor = 250; break;
      case 'e_revive': if (p.selfRevive >= 1) return fail('Already carrying one'); p.selfRevive = 1; break;
      case 'e_turret': if (p.turrets >= 2) return fail('Carrying max'); p.turrets++; break;
      case 'a_strike': if (p.strikes >= 2) return fail('Carrying max'); p.strikes++; break;
      case 'a_drone': if (p.drones >= 1) return fail('Carrying max'); p.drones++; break;
      case 'a_carpet': if (p.carpets >= 1) return fail('Carrying max'); p.carpets++; break;
      default:
        if (it.weapon) {
          if (p.weapons.includes(it.weapon)) return fail('Already owned — buy ammo instead');
          let dropped = null;
          if (p.weapons.length >= 2) {
            // replace the held weapon
            const idx = Math.max(0, p.weapons.indexOf(p.cur));
            dropped = p.weapons[idx];
            p.weapons[idx] = it.weapon;
          } else p.weapons.push(it.weapon);
          p.cur = it.weapon;
          grant = { weapon: it.weapon, dropped };
        }
    }
    p.money -= it.price;
    this.ev({ t: 'buy', to: p.id, ok: true, item: it.id, name: it.name, price: it.price, ...grant });
  }

  playerHits(p, m) {
    if (p.dead || !Array.isArray(m.hits) || (p.downed && m.w !== 'pistol')) return;
    const w = WEAPONS[m.w];
    if (!w || !p.weapons.includes(m.w) || w.rocket) return;
    const per = new Map();
    for (const h of m.hits.slice(0, 12)) {
      const e = this.enemies.find((e) => e.id === h.eid);
      if (!e) continue;
      const def = ENEMIES[e.type];
      let d = damageAt(w, +h.dist || 0);
      const head = h.zone === 0;
      if (head) d *= 1 + (w.headMult - 1) * def.headMult; else if (h.zone === 2) d *= 0.75;
      const cur = per.get(e) || { d: 0, head: false };
      cur.d += d; cur.head = cur.head || head;
      per.set(e, cur);
    }
    for (const [e, v] of per) this.damageEnemy(e, v.d, p, { head: v.head });
  }

  damageEnemy(e, dmg, p, o = {}) {
    if (e.hp <= 0) return;
    e.hp -= dmg;
    e.alert = 1;
    if (e.hp > 0) {
      if (p) this.ev({ t: 'hit', to: p.id, eid: e.id, dmg: Math.round(dmg), head: !!o.head, src: o.src });
      return;
    }
    // --- kill
    const def = ENEMIES[e.type];
    this.enemies.splice(this.enemies.indexOf(e), 1);
    let money = 0, combo = 0, bonus = 0;
    if (p) {
      p.kills++;
      if (o.head) p.heads++;
      p.combo = p.comboT > 0 ? p.combo + 1 : 1;
      p.comboT = 4;
      combo = p.combo;
      money = def.reward + (o.head ? 25 : 0) + (o.melee ? 50 : 0);
      bonus = combo >= 2 ? Math.min(300, 25 * (combo - 1)) : 0;
      p.money += money + bonus; p.earned += money + bonus;
    }
    this.ev({ t: 'kill', pid: p ? p.id : 0, eid: e.id, et: e.type, x: r2(e.x), z: r2(e.z), yaw: r2(e.yaw), head: !!o.head, melee: !!o.melee, src: o.src, expl: !!o.expl, money, combo, bonus });
  }

  damagePlayer(p, dmg, fx, fz) {
    if (p.dead || p.downed || this.state === 'over') return;
    p.lastDmg = this.time; p.flawless = false;
    if (p.armor > 0) { const a = Math.min(p.armor, dmg); p.armor -= a; dmg -= a * 0.9; }
    p.hp -= dmg;
    this.ev({ t: 'dmg', to: p.id, x: r2(fx), z: r2(fz), amt: Math.round(dmg) });
    if (p.hp <= 0) {
      p.hp = 0; p.downed = true; p.downs++; p.revP = 0;
      p.downT = p.selfRevive ? 5 : 35;
      this.ev({ t: 'down', pid: p.id, self: !!p.selfRevive });
    }
  }

  explode(x, y, z, r, dmg, owner, src) {
    this.ev({ t: 'explode', x: r2(x), y: r2(y), z: r2(z), r });
    const p = this.players.get(owner);
    for (const e of this.enemies.slice()) {
      const d = Math.hypot(e.x - x, e.z - z, 1 - y > 0 ? 0 : (y - 1) * 0.5);
      if (d < r) this.damageEnemy(e, dmg * (1 - 0.75 * d / r), p, { expl: true, src });
    }
    for (const q of this.players.values()) {
      const d = Math.hypot(q.x - x, q.y + 1 - y, q.z - z);
      if (d < r * 0.8 && !segmentBlocked(x, y + 0.3, z, q.x, q.y + 1.2, q.z)) this.damagePlayer(q, dmg * 0.22 * (1 - d / (r * 0.8)) * (q.id === owner ? 1 : 0.5), x, z);
    }
  }

  // ------------------------------------------------------------------ waves
  startWave() {
    this.wave++;
    this.state = 'active';
    const n = this.players.size || 1;
    const w = this.wave;
    const count = Math.round((5 + w * 2.2 + Math.min(12, w * 0.4)) * (1 + 0.6 * (n - 1)));
    const q = [];
    for (let i = 0; i < count; i++) {
      const r = Math.random();
      let t = 'grunt';
      if (w >= 2 && r < Math.min(0.4, 0.1 + w * 0.03)) t = 'rifleman';
      else if (w >= 3 && r < Math.min(0.6, 0.25 + w * 0.035)) t = 'rusher';
      else if (w >= 4 && r < Math.min(0.78, 0.33 + w * 0.045)) t = 'shotgunner';
      q.push(t);
    }
    if (w % 5 === 0) for (let i = 0; i < Math.ceil(w / 10) + Math.floor((n - 1) / 2); i++) q.splice(Math.floor(q.length * rnd(0.3, 0.8)), 0, 'heavy');
    else if (w > 6 && Math.random() < 0.35) q.push('heavy');
    this.spawnQueue = q;
    this.spawnT = 1.5;
    for (const p of this.players.values()) { p.ready = false; p.flawless = true; }
    this.ev({ t: 'wave', n: w, count: q.length, boss: w % 5 === 0 });
  }

  endWave() {
    this.cleared = this.wave;
    this.state = 'inter';
    this.timer = 30;
    const bonus = waveBonus(this.wave);
    let i = 0;
    for (const p of this.players.values()) {
      if (p.dead || p.downed) { this.respawn(p, i); }
      i++;
      const fl = p.flawless ? 150 : 0;
      p.money += bonus + fl; p.earned += bonus + fl;
      p.ready = false;
      this.ev({ t: 'money', to: p.id, amt: bonus, label: 'WAVE SURVIVED' });
      if (fl) this.ev({ t: 'money', to: p.id, amt: fl, label: 'FLAWLESS' });
    }
    const unl = SHOP.filter((s) => s.after === this.cleared).map((s) => s.name);
    this.ev({ t: 'waveEnd', n: this.wave, bonus, unlocks: unl });
  }

  respawn(p, idx = 0) {
    const s = PLAYER_SPAWNS[idx % PLAYER_SPAWNS.length];
    p.dead = false; p.downed = false; p.hp = 100; p.x = s.x; p.z = s.z; p.y = 0; p.tp = 1;
    this.ev({ t: 'respawn', to: p.id, x: s.x, z: s.z });
  }

  spawnEnemy(type) {
    // prefer gates that no player is camping right next to
    let best = null, bs = -1;
    for (let k = 0; k < 3; k++) {
      const s = SPAWNS[rint(0, SPAWNS.length - 1)];
      let d = 1e9;
      for (const p of this.players.values()) d = Math.min(d, Math.hypot(p.x - s.x, p.z - s.z));
      const score = Math.min(d, 30) + Math.random() * 10;
      if (score > bs) { bs = score; best = s; }
    }
    const def = ENEMIES[type];
    const hpMul = 1 + Math.max(0, this.wave - 1) * 0.045 + (this.players.size - 1) * 0.15;
    this.enemies.push({
      id: this.nextId++, type, x: best.x + rnd(-1.5, 1.5), z: best.z + rnd(-1.5, 1.5), yaw: 0,
      hp: def.hp * hpMul, maxHp: def.hp * hpMul, st: 0, tgt: 0, losT: Math.random() * 0.3, los: false, seen: 0,
      burst: 0, cd: rnd(0.5, 1.5), strafe: Math.random() < 0.5 ? 1 : -1, strafeT: 0, alert: 0, shot: 0,
      spd: def.speed * rnd(0.92, 1.08),
    });
  }

  // ------------------------------------------------------------------ nav
  cellOf(x, z) {
    const i = Math.max(0, Math.min(NAV.n - 1, Math.floor(x - NAV.min)));
    const j = Math.max(0, Math.min(NAV.n - 1, Math.floor(z - NAV.min)));
    return j * NAV.n + i;
  }

  buildFlow() {
    const { n, blocked } = NAV, f = this.flow, q = this.queue;
    f.fill(32767);
    let head = 0, tail = 0;
    for (const p of this.alivePlayers()) {
      let c = this.cellOf(p.x, p.z);
      if (blocked[c]) {
        // find closest free cell (player is standing on top of something)
        let found = -1, bd = 1e9;
        const ci = c % n, cj = (c / n) | 0;
        for (let dj = -4; dj <= 4; dj++) for (let di = -4; di <= 4; di++) {
          const i = ci + di, j = cj + dj;
          if (i < 0 || j < 0 || i >= n || j >= n || blocked[j * n + i]) continue;
          const d = di * di + dj * dj;
          if (d < bd) { bd = d; found = j * n + i; }
        }
        if (found < 0) continue;
        c = found;
      }
      if (f[c] !== 0) { f[c] = 0; q[tail++] = c; }
    }
    while (head < tail) {
      const c = q[head++], d = f[c] + 1, i = c % n, j = (c / n) | 0;
      if (i > 0 && !blocked[c - 1] && f[c - 1] > d) { f[c - 1] = d; q[tail++] = c - 1; }
      if (i < n - 1 && !blocked[c + 1] && f[c + 1] > d) { f[c + 1] = d; q[tail++] = c + 1; }
      if (j > 0 && !blocked[c - n] && f[c - n] > d) { f[c - n] = d; q[tail++] = c - n; }
      if (j < n - 1 && !blocked[c + n] && f[c + n] > d) { f[c + n] = d; q[tail++] = c + n; }
    }
  }

  flowDir(x, z) {
    const { n, blocked, min } = NAV, f = this.flow;
    const ci = Math.max(1, Math.min(n - 2, Math.floor(x - min))), cj = Math.max(1, Math.min(n - 2, Math.floor(z - min)));
    let best = f[cj * n + ci], bi = 0, bj = 0;
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
      if (!di && !dj) continue;
      const c = (cj + dj) * n + ci + di;
      if (blocked[c]) continue;
      if (di && dj && (blocked[cj * n + ci + di] || blocked[(cj + dj) * n + ci])) continue;   // no corner cutting
      const v = f[c] + (di && dj ? 0.4 : 0);
      if (v < best) { best = v; bi = di; bj = dj; }
    }
    if (!bi && !bj) return null;
    const tx = min + ci + bi + 0.5 - x, tz = min + cj + bj + 0.5 - z;
    const l = Math.hypot(tx, tz) || 1;
    return [tx / l, tz / l];
  }

  // ------------------------------------------------------------------ tick
  tick(dt) {
    this.time += dt;
    const players = this.alivePlayers();

    // players: regen, combos, downed, revive
    let anyUp = false, anyPlayer = this.players.size > 0;
    for (const p of this.players.values()) {
      if (p.comboT > 0) { p.comboT -= dt; if (p.comboT <= 0) p.combo = 0; }
      if (p.dead) continue;
      if (p.downed) {
        p.downT -= dt;
        let helper = null;
        for (const q of this.players.values()) if (q !== p && !q.downed && !q.dead && q.rev === p.id && Math.hypot(q.x - p.x, q.z - p.z) < 3) helper = q;
        if (helper) { p.revP += dt / 3; p.downT += dt; } else p.revP = Math.max(0, p.revP - dt);
        if (p.revP >= 1) {
          p.downed = false; p.hp = 40; p.lastDmg = this.time - 3;
          this.ev({ t: 'revived', pid: p.id, by: helper.id });
          helper.money += 100; helper.earned += 100;
          this.ev({ t: 'money', to: helper.id, amt: 100, label: 'REVIVE' });
        } else if (p.downT <= 0) {
          if (p.selfRevive) {
            p.selfRevive = 0; p.downed = false; p.hp = 60; p.lastDmg = this.time - 2;
            this.ev({ t: 'revived', pid: p.id, by: p.id });
          } else { p.dead = true; this.ev({ t: 'died', pid: p.id }); }
        }
        if (p.downed && (p.selfRevive || this.players.size > 1)) { /* still in the fight */ }
      } else if (p.hp < 100 && this.time - p.lastDmg > 5) p.hp = Math.min(100, p.hp + 30 * dt);
      if (!p.dead && (!p.downed || p.selfRevive)) anyUp = true;
    }
    if (this.state !== 'over' && anyPlayer) {
      // game is lost when nobody is standing and nobody can get themselves up
      let standing = players.length > 0;
      if (!standing && !anyUp) this.gameOver();
    }

    if (this.state === 'inter') {
      if (anyPlayer) this.timer -= dt;
      if (this.timer <= 0) this.startWave();
    } else if (this.state === 'active') {
      // spawning
      this.spawnT -= dt;
      const cap = Math.min(30, 12 + this.wave + (this.players.size - 1) * 4);
      if (this.spawnQueue.length && this.spawnT <= 0 && this.enemies.length < cap) {
        this.spawnEnemy(this.spawnQueue.shift());
        this.spawnT = rnd(0.35, 1.2) * Math.max(0.45, 1 - this.wave * 0.03);
      }
      if (!this.spawnQueue.length && !this.enemies.length) this.endWave();
    }

    // nav
    this.flowT -= dt;
    if (this.flowT <= 0) { this.flowT = 0.35; this.buildFlow(); }

    if (this.state !== 'over') {
      this.tickEnemies(dt, players);
      this.tickProjectiles(dt);
      this.tickSupport(dt);
    }

    const events = this.events;
    this.events = [];
    return events;
  }

  gameOver() {
    this.state = 'over';
    const stats = [];
    for (const p of this.players.values()) stats.push({ id: p.id, name: p.name, kills: p.kills, heads: p.heads, earned: p.earned, downs: p.downs });
    this.ev({ t: 'gameover', wave: this.wave, stats });
  }

  tickEnemies(dt, players) {
    const es = this.enemies;
    const accMul = Math.min(1.6, 1 + this.wave * 0.025);
    for (let i = 0; i < es.length; i++) {
      const e = es[i], def = ENEMIES[e.type];
      // target: nearest standing player
      let tgt = null, td = 1e9;
      for (const p of players) { const d = Math.hypot(p.x - e.x, p.z - e.z); if (d < td) { td = d; tgt = p; } }
      e.shot = 0;
      if (!tgt) { e.st = 0; continue; }

      e.losT -= dt;
      if (e.losT <= 0) {
        e.losT = 0.22;
        e.los = td < 70 && !segmentBlocked(e.x, 1.45 * def.scale, e.z, tgt.x, tgt.y + (tgt.cr ? 0.8 : 1.35), tgt.z);
        if (!e.los) e.seen = 0;
      }
      if (e.los) e.seen += dt;

      const dxT = tgt.x - e.x, dzT = tgt.z - e.z;
      let mvx = 0, mvz = 0, speed = e.spd;
      const inYard = Math.abs(e.x) < HALF - 1 && Math.abs(e.z) < HALF - 1;

      if (def.melee) {
        // rushers go straight for the player once they can see them
        const fd = (e.los && td < 6) ? [dxT / td, dzT / td] : this.flowDir(e.x, e.z);
        if (td > 1.1 && fd) { mvx = fd[0]; mvz = fd[1]; }
        e.st = 0;
        e.cd -= dt;
        if (td < def.range && Math.abs(tgt.y) < 1.7 && e.cd <= 0) {
          e.cd = 0.85; e.st = 2; e.shot = 1;
          this.damagePlayer(tgt, def.dmg, e.x, e.z);
        }
        if (td < 3) e.yaw = Math.atan2(dxT, dzT);
      } else {
        const engage = e.los && td < def.range && inYard;
        const tooFar = td > def.range * 0.55;
        if (!engage || (tooFar && e.burst <= 0)) {
          const fd = this.flowDir(e.x, e.z);
          if (fd) { mvx = fd[0]; mvz = fd[1]; }
          if (engage) speed *= 0.6;
        } else {
          // hold position, strafe a bit
          e.strafeT -= dt;
          if (e.strafeT <= 0) { e.strafeT = rnd(0.8, 2.2); e.strafe = Math.random() < 0.3 ? 0 : (Math.random() < 0.5 ? 1 : -1); }
          mvx = (dzT / td) * e.strafe; mvz = (-dxT / td) * e.strafe; speed *= 0.35;
        }
        e.st = engage ? 1 : 0;
        if (engage) {
          e.yaw = Math.atan2(dxT, dzT);
          e.cd -= dt;
          if (e.seen > 0.45 && e.cd <= 0) {
            if (e.burst <= 0) e.burst = rint(def.burst[0], def.burst[1]);
            e.burst--;
            e.cd = e.burst > 0 ? 60 / def.rpm : rnd(def.pause[0], def.pause[1]);
            e.shot = 1;
            // hit roll
            let acc = def.acc * accMul * (1 - 0.6 * Math.min(1, td / (def.range * 1.3)));
            if (tgt.cr) acc *= 0.75;
            const hit = Math.random() < acc;
            const my = 1.38 * def.scale;
            let ex, ey, ez;
            if (hit) { ex = tgt.x; ey = tgt.y + (tgt.cr ? 0.7 : 1.2); ez = tgt.z; this.damagePlayer(tgt, def.dmg * (1 + this.wave * 0.02), e.x, e.z); }
            else {
              const dx = dxT + rnd(-1.2, 1.2), dy = (tgt.y + 1.3 - my) + rnd(-0.6, 0.9), dz = dzT + rnd(-1.2, 1.2);
              const l = Math.hypot(dx, dy, dz) || 1;
              const h = raycastWorld(e.x, my, e.z, dx / l || 1e-9, dy / l || 1e-9, dz / l || 1e-9, 90);
              const t = Math.min(h.t, 90);
              ex = e.x + dx / l * t; ey = my + dy / l * t; ez = e.z + dz / l * t;
            }
            this.ev({ t: 'tracer', k: 'e', eid: e.id, et: e.type, o: [r2(e.x + Math.sin(e.yaw) * 0.6), r2(my), r2(e.z + Math.cos(e.yaw) * 0.6)], e: [r2(ex), r2(ey), r2(ez)], hit });
          }
        } else { e.burst = 0; }
      }

      if (mvx || mvz) {
        if (e.st !== 1) {
          // smooth turning toward move direction
          const want = Math.atan2(mvx, mvz);
          let d = want - e.yaw; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI;
          e.yaw += d * Math.min(1, dt * 10);
        }
        e.x += mvx * speed * dt; e.z += mvz * speed * dt;
      }
      e.mv = (mvx || mvz) ? 1 : 0;
    }
    // separation + world collision
    for (let i = 0; i < es.length; i++) {
      const a = es[i], ra = 0.38 * ENEMIES[a.type].scale;
      for (let j = i + 1; j < es.length; j++) {
        const b = es[j];
        const dx = b.x - a.x, dz = b.z - a.z, d2 = dx * dx + dz * dz, rr = ra + 0.38 * ENEMIES[b.type].scale;
        if (d2 < rr * rr && d2 > 1e-6) {
          const d = Math.sqrt(d2), p = (rr - d) / d * 0.5;
          a.x -= dx * p; a.z -= dz * p; b.x += dx * p; b.z += dz * p;
        }
      }
      [a.x, a.z] = collideCircle(a.x, a.z, ra, 0, 1.7, 0.3);
    }
  }

  tickProjectiles(dt) {
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const p = this.projectiles[i];
      p.fuse -= dt;
      let boom = p.fuse <= 0;
      if (p.k === 'frag') {
        p.vy -= 16 * dt;
        const nx = p.x + p.vx * dt, ny = p.y + p.vy * dt, nz = p.z + p.vz * dt;
        if (pointInBox(nx, p.y, p.z)) p.vx *= -0.35; else p.x = nx;
        if (pointInBox(p.x, p.y, nz)) p.vz *= -0.35; else p.z = nz;
        if (ny < 0.08 || pointInBox(p.x, ny, p.z)) {
          if (p.vy < 0) { p.vx *= 0.6; p.vz *= 0.6; }
          p.vy *= -0.35;
          if (Math.abs(p.vy) < 0.6) p.vy = 0;
          if (ny < 0.08) p.y = 0.08;
        } else p.y = ny;
      } else {
        const steps = 3;
        for (let s = 0; s < steps && !boom; s++) {
          p.x += p.vx * dt / steps; p.y += p.vy * dt / steps; p.z += p.vz * dt / steps;
          if (p.y < 0.05 || pointInBox(p.x, p.y, p.z) || Math.abs(p.x) > 90 || Math.abs(p.z) > 90 || p.y > 80) boom = true;
          for (const e of this.enemies) if (Math.abs(e.x - p.x) < 0.6 && Math.abs(e.z - p.z) < 0.6 && p.y < 2.1) boom = true;
        }
      }
      if (boom) {
        this.projectiles.splice(i, 1);
        if (p.k === 'frag') this.explode(p.x, p.y + 0.2, p.z, 7, 260, p.owner, 'frag');
        else this.explode(p.x, Math.max(0.2, p.y), p.z, 6.5, 420, p.owner, 'rocket');
      }
    }
    for (let i = this.mines.length - 1; i >= 0; i--) {
      const m = this.mines[i];
      if (m.arm > 0) { m.arm -= dt; continue; }
      for (const e of this.enemies) {
        if (Math.hypot(e.x - m.x, e.z - m.z) < 2.3) {
          this.mines.splice(i, 1);
          this.explode(m.x, m.y + 0.3, m.z, 6, 320, m.owner, 'mine');
          break;
        }
      }
    }
  }

  tickSupport(dt) {
    // sentry guns
    for (let i = this.turrets.length - 1; i >= 0; i--) {
      const t = this.turrets[i];
      t.life -= dt; t.cd -= dt; t.fire = 0;
      if (t.life <= 0) { this.turrets.splice(i, 1); this.ev({ t: 'fx', k: 'turretGone', x: t.x, z: t.z }); continue; }
      let tgt = null, td = 30;
      for (const e of this.enemies) {
        const d = Math.hypot(e.x - t.x, e.z - t.z);
        if (d < td && !segmentBlocked(t.x, 1.15, t.z, e.x, 1.2, e.z)) { td = d; tgt = e; }
      }
      if (tgt) {
        const want = Math.atan2(tgt.x - t.x, tgt.z - t.z);
        let d = want - t.yaw; while (d > Math.PI) d -= 2 * Math.PI; while (d < -Math.PI) d += 2 * Math.PI;
        t.yaw += Math.max(-dt * 5, Math.min(dt * 5, d));
        if (Math.abs(d) < 0.25 && t.cd <= 0) {
          t.cd = 0.11; t.fire = 1;
          const hit = Math.random() < 0.8;
          this.ev({ t: 'tracer', k: 't', o: [r2(t.x + Math.sin(t.yaw) * 0.7), 1.15, r2(t.z + Math.cos(t.yaw) * 0.7)], e: [r2(tgt.x + (hit ? 0 : rnd(-1, 1))), hit ? 1.2 : rnd(0, 2), r2(tgt.z + (hit ? 0 : rnd(-1, 1)))] });
          if (hit) this.damageEnemy(tgt, 22, this.players.get(t.owner), { src: 'turret' });
        }
      }
    }
    // gunship drones
    for (let i = this.drones.length - 1; i >= 0; i--) {
      const d = this.drones[i];
      d.life -= dt; d.cd -= dt; d.a += dt * 0.35;
      d.x = Math.sin(d.a) * 30; d.z = Math.cos(d.a) * 30; d.y = 30;
      if (d.life <= 0) { this.drones.splice(i, 1); this.ev({ t: 'msg', text: 'Gunship leaving the area' }); continue; }
      if (d.cd <= 0 && this.enemies.length) {
        let tgt = null;
        for (let k = 0; k < 6 && !tgt; k++) {
          const e = this.enemies[rint(0, this.enemies.length - 1)];
          if (!segmentBlocked(d.x, d.y, d.z, e.x, 1.2, e.z)) tgt = e;
        }
        d.cd = tgt ? 0.13 : 0.4;
        if (tgt) {
          d.burst = (d.burst || 0) + 1;
          if (d.burst > 14) { d.burst = 0; d.cd = 1.1; }
          const hit = Math.random() < 0.7;
          this.ev({ t: 'tracer', k: 'd', o: [r2(d.x), r2(d.y - 1), r2(d.z)], e: [r2(tgt.x + (hit ? 0 : rnd(-1.5, 1.5))), hit ? 1 : 0, r2(tgt.z + (hit ? 0 : rnd(-1.5, 1.5)))] });
          if (hit) this.damageEnemy(tgt, 55, this.players.get(d.owner), { src: 'drone' });
        }
      }
    }
    // airstrikes
    for (let i = this.strikes.length - 1; i >= 0; i--) {
      const s = this.strikes[i];
      s.t -= dt;
      if (s.t > 0) continue;
      s.gap -= dt;
      while (s.gap <= 0 && s.n < s.count) {
        const off = (s.n - (s.count - 1) / 2) * s.spacing;
        const x = s.x + Math.sin(s.ang) * off + rnd(-1.5, 1.5), z = s.z + Math.cos(s.ang) * off + rnd(-1.5, 1.5);
        this.explode(x, 0.5, z, 9.5, 700, s.owner, 'strike');
        s.n++; s.gap += 0.14;
      }
      if (s.n >= s.count) this.strikes.splice(i, 1);
    }
  }

  // ------------------------------------------------------------------ snapshot
  snapshot() {
    const players = [];
    for (const p of this.players.values()) {
      players.push({
        id: p.id, n: p.name, x: r2(p.x), y: r2(p.y), z: r2(p.z), yaw: r2(p.yaw), pitch: r2(p.pitch), cr: p.cr,
        hp: Math.ceil(p.hp), ar: Math.ceil(p.armor), $: p.money, w: p.weapons, cur: p.cur, fr: p.frags, mi: p.mines, tu: p.turrets,
        sr: p.selfRevive, as: p.strikes, dr: p.drones, cb: p.carpets, dn: p.downed ? 1 : 0, dd: p.dead ? 1 : 0, dt: r2(p.downT), rp: r2(p.revP),
        k: p.kills, h: p.heads, e: p.earned, rd: p.ready ? 1 : 0, co: p.combo, tp: p.tp,
      });
    }
    return {
      t: 'snap', time: r2(this.time), wave: this.wave, cleared: this.cleared, state: this.state, timer: Math.ceil(this.timer),
      left: this.enemies.length + this.spawnQueue.length,
      players,
      enemies: this.enemies.map((e) => [e.id, e.type, r2(e.x), r2(e.z), r2(e.yaw), Math.max(0, Math.round(100 * e.hp / e.maxHp)), e.st, e.mv ? 1 : 0]),
      proj: this.projectiles.map((p) => [p.id, p.k, r2(p.x), r2(p.y), r2(p.z)]),
      mines: this.mines.map((m) => [m.id, r2(m.x), r2(m.y), r2(m.z), m.arm > 0 ? 0 : 1]),
      turrets: this.turrets.map((t) => [t.id, t.x, t.z, r2(t.yaw), Math.ceil(t.life)]),
      drones: this.drones.map((d) => [d.id, r2(d.x), r2(d.y), r2(d.z), r2(d.a), Math.ceil(d.life)]),
    };
  }
}
