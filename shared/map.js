// Map layout + collision helpers. Everything is axis-aligned boxes so the same
// data drives rendering, player collision, enemy navigation and line of sight.
// Coordinates: x = east, y = up, z = south. Units are metres.

export const HALF = 42;          // playable yard is -HALF..HALF
export const BOXES = [];
export const PROPS = [];         // purely decorative things the renderer may want (lamps etc.)

function box(kind, cx, cz, w, d, h, y0 = 0, extra = {}) {
  const b = { kind, x0: cx - w / 2, x1: cx + w / 2, z0: cz - d / 2, z1: cz + d / 2, y0, y1: y0 + h, ...extra };
  BOXES.push(b);
  return b;
}

// ---- Perimeter wall with four gates -------------------------------------
const GATE = 7, WT = 1.2, WH = 5.5;
const seg = (HALF - GATE / 2) ;
for (const s of [-1, 1]) {
  // north/south walls (two segments each, gap in the middle)
  box('wall', -(GATE / 2 + (seg + WT) / 2), s * (HALF + WT / 2), seg + WT, WT, WH);
  box('wall', (GATE / 2 + (seg + WT) / 2), s * (HALF + WT / 2), seg + WT, WT, WH);
  // east/west walls
  box('wall', s * (HALF + WT / 2), -(GATE / 2 + (seg + WT) / 2), WT, seg + WT, WH);
  box('wall', s * (HALF + WT / 2), (GATE / 2 + (seg + WT) / 2), WT, seg + WT, WH);
  // spawn alleys behind each gate (closed dead ends)
  const A = 11;
  box('wall', -(GATE / 2 + 0.6), s * (HALF + WT + A / 2), 1.2, A, WH);
  box('wall', (GATE / 2 + 0.6), s * (HALF + WT + A / 2), 1.2, A, WH);
  box('wall', 0, s * (HALF + WT + A + 0.6), GATE + 2.4, 1.2, WH);
  box('wall', s * (HALF + WT + A / 2), -(GATE / 2 + 0.6), A, 1.2, WH);
  box('wall', s * (HALF + WT + A / 2), (GATE / 2 + 0.6), A, 1.2, WH);
  box('wall', s * (HALF + WT + A + 0.6), 0, 1.2, GATE + 2.4, WH);
}

export const SPAWNS = [
  { x: 0, z: -(HALF + 9) }, { x: 0, z: HALF + 9 }, { x: -(HALF + 9), z: 0 }, { x: HALF + 9, z: 0 },
  { x: 2, z: -(HALF + 6) }, { x: -2, z: HALF + 6 }, { x: -(HALF + 6), z: 2 }, { x: HALF + 6, z: -2 },
];

export const PLAYER_SPAWNS = [{ x: 0, z: 4 }, { x: 2.5, z: 5 }, { x: -2.5, z: 5 }, { x: 0, z: 7 }, { x: 4, z: 7 }, { x: -4, z: 7 }];

// ---- The armory (the physical shop) --------------------------------------
// Open-fronted bunker on the north side of the yard, facing south.
const AZ = -22;
box('bunker', 0, AZ - 4.25, 15, 0.5, 3.4);            // back wall
box('bunker', -7.25, AZ - 1, 0.5, 6, 3.4);            // west wall
box('bunker', 7.25, AZ - 1, 0.5, 6, 3.4);             // east wall
box('roof', 0, AZ - 0.9, 16, 7.6, 0.35, 3.4);         // roof slab
box('pillar', -7.25, AZ + 2.4, 0.5, 0.5, 3.4);
box('pillar', 7.25, AZ + 2.4, 0.5, 0.5, 3.4);
export const STATIONS = [
  { cat: 'weapons', x: -4.6, z: AZ - 3.1, label: 'Weapon Armory', color: 0xff8a2a },
  { cat: 'equipment', x: 0, z: AZ - 3.1, label: 'Equipment Armory', color: 0x4fd06a },
  { cat: 'air', x: 4.6, z: AZ - 3.1, label: 'Air Support Armory', color: 0x4aa8ff },
];
for (const s of STATIONS) box('station', s.x, s.z, 2.6, 1.0, 1.0, 0, { cat: s.cat });

// ---- Buildings ------------------------------------------------------------
box('building', -27, -25, 16, 14, 8, 0, { tint: 0 });
box('building', 27, -26, 14, 12, 10.5, 0, { tint: 1 });
box('building', -28, 26, 14, 16, 7, 0, { tint: 2 });
box('building', 26, 27, 18, 12, 9, 0, { tint: 3 });
box('building', -24.5, -14.5, 6, 7, 4, 0, { tint: 1 });   // annex
box('building', 31, 17.5, 7, 7, 4.5, 0, { tint: 0 });

