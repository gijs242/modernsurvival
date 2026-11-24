# NOTES FOR ME

Working notes for the wave-survival shooter (Unreal Engine 5.8, C++). Newest status first.

## 0. Status — read this first

**The code has never been compiled or run in Unreal.** The session that wrote it ran in a
Linux cloud container with no Unreal Engine install, no Unreal MCP connection (the brief said
there would be one, but no Unreal tools were attached) and no access to your computer. So:

| Check | Status |
|---|---|
| Engine-free gameplay rules (`MSRules.h`) unit tests | **Ran: 119 checks pass** (g++, `-Werror -Wconversion`). CI runs them on every push. |
| Tuning CSVs vs C++ row structs, cross-references | **Ran: OK** (`python3 Tools/make_data.py --check`, also in CI). |
| Include and generated-header sanity over all 78 C++ files | **Ran: OK** (script, no engine). |
| Lindenborg data pipeline (3D BAG + AHN + BGT -> layout) | **Ran: OK**. Plan previews are in `Docs/`. |
| Terrain-import orientation maths (`setup_project.py`) | **Ran: OK**, simulated for all 48 axis mappings × 2 unit scales. |
| UE compile, automation tests, editor Python script, play-test | **Not run.** Needs UE 5.8 (section 2). |

Expect a handful of compile errors on the first build: I wrote against the UE 5.4–5.6 APIs I
know, and 5.8 may have renamed some. Section 9 lists the spots most likely to break and how to
fix each. If you attach a machine with UE 5.8 (or the Unreal MCP) to a session, I can do the
compile → test → play-test → fix loop myself.

## 1. What's in the repo

```
ModernSurvival.uproject        UE 5.8, modules ModernSurvival (runtime) + ModernSurvivalEditor
Config/                        Lumen, VSR, TSR, Weapon trace channel, dynamic navmesh, maps, table paths
Source/ModernSurvival/
  Public/Core/MSRules.h        engine-free rules (waves, cash, damage, spawn visibility, springs, acoustics)
  Data/                        DataTable row structs, settings, data subsystem (CSV fallback in editor)
  Player/                      character (sprint/slide/ADS/last stand/equipment), camera feel, view model, input, player state
  Weapons/                     weapon (hitscan + projectile), swappable visual component, projectile
  AI/                          AI character, controller (Perception + StateTree), combat brain, StateTree nodes, EQS, helicopter
  Game/                        game mode (waves/spawns/cash), game state, spawn points, buy stations, game instance (save)
  Equipment/                   frag, claymore, sentry gun, airstrike
  Audio/                       acoustics probe + room-dependent gunshot echo/reverb
  Look/                        colour grade / film grain / low-health post process
  UI/                          canvas HUD, C++-built UMG menus (main, pause, game over, shop)
  Private/Tests/               automation tests
Source/ModernSurvivalEditor/   builds the enemy StateTree asset from code
Data/*.csv                     ALL tuning numbers (DataTables) + FeelCurves.csv (curve table)
RawAssets/                     placeholder art to import: CC0/PD/CC-BY guns, CC0 gun sounds, Lindenborg layout + terrain
Scripts/setup_project.py       run inside the editor: imports everything, builds StateTree + 3 maps
Scripts/run_tests.sh|.bat      compile + headless automation tests
Tools/make_data.py             regenerates / validates the CSVs
Tools/build_lindenborg.py      rebuilds the school layout from public data
Tests/Rules/rules_test.cpp     engine-free unit tests (CI)
Docs/lindenborg_plan_*.png     plan previews of the school map
```

The old Godot project is gone from the working tree but still in git history (commit `89f80c4`
and earlier).

## 2. Getting it running (do these in order)

1. Install **UE 5.8** and Visual Studio 2022 (Game dev with C++ workload) or Rider.
2. Right-click `ModernSurvival.uproject` → *Generate Visual Studio project files*. Build
   `ModernSurvivalEditor` (Development Editor, Win64). Fix compile errors with section 9.
