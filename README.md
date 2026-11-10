# Modern Survival

A wave-based survival shooter inspired by the *Survival* mode of classic modern military shooters, built in **Godot 4.7**.
Defend **Winkelcentrum De Liekeblom** in Leek (NL) — a to-scale model of the real shopping centre and the streets around it,
built from open government and OpenStreetMap data — or the original industrial yard. Earn cash for kills, combos and
surviving waves, and spend it at the **Armory** (inside the vacant shop unit in the mall) with four counters:
Weapons, Gunsmith (attachments), Equipment and Air Support. New gear unlocks every few waves.

**Maps**
- **De Liekeblom (Leek)** — real building footprint, corridors, entrances and shop units (BAG + OpenStreetMap), real 3D shapes
  of every surrounding building (3D BAG), the glass-roofed main hall with its white space frame, café terrace and flower stall,
  streets, parking, the canal, trees, street furniture and clutter. Beyond the playable area the rest of Leek
  (~4,500 buildings with measured roof heights, every street, the canals, parks, woods and fields in a 2.5 km square)
  is shown as low-detail scenery — accurate in layout and height, but cheap to render and not playable.
- **Industrial Yard** — the original walled yard.

- **Singleplayer**, **co-op (up to 4)** as a listen server, or a **dedicated headless server** on your own hardware.
- Realistic rendering: physically based materials (CC0 scans from ambientCG), HDRI sky lighting (Poly Haven),
  SDFGI global illumination, SSAO/SSIL, volumetric fog, soft cascaded shadows, AgX tonemapping and a colour grade.
- Enemies that fight back smartly: they take cover behind low walls and corners and pop out to shoot, flank
  through side streets and corridors, and lob grenades at anyone who camps. Snipers paint you with a red laser
  before every shot, riot shields soak frontal fire, grenadiers, attack dogs, Juggernauts, and from wave 8 a troop
  helicopter with a door gunner that you can shoot down.
- A run moves from afternoon to dusk by wave 10. Special waves every few rounds — night (with a power cut in the mall:
  buy night vision), smoke, an all-out rush, sniper alley — and endless-mode modifiers after wave 20 (armour plating,
  enemies that explode). Between waves you hear the convoy pull up where the next attack will come from.
- An exterior steel staircase on De Liekeblom leads up to the flat mall roof and a sandbagged sniper nest over
  the street (enemies can follow you up).
- Difficulty (Recruit / Regular / Veteran), best wave and score per map and difficulty, and an end-of-run summary
  (score, accuracy, headshot rate, favourite weapon, best streak, time).
- Shop windows shatter, lights can be shot out, bullets punch through glass, wood and thin metal. Tactical reloads
  keep a round chambered, hold your breath on scopes, inspect your weapon. Reverb changes indoors / outdoors and
  footsteps change with the floor.
- Satisfying feedback: client-side hitmarkers (white = hit, gold = headshot, red = kill) with distinct sounds,
  blood/impact effects, money pop-ups, kill-combo callouts, screen shake, damage-direction indicators.

---

## 1. Install and play (5 minutes)

1. **Download Godot 4.7** (the standard build, *not* the .NET build) from <https://godotengine.org/download>.
   It is a single executable — no installer needed. Any 4.7.x works (developed and tested on 4.7.2).
2. **Get the project**
   ```bash
   git clone https://github.com/gijs242/modernsurvival.git
   ```
   (or on GitHub: *Code → Download ZIP* and unzip it).
3. **Open it**: start Godot → *Project Manager* → **Import** → pick `modernsurvival/project.godot` → **Import & Edit**.
   The first open imports all textures and models; this takes 1–3 minutes. Later opens are instant.
4. Press **F5** (or the ▶ button top-right) to play.
5. In the menu choose **Singleplayer**, or **Host Co-op** / **Join** for multiplayer. Pick a graphics preset that suits
   your PC (*Ultra* adds TAA + screen-space reflections, *Low* uses FSR upscaling for weaker GPUs, *Performance*
   is for laptops / integrated graphics: 60% render scale with FSR 1, short shadows, no light shadows).

