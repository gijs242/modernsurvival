// All sounds are synthesised with WebAudio, so the game needs no audio assets.
export class Audio {
  constructor() {
    this.ctx = null;
    this.vol = 0.8;
  }

  init() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const ctx = this.ctx = new (window.AudioContext || window.webkitAudioContext)();
    this.master = ctx.createGain(); this.master.gain.value = this.vol;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.ratio.value = 6; comp.attack.value = 0.002; comp.release.value = 0.2;
    this.master.connect(comp).connect(ctx.destination);
    // short convolution reverb (outdoor slap-back)
    this.verb = ctx.createConvolver();
    const len = ctx.sampleRate * 1.6, ir = ctx.createBuffer(2, len, ctx.sampleRate);
    for (let c = 0; c < 2; c++) {
      const d = ir.getChannelData(c);
      for (let i = 0; i < len; i++) { const t = i / ctx.sampleRate; d[i] = (Math.random() * 2 - 1) * Math.exp(-t * 3.2) * (t > 0.06 ? 1 : 0.3); }
    }
    this.verb.buffer = ir;
    this.verbGain = ctx.createGain(); this.verbGain.gain.value = 0.35;
    this.verb.connect(this.verbGain).connect(this.master);
    // noise buffers
    const nb = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate), nd = nb.getChannelData(0);
    for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
    this.noise = nb;
    const bb = ctx.createBuffer(1, ctx.sampleRate * 2, ctx.sampleRate), bd = bb.getChannelData(0);
    let last = 0; for (let i = 0; i < bd.length; i++) { last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02; bd[i] = last * 3.5; }
    this.brown = bb;
    this.startAmbience();
  }

  setVolume(v) { this.vol = v; if (this.master) this.master.gain.value = v; }

  // ----- listener positioning
  listen(x, y, z, yaw) {
    if (!this.ctx) return;
    const l = this.ctx.listener, t = this.ctx.currentTime;
    const fx = -Math.sin(yaw), fz = -Math.cos(yaw);
    if (l.positionX) {
      l.positionX.setValueAtTime(x, t); l.positionY.setValueAtTime(y, t); l.positionZ.setValueAtTime(z, t);
      l.forwardX.setValueAtTime(fx, t); l.forwardY.setValueAtTime(0, t); l.forwardZ.setValueAtTime(fz, t);
      l.upX.setValueAtTime(0, t); l.upY.setValueAtTime(1, t); l.upZ.setValueAtTime(0, t);
    } else { l.setPosition(x, y, z); l.setOrientation(fx, 0, fz, 0, 1, 0); }
  }

  out(pos, verb = 0.3) {
    const ctx = this.ctx, g = ctx.createGain();
    let node = g;
    if (pos) {
      const p = ctx.createPanner();
      p.panningModel = 'HRTF'; p.distanceModel = 'inverse'; p.refDistance = 4; p.rolloffFactor = 1.1; p.maxDistance = 300;
      p.positionX.value = pos[0]; p.positionY.value = pos[1]; p.positionZ.value = pos[2];
      g.connect(p); p.connect(this.master);
      if (verb) { const v = ctx.createGain(); v.gain.value = verb; p.connect(v); v.connect(this.verb); }
    } else {
      g.connect(this.master);
      if (verb) { const v = ctx.createGain(); v.gain.value = verb; g.connect(v); v.connect(this.verb); }
    }
    return node;
  }

  noiseSrc(buf = this.noise, offset = Math.random()) {
    const s = this.ctx.createBufferSource(); s.buffer = buf; s.loop = true; s.loopStart = 0; s.loopEnd = buf.duration;
    s._off = offset * 1.5;
    return s;
  }

  burst(dest, t, dur, freq, q, gain, type = 'bandpass', buf) {
    const ctx = this.ctx, s = this.noiseSrc(buf), f = ctx.createBiquadFilter(), g = ctx.createGain();
    f.type = type; f.frequency.value = freq; f.Q.value = q;
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(gain, t + 0.003); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f).connect(g).connect(dest);
    s.start(t, s._off); s.stop(t + dur + 0.05);
    return f;
  }

  tone(dest, t, dur, f0, f1, gain, type = 'sine') {
    const ctx = this.ctx, o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(Math.max(1, f1), t + dur);
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(gain, t + 0.004); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(dest); o.start(t); o.stop(t + dur + 0.05);
  }

  // ----- weapons
  gun(kind, pos = null, distant = false) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    const P = {
      pistol:   { crack: 2600, body: 900,  boom: 140, len: 0.16, g: 0.9 },
      smg:      { crack: 3000, body: 1100, boom: 130, len: 0.12, g: 0.75 },
      shotgun:  { crack: 1400, body: 600,  boom: 75,  len: 0.38, g: 1.2 },
      ar:       { crack: 2400, body: 850,  boom: 105, len: 0.2,  g: 0.95 },
      dmr:      { crack: 2000, body: 700,  boom: 80,  len: 0.42, g: 1.25 },
      lmg:      { crack: 2100, body: 750,  boom: 90,  len: 0.24, g: 1.0 },
      launcher: { crack: 700,  body: 300,  boom: 55,  len: 0.6,  g: 1.0 },
      turret:   { crack: 2800, body: 1000, boom: 120, len: 0.12, g: 0.6 },
      gunship:  { crack: 900,  body: 350,  boom: 50,  len: 0.35, g: 1.0 },
    }[kind] || { crack: 2400, body: 850, boom: 105, len: 0.2, g: 0.9 };
    const dest = this.out(pos, distant ? 0.6 : 0.35);
    let g = P.g * (pos ? 1.6 : 0.6);
    if (distant) {
      const lp = this.ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 1800;
      lp.connect(dest);
      this.burst(lp, t, P.len * 1.4, P.body, 0.8, g * 0.9);
      this.tone(lp, t, P.len, P.boom * 1.3, P.boom * 0.5, g * 0.7);
      return;
    }
    this.burst(dest, t, 0.05, P.crack, 0.7, g * 0.9, 'highpass');
    this.burst(dest, t, P.len, P.body, 0.9, g);
    this.tone(dest, t, P.len * 0.9, P.boom * 2, P.boom * 0.6, g * 1.1);
    this.burst(dest, t + 0.002, P.len * 1.8, 300, 0.5, g * 0.5, 'lowpass', this.brown);
    if (!pos && kind !== 'launcher') {
      // mechanical action click
      this.burst(dest, t + 0.03, 0.03, 4500, 6, 0.08);
    }
  }

  dry() { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(null, 0); this.burst(d, t, 0.03, 3500, 5, 0.25); }
  reload(stage) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0.1);
    if (stage === 0) { this.burst(d, t, 0.06, 1800, 4, 0.3); this.tone(d, t, 0.05, 400, 300, 0.1, 'square'); }
    else if (stage === 1) { this.burst(d, t, 0.05, 2500, 6, 0.35); this.burst(d, t + 0.05, 0.04, 1200, 6, 0.3); }
    else { this.burst(d, t, 0.04, 3200, 8, 0.4); this.burst(d, t + 0.08, 0.05, 2200, 8, 0.4); }
  }
  pump() { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(null, 0.1); this.burst(d, t, 0.05, 1500, 4, 0.35); this.burst(d, t + 0.12, 0.06, 1100, 4, 0.4); }
  swap() { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(null, 0); this.burst(d, t, 0.08, 900, 1, 0.12); this.burst(d, t + 0.1, 0.03, 3000, 8, 0.2); }
  casing() { if (!this.ctx) return; const t = this.ctx.currentTime + 0.25 + Math.random() * 0.15, d = this.out(null, 0); this.tone(d, t, 0.08, 5200 + Math.random() * 1500, 4800, 0.025, 'triangle'); this.tone(d, t + 0.09, 0.06, 4900, 4500, 0.012, 'triangle'); }

  // ----- feedback (the satisfying part)
  hit(head) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.burst(d, t, 0.035, 2800, 3, 0.55);
    this.tone(d, t, 0.045, 1900, 1500, 0.18, 'square');
    if (head) { this.tone(d, t, 0.25, 3600, 3400, 0.16, 'triangle'); this.tone(d, t, 0.18, 5400, 5300, 0.06, 'sine'); }
  }
  kill(head) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.burst(d, t, 0.05, 2200, 2, 0.6);
    this.tone(d, t, 0.12, 180, 70, 0.6, 'sine');                  // body thump
    this.tone(d, t + 0.01, 0.06, 1400, 1100, 0.15, 'square');
    if (head) { this.tone(d, t, 0.4, 3000, 2900, 0.18, 'triangle'); this.tone(d, t + 0.06, 0.35, 4500, 4400, 0.1, 'triangle'); }
  }
  impact(pos, soft) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(pos, 0.1);
    if (soft) this.burst(d, t, 0.08, 600, 1, 0.5);
    else { this.burst(d, t, 0.05, 3500 + Math.random() * 2000, 3, 0.3); if (Math.random() < 0.3) this.tone(d, t, 0.25, 2600 + Math.random() * 2000, 1800, 0.03, 'sine'); }
  }
  whiz(pos) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(pos, 0);
    const f = this.burst(d, t, 0.18, 2500, 3, 0.5);
    f.frequency.exponentialRampToValueAtTime(900, t + 0.18);
  }
  hurt() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.tone(d, t, 0.2, 110, 50, 0.7); this.burst(d, t, 0.15, 400, 1, 0.5, 'lowpass');
  }
  heartbeat() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.tone(d, t, 0.12, 60, 40, 0.6); this.tone(d, t + 0.18, 0.12, 55, 38, 0.45);
  }
  explosion(pos, big) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(pos, 0.9);
    const g = big ? 3.0 : 2.2;
    this.burst(d, t, 0.08, 1800, 0.6, g * 0.7);
    this.burst(d, t, 1.6, 180, 0.6, g, 'lowpass', this.brown);
    this.burst(d, t, 0.9, 500, 0.8, g * 0.6);
    this.tone(d, t, 0.9, 70, 25, g * 1.1);
    // debris patter
    for (let i = 0; i < 6; i++) this.burst(d, t + 0.3 + Math.random() * 0.8, 0.04, 2000 + Math.random() * 3000, 3, 0.08);
  }
  jet(pos) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0.5);
    const f = this.burst(d, t, 3.2, 600, 0.6, 1.1, 'bandpass', this.brown);
    f.frequency.setValueAtTime(1600, t); f.frequency.exponentialRampToValueAtTime(260, t + 3.2);
    const f2 = this.burst(d, t, 3.0, 4000, 1, 0.25);
    f2.frequency.setValueAtTime(5000, t); f2.frequency.exponentialRampToValueAtTime(1200, t + 3.0);
  }
  melee() { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(null, 0); const f = this.burst(d, t, 0.15, 1200, 2, 0.4); f.frequency.exponentialRampToValueAtTime(400, t + 0.15); }
  stab(pos) { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(pos, 0); this.burst(d, t, 0.1, 800, 1.5, 0.8); this.tone(d, t, 0.1, 150, 60, 0.5); }

  // ----- UI / announcer
  money() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.tone(d, t, 0.08, 1568, 1568, 0.12, 'triangle'); this.tone(d, t + 0.07, 0.18, 2093, 2093, 0.12, 'triangle');
  }
  buy() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.burst(d, t, 0.06, 3000, 4, 0.3);
    [1318, 1760, 2637].forEach((f, i) => this.tone(d, t + 0.05 + i * 0.06, 0.25, f, f, 0.1, 'triangle'));
  }
  deny() { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(null, 0); this.tone(d, t, 0.15, 220, 200, 0.2, 'square'); this.tone(d, t + 0.16, 0.2, 180, 160, 0.2, 'square'); }
  ui() { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(null, 0); this.tone(d, t, 0.04, 1200, 1100, 0.08, 'triangle'); }
  radio() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.burst(d, t, 0.25, 2000, 1.5, 0.35); this.tone(d, t + 0.25, 0.12, 1000, 1000, 0.12, 'square'); this.tone(d, t + 0.4, 0.12, 1400, 1400, 0.12, 'square');
  }
  waveStart() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0.6);
    // ominous low brass hit + drum
    [55, 82.4, 110].forEach((f) => this.tone(d, t, 2.2, f, f * 0.97, 0.3, 'sawtooth'));
    for (let i = 0; i < 3; i++) { this.tone(d, t + i * 0.35, 0.4, 90, 40, 0.8); this.burst(d, t + i * 0.35, 0.2, 200, 1, 0.5, 'lowpass', this.brown); }
  }
  waveEnd() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0.5);
    [261.6, 329.6, 392, 523.2].forEach((f, i) => this.tone(d, t + i * 0.12, 1.2, f, f, 0.14, 'triangle'));
  }
  unlock() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0.4);
    [659, 880, 1175, 1568].forEach((f, i) => this.tone(d, t + i * 0.08, 0.5, f, f, 0.1, 'sine'));
  }
  footstep(sprint) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime, d = this.out(null, 0);
    this.burst(d, t, 0.07, 700 + Math.random() * 300, 1.2, sprint ? 0.16 : 0.1);
    this.burst(d, t + 0.01, 0.05, 2500, 2, 0.03);
  }
  land() { if (!this.ctx) return; const t = this.ctx.currentTime, d = this.out(null, 0); this.burst(d, t, 0.12, 400, 1, 0.35); }

  startAmbience() {
    const ctx = this.ctx;
    const s = ctx.createBufferSource(); s.buffer = this.brown; s.loop = true;
    const f = ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = 350; f.Q.value = 0.4;
    const g = ctx.createGain(); g.gain.value = 0.05;
    const lfo = ctx.createOscillator(), lg = ctx.createGain(); lfo.frequency.value = 0.07; lg.gain.value = 0.03;
    lfo.connect(lg).connect(g.gain); lfo.start();
    s.connect(f).connect(g).connect(this.master); s.start();
  }
}