3. Open the project. On the first open it will ask to build modules: say yes.
4. **Window → Output Log**, switch the input box to `Python`, and run:
   `py "<full path>/Scripts/setup_project.py"`
   It imports audio, weapons and data, builds `/Game/AI/ST_Enemy`, the grey-box materials and
   the three maps. It takes a few minutes; Lindenborg spawns about 2,300 boxes. Problems are
   listed at the end of the log.
5. Open `/Game/Maps/L_TestGrey` and press Play (PIE). `L_MainMenu` is the game's start map.
6. Tests: Tools → Session Frontend → Automation → filter `ModernSurvival` → Run. Or run
   `Scripts/run_tests.bat` (set `UE_ROOT` first).

**It still runs if setup is skipped:** in the editor, any missing DataTable is read straight from
`Data/*.csv`, and the AI uses a C++ fallback brain if the StateTree asset is missing. Missing
sounds and meshes fall back to silence and placeholder shapes. You still need a map with a
navmesh; the setup script makes those.

Useful console commands during play: `MSGiveCash 10000`, `MSGiveAll`, `MSGod`, `MSKillAll`,
`MSSkipWave`, `MSSetWave 10`, `MSGiveWeapon LMG_Hammer`, `MSAcoustics` (prints the room class),
`MS.ReloadData` (reload the CSVs/tables while playing), `MS.BuildStateTree` (editor),
`showdebug ai`, and `'` (apostrophe) for the gameplay debugger.

## 3. How to test each milestone

**M1 – Movement + one gun (L_TestGrey)**
- WASD/mouse. Shift sprints (toggle, forward only). C/Ctrl crouches; while sprinting fast it
  slides (≈0.85 s, camera rolls, FOV kicks). Space jumps, and stands you up from a crouch.
- RMB aims: FOV zooms to the weapon's `ADSFOV`, the gun snaps to the sight line, and sway and
  spread drop. LMB fires: camera kicks up and climbs, then recovers after you stop; the
  view-model kicks back and settles on a spring; the crosshair grows with spread.
- Fire straight out of a sprint: there is a short sprint-to-fire delay (`SprintToFireTime`).
- Take damage (let an enemy shoot you): the screen edge goes red and desaturates, health regens
  after 4 s, and red arcs point at the shooter.
- Gunshots in the open have a long slap-back echo; in the small room a tight echo; in the big
  hall a long reverb. `MSAcoustics` prints which one is active.

**M2 – Enemy AI that takes cover and shoots back**
- `MSSetWave 2`, then watch riflemen: they run (via EQS) to spots hidden at crouch height but
  able to see you standing, crouch, peek, fire bursts, and move to new cover when you suppress
  them. Some flank wide (EQS flank query, at most 2 at a time).
- `showdebug ai` / gameplay debugger shows the StateTree state. Warning in the log
  *"Enemy StateTree not found ... Using the C++ fallback brain"* means step 4 didn't build the
  asset; the behaviour is the same.

**M3 – Waves + cash + buy station**
- First break 10 s, then 30 s between waves. Hold **N** to start early (bonus cash per second
  skipped). Kills pay `CashReward`, headshots +50, melee +50, and each cleared wave pays a bonus.
- Walk up to a buy station and press **E**: the shop opens, items show price, lock wave and
  full/poor state. Buying a gun you own refills its ammo.

**M4 – All enemy types, weapons, killstreaks**
- Rushers from wave 3, dogs from 5 (wave 7 is a dog wave), juggernauts from 8 (wave 12 heavy),
  helicopter on waves 10/15/20, then every 5th wave in endless mode. `MSSetWave 10` to see the
  helicopter; the launcher (`MSGiveWeapon Launcher_Thumper`) does 1.6× damage to it.
- Equipment: G frag (hold to cook — too long and it goes off in your hand), 3 claymore,
  4 sentry, 5 airstrike (aim at the ground), 6 AI squad (two soldiers follow and fight).