// ---- Shipping containers ---------------------------------------------------
const CL = 6.1, CW = 2.44, CH = 2.6;
const cont = (x, z, rot, c, y = 0) => box('container', x, z, rot ? CW : CL, rot ? CL : CW, CH, y, { rot, c });
cont(-11, 9, 0, 0); cont(-11, 11.6, 0, 1); cont(-10.5, 10.3, 0, 2, CH);
cont(13, -5, 1, 3); cont(15.6, -6, 1, 0);
cont(9, 17, 0, 2); cont(-19, -4, 1, 1);
cont(21, 6, 0, 4); cont(-3, 25, 0, 3); cont(-3, 27.6, 0, 0);
cont(0, -36, 0, 4); cont(-36, 6, 1, 2); cont(36, -8, 1, 1);

// ---- Low cover -------------------------------------------------------------
const barrier = (x, z, rot) => box('barrier', x, z, rot ? 0.6 : 2.4, rot ? 2.4 : 0.6, 0.95, 0, { rot });
barrier(-4, 0, 0); barrier(4, 0, 0); barrier(0, 12, 0); barrier(-6, 14, 1); barrier(6, 14, 1);
barrier(-14, -10, 0); barrier(14, 8, 1); barrier(18, -16, 0); barrier(-20, 14, 0); barrier(-8, -14, 1);
barrier(8, -14, 1); barrier(26, -2, 1); barrier(-30, 0, 1); barrier(0, 34, 0); barrier(-12, 30, 1); barrier(14, 30, 1);
barrier(-3, -34, 1); barrier(3, -34, 1); barrier(32, 4, 0); barrier(-32, -6, 0);

const sand = (x, z, w, d) => box('sandbag', x, z, w, d, 1.0);
sand(0, -6, 5, 0.9); sand(-2.9, -4.6, 0.9, 2.2); sand(2.9, -4.6, 0.9, 2.2);
sand(-16, 20, 4, 0.9); sand(18, 18, 0.9, 4); sand(20, -10, 4, 0.9); sand(-22, 4, 0.9, 4);

const crate = (x, z, s = 1.1, y = 0) => box('crate', x, z, s, s, s, y);
crate(-7.2, 9, 1.1); crate(-14.6, 11.6, 1.2); crate(-14.6, 10.3, 1.0); crate(16.5, -1.2, 1.1);
crate(12.6, 17, 1.1); crate(5.4, 16.6, 1.0); crate(-19, 0, 1.2); crate(-19, 1.2, 0.9, 0);
crate(24.6, 6, 1.1); crate(-6.8, 25, 1.1); crate(-6.8, 26.3, 1.2); crate(-6.6, 25.6, 0.9, 1.2);
crate(9, -20, 1.2); crate(10.3, -20.4, 1.0); crate(-10, -21, 1.2); crate(34, 34, 1.3); crate(-35, -36, 1.3);
crate(-35, 36, 1.2); crate(36, -37, 1.2); crate(-5.6, -19.3, 1.0); crate(5.8, -19.5, 1.1);

// ---- Wrecked vehicles (collision is one box, renderer draws something nicer)
const car = (x, z, rot, c) => box('car', x, z, rot ? 1.9 : 4.5, rot ? 4.5 : 1.9, 1.35, 0, { rot, c });
car(8, 5, 0, 0); car(-16, -18, 1, 1); car(22, -20, 0, 2); car(-24, 10, 1, 3); car(16, 36, 0, 1); car(-10, -30, 0, 2);
box('truck', -1, 18.5, 7.2, 2.6, 2.9, 0, { rot: 0 });

// ---- Lamps (decorative, thin collision) ------------------------------------
for (const [x, z] of [[-12, -12], [12, -12], [-12, 20], [12, 22], [-30, -8], [30, -12], [30, 10], [-32, 16]]) {
  box('lamp', x, z, 0.3, 0.3, 6.5);
  PROPS.push({ kind: 'lamp', x, z });
}

// ============================================================================
// Collision helpers
// ============================================================================

/** Push a vertical cylinder (feet at fy, height hh, radius r) out of all boxes. Returns [x, z]. */
export function collideCircle(x, z, r, fy = 0, hh = 1.8, step = 0.35) {
  for (let it = 0; it < 3; it++) {
    let moved = false;
    for (let i = 0; i < BOXES.length; i++) {
      const b = BOXES[i];
      if (b.y1 <= fy + step || b.y0 >= fy + hh) continue;
      const cx = x < b.x0 ? b.x0 : x > b.x1 ? b.x1 : x;
      const cz = z < b.z0 ? b.z0 : z > b.z1 ? b.z1 : z;
      const dx = x - cx, dz = z - cz;
      const d2 = dx * dx + dz * dz;
      if (d2 >= r * r) continue;
      if (d2 > 1e-9) {
        const d = Math.sqrt(d2), p = (r - d) / d;
        x += dx * p; z += dz * p;
      } else {
        // centre is inside the box: push out through the nearest face
        const l = x - b.x0, rr = b.x1 - x, t = z - b.z0, bt = b.z1 - z;
        const m = Math.min(l, rr, t, bt);
        if (m === l) x = b.x0 - r; else if (m === rr) x = b.x1 + r; else if (m === t) z = b.z0 - r; else z = b.z1 + r;
      }
      moved = true;
    }
    if (!moved) break;
  }
  return [x, z];
}