**Controls**

| Key | Action | Key | Action |
|---|---|---|---|
| WASD | move | Shift | sprint |
| Space | jump | C / Ctrl | crouch |
| Left mouse | fire | Right mouse | aim down sights |
| R | reload | 1 / 2 / wheel | switch weapon |
| G | throw frag | V | melee |
| E | open armory station / hold to revive | F | ready up (start next wave early) |
| 4 | place claymore | 5 | place sentry gun |
| 6 | airstrike (aim, click to mark) | 7 | gunship |
| 8 | carpet bombing | Tab | squad scoreboard |
| T | inspect weapon | N | night vision (once bought) |
| Shift (scoped) | hold breath | LMB / RMB (dead) | switch spectated teammate |
| Esc | pause / close shop | F11 | fullscreen |

---

## 2. Hosting on your own hardware

Co-op uses **UDP port 7777** by default (change it in the menu or with `--port`).

Games on your local network show up automatically in the **SERVERS** list on the main menu (servers broadcast on
UDP 7779 and answer status queries on game port + 1, e.g. 7778). Servers you joined before are listed there too
while they're online — click **JOIN**.

### Option A — Listen server (simplest)
One player clicks **Host Co-op**. Others type the host's IP address in *Server address* and click **Join**.
- Same house/LAN: use the host's local IP (e.g. `192.168.1.20`; find it with `ipconfig` on Windows or `ip a` on Linux).
- Over the internet: forward **UDP 7777** on the host's router to the host PC, and give friends your public IP
  (search "what is my ip"). Allow Godot / the game through the Windows firewall when it asks.

### Option B — Dedicated server (always-on box, home server, VPS, Raspberry-Pi-class machines are too slow)
The same project runs headless as a server with no window or GPU required:

```bash
godot --headless --path /path/to/modernsurvival -- --server --port 7777
```

It prints its LAN address. Players use **Join** with that address. The server resets itself when everyone leaves.

To keep it running on Linux with systemd, create `/etc/systemd/system/modernsurvival.service`:

```ini
[Unit]
Description=Modern Survival dedicated server
After=network-online.target

[Service]
ExecStart=/usr/local/bin/godot --headless --path /opt/modernsurvival -- --server --port 7777
Restart=always
User=games

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now modernsurvival
```

```bash
sudo ufw allow 7777/udp
```

### Option C — Exported builds (share the game without Godot)
1. In the editor: **Editor → Manage Export Templates → Download and Install** (one-time).
2. **Project → Export…** — presets for *Windows*, *Linux* and *Linux Dedicated Server* are already set up.
   Click **Export Project** for each one you need; output goes to `build/`.
3. Run the server build with `./ModernSurvivalServer.x86_64 --headless -- --server --port 7777`.

Command-line options (after `--`): `--server`, `--port N`, `--map liekeblom|yard`, `--join ADDRESS`, `--name CALLSIGN`.
Joining players automatically load the map the server is running.

---

## 3. Gameplay

- **Waves** grow in size and difficulty; every 5th wave brings Juggernauts (heavily armoured LMG gunners).
- **Enemies**: Militia (light), Riflemen (accurate), Breachers (shotguns), Rushers (sprinting knife attackers), Juggernauts.
- **Money**: $50–$500 per kill by type, +$25 headshot, +$50 melee, kill-combo bonus (up to +$300),
  wave-survived bonus ($250 + $50 × wave), +$150 flawless wave (no damage), +$100 for reviving a teammate.
- **Downed** players get a pistol and 35 s to be revived (hold E next to them); a Self-Revive Kit gets you up after 5 s.
  The game ends when nobody is left standing. Dead players redeploy when the wave ends.