- 11 weapons, all different (pistols, SMG, 3 rifles, pump shotgun with shell reload, LMG,
  2 snipers, rocket launcher).

**M5 – HUD, menus, game over, look & feel**
- HUD: wave, enemies left, cash with popups, ammo/reserve, equipment counts, crosshair,
  hitmarker (white, blue on armour, red on kill, pops bigger), damage arcs, last-stand banner,
  helicopter health bar, straggler markers (last 3 enemies after 45 s).
- Esc pauses. Die twice (the first lethal hit drops you into **last stand**: pistol only,
  survive 10 s to get up, once per game) for the game-over screen with stats and best wave.
- Grade: desaturated, contrasty, light film grain, vignette (all in `Data/LookFeel.csv`).

**M6 – Lindenborg school (abandoned / war-damaged)**
- Open `L_Lindenborg`. It should look abandoned:
  - Overcast, hazy light and a dusty, green-grey grade (LookFeel row `Abandoned`).
  - Four roof collapses with rubble and fallen slabs. One goes through the first floor, so you
    can drop from upstairs.
  - Blown-out wall breaches you can walk through, and boarded-up windows.
  - Wrecked classrooms: knocked-down walls, scattered and tipped desks, debris, ceiling panels.
  - Outside: burnt-out cars, abandoned sandbag positions, containers, barrels, tyres, scorch
    marks, overgrown bushes and grass, and ruined neighbouring houses.
  - Bushes and grass hide you but don't stop bullets.
- Toggle the **Destruction** data layer to see the dressing on its own. Window → World Partition → Data Layers: toggle **Guessed** to see
  exactly what is invented. Measured shell = 3D BAG heights. You start in the guessed entrance
  hall on the south side; buy stations are in the hall and on the forecourt.
- `Docs/lindenborg_plan_ground.png` / `_first.png` show the layout from above.

**Co-op (2 players, MW3-style)**
- *Quick test in the editor:* Play button ▸ ⋮ ▸ **Number of Players = 2**, **Net Mode = Play As
  Listen Server**, then Play. Two windows open: the host and a client.
- *Real test on two PCs (same LAN, or the host forwards UDP port 7777):* the host clicks
  **HOST CO-OP** in the main menu; the other player types the host's IP in the box and clicks
  **JOIN CO-OP**. There is no Steam or online lobby yet.
- Rules:
  - A lethal hit puts you **down** instead of killing you. You crawl with a pistol and can
    still shoot.
  - Your teammate holds **E** next to you for 3 s to revive you; a bar shows the progress on
    both screens.
  - You **bleed out** after 30 s. If you still have your last stand left, you get up by
    yourself after 10 s instead (as in solo).
  - A dead player **respawns at the next break** with the starting loadout and keeps their
    cash. The game is over only when **both players are down or dead** at the same time.
  - Each extra player makes a wave **+60 % bigger**, with up to +40 % more enemies alive at
    once (`GameRules` row: `CoopEnemiesPerExtraPlayer`, `CoopMaxAlivePerExtraPlayer`;
    bleed-out, revive time and range are there too).
  - Enemies spawn only where **neither** player can see them. AI picks the nearest player.
  - Each player has their own cash and shop. Skipping the break needs **both** players to
    hold N: the HUD shows "(1/2 ready)".
  - HUD: teammate panel (name, health, downed or dead) and a marker over your teammate, which
    turns red with **REVIVE** when they are down.
  - Only the host can restart from the game-over screen and use the `MS*` cheat commands.
- What to check: hits and kills count for the client; the client's cash and ammo update right
  after buying; explosions, airstrikes and the helicopter look the same on both screens; the
  client sees the host's gun and shots, and the other way round.

## 4. Decisions I made (change any of them)

- **Two-player co-op, listen server.** Solo still works the same (a standalone game). The game
  mode, waves, cash, damage and AI run on the host; the second player joins by IP. See the co-op
  section at the end of section 3 for the rules and the network design.