/** Highest surface under the circle that the feet (at fy) can stand on. */
export function groundHeight(x, z, r, fy, step = 0.35) {
  let g = 0;
  for (let i = 0; i < BOXES.length; i++) {
    const b = BOXES[i];
    if (b.y1 > fy + step || b.y1 <= g) continue;
    if (x + r * 0.7 < b.x0 || x - r * 0.7 > b.x1 || z + r * 0.7 < b.z0 || z - r * 0.7 > b.z1) continue;
    g = b.y1;
  }
  return g;
}

/** Lowest ceiling above the head. */
export function ceilingHeight(x, z, r, headY) {
  let c = Infinity;
  for (let i = 0; i < BOXES.length; i++) {
    const b = BOXES[i];
    if (b.y0 < headY - 0.2 || b.y0 >= c) continue;
    if (x + r < b.x0 || x - r > b.x1 || z + r < b.z0 || z - r > b.z1) continue;
    c = b.y0;
  }
  return c;
}

const _hit = { t: Infinity, nx: 0, ny: 1, nz: 0, box: null };
/** Ray vs world. Returns shared object {t, nx, ny, nz, box}; t = Infinity when nothing is hit within max. */
export function raycastWorld(ox, oy, oz, dx, dy, dz, max = 500) {
  let best = max, bn = 0, bs = 0, bb = null;
  const ix = 1 / dx, iy = 1 / dy, iz = 1 / dz;
  for (let i = 0; i < BOXES.length; i++) {
    const b = BOXES[i];
    let t1 = (b.x0 - ox) * ix, t2 = (b.x1 - ox) * ix, axis = 0, sgn;
    let tmin = t1 < t2 ? t1 : t2, tmax = t1 < t2 ? t2 : t1; sgn = t1 < t2 ? -1 : 1;
    t1 = (b.y0 - oy) * iy; t2 = (b.y1 - oy) * iy;
    let lo = t1 < t2 ? t1 : t2, hi = t1 < t2 ? t2 : t1;
    if (lo > tmin) { tmin = lo; axis = 1; sgn = t1 < t2 ? -1 : 1; }
    if (hi < tmax) tmax = hi;
    t1 = (b.z0 - oz) * iz; t2 = (b.z1 - oz) * iz;
    lo = t1 < t2 ? t1 : t2; hi = t1 < t2 ? t2 : t1;
    if (lo > tmin) { tmin = lo; axis = 2; sgn = t1 < t2 ? -1 : 1; }
    if (hi < tmax) tmax = hi;
    if (tmax < tmin || tmin < 0 || tmin >= best) continue;
    best = tmin; bn = axis; bs = sgn; bb = b;
  }
  _hit.nx = _hit.ny = _hit.nz = 0; _hit.box = bb;
  if (bb) { if (bn === 0) _hit.nx = bs; else if (bn === 1) _hit.ny = bs; else _hit.nz = bs; }
  // ground plane
  if (dy < 0) {
    const tg = -oy / dy;
    if (tg >= 0 && tg < best) { best = tg; _hit.nx = 0; _hit.ny = 1; _hit.nz = 0; _hit.box = null; bb = 'ground'; }
  }
  _hit.t = bb ? best : Infinity;
  return _hit;
}

/** True when the straight segment a->b is blocked by world geometry. */
export function segmentBlocked(ax, ay, az, bx, by, bz) {
  const dx = bx - ax, dy = by - ay, dz = bz - az;
  const len = Math.sqrt(dx * dx + dy * dy + dz * dz);
  if (len < 1e-6) return false;
  const h = raycastWorld(ax, ay, az, dx / len || 1e-9, dy / len || 1e-9, dz / len || 1e-9, len);
  return h.t < len - 0.05;
}

/** Is a point inside any solid box? */
export function pointInBox(x, y, z) {
  for (let i = 0; i < BOXES.length; i++) {
    const b = BOXES[i];
    if (x > b.x0 && x < b.x1 && y > b.y0 && y < b.y1 && z > b.z0 && z < b.z1) return b;
  }
  return null;
}

// ---- Navigation grid for the enemy flow field ------------------------------
export const NAV = (() => {
  const min = -(HALF + 14), size = (HALF + 14) * 2, n = size;         // 1 m cells
  const blocked = new Uint8Array(n * n);
  const R = 0.38;
  for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
    const x = min + i + 0.5, z = min + j + 0.5;
    for (const b of BOXES) {
      if (b.y0 > 1.6 || b.y1 < 0.4) continue;
      if (x > b.x0 - R && x < b.x1 + R && z > b.z0 - R && z < b.z1 + R) { blocked[j * n + i] = 1; break; }
    }
  }
  return { min, n, blocked };
})();
