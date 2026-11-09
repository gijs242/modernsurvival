// Procedural PBR-ish textures generated on canvases at startup (no external assets needed).
import * as THREE from 'three';

let seed = 1337;
const rand = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };

function canvas(size) { const c = document.createElement('canvas'); c.width = c.height = size; return [c, c.getContext('2d')]; }

// Tileable value noise
function noiseField(size, cells, octaves = 4) {
  const out = new Float32Array(size * size);
  let amp = 1, total = 0;
  for (let o = 0; o < octaves; o++) {
    const n = cells << o, g = new Float32Array(n * n);
    for (let i = 0; i < g.length; i++) g[i] = rand();
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const fx = x / size * n, fy = y / size * n;
      const x0 = Math.floor(fx), y0 = Math.floor(fy), tx = fx - x0, ty = fy - y0;
      const sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty);
      const a = g[(y0 % n) * n + x0 % n], b = g[(y0 % n) * n + (x0 + 1) % n];
      const c = g[((y0 + 1) % n) * n + x0 % n], d = g[((y0 + 1) % n) * n + (x0 + 1) % n];
      out[y * size + x] += amp * ((a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy);
    }
    total += amp; amp *= 0.5;
  }
  for (let i = 0; i < out.length; i++) out[i] /= total;
  return out;
}