- **Lyra / Game Animation Sample are used for art and animation, not code.** Lyra's gameplay
  stack (GAS, experiences, modular game features) would swallow this project, so the shooter
  systems are custom C++ as you asked. GASP/Lyra animations plug in through the enemy row
  (`SkeletalMesh` + `AnimClass`) and the view-model pivot (see section 5).
- **Co-op network design (trust over anti-cheat).** This is a 2-player game with a friend,
  so feel wins over cheat protection:
  - Player movement is client-authoritative: the server accepts the client's position, so
    sprint, slide and mantle never rubber-band.
  - Shooting is predicted: the client fires, recoils and shows the hitmarker at once. It then
    sends the exact shot directions; the server re-traces them and applies the damage.
  - Cash, purchases, health, waves and AI are server-only. The client asks, and the server
    answers and replicates.
  - Not done: Steam or any online subsystem (direct IP only), a dedicated server (it should
    work but is untested), voice chat, more than 2 players (`MaxPlayers=2` in
    `DefaultGame.ini`; the code scales to more).
- **Feel is data:** every number lives in `Data/*.csv` → DataTables (`/Game/Data/DT_*`). Recoil
  spray shapes are curves in `Data/FeelCurves.csv`. Edit the CSV and run `MS.ReloadData` in
  PIE (CSV fallback), or edit the DataTable asset directly. After editing a DataTable in the
  editor, re-export it to CSV if you want git to see the change. `Tools/make_data.py --check`
  validates the CSVs.
- **No editor-authored assets needed for gameplay.** Enhanced Input actions and mappings, EQS
  queries, the reverb, sound attenuation, post-process and menus are all created in C++ at
  runtime, so the game works from source. Each one has an override hook (Project Settings →
  Game → Modern Survival, or `AMSPlayerController::OverrideMappingContext`).
- **AI architecture:** StateTree picks the activity (dead / follow / hunt / melee / rush /
  advance / flank / take cover → hold cover → reposition), and `UMSCombatBrainComponent` does the
  work. AI Perception (sight, hearing, damage) feeds target selection. EQS (custom generator +
  "MS Cover Quality" test) scores cover: hidden at crouch height, can shoot when standing or
  side-stepping, near the preferred range, away from other AI. Flank mode also wants to be ≥60°
  off the player's facing. A C++ fallback runs the same priorities if the StateTree asset is
  missing.
- **Wave enemies always know roughly where you are** (they converge on you, as in MW3), but they
  only shoot with real line of sight, after a reaction delay, with an aim-error cone that grows
  with distance and your speed.
- **Spawning:** only at `MSSpawnPoint`s outside the view cone (FOV/2 + 20° margin) **or**
  occluded by geometry, 15–90 m away, with behind-you points preferred. Without spawn points it
  falls back to random navmesh points with the same rules. This is unit tested.
- **Damage numbers:** enemy bullets use their gun's player damage × `WeaponDamageScale` (0.26–0.45),
  so a rifleman burst hurts without one-shotting you. Juggernauts: 1,800 HP, 30% damage
  reduction, reduced headshot multiplier.
- **Last stand:** solo-style. You go down with a pistol, are invulnerable for 1.5 s, and get up
  after 10 s if you survive. Once per game (`LastStandsPerGame`).
- **Echo by room size:** a 12-ray probe around the listener every 0.25 s classifies the space as
  outdoor, small room or large room (ceiling + enclosure + average distance). That drives a
  runtime reverb effect and a delayed, pitched-down "tail" copy of each gunshot.
- **Navmesh is dynamic** (Recast runtime generation) so the sentry and edits to the grey-box
  update it.
- **Lindenborg is abandoned and war-damaged** (your request). It's procedural and seeded rather
  than hand-placed, so it regenerates cleanly when the real floor plan arrives. Each map picks
  its colour grade with a placed `MSLookManager` (`LookRow`); other maps keep `Default`.
