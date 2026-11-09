// Builds the renderer, sky, lighting, post-processing and all static map geometry.
import * as THREE from 'three';
import { Sky } from 'three/addons/objects/Sky.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { BOXES, STATIONS, HALF } from '/shared/map.js';
import { CAT_NAMES } from '/shared/defs.js';
import { makeTextures, signTexture } from './textures.js';

export const SUN_DIR = new THREE.Vector3(-0.55, 0.42, -0.72).normalize();

const GradeShader = {
  uniforms: { tDiffuse: { value: null }, time: { value: 0 }, hurt: { value: 0 }, vig: { value: 0.32 } },
  vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform float time; uniform float hurt; uniform float vig; varying vec2 vUv;
    float rnd(vec2 p){ return fract(sin(dot(p, vec2(12.9898,78.233)) + time) * 43758.5453); }
    void main(){
      vec4 c = texture2D(tDiffuse, vUv);
      float l = dot(c.rgb, vec3(0.299,0.587,0.114));
      c.rgb = mix(vec3(l), c.rgb, 0.88 - hurt * 0.5);          // slight desaturation, more when hurt
      c.rgb = (c.rgb - 0.5) * 1.07 + 0.5;                       // contrast
      c.rgb *= vec3(1.02, 1.0, 0.96);                           // warm grade
      vec2 d = vUv - 0.5;
      float v = smoothstep(0.85, 0.2, length(d) * (1.0 + hurt * 0.6));
      c.rgb *= mix(1.0 - vig, 1.0, v);
      c.rgb = mix(c.rgb, vec3(0.45, 0.0, 0.0), hurt * (1.0 - v) * 0.85);
      c.rgb += (rnd(vUv * 731.0) - 0.5) * 0.028;                // film grain
      gl_FragColor = vec4(clamp(c.rgb, 0.0, 1.0), 1.0);
    }`,
};

/** Box geometry with world-scaled UVs (tile metres per texture repeat). */
function boxGeo(w, h, d, tile = 4, tileV = tile) {
  const g = new THREE.BoxGeometry(w, h, d);
  if (!tile) return g;
  const uv = g.attributes.uv;
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) {
    const i = f * 4 + k;
    uv.setXY(i, uv.getX(i) * dims[f][0] / tile, uv.getY(i) * dims[f][1] / (f === 2 || f === 3 ? tile : tileV));
  }
  return g;
}

export class World {
  constructor(canvas, quality = 'high') {
    this.quality = quality;
    const r = this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance' });
    r.setPixelRatio(Math.min(devicePixelRatio, quality === 'low' ? 1 : 1.5));
    r.setSize(innerWidth, innerHeight);
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 0.9;
    r.shadowMap.enabled = quality !== 'low';
    r.shadowMap.type = THREE.PCFSoftShadowMap;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(75, innerWidth / innerHeight, 0.05, 900);
    this.scene.add(this.camera);
    // Separate scene for the first-person weapon so it never clips into walls.
    this.vmScene = new THREE.Scene();
    this.vmCamera = new THREE.PerspectiveCamera(58, innerWidth / innerHeight, 0.01, 10);

    this.T = makeTextures();
    this.buildSky();
    this.buildLights();
    this.buildGround();
    this.buildMap();
    this.buildBackdrop();
    this.buildPost();

    addEventListener('resize', () => this.resize());
  }

  resize() {
    const w = innerWidth, h = innerHeight;
    this.renderer.setSize(w, h);
    this.composer.setSize(w, h);
    this.camera.aspect = this.vmCamera.aspect = w / h;
    this.camera.updateProjectionMatrix(); this.vmCamera.updateProjectionMatrix();
  }

  buildSky() {
    const sky = new Sky();
    sky.scale.setScalar(4000);
    const u = sky.material.uniforms;
    u.turbidity.value = 8; u.rayleigh.value = 1.6; u.mieCoefficient.value = 0.006; u.mieDirectionalG.value = 0.86;
    u.sunPosition.value.copy(SUN_DIR).multiplyScalar(1000);
    this.scene.add(sky);
    // Environment lighting from the sky
    const pm = new THREE.PMREMGenerator(this.renderer);
    const envScene = new THREE.Scene();
    const sky2 = sky.clone(); envScene.add(sky2);
    const ground = new THREE.Mesh(new THREE.CircleGeometry(3000, 16).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0x4a4038 }));
    ground.position.y = -10; envScene.add(ground);
    this.env = pm.fromScene(envScene, 0.02).texture;
    this.scene.environment = this.env;
    this.scene.environmentIntensity = 0.55;
    this.vmScene.environment = this.env;
    this.vmScene.environmentIntensity = 0.55;
    this.scene.fog = new THREE.FogExp2(0xb7a990, 0.0085);
  }

  buildLights() {
    const sun = this.sun = new THREE.DirectionalLight(0xffdcb0, 3.2);
    sun.position.copy(SUN_DIR).multiplyScalar(120);
    sun.castShadow = this.quality !== 'low';
    const s = this.quality === 'high' ? 4096 : 2048;
    sun.shadow.mapSize.set(s, s);
    const c = sun.shadow.camera; c.left = c.bottom = -62; c.right = c.top = 62; c.near = 10; c.far = 260;
    sun.shadow.bias = -0.0004; sun.shadow.normalBias = 0.04;
    this.scene.add(sun, sun.target);
    this.scene.add(new THREE.HemisphereLight(0xbfd2e8, 0x5a4a38, 0.55));
    // viewmodel lighting
    const vs = new THREE.DirectionalLight(0xffdcb0, 2.4); vs.position.copy(SUN_DIR);
    this.vmScene.add(vs, new THREE.HemisphereLight(0xbfd2e8, 0x5a4a38, 0.9));
    this.vmSun = vs;
  }

  buildGround() {
    const T = this.T;
    const mat = new THREE.MeshStandardMaterial({ map: T.ground, normalMap: T.groundN, normalScale: new THREE.Vector2(0.6, 0.6), roughness: 0.93, color: 0xd8d0c4 });
    const g = new THREE.PlaneGeometry(600, 600).rotateX(-Math.PI / 2);
    g.attributes.uv.array.forEach((v, i, a) => { a[i] = v * 600 / 8; });
    T.ground.repeat.set(1, 1); T.groundN.repeat.set(1, 1);
    const ground = new THREE.Mesh(g, mat);
    ground.receiveShadow = true;
    this.scene.add(ground);
    // painted road lines across the yard
    const lm = new THREE.MeshStandardMaterial({ color: 0xc9b46a, roughness: 0.8, transparent: true, opacity: 0.55, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 });
    const lines = [];
    for (let z = -40; z < 40; z += 5) lines.push(new THREE.PlaneGeometry(0.18, 2.6).rotateX(-Math.PI / 2).translate(-0.2 + 0, 0.01, z));
    for (let x = -40; x < 40; x += 5) if (Math.abs(x) > 3) lines.push(new THREE.PlaneGeometry(2.6, 0.18).rotateX(-Math.PI / 2).translate(x, 0.01, 0.2));
    const lmesh = new THREE.Mesh(mergeGeometries(lines), lm); lmesh.receiveShadow = true; this.scene.add(lmesh);
    // the armory pad
    const pad = new THREE.Mesh(boxGeo(18, 0.06, 11, 3), new THREE.MeshStandardMaterial({ map: T.concrete, normalMap: T.concreteN, roughness: 0.85, color: 0x9a9690 }));
    pad.position.set(0, 0.03, -21); pad.receiveShadow = true; this.scene.add(pad);
  }

  buildMap() {
    const T = this.T;
    const mats = {
      wall: new THREE.MeshStandardMaterial({ map: T.concrete, normalMap: T.concreteN, roughness: 0.9, color: 0xc4bfb6 }),
      bunker: new THREE.MeshStandardMaterial({ map: T.concrete, normalMap: T.concreteN, roughness: 0.9, color: 0x9d9d94 }),
      brick: new THREE.MeshStandardMaterial({ map: T.brick, normalMap: T.brickN, roughness: 0.92 }),
      facade: [0xd8d2c6, 0xb9b0a3, 0xc8c2b8, 0xa8a49c].map((c) => new THREE.MeshStandardMaterial({ map: T.facade, normalMap: T.facadeN, roughness: 0.88, color: c })),
      roof: new THREE.MeshStandardMaterial({ map: T.concrete, normalMap: T.concreteN, roughness: 0.95, color: 0x6e6a64 }),
      sand: new THREE.MeshStandardMaterial({ map: T.sand, normalMap: T.sandN, roughness: 1 }),
      crate: new THREE.MeshStandardMaterial({ map: T.crate, normalMap: T.crateN, roughness: 0.85 }),
      barrier: new THREE.MeshStandardMaterial({ map: T.barrier, roughness: 0.9 }),
      container: [0x8b2e22, 0x1f4e7a, 0x2f5a35, 0xb8611e, 0x6c6e70].map((c) => new THREE.MeshStandardMaterial({ map: T.metal, normalMap: T.metalN, color: c, roughness: 0.62, metalness: 0.55 })),
      dark: new THREE.MeshStandardMaterial({ color: 0x1b1c1e, roughness: 0.6, metalness: 0.6 }),
      steel: new THREE.MeshStandardMaterial({ color: 0x5a5d60, roughness: 0.45, metalness: 0.85 }),
      glass: new THREE.MeshStandardMaterial({ color: 0x0e1418, roughness: 0.08, metalness: 0.9 }),
      tire: new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.95 }),
    };
    this.mats = mats;
    const groups = new Map();
    const add = (mat, geo) => { if (!groups.has(mat)) groups.set(mat, []); groups.get(mat).push(geo); };

    for (const b of BOXES) {
      const w = b.x1 - b.x0, d = b.z1 - b.z0, h = b.y1 - b.y0, cx = (b.x0 + b.x1) / 2, cz = (b.z0 + b.z1) / 2, cy = (b.y0 + b.y1) / 2;
      switch (b.kind) {
        case 'wall': {
          add(mats.wall, boxGeo(w, h, d, 4).translate(cx, cy, cz));
          add(mats.roof, boxGeo(w + 0.25, 0.25, d + 0.25, 2).translate(cx, b.y1 + 0.12, cz));
          // buttresses every 8 m on the inside
          const along = w > d ? 'x' : 'z', len = Math.max(w, d);
          for (let t = -len / 2 + 2; t < len / 2 - 1; t += 8) {
            const g = along === 'x' ? boxGeo(0.5, h, d + 0.5, 2) : boxGeo(w + 0.5, h, 0.5, 2);
            add(mats.wall, g.translate(cx + (along === 'x' ? t : 0), cy, cz + (along === 'z' ? t : 0)));
          }
          break;
        }
        case 'bunker': case 'pillar': add(mats.bunker, boxGeo(w, h, d, 3).translate(cx, cy, cz)); break;
        case 'roof': add(mats.bunker, boxGeo(w, h, d, 3).translate(cx, cy, cz)); break;
        case 'building': {
          const fm = mats.facade[b.tint || 0];
          const floors = Math.max(1, Math.round(h / 3.5));
          // facade texture: 1 tile = 2 windows ~ 7 m wide, 7 m tall
          add(b.tint % 2 ? mats.brick : fm, boxGeo(w, h, d, b.tint % 2 ? 3 : 7).translate(cx, cy, cz));
          add(mats.roof, boxGeo(w + 0.3, 0.6, 0.3, 2).translate(cx, b.y1 + 0.3, b.z0));
          add(mats.roof, boxGeo(w + 0.3, 0.6, 0.3, 2).translate(cx, b.y1 + 0.3, b.z1));
          add(mats.roof, boxGeo(0.3, 0.6, d, 2).translate(b.x0, b.y1 + 0.3, cz));
          add(mats.roof, boxGeo(0.3, 0.6, d, 2).translate(b.x1, b.y1 + 0.3, cz));
          // rooftop AC units / water tank
          if (w > 8) {
            add(mats.steel, boxGeo(1.6, 1.0, 1.2, 0).translate(cx - w / 4, b.y1 + 0.5, cz));
            add(mats.steel, boxGeo(1.6, 1.0, 1.2, 0).translate(cx + w / 5, b.y1 + 0.5, cz - d / 5));
          }
          // ledges between floors
          for (let f = 1; f < floors; f++) add(mats.roof, boxGeo(w + 0.2, 0.18, d + 0.2, 3).translate(cx, f * (h / floors), cz));
          // a door on each face pointing into the yard
          const door = (x, z, rot) => { const g = boxGeo(1.4, 2.3, 0.12, 0).translate(0, 1.15, 0); if (rot) g.rotateY(Math.PI / 2); add(mats.dark, g.translate(x, 0, z)); };
          if (Math.abs(cz) > Math.abs(cx)) door(cx, cz > 0 ? b.z0 - 0.04 : b.z1 + 0.04, 0); else door(cx > 0 ? b.x0 - 0.04 : b.x1 + 0.04, cz, 1);
          break;
        }
        case 'container': {
          const m = mats.container[b.c % mats.container.length];
          const g = boxGeo(b.rot ? d : w, h, b.rot ? w : d, 0);
          // UVs: stretch rib texture along length, ~12 ribs per 6 m
          const uv = g.attributes.uv;
          for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 2.4, uv.getY(i));
          if (b.rot) g.rotateY(Math.PI / 2);
          add(m, g.translate(cx, cy, cz));
          // corner castings & door bars
          const L = b.rot ? d : w;
          for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
            const cg = boxGeo(0.2, 0.2, 2.5, 0).translate(sx * (L / 2 - 0.08), sy * 1.2, 0);
            if (b.rot) cg.rotateY(Math.PI / 2);
            add(mats.dark, cg.translate(cx, b.y0 + h / 2, cz));
          }
          for (let k = -2; k <= 2; k += 1.3) {
            const bar = boxGeo(0.05, h * 0.9, 0.05, 0).translate(L / 2 + 0.03, 0, k * 0.4);
            if (b.rot) bar.rotateY(Math.PI / 2);
            add(mats.steel, bar.translate(cx, cy, cz));
          }
          break;
        }
        case 'barrier': {
          const shape = new THREE.Shape();
          shape.moveTo(-0.3, 0); shape.lineTo(0.3, 0); shape.lineTo(0.3, 0.1); shape.lineTo(0.12, 0.3); shape.lineTo(0.09, 0.95); shape.lineTo(-0.09, 0.95); shape.lineTo(-0.12, 0.3); shape.lineTo(-0.3, 0.1); shape.closePath();
          const g = new THREE.ExtrudeGeometry(shape, { depth: 2.4, bevelEnabled: false });
          g.translate(0, 0, -1.2);
          const uv = g.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 0.4 + 0.5, uv.getY(i) * 0.25);
          if (!b.rot) g.rotateY(Math.PI / 2);
          add(mats.barrier, g.translate(cx, 0, cz));
          break;
        }
        case 'sandbag': {
          // stacked rows, slightly rounded look via 3 layered boxes
          for (let row = 0; row < 3; row++) {
            const inset = row * 0.06, y = row * 0.33 + 0.165;
            add(mats.sand, boxGeo(Math.max(0.3, w - inset * 2), 0.32, Math.max(0.3, d - inset * 2), 0.9, 0.66).translate(cx, y, cz));
          }
          break;
        }
        case 'crate': add(mats.crate, boxGeo(w, h, d, 0).translate(cx, cy, cz)); break;
        case 'station': break;   // drawn separately below
        case 'car': this.addCar(b, add); break;
        case 'truck': this.addTruck(b, add); break;
        case 'lamp': {
          add(mats.steel, new THREE.CylinderGeometry(0.08, 0.12, h, 8).translate(cx, h / 2, cz));
          add(mats.steel, boxGeo(1.4, 0.08, 0.1, 0).translate(cx + 0.6, h - 0.1, cz));
          add(mats.dark, boxGeo(0.5, 0.15, 0.3, 0).translate(cx + 1.2, h - 0.2, cz));
          break;
        }
      }
    }
    for (const [mat, list] of groups) {
      const mesh = new THREE.Mesh(mergeGeometries(list.map((g) => g.index ? g.toNonIndexed() : g)), mat);
      mesh.castShadow = mesh.receiveShadow = true;
      this.scene.add(mesh);
    }
    this.buildArmory();
  }

  addCar(b, add) {
    const m = this.mats;
    const paints = [0x3c4a3a, 0x6b6156, 0x4a2a24, 0x2c3440];
    if (!this.carMats) this.carMats = paints.map((c) => new THREE.MeshStandardMaterial({ color: c, roughness: 0.55, metalness: 0.5, map: this.T.concrete }));
    const paint = this.carMats[b.c % 4];
    const cx = (b.x0 + b.x1) / 2, cz = (b.z0 + b.z1) / 2;
    const parts = [
      [paint, boxGeo(4.4, 0.62, 1.8, 0).translate(0, 0.62, 0)],
      [paint, boxGeo(2.2, 0.5, 1.6, 0).translate(-0.25, 1.15, 0)],
      [m.glass, boxGeo(2.24, 0.42, 1.5, 0).translate(-0.25, 1.15, 0)],
      [m.dark, boxGeo(4.45, 0.18, 1.82, 0).translate(0, 0.38, 0)],
    ];
    for (const [sx, sz] of [[-1.35, -0.82], [1.35, -0.82], [-1.35, 0.82], [1.35, 0.82]]) parts.push([m.tire, new THREE.CylinderGeometry(0.34, 0.34, 0.24, 14).rotateX(Math.PI / 2).translate(sx, 0.34, sz)]);
    for (const [mat, g] of parts) { if (b.rot) g.rotateY(Math.PI / 2); g.rotateY(b.c * 0.05); add(mat, g.translate(cx, 0, cz)); }
  }

  addTruck(b, add) {
    const m = this.mats;
    if (!this.truckMat) this.truckMat = new THREE.MeshStandardMaterial({ color: 0x4c5238, roughness: 0.7, metalness: 0.3, map: this.T.camoWood });
    const cx = (b.x0 + b.x1) / 2, cz = (b.z0 + b.z1) / 2;
    const parts = [
      [this.truckMat, boxGeo(2.2, 1.6, 2.4, 0).translate(-2.4, 1.6, 0)],
      [m.glass, boxGeo(0.06, 0.7, 2.0, 0).translate(-3.52, 2.0, 0)],
      [this.truckMat, boxGeo(4.8, 0.3, 2.5, 0).translate(1.1, 1.05, 0)],
      [this.truckMat, boxGeo(4.8, 0.9, 0.08, 0).translate(1.1, 1.6, 1.22)],
      [this.truckMat, boxGeo(4.8, 0.9, 0.08, 0).translate(1.1, 1.6, -1.22)],
      [m.crate, boxGeo(1.1, 1.1, 1.1, 0).translate(0.4, 1.75, 0.5)],
      [m.crate, boxGeo(1.1, 1.1, 1.1, 0).translate(1.7, 1.75, -0.4)],
      [m.dark, boxGeo(7, 0.3, 1.4, 0).translate(-0.2, 0.7, 0)],
    ];
    for (const [sx, sz] of [[-2.5, -1.1], [-2.5, 1.1], [1.2, -1.1], [1.2, 1.1], [2.5, -1.1], [2.5, 1.1]]) parts.push([m.tire, new THREE.CylinderGeometry(0.48, 0.48, 0.32, 16).rotateX(Math.PI / 2).translate(sx, 0.48, sz)]);
    for (const [mat, g] of parts) add(mat, g.translate(cx, 0, cz));
  }

  buildArmory() {
    const m = this.mats;
    this.stationMeshes = [];
    for (const s of STATIONS) {
      const g = new THREE.Group();
      g.position.set(s.x, 0, s.z);
      const counter = new THREE.Mesh(boxGeo(2.6, 1.0, 1.0, 0), m.dark); counter.position.y = 0.5;
      const top = new THREE.Mesh(boxGeo(2.7, 0.06, 1.1, 0), m.steel); top.position.y = 1.03;
      const col = new THREE.Color(s.color);
      // illuminated sign on the back wall
      const sign = new THREE.Mesh(new THREE.PlaneGeometry(2.6, 0.65), new THREE.MeshBasicMaterial({ map: signTexture(s.label, '#' + col.getHexString(), 'PRESS  E') }));
      sign.position.set(0, 2.55, -0.62);
      const strip = new THREE.Mesh(boxGeo(2.6, 0.05, 0.05, 0), new THREE.MeshStandardMaterial({ color: 0x000000, emissive: col, emissiveIntensity: 4 }));
      strip.position.set(0, 1.0, 0.52);
      // a rack with props behind the counter
      const rack = new THREE.Mesh(boxGeo(2.4, 1.2, 0.12, 0), m.steel); rack.position.set(0, 1.65, -0.6);
      g.add(counter, top, sign, strip, rack);
      for (let k = -1; k <= 1; k++) {
        const item = s.cat === 'weapons' ? new THREE.Mesh(boxGeo(0.12, 0.9, 0.08, 0), m.dark) : s.cat === 'equipment' ? new THREE.Mesh(new THREE.SphereGeometry(0.1, 10, 8), new THREE.MeshStandardMaterial({ color: 0x3b4430, roughness: 0.6 })) : new THREE.Mesh(boxGeo(0.4, 0.3, 0.06, 0), new THREE.MeshStandardMaterial({ color: 0x223, emissive: col, emissiveIntensity: 0.6 }));
        item.position.set(k * 0.7, s.cat === 'weapons' ? 1.65 : 1.3, -0.48);
        if (s.cat === 'equipment') item.position.y = 1.15;
        g.add(item);
      }
      const light = new THREE.PointLight(col, 6, 7, 2); light.position.set(0, 2.6, 0.6); g.add(light);
      // floor ring marking where to stand
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.75, 0.9, 40).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.6, depthWrite: false }));
      ring.position.set(0, 0.07, 1.6); g.add(ring);
      g.traverse((o) => { if (o.isMesh) { o.castShadow = o.receiveShadow = true; } });
      ring.castShadow = sign.castShadow = false;
      this.scene.add(g);
      this.stationMeshes.push({ s, ring, light });
    }
    // big ARMORY sign over the bunker front
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(6, 1.2), new THREE.MeshBasicMaterial({ map: signTexture('ARMORY', '#e8d07a', 'WEAPONS · EQUIPMENT · AIR SUPPORT'), toneMapped: false }));
    sign.position.set(0, 4.35, -22 + 2.95); this.scene.add(sign);
    const bracket = new THREE.Mesh(boxGeo(6.2, 1.4, 0.1, 0), m.dark); bracket.position.set(0, 4.35, -22 + 2.88); this.scene.add(bracket);
    // ceiling lights inside the armory
    for (const x of [-4.6, 0, 4.6]) {
      const l = new THREE.Mesh(boxGeo(1.4, 0.06, 0.2, 0), new THREE.MeshStandardMaterial({ color: 0, emissive: 0xfff2d8, emissiveIntensity: 3 }));
      l.position.set(x, 3.37, -23); this.scene.add(l);
    }
    const fill = new THREE.PointLight(0xfff0d0, 10, 12, 2); fill.position.set(0, 3.0, -22); this.scene.add(fill);
  }

  buildBackdrop() {
    // distant ruined city & hills beyond the walls, fog does the rest
    const T = this.T;
    const mats = [0xa59d90, 0x8f877c, 0xb4ad9f].map((c) => new THREE.MeshStandardMaterial({ map: T.facade, color: c, roughness: 0.95 }));
    const geos = [[], [], []];
    let s = 99;
    const r = () => { s = (s * 16807) % 2147483647; return s / 2147483647; };
    for (let i = 0; i < 90; i++) {
      const a = r() * Math.PI * 2, dist = 85 + r() * 140;
      const x = Math.cos(a) * dist, z = Math.sin(a) * dist;
      if (Math.abs(x) < HALF + 20 && Math.abs(z) < HALF + 20) continue;
      const w = 8 + r() * 18, d = 8 + r() * 18, h = 6 + r() * 30;
      const g = boxGeo(w, h, d, 7);
      g.rotateY(r() * 0.4 - 0.2);
      geos[i % 3].push(g.translate(x, h / 2, z));
    }
    geos.forEach((list, i) => { const mesh = new THREE.Mesh(mergeGeometries(list), mats[i]); mesh.castShadow = false; mesh.receiveShadow = true; this.scene.add(mesh); });
    // hills
    const hg = new THREE.CylinderGeometry(520, 600, 40, 64, 1, true);
    const pos = hg.attributes.position;
    for (let i = 0; i < pos.count; i++) if (pos.getY(i) > 0) pos.setY(i, pos.getY(i) + Math.sin(i * 0.7) * 14 + Math.sin(i * 0.23) * 22);
    hg.computeVertexNormals();
    const hills = new THREE.Mesh(hg, new THREE.MeshStandardMaterial({ color: 0x8a7a62, roughness: 1, side: THREE.BackSide }));
    hills.position.y = 4; this.scene.add(hills);
  }

  buildPost() {
    const r = this.renderer;
    const rt = new THREE.WebGLRenderTarget(innerWidth, innerHeight, { type: THREE.HalfFloatType, samples: this.quality === 'low' ? 0 : 4 });
    const c = this.composer = new EffectComposer(r, rt);
    c.addPass(new RenderPass(this.scene, this.camera));
    const vm = new RenderPass(this.vmScene, this.vmCamera);
    vm.clear = false; vm.clearDepth = true;
    c.addPass(vm);
    if (this.quality !== 'low') c.addPass(this.bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth / 2, innerHeight / 2), 0.35, 0.5, 0.92));
    c.addPass(new OutputPass());
    c.addPass(this.grade = new ShaderPass(GradeShader));
  }

  render(t, hurt) {
    this.grade.uniforms.time.value = t % 100;
    this.grade.uniforms.hurt.value = hurt;
    // keep shadow camera centred on the player for crisp shadows
    const p = this.camera.position;
    const sx = Math.round(p.x / 4) * 4, sz = Math.round(p.z / 4) * 4;
    this.sun.position.set(sx + SUN_DIR.x * 120, SUN_DIR.y * 120, sz + SUN_DIR.z * 120);
    this.sun.target.position.set(sx, 0, sz);
    this.vmCamera.position.copy(this.camera.position);
    this.vmCamera.quaternion.copy(this.camera.quaternion);
    this.composer.render();
  }
}

export { boxGeo, CAT_NAMES };