function fromField(size, field, colorFn) {
  const [c, ctx] = canvas(size);
  const img = ctx.createImageData(size, size);
  for (let i = 0; i < size * size; i++) {
    const [r, g, b] = colorFn(field[i], i % size, (i / size) | 0);
    img.data[i * 4] = r; img.data[i * 4 + 1] = g; img.data[i * 4 + 2] = b; img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return [c, ctx];
}

// Normal map from a height canvas
function normalFrom(srcCanvas, strength = 2) {
  const s = srcCanvas.width, src = srcCanvas.getContext('2d').getImageData(0, 0, s, s).data;
  const [c, ctx] = canvas(s);
  const img = ctx.createImageData(s, s);
  const h = (x, y) => src[(((y + s) % s) * s + ((x + s) % s)) * 4] / 255;
  for (let y = 0; y < s; y++) for (let x = 0; x < s; x++) {
    const dx = (h(x - 1, y) - h(x + 1, y)) * strength, dy = (h(x, y - 1) - h(x, y + 1)) * strength;
    const l = Math.hypot(dx, dy, 1), i = (y * s + x) * 4;
    img.data[i] = (dx / l * 0.5 + 0.5) * 255; img.data[i + 1] = (dy / l * 0.5 + 0.5) * 255; img.data[i + 2] = (1 / l * 0.5 + 0.5) * 255; img.data[i + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return c;
}

function tex(c, repeat = 1, srgb = true) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  t.anisotropy = 8;
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

const mix = (a, b, t) => a + (b - a) * t;
const clamp = (v) => Math.max(0, Math.min(255, v));

export function makeTextures() {
  const T = {};
  const S = 512;

  // ---- Ground: dirty asphalt / packed dirt blend
  {
    const n = noiseField(S, 4, 6), d = noiseField(S, 2, 3), f = noiseField(S, 32, 2);
    const [c, ctx] = fromField(S, n, (v, x, y) => {
      const i = y * S + x, dirt = Math.max(0, Math.min(1, (d[i] - 0.45) * 4));
      const grain = (f[i] - 0.5) * 40 + (rand() - 0.5) * 22;
      const asphalt = 58 + v * 40 + grain, r = mix(asphalt, 112 + v * 50 + grain, dirt), g = mix(asphalt, 98 + v * 42 + grain, dirt), b = mix(asphalt + 2, 78 + v * 30 + grain, dirt);
      return [clamp(r), clamp(g), clamp(b)];
    });
    // cracks
    ctx.strokeStyle = 'rgba(20,20,20,0.55)';
    for (let k = 0; k < 26; k++) {
      ctx.lineWidth = 0.6 + rand() * 1.2; ctx.beginPath();
      let x = rand() * S, y = rand() * S; ctx.moveTo(x, y);
      for (let s = 0; s < 14; s++) { x += (rand() - 0.5) * 30; y += (rand() - 0.5) * 30; ctx.lineTo(x, y); }
      ctx.stroke();
    }
    // oil stains
    for (let k = 0; k < 10; k++) {
      const x = rand() * S, y = rand() * S, r = 10 + rand() * 40;
      const gr = ctx.createRadialGradient(x, y, 0, x, y, r);
      gr.addColorStop(0, 'rgba(15,12,10,0.35)'); gr.addColorStop(1, 'rgba(15,12,10,0)');
      ctx.fillStyle = gr; ctx.fillRect(x - r, y - r, r * 2, r * 2);
    }
    T.ground = tex(c, 22); T.groundN = tex(normalFrom(c, 3), 22, false);
  }

  // ---- Concrete
  {
    const n = noiseField(S, 8, 6), stain = noiseField(S, 2, 3);
    const [c, ctx] = fromField(S, n, (v, x, y) => {
      const st = stain[y * S + x], g = 128 + v * 55 + (rand() - 0.5) * 18 - Math.max(0, st - 0.55) * 120;
      return [clamp(g), clamp(g - 2), clamp(g - 6)];
    });
    // form-work seams
    ctx.fillStyle = 'rgba(40,40,40,0.35)';
    ctx.fillRect(0, 0, S, 3); ctx.fillRect(0, 0, 3, S);
    for (let k = 0; k < 40; k++) { ctx.fillStyle = `rgba(30,30,30,${0.2 + rand() * 0.3})`; ctx.beginPath(); ctx.arc(rand() * S, rand() * S, 1 + rand() * 2.5, 0, 7); ctx.fill(); }
    // rain streaks
    for (let k = 0; k < 60; k++) { ctx.fillStyle = `rgba(35,32,28,${rand() * 0.12})`; ctx.fillRect(rand() * S, 0, 1 + rand() * 4, S * rand()); }
    T.concrete = tex(c, 1); T.concreteN = tex(normalFrom(c, 2.5), 1, false);
  }

  // ---- Brick
  {
    const [c, ctx] = canvas(S);
    ctx.fillStyle = '#6b665e'; ctx.fillRect(0, 0, S, S);
    const bh = S / 16, bw = S / 8;
    for (let row = 0; row < 16; row++) for (let col = -1; col < 9; col++) {
      const x = col * bw + (row % 2 ? bw / 2 : 0), y = row * bh;
      const r = 120 + rand() * 50, g = 62 + rand() * 25, b = 46 + rand() * 18, v = rand() < 0.1 ? 0.7 : 1;
      ctx.fillStyle = `rgb(${r * v},${g * v},${b * v})`;
      ctx.fillRect(x + 2, y + 2, bw - 4, bh - 4);
      for (let k = 0; k < 30; k++) { ctx.fillStyle = `rgba(0,0,0,${rand() * 0.15})`; ctx.fillRect(x + 2 + rand() * (bw - 6), y + 2 + rand() * (bh - 6), 2, 2); }
    }
    const n = noiseField(S, 4, 3), img = ctx.getImageData(0, 0, S, S);
    for (let i = 0; i < S * S; i++) { const d = (n[i] - 0.5) * 50; img.data[i * 4] += d; img.data[i * 4 + 1] += d; img.data[i * 4 + 2] += d; }
    ctx.putImageData(img, 0, 0);
    // height for normals: mortar low
    const [h, hc] = canvas(S); hc.fillStyle = '#000'; hc.fillRect(0, 0, S, S); hc.fillStyle = '#fff';
    for (let row = 0; row < 16; row++) for (let col = -1; col < 9; col++) hc.fillRect(col * bw + (row % 2 ? bw / 2 : 0) + 3, row * bh + 3, bw - 6, bh - 6);
    T.brick = tex(c, 1); T.brickN = tex(normalFrom(h, 4), 1, false);
  }

  // ---- Corrugated container metal (greyscale, tinted by material colour)
  {
    const n = noiseField(S, 8, 5), rust = noiseField(S, 4, 5);
    const [c, ctx] = fromField(S, n, (v, x, y) => {
      const rib = Math.sin(x / S * Math.PI * 2 * 18) * 0.5 + 0.5, ru = Math.max(0, rust[y * S + x] - 0.58) * 3.5;
      const base = 170 + rib * 50 + v * 40 - 20;
      return [clamp(mix(base, 120, ru)), clamp(mix(base, 70, ru)), clamp(mix(base, 40, ru))];
    });
    for (let k = 0; k < 40; k++) { ctx.fillStyle = `rgba(60,30,10,${rand() * 0.25})`; ctx.fillRect(rand() * S, rand() * S * 0.3 + S * 0.7, 2 + rand() * 6, rand() * 120); }
    const [h] = fromField(S, n, (v, x) => { const r = Math.sin(x / S * Math.PI * 2 * 18) * 0.5 + 0.5; return [r * 255, r * 255, r * 255]; });
    T.metal = tex(c, 1); T.metalN = tex(normalFrom(h, 6), 1, false);
  }

  // ---- Sandbags
  {
    const [c, ctx] = canvas(256);
    ctx.fillStyle = '#4f4a3a'; ctx.fillRect(0, 0, 256, 256);
    for (let row = 0; row < 4; row++) for (let col = -1; col < 4; col++) {
      const x = col * 80 + (row % 2) * 40, y = row * 64;
      const gr = ctx.createRadialGradient(x + 40, y + 28, 4, x + 40, y + 32, 46);
      const t = 0.85 + rand() * 0.3;
      gr.addColorStop(0, `rgb(${158 * t},${146 * t},${112 * t})`); gr.addColorStop(1, `rgb(${92 * t},${84 * t},${62 * t})`);
      ctx.fillStyle = gr; ctx.beginPath(); ctx.ellipse(x + 40, y + 32, 39, 29, 0, 0, 7); ctx.fill();
    }
    const img = ctx.getImageData(0, 0, 256, 256);
    for (let i = 0; i < img.data.length; i += 4) { const d = (rand() - 0.5) * 26; img.data[i] += d; img.data[i + 1] += d; img.data[i + 2] += d; }
    ctx.putImageData(img, 0, 0);
    T.sand = tex(c, 1); T.sandN = tex(normalFrom(c, 3), 1, false);
  }

  // ---- Wood crate
  {
    const n = noiseField(256, 4, 4);
    const [c, ctx] = fromField(256, n, (v, x, y) => {
      const grain = Math.sin(y * 0.35 + v * 14) * 0.5 + 0.5, t = 0.75 + v * 0.4;
      return [clamp((128 + grain * 30) * t), clamp((98 + grain * 22) * t), clamp((62 + grain * 12) * t)];
    });
    ctx.strokeStyle = 'rgba(30,20,10,0.8)'; ctx.lineWidth = 3;
    for (let k = 0; k <= 5; k++) { ctx.beginPath(); ctx.moveTo(0, k * 51); ctx.lineTo(256, k * 51); ctx.stroke(); }
    ctx.lineWidth = 16; ctx.strokeStyle = 'rgba(90,64,36,1)'; ctx.strokeRect(8, 8, 240, 240);
    ctx.beginPath(); ctx.moveTo(16, 16); ctx.lineTo(240, 240); ctx.stroke();
    ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(20,12,6,0.9)'; ctx.strokeRect(1, 1, 254, 254); ctx.strokeRect(16, 16, 224, 224);
    ctx.fillStyle = 'rgba(30,30,30,0.7)'; ctx.font = 'bold 22px monospace'; ctx.fillText('AMMO 5.56', 70, 120);
    T.crate = tex(c, 1); T.crateN = tex(normalFrom(c, 2), 1, false);
  }

  // ---- Jersey barrier concrete with hazard stripes
  {
    const n = noiseField(256, 8, 5);
    const [c, ctx] = fromField(256, n, (v) => { const g = 150 + v * 60 + (rand() - 0.5) * 20; return [clamp(g), clamp(g - 3), clamp(g - 8)]; });
    for (let k = 0; k < 6; k++) { ctx.fillStyle = k % 2 ? 'rgba(30,30,30,0.85)' : 'rgba(220,170,20,0.85)'; ctx.save(); ctx.translate(k * 50 - 30, 0); ctx.transform(1, 0, 0.6, 1, 0, 0); ctx.fillRect(0, 200, 50, 40); ctx.restore(); }
    T.barrier = tex(c, 1);
  }

  // ---- Windows / facade for buildings (grid of dark windows over concrete)
  {
    const [c, ctx] = canvas(512);
    ctx.drawImage(T.concrete.image, 0, 0, 512, 512);
    for (let fy = 0; fy < 2; fy++) for (let fx = 0; fx < 2; fx++) {
      const x = 60 + fx * 256, y = 50 + fy * 256;
      ctx.fillStyle = '#2b2b2b'; ctx.fillRect(x - 6, y - 6, 148, 158);
      const broken = rand() < 0.4;
      const gr = ctx.createLinearGradient(x, y, x + 136, y + 146);
      gr.addColorStop(0, broken ? '#0b0c0d' : '#3d4a55'); gr.addColorStop(1, broken ? '#141516' : '#151a1f');
      ctx.fillStyle = gr; ctx.fillRect(x, y, 136, 146);
      ctx.fillStyle = '#3a3a38'; ctx.fillRect(x + 64, y, 8, 146); ctx.fillRect(x, y + 70, 136, 8);
      ctx.fillStyle = '#8a8680'; ctx.fillRect(x - 10, y + 150, 156, 10);
      ctx.fillStyle = 'rgba(30,25,20,0.35)'; ctx.fillRect(x - 4, y + 160, 148, 60 * rand());
    }
    const [h, hc] = canvas(512); hc.fillStyle = '#888'; hc.fillRect(0, 0, 512, 512);
    for (let fy = 0; fy < 2; fy++) for (let fx = 0; fx < 2; fx++) { hc.fillStyle = '#222'; hc.fillRect(54 + fx * 256, 44 + fy * 256, 148, 158); hc.fillStyle = '#ddd'; hc.fillRect(50 + fx * 256, 200 + fy * 256, 156, 10); }
    T.facade = tex(c, 1); T.facadeN = tex(normalFrom(h, 3), 1, false);
  }

  // ---- Camo patterns for soldier fabrics
  const camo = (cols) => {
    const S2 = 128, a = noiseField(S2, 4, 3), b = noiseField(S2, 6, 3);
    const [c] = fromField(S2, a, (v, x, y) => { const w = b[y * S2 + x]; const k = v > 0.56 ? 1 : w > 0.55 ? 2 : v < 0.42 ? 3 : 0; return cols[k]; });
    return tex(c, 2);
  };
  T.camoDesert = camo([[150, 132, 100], [112, 92, 66], [176, 160, 124], [90, 80, 60]]);
  T.camoWood = camo([[80, 88, 60], [52, 58, 40], [106, 100, 72], [36, 34, 28]]);
  T.camoUrban = camo([[78, 80, 84], [50, 52, 56], [110, 112, 114], [30, 31, 34]]);
  T.camoBlack = camo([[40, 40, 42], [28, 28, 30], [56, 55, 52], [20, 20, 22]]);
  T.camoRed = camo([[70, 40, 36], [45, 30, 28], [96, 64, 52], [30, 22, 22]]);

  // ---- Fabric noise for normals
  {
    const n = noiseField(128, 32, 2);
    const [c] = fromField(128, n, (v) => [v * 255, v * 255, v * 255]);
    T.fabricN = tex(normalFrom(c, 1.5), 3, false);
  }

  // ---- Weapon metal (subtle brushed)
  {
    const [c, ctx] = canvas(128); ctx.fillStyle = '#808080'; ctx.fillRect(0, 0, 128, 128);
    for (let k = 0; k < 400; k++) { ctx.fillStyle = `rgba(${rand() < 0.5 ? 255 : 0},${rand() < 0.5 ? 255 : 0},255,${rand() * 0.06})`; ctx.fillRect(0, rand() * 128, 128, 1); }
    T.gunRough = tex(c, 2, false);
  }

  // ---- Particle sprites
  {
    const [c, ctx] = canvas(128);
    const gr = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.3, 'rgba(255,255,255,0.6)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, 128, 128);
    T.glow = new THREE.CanvasTexture(c); T.glow.colorSpace = THREE.SRGBColorSpace;
  }
  {
    const n = noiseField(128, 4, 4);
    const [c] = fromField(128, n, (v, x, y) => [255, 255, 255]);
    const ctx = c.getContext('2d'), img = ctx.getImageData(0, 0, 128, 128);
    for (let y = 0; y < 128; y++) for (let x = 0; x < 128; x++) {
      const d = Math.hypot(x - 64, y - 64) / 64, a = Math.max(0, 1 - d) * (0.5 + n[y * 128 + x] * 0.8);
      img.data[(y * 128 + x) * 4 + 3] = clamp(a * a * 255);
    }
    ctx.putImageData(img, 0, 0);
    T.smoke = new THREE.CanvasTexture(c); T.smoke.colorSpace = THREE.SRGBColorSpace;
  }
  {
    // muzzle flash star
    const [c, ctx] = canvas(128);
    ctx.translate(64, 64);
    for (let k = 0; k < 7; k++) {
      ctx.rotate(Math.PI * 2 / 7 + rand() * 0.3);
      const gr = ctx.createLinearGradient(0, 0, 60, 0);
      gr.addColorStop(0, 'rgba(255,240,200,1)'); gr.addColorStop(1, 'rgba(255,140,40,0)');
      ctx.fillStyle = gr; ctx.beginPath(); ctx.moveTo(0, -7); ctx.lineTo(40 + rand() * 24, 0); ctx.lineTo(0, 7); ctx.fill();
    }
    const gr = ctx.createRadialGradient(0, 0, 0, 0, 0, 30); gr.addColorStop(0, 'rgba(255,255,230,1)'); gr.addColorStop(1, 'rgba(255,180,80,0)');
    ctx.fillStyle = gr; ctx.fillRect(-30, -30, 60, 60);
    T.flash = new THREE.CanvasTexture(c); T.flash.colorSpace = THREE.SRGBColorSpace;
  }
  {
    // bullet hole decal
    const [c, ctx] = canvas(64);
    const gr = ctx.createRadialGradient(32, 32, 0, 32, 32, 30);
    gr.addColorStop(0, 'rgba(0,0,0,1)'); gr.addColorStop(0.18, 'rgba(10,10,10,0.95)'); gr.addColorStop(0.3, 'rgba(40,36,32,0.6)'); gr.addColorStop(1, 'rgba(60,55,50,0)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, 64, 64);
    T.hole = new THREE.CanvasTexture(c); T.hole.colorSpace = THREE.SRGBColorSpace;
  }
  {
    // scorch
    const [c, ctx] = canvas(128);
    const gr = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
    gr.addColorStop(0, 'rgba(0,0,0,0.9)'); gr.addColorStop(0.5, 'rgba(10,8,6,0.6)'); gr.addColorStop(1, 'rgba(20,16,12,0)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, 128, 128);
    T.scorch = new THREE.CanvasTexture(c); T.scorch.colorSpace = THREE.SRGBColorSpace;
  }
  {
    // blood
    const [c, ctx] = canvas(64);
    for (let k = 0; k < 14; k++) { ctx.fillStyle = `rgba(${90 + rand() * 40},0,0,${0.5 + rand() * 0.5})`; ctx.beginPath(); ctx.arc(32 + (rand() - 0.5) * 30, 32 + (rand() - 0.5) * 30, 2 + rand() * 9, 0, 7); ctx.fill(); }
    T.blood = new THREE.CanvasTexture(c); T.blood.colorSpace = THREE.SRGBColorSpace;
  }
  return T;
}

/** Text sign texture (used for armory station labels). */
export function signTexture(text, color = '#ff8a2a', sub = '') {
  const [c, ctx] = canvas(512);
  c.height = 128;
  ctx.fillStyle = '#121416'; ctx.fillRect(0, 0, 512, 128);
  ctx.strokeStyle = color; ctx.lineWidth = 6; ctx.strokeRect(6, 6, 500, 116);
  ctx.fillStyle = color; ctx.font = 'bold 44px "Arial Narrow", Arial, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(text.toUpperCase(), 256, sub ? 52 : 64);
  if (sub) { ctx.fillStyle = '#aab'; ctx.font = '24px Arial, sans-serif'; ctx.fillText(sub, 256, 96); }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 8;
  return t;
}