- **Map scale:** 1 uu = 1 cm everywhere; Lindenborg is at true scale from 3D BAG. Floor height
  splits are guessed.
- **No Call of Duty names:** the game is "Modern Survival"; guns are "Kestrel Carbine",
  "Brigand Rifle", "Hammer LMG", etc. The CC0/PD gun models are generic real-world types with no
  branding.
- **Placeholder art kept from the old repo:** public-domain / CC0 / CC-BY gun models
  (`RawAssets/Weapons`, credits in section 10) and CC0 gun recordings (`RawAssets/Audio`).
  CC-BY-SA models were dropped to keep licensing simple.

## 5. Placeholders and how to swap in final art

| Thing | Placeholder now | How to swap |
|---|---|---|
| Guns (first person and AI) | Imported glTF (auto-oriented/scaled), else basic-shape gun | Set `Mesh` / `MeshTransform` / sounds / FX columns in `Weapons.csv`. For skeletal guns + arm animations, subclass `UMSWeaponVisualComponent` (override `BuildVisual`, `GetMuzzleTransform`) and set `AMSWeapon::VisualClass`. |
| Player arms | none (gun floats on the view-model pivot) | Attach a first-person arms skeletal mesh to `WeaponPivot` in a BP child of `AMSPlayerCharacter`; `UMSViewModelComponent` keeps doing sway/kick on top of the animation. |
| Enemies | Basic-shape soldiers / dog / juggernaut; "Head"-tagged sphere for headshots | Fill `SkeletalMesh` + `AnimClass` + `MeshTransform` (yaw −90 for UE mannequins) in `Enemies.csv`. Any bone containing "head" counts as a headshot; ragdoll needs a physics asset. |
| Helicopter | Basic shapes, spinning rotor | `StaticMesh` column of the `AttackHelicopter` row. |
| Muzzle flash / tracers / impacts / explosions | Light flash + basic shapes | `MuzzleFlashFX`, `TracerFX`, `ImpactFX` (weapons), `ExplosionFX` (equipment) Niagara columns. |
| Hitmarker / kill sounds | none | `HitmarkerSound`, `KillSound` in `LookFeel.csv`. |
| Enemy voices / dog bark / death | none | `AlertSound`, `DeathSound` in `Enemies.csv`. |
| Buy stations | Table + crate + sign from basic shapes | Make a BP child of `AMSBuyStation` and add Megascans props. |
| School | Grey boxes | Keep the grey-box as blocking volumes, or replace it piece by piece with Megascans modular kits. Guessed data layer first. |

## 6. Assets to buy or download (Fab / Epic)

Free from Epic (use these first):
- **Megascans** (free with UE on Fab): concrete, brick, paving, asphalt, grass and school props
  (chairs, desks, lockers, bins, bike racks).
- **Game Animation Sample Project** (free, Epic): locomotion and AI movement for enemies.
  Retarget to your soldier mesh.
- **Lyra Starter Game** (free, Epic): first-person-capable rifle/pistol animations, hit
  reactions, a UE5 Mannequin soldier base, and weapon meshes you can reuse.
- **Paragon** characters (free, Epic) if you want a heavy body for the juggernaut while
  prototyping.

To buy (no good free option; search Fab with these terms and pick by reviews):
- **Modern military soldier characters, rigged to the UE5 skeleton**: riflemen, shotgunner,
  juggernaut armour.
- **First-person arms + modern weapon pack with animations** (AR, SMG, shotgun, LMG, sniper,
  pistol, launcher). This is the biggest visual upgrade.
- **Attack helicopter** (rigged rotor, damage states).
- **Military dog / German shepherd**, rigged with run/attack/bite animations.
- **Realistic gunshot + explosion sound library** (indoor/outdoor tails). The free Sonniss GDC
  Game Audio Bundle is also worth grabbing.