**Weapons** (17): P38 pistol, M9, M1911, Mk II SMG (scoped), pump shotgun, M4 (holo), AK-47, L85A1, G3A3, SCAR-H (holo),
Mosin-Nagant, bolt-action sniper (6x), Dragunov SVD (4x), M60, MG-M-250, RPG-7 — each tier hits harder, recoils less or holds more.

**Attachments** (Gunsmith counter, fitted to the weapon you're holding): red dot, holographic sight, ACOG 4x, sniper scope 6x,
compensator, suppressor (quiet, no muzzle flash), foregrip, laser, extended magazine. Iron sights are calibrated from each
model's real front/rear sights, and every gun is tested to put its sight line exactly at the screen centre.

**Unlock schedule** (unlocks after you *complete* the listed wave):

| After wave | Weapons | Equipment | Air support |
|---|---|---|---|
| 0 | Mk II SMG $1000, Pump Shotgun $1200 | Ammo $350, Frags $400 | — |
| 1 | M9 $700 | red dot, laser | — |
| 2 | M4 Carbine $2200, M1911 $1300 | Body Armor $800, compensator, foregrip | — |
| 3 | AK-47 $2600 | holo sight, extended mag | — |
| 4 | Mosin-Nagant $2400 | Claymores $700, Self-Revive $1500, suppressor | Precision Airstrike $2000 |
| 5 | L85A1 $3200 | ACOG 4x | — |
| 6 | Bolt-Action Sniper $3000 | Heavy Armor $2000, Sentry Gun $2500 | — |
| 7 | G3A3 $3800 | — | — |
| 8 | M60 $4500 | sniper scope 6x | Gunship $4000 |
| 9 | SCAR-H $5000 | — | — |
| 10 | RPG-7 $5500 | — | — |
| 11 | Dragunov SVD $5800 | — | — |
| 12 | — | — | Carpet Bombing $6000 |
| 13 | MG-M-250 $7000 | — | — |

Tweak anything in `scripts/defs.gd` (weapon stats, prices, unlocks, enemy stats).

---

## 4. Making it look even closer to a AAA shooter (optional)

Everything already works with the bundled CC0 assets: real PBR textures for the ground, walls, buildings,
containers, sandbags and vehicles, an HDRI sky, and Poly Haven props (concrete road barriers, military crates,
barrels, covered cars, street lamps, jerry cans, an ammo box and a real 3D-scanned service pistol used as your sidearm).
All guns are real 3D models (free OpenGameArt / Poly Haven assets, credited below). Soldiers are procedural
(camo-shaded, animated in code); the biggest remaining visual upgrade is rigged characters. The code already supports this — just drop files in:

### Realistic animated soldiers (free, ~15 minutes) — Mixamo
1. Go to <https://www.mixamo.com> and sign in with a free Adobe account.
2. **Characters** tab → pick a military-looking one (e.g. search "soldier" or "swat").
   **Download** → Format *FBX Binary*, Pose *T-pose* → save as `assets/characters/soldier.fbx`.
   (Optional: different looks per enemy type: `grunt.fbx`, `rifleman.fbx`, `shotgunner.fbx`, `rusher.fbx`, `heavy.fbx`, `friendly.fbx`.)
3. **Animations** tab (with that character selected) — for each of these, tick **In Place** where offered and download
   as *FBX Binary*, **Without Skin**, into `assets/characters/anims/` with exactly these names:

   | File | Search Mixamo for |
   |---|---|
   | `idle.fbx` | "Rifle Aiming Idle" |
   | `walk.fbx` | "Rifle Walk" |
   | `run.fbx` | "Rifle Run" |
   | `fire.fbx` | "Firing Rifle" |
   | `death.fbx` | "Death From Front Headshot" (or any death) |
   | `melee.fbx` | "Stabbing" (used by Rushers) |

4. Re-open the project (Godot imports the FBX files automatically) and play. The game scales the character to 1.8 m,
   attaches the weapon to the right hand bone and blends the clips automatically. If the gun sits wrong in the hand,
   adjust the rotation in `scripts/soldier.gd` → `_try_custom()` (`gun.rotation = ...`).

### Swapping a weapon model
Each gun is `assets/weapons/<id>.glb` (ids: `smg`, `shotgun`, `ar`, `dmr`, `lmg`, `launcher`, `frag`; add `pistol` to replace the scanned pistol).
- Easiest: add your source file to `tools/convert_weapons.py` (one line per gun) and run it with Blender — it orients, scales,
  and adds all the markers for you.
- By hand: barrel down **-Z**, +Y up, metres, origin on the sight line above the grip, with optional empty child nodes
  `Muzzle`, `Mag`, `Eject`, `GripR`, `GripL`.
- Good sources: Sketchfab (filter *Downloadable* + licence *CC0* or *CC-BY*, credit the authors), or paid packs on the Unity Asset Store / Fab
  that allow use in other engines.

### Weapon sounds
Gunshots (one recording per weapon, plus a mid-distance `_far` take used for shots more than 35 m away), reloads,
dry fire, weapon swap, explosions and bullet impacts are real recordings in `assets/sounds/`, built by
`tools/make_sounds.py` from these free packs (download/extract them into one folder, then
`python3 tools/make_sounds.py <folder>`; needs ffmpeg + numpy):
- [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) — CC0 ("Prepared SFX Library")
- [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds) — CC0
- [Equipment Clicks II](https://opengameart.org/content/equipment-clicks-ii) — CC0
- [2 high quality explosions](https://opengameart.org/content/2-high-quality-explosions) — CC-BY 3.0, Michel Baradari
- [Impact](https://opengameart.org/content/impact) — CC0, qubodup

Everything else (UI, hitmarkers, footsteps, ambience…) is synthesised in `scripts/sfx.gd`. To replace any sound,
drop `<name>.wav`/`.ogg` into `assets/sounds/`; the names are in `_generate()`.

### More textures / a different sky
`python3 tools/fetch_assets.py` re-downloads the CC0 assets. Edit the lists at the top of that script to swap
materials (any ambientCG id) or the HDRI (any Poly Haven HDRI id), then reopen the project.
If you change the HDRI, also update `SUN_DIR` in `scripts/map.gd` so shadows match the sun in the sky.

---

## 5. Project layout

```
project.godot          Godot project (Forward+ renderer, Jolt physics)
scenes/main.tscn       entry scene
scripts/
  main.gd              menus, session start (SP / host / join / dedicated), pause, game over
  net.gd               ENet networking + command-line args (autoload "Net")
  game_state.gd        game session 1/5: shared state and helpers
  game_combat.gd       game session 2/5: damage, explosions, breakable glass / lights / power
  game_waves.gd        game session 3/5: waves, spawning, server tick, support items, enemy helicopter
  game_sync.gd         game session 4/5: snapshots (server -> every peer)
  game.gd              game session 5/5: setup, networking, player commands, shop, client events & effects
  enemy.gd             enemy AI (cover, flanking, grenades, snipers, shields, reloads) and client puppets
  dog.gd               attack dog model
  backdrop.gd          low-detail Leek town around the playable map
  player.gd            first-person controller, weapons, viewmodel, revive, designator
  map.gd               the yard: walls, armory, buildings, containers, cover, lighting, sky, navmesh
  hud.gd               HUD, hitmarkers, minimap, shop panel, scoreboard
  effects.gd           particles, tracers, decals, explosions, casings
  sfx.gd               procedural sound synthesis + overrides (autoload "Sfx")
  soldier.gd           soldier models + procedural animation (walk/run/strafe, aim, reload, throw, flinch, ragdoll)
  weapon_model.gd      weapon models (procedural or custom .glb)
  props.gd             grenades, rockets, claymores, sentries, aircraft
  defs.gd              all tunable game data (autoload "Defs")
assets/                CC0 textures (ambientCG), HDRI + props (Poly Haven)
tools/fetch_assets.py  re-download / change the CC0 assets
```

## 6. Automated checks (for development)

```bash
godot --headless --path . --fixed-fps 60 -- --selftest
```
Opens/closes a shop with E, fires to check recoil, and kills an enemy to check the death animation and corpse cleanup.

```bash
godot --headless --path . --fixed-fps 60 -- --autotest 120
```
Plays two minutes of scripted waves (buying, shooting, every support item) and reports progress.

## 7. Troubleshooting

- **Black or very slow screen**: choose *Low* or *Medium* graphics in the menu. *High/Ultra* use SDFGI and volumetric
  fog, which need a reasonably modern GPU (GTX 1060 / RX 580 or better recommended for High).
- **Friends can't join**: check the port is forwarded as **UDP** (not TCP), that the host firewall allows Godot,
  and that everyone uses the same game version.
- **"Parse error" on open**: you are on an older Godot. Use 4.7 or newer.

## Credits & licences

- Textures: [ambientCG](https://ambientcg.com) — CC0.
- Weapon models (converted with `tools/convert_weapons.py`, sources via `tools/fetch_weapons.py`):
  - M4 carbine + EOTech sight, pump shotgun — "FPS Weapons" by **biglew**, [OpenGameArt](https://opengameart.org/content/fps-weapons), CC-BY-SA 3.0
  - SMG — "Bullpup submachine gun" by **kutejnikov**, [OpenGameArt](https://opengameart.org/content/bullpup-submachine-gun), CC-BY 4.0
  - M60 — by **mightydinosaurcol**, [OpenGameArt](https://opengameart.org/content/m60-machine-gun), CC-BY 4.0
  - RPG-7 — by **lucian-pavel**, [OpenGameArt](https://opengameart.org/content/low-poly-rpg7), CC0
  - MK2 grenade — by **lonesomeducky**, [OpenGameArt](https://opengameart.org/content/mk2-grenade), CC0
  - Bolt-action sniper rifle and service pistol — [Poly Haven](https://polyhaven.com), CC0
  - AK-47, M1911, L85A1, G3A3, Mosin-Nagant, Dragunov — "Various Small Arms" by **Julius**, [OpenGameArt](https://opengameart.org/content/various-small-arms-assault-rifles-sniper-pistol), public domain
  - SCAR-H, M9 — "FPS Weapons" by **biglew**, CC-BY-SA 3.0
  - MG-M-250 — [OpenGameArt](https://opengameart.org/content/mg-m-250-light-machine-gun), CC-BY-SA 4.0
- Map data (detailed map: `tools/build_liekeblom.py`; town backdrop: `tools/build_leek_backdrop.py`): BAG (Kadaster) via PDOK — CC0; 3D BAG (TU Delft / 3DGI) — CC BY 4.0; © OpenStreetMap contributors — ODbL.
- Surface textures (brick, paving, roofs, plaster, concrete, asphalt, corrugated iron, planks, ground) and props/vegetation
  (trees, shrubs, grass, bins, bags, crates, street furniture, shutters): [Poly Haven](https://polyhaven.com) — CC0.
- HDRI sky and props (barriers, crates, barrels, lamp, car, jerrycan, ammo box, service pistol, etc.): [Poly Haven](https://polyhaven.com) — CC0.
- Sounds (built with `tools/make_sounds.py`): gunshots — [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library), CC0;
  reloads — [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds), CC0; clicks — [Equipment Clicks II](https://opengameart.org/content/equipment-clicks-ii), CC0;
  explosion — "2 high quality explosions" by **Michel Baradari**, [OpenGameArt](https://opengameart.org/content/2-high-quality-explosions), CC-BY 3.0;
  impacts — by **qubodup**, [OpenGameArt](https://opengameart.org/content/impact), CC0.
- Engine: [Godot Engine](https://godotengine.org) — MIT.
- Everything else (code, procedural models, synthesised sounds) is part of this project.
