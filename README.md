# Modern Survival

A first-person wave-survival shooter for **Unreal Engine 5.8** (C++), modelled on the gameplay
and feel of a classic modern-military "survival" spec-ops mode. It contains no assets, names or
logos from any existing game.

Hold out against waves that grow bigger and tougher: riflemen, then shotgun rushers, attack dogs,
armoured juggernauts and an attack helicopter. Kills earn cash (headshots pay more). Between
waves you get a 30-second break (hold **N** to skip it). Three buy stations sell **weapons**,
**equipment** (armor, frags, claymores, sentry gun) and **air support** (airstrike, AI squad).
You have regenerating health, sprint, slide and aim-down-sights, plus one last stand per game.

Maps:
- **Test Range**: grey-box arena for tuning.
- **Lindenborg**: the real rsg de Borgen school building in Leek (NL), at true scale from public
  3D BAG / AHN / BGT data. It is grey-boxed and dressed as an abandoned, war-damaged site
  (`Tools/lindenborg_ruin.py`; use `--intact` for the clean building).

> **Status:** written without access to Unreal Engine. The engine-free rules and the data are
> tested in CI, but the C++ has not been compiled yet. Start with
> [`NOTES_FOR_ME.md`](NOTES_FOR_ME.md): setup steps, milestone test checklists, decisions,
> asset list and open questions.

## Quick start

1. Generate project files, then build `ModernSurvivalEditor` with UE 5.8.
2. Open the project and run `Scripts/setup_project.py` from the Output Log (Python). This imports
   the placeholder audio, weapons and data tables, builds the enemy StateTree and builds the maps.
3. Open `/Game/Maps/L_TestGrey` and press Play.

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Move / look | WASD / mouse | sticks |
| Fire / aim | LMB / RMB | RT / LT |
| Sprint (toggle) | Shift | L3 |
| Crouch, slide while sprinting | C or Ctrl | B |
| Jump | Space | A |
| Reload | R | X |
| Use buy station | E | D-pad down |
| Switch weapon | 1, 2, mouse wheel | Y |
| Melee | V | R3 |
| Frag (hold to cook) | G | RB |
| Claymore / sentry / airstrike / AI squad | 3 / 4 / 5 / 6 | LB / D-pad left / up / right |
| Skip break (hold) | N | View |
| Pause | Esc | Menu |

## Tuning

Every gameplay and feel number lives in `Data/*.csv`, which is imported as DataTables in
`/Game/Data`:

| Table | What it tunes |
|---|---|
| `PlayerFeel` | Movement, slide, health regen, last stand, FOV, head bob, sway |
| `Weapons` | Damage, falloff, fire rate, recoil, view-model kick, ADS, ammo, art references |
| `Enemies` | Health, armor, speed, accuracy, bursts, melee, perception, art references |
| `AIBehaviour` | Cover search, peek and hide timing, flanking, rushing |
| `Waves` | Waves 1–20 (endless growth past that is set in `GameRules`) |
| `GameRules` | Break length, cash, spawn distances, endless growth |
| `ShopItems` | What each buy station sells, prices, unlock waves |
| `Equipment` | Grenades, claymore, sentry, airstrike, squad, armor |
| `LookFeel` | Colour grade, film grain, vignette, camera shake, hitmarkers, HUD |
| `Acoustics` | Room-size thresholds, reverb and gunshot echo per room type |

`FeelCurves.csv` holds the recoil spray patterns. Edit a CSV and run `MS.ReloadData` while
playing in the editor. `python3 Tools/make_data.py --check` validates the CSVs against the C++
structs.

## Tests

- Engine-free rules: `g++ -std=c++20 -I Source/ModernSurvival/Public Tests/Rules/rules_test.cpp && ./a.out`
  (runs in CI).
- Unreal automation tests (`ModernSurvival.*`): `Scripts/run_tests.bat` or `.sh`, or Session
  Frontend → Automation.

## Credits

Placeholder gun models and sounds come from OpenGameArt and Poly Haven (public domain, CC0 and
CC-BY). Map data: 3D BAG (TU Delft / 3DGI, CC BY 4.0) and BAG / AHN / BGT via PDOK (CC0).
Details are in `NOTES_FOR_ME.md` §10 and `RawAssets/Lindenborg/SOURCES.md`.