- **Realistic VFX pack**: muzzle flashes, bullet impacts per surface, explosions, smoke.
- **Modern Dutch school interior props** (lockers, classroom furniture, sports-hall kit) if
  Megascans doesn't cover them.

## 7. Lindenborg map: measured vs guessed

Address check: BAG says Waezenburglaan 55, Leek = pand `0022100000007775`, education use,
7,895 m², built 1985. Footprint 4,777 m², rotated 12.5°. 3D BAG roof parts: two two-storey
masses (7.8 m: 3,475 m² + 549 m²) and single-storey links (4.5 m: 629 + 87 + 36 m²). Ground is
2.32 m NAP (AHN). The other campus building (likely Nijeborg) and the surrounding houses are
placed from 3D BAG as LoD1 blocks.

No usable floor plan was found. The school website, Google and TenderNed are blocked from the
build environment, and web search found no plans or photos with layout detail. A 2021 TenderNed
renovation tender (publication 230247, documents 6806304 and 6840032) may contain drawings; the
renovation was later stopped.

**Guessed** (data layer "Guessed", folder `Lindenborg/Guessed`, actor tag `Guessed`):
1. First-floor level: 3.70 m (typical for a 1985 school with a 7.8 m roof).
2. All interior layout: 2.8 m corridors in the wide two-storey wings with ~7.2 m classrooms
   both sides; single-loaded corridors in narrower parts. That gives about 55 classrooms on the
   ground floor and 59 on the first floor, which is too many (the real building also has
   offices, labs, toilets and so on).
3. **Entrance hall:** a ~16 m open section of the wing around the main doors. The south
   side is confirmed by you; the exact door position along that façade is guessed.
   **Bike storage** (confirmed by you): the big single-storey block in the north-west (≈630 m²)
   is roofed and open-sided, with columns every ~5 m and a door into the school. The rack rows
   inside are guessed.
4. 7 staircases at corridor ends (20 steps, 6 m run).
5. Exterior doors: the main entrance (3.6 m) plus a side/fire door about every 38 m of perimeter.
   Window rhythm: 2.0 m windows on a 3.6 m bay, sill 0.9 m, head 2.8 m, on every façade.
6. Desks in every classroom, parked cars on about 45% of the real BGT parking bays, bike sheds by
   the entrance.
7. Spawn points (outside ring + indoor corridor ends from wave 4) and buy-station positions
   (gameplay choices, not real).
8. **The whole abandoned / war-damaged state is invented.** It's a seeded pass in
   `Tools/lindenborg_ruin.py`, data layer "Destruction", about 2,650 extra pieces with about
   300 shell/interior pieces knocked out.
   - **Change it:** edit `RuinSettings` (amounts) or `RUIN_SEED` (different layout), then rerun
     `python3 Tools/build_lindenborg.py --offline` and `setup_project.py lindenborg`.
   - **Clean school:** `--intact` gives the undamaged building and the default grade.
   - **What it keeps clear:** the main entrance, the buy stations and the doors (14 m).

## 8. Questions for you

Answered: main entrance faces south (yes); north-west block = roofed bike storage; neighbouring
campus building stays non-playable (it remains an LoD1 backdrop block); co-op = yes (built: see
"Co-op" at the end of section 3).

Still open:
1. Where are the aula/canteen, gym(s), stairs and corridors, and where exactly along the south
   façade is the main door? A photo of the fire-escape plans (the "vluchtplan" on the wall)
   would answer all of this at once.
2. Is the first-floor height about right (3.6–3.8 m floor to floor)?

## 9. If it doesn't compile: likely API drift points

