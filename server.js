// Modern Survival dedicated server.
// Serves the browser client and runs the authoritative co-op simulation over WebSocket.
//   PORT=8080 node server.js
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';
import { Game } from './shared/sim.js';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PORT = +process.env.PORT || 8080;
const MAX_PLAYERS = +process.env.MAX_PLAYERS || 4;
const TICK = 1 / 30;
const SNAP_EVERY = 2;   // snapshots at 15 Hz

const MOUNTS = [
  ['/vendor/three/', path.join(ROOT, 'node_modules/three/')],
  ['/shared/', path.join(ROOT, 'shared/')],
  ['/', path.join(ROOT, 'public/')],
];
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon' };

const server = http.createServer((req, res) => {
  let url = decodeURIComponent((req.url || '/').split('?')[0]);
  if (url === '/') url = '/index.html';
  if (url === '/status') {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ players: game.players.size, max: MAX_PLAYERS, wave: game.wave, state: game.state }));
  }
  for (const [prefix, dir] of MOUNTS) {
    if (!url.startsWith(prefix)) continue;
    const file = path.normalize(path.join(dir, url.slice(prefix.length)));
    if (!file.startsWith(dir)) break;
    return fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); return res.end('Not found'); }
      res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
      res.end(data);
    });
  }
  res.writeHead(404); res.end('Not found');
});

const game = new Game();
const wss = new WebSocketServer({ server, maxPayload: 64 * 1024 });
let nextPid = 1;

wss.on('connection', (ws) => {
  let pid = 0;
  ws.on('message', (raw) => {
    let m;
    try { m = JSON.parse(raw); } catch { return; }
    if (!pid) {
      if (m.t !== 'join') return;
      if (game.players.size >= MAX_PLAYERS) { ws.send(JSON.stringify({ t: 'full' })); return ws.close(); }
      pid = nextPid++;
      game.addPlayer(pid, m.name);
      ws.send(JSON.stringify({ t: 'welcome', id: pid }));
      console.log(`[+] ${game.players.get(pid).name} (#${pid}) — ${game.players.size} online`);
      return;
    }
    game.handle(pid, m);
  });
  ws.on('close', () => {
    if (!pid) return;
    console.log(`[-] player #${pid} left`);
    game.removePlayer(pid);
    if (game.players.size === 0) game.reset();
  });
});

let tickN = 0, last = performance.now(), acc = 0;
setInterval(() => {
  const now = performance.now();
  acc += Math.min(0.25, (now - last) / 1000);
  last = now;
  let events = [];
  while (acc >= TICK) { acc -= TICK; events = events.concat(game.tick(TICK)); tickN++; }
  if (!game.players.size) return;
  const out = [];
  if (events.length) out.push(JSON.stringify({ t: 'ev', list: events }));
  if (tickN % SNAP_EVERY === 0) out.push(JSON.stringify(game.snapshot()));
  for (const ws of wss.clients) if (ws.readyState === 1) for (const s of out) ws.send(s);
}, 1000 * TICK);

server.listen(PORT, () => {
  console.log(`Modern Survival server running on port ${PORT} (max ${MAX_PLAYERS} players)`);
  for (const list of Object.values(os.networkInterfaces())) for (const a of list || []) {
    if (a.family === 'IPv4' && !a.internal) console.log(`  LAN:   http://${a.address}:${PORT}`);
  }
  console.log(`  Local: http://localhost:${PORT}`);
});