| File | What | Fix |
|---|---|---|
| `AI/MSAIController.cpp` | `UStateTreeComponent::SetStateTree`, `SetStartLogicAutomatically` | Name changes in StateTree: look in `StateTreeComponent.h` for the setter that takes a `UStateTree*` or `FStateTreeReference`. |
| `ModernSurvivalEditor/.../MSEditorBuildLibrary.cpp` | `UStateTreeState::AddTransition`, `AddEnterCondition`, `FStateTreeCompiler` | Compare with `StateTreeEditorData.h` / `StateTreeState.h` in 5.8. Worst case: delete the editor module from the .uproject; the game uses the C++ fallback brain. |
| `Weapons/MSWeaponVisualComponent.cpp`, `Player/MSCameraFeelComponent.cpp` | First-person rendering (`FirstPersonPrimitiveType`, camera `FirstPersonFieldOfView/Scale`) | Guarded by `MS_WITH_FIRST_PERSON_RENDERING` (`Core/MSEngineCompat.h`); set it to 0 to drop it. |
| `AI/MSEnvQuery.cpp` | `UEnvQueryTest` members (`Cost`, `ValidItemType`, `FloatValueMin`), `AddItemData<UEnvQueryItemType_Point>` | Compare with `EnvQueryTest.h` / engine tests such as `EnvQueryTest_Distance.cpp`. |
| `Tests/MSAutomationTests.cpp` | `EAutomationTestFlags` | Use whatever the engine's own tests use in 5.8. |
| `Data/MSDataSubsystem.cpp` | `UDataTable::RowStruct` assignment, `CreateTableFromCSVString` (editor only) | Use `UDataTable::RowStruct` setter if it became private. |
| `Weapons/MSWeapon.cpp`, `Player/*`, `AI/*` | `SetNetUpdateFrequency` (was the `NetUpdateFrequency` property before 5.5) | Use whichever compiles; it only changes how often actors send updates. |
| `Player/MSPlayerCharacter.cpp` | CharacterMovement `bIgnoreClientMovementErrorChecksAndCorrection`, `bServerAcceptClientAuthoritativePosition` | If renamed, look in `CharacterMovementComponent.h`. Without them co-op still works but may rubber-band. |
| Any | Deprecation warnings | Harmless; fix later. |

## 10. Credits / licences of placeholder assets

- Gun models (`RawAssets/Weapons`): AK-47, M1911, L85A1, G3A3, Mosin-Nagant, Dragunov — "Various
  Small Arms" by Julius (OpenGameArt, public domain); bolt-action rifle, service pistol — Poly
  Haven (CC0); RPG-7 — lucian-pavel (CC0); MK2 grenade — lonesomeducky (CC0); bullpup SMG —
  kutejnikov (CC-BY 4.0); M60 — mightydinosaurcol (CC-BY 4.0).
- Gun sounds (`RawAssets/Audio`): The Free Firearm Sound Library (CC0), Gun reload sounds (CC0),
  Equipment Clicks II (CC0), "Impact" by qubodup (CC0); explosion — "2 high quality explosions"
  by Michel Baradari (CC-BY 3.0).
- Map data: see `RawAssets/Lindenborg/SOURCES.md` (3D BAG CC BY 4.0; BAG/AHN/BGT CC0).

## 11. Everything I need from you

1. **A machine with UE 5.8** I can drive: attach your PC to a Claude session via Remote
   Control, or enable the Unreal MCP in a session that runs on your machine. Or compile it
   yourself (section 2) and send me the error log. Nothing has been compiled or play-tested yet.
2. **Fab/Epic downloads** (section 6). The free ones first: Megascans, Game Animation Sample,
   Lyra. Then decide on the paid packs: soldiers, FP arms + guns, helicopter, dog, sounds, VFX.
3. **Lindenborg layout info** (section 8): a photo of the fire-escape plans
   (vluchtplannen) per floor, photos of the entrance, aula and corridors, and any measurements
   (corridor width, floor height). Or the TenderNed renovation drawings if you can download them.
4. **Your answers** to the two open questions in section 8 (room layout, floor height).
5. **Git LFS:** turn it on for the repo before committing `.uasset`/`.umap` files
   (`.gitattributes` is ready).
6. **Co-op test partner:** after it compiles, one session with two players (or PIE with
   2 players) to check the feel on the client side.
