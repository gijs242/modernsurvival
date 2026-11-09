extends Node
## Shared game data: weapons, enemies, shop catalogue, economy. Autoloaded as `Defs`.

const WEAPONS := {
	"pistol": {"name": "Kestrel 9mm", "cls": "Sidearm", "dmg": 30.0, "rpm": 420.0, "auto": false, "mag": 15, "reserve": -1,
		"reload": 1.3, "spread": 0.010, "ads_spread": 0.002, "bloom": 0.012, "recoil": 1.1, "pellets": 1, "head": 2.2,
		"falloff": [18.0, 45.0, 0.6], "zoom": 1.2, "move": 1.0},
	"smg": {"name": "Wasp SMG", "cls": "Submachine gun", "dmg": 24.0, "rpm": 880.0, "auto": true, "mag": 32, "reserve": 224,
		"reload": 1.9, "spread": 0.022, "ads_spread": 0.006, "bloom": 0.006, "recoil": 0.55, "pellets": 1, "head": 1.8,
		"falloff": [14.0, 35.0, 0.5], "zoom": 1.25, "move": 1.0},
	"shotgun": {"name": "Breacher 12G", "cls": "Shotgun", "dmg": 22.0, "rpm": 78.0, "auto": false, "mag": 7, "reserve": 49,
		"reload": 2.6, "spread": 0.075, "ads_spread": 0.055, "bloom": 0.0, "recoil": 3.2, "pellets": 9, "head": 1.4,
		"falloff": [7.0, 22.0, 0.2], "zoom": 1.15, "move": 0.96},
	"ar": {"name": "Ranger AR", "cls": "Assault rifle", "dmg": 36.0, "rpm": 680.0, "auto": true, "mag": 30, "reserve": 210,
		"reload": 2.2, "spread": 0.016, "ads_spread": 0.0025, "bloom": 0.005, "recoil": 0.8, "pellets": 1, "head": 2.0,
		"falloff": [30.0, 70.0, 0.7], "zoom": 1.45, "move": 0.95},
	"dmr": {"name": "Longbow DMR", "cls": "Marksman rifle", "dmg": 110.0, "rpm": 190.0, "auto": false, "mag": 10, "reserve": 70,
		"reload": 2.6, "spread": 0.03, "ads_spread": 0.0004, "bloom": 0.02, "recoil": 2.4, "pellets": 1, "head": 2.5,
		"falloff": [60.0, 120.0, 0.85], "zoom": 3.2, "move": 0.92, "scope": true},
	"lmg": {"name": "Bulwark LMG", "cls": "Light machine gun", "dmg": 40.0, "rpm": 760.0, "auto": true, "mag": 100, "reserve": 300,
		"reload": 4.6, "spread": 0.024, "ads_spread": 0.006, "bloom": 0.004, "recoil": 0.75, "pellets": 1, "head": 1.8,
		"falloff": [35.0, 80.0, 0.75], "zoom": 1.4, "move": 0.85},
	"launcher": {"name": "Ravager RL", "cls": "Rocket launcher", "dmg": 0.0, "rpm": 40.0, "auto": false, "mag": 1, "reserve": 7,
		"reload": 3.0, "spread": 0.01, "ads_spread": 0.001, "bloom": 0.0, "recoil": 4.0, "pellets": 0, "head": 1.0,
		"falloff": [999.0, 999.0, 1.0], "zoom": 1.3, "move": 0.85, "rocket": true},
}

const ENEMIES := {
	"grunt": {"name": "Militia", "hp": 70.0, "speed": 3.3, "dmg": 5.0, "rpm": 300.0, "burst": [2, 4], "pause": [0.8, 1.8], "range": 24.0, "acc": 0.30, "reward": 50, "scale": 1.0, "head": 1.0, "gun": "ar"},
	"rifleman": {"name": "Rifleman", "hp": 105.0, "speed": 3.1, "dmg": 8.0, "rpm": 520.0, "burst": [3, 5], "pause": [0.7, 1.5], "range": 38.0, "acc": 0.36, "reward": 75, "scale": 1.0, "head": 1.0, "gun": "ar"},
	"shotgunner": {"name": "Breacher", "hp": 140.0, "speed": 4.0, "dmg": 20.0, "rpm": 60.0, "burst": [1, 1], "pause": [0.9, 1.3], "range": 10.0, "acc": 0.65, "reward": 80, "scale": 1.04, "head": 1.0, "gun": "shotgun"},
	"rusher": {"name": "Rusher", "hp": 60.0, "speed": 6.2, "dmg": 24.0, "melee": true, "range": 1.7, "acc": 1.0, "reward": 60, "scale": 0.97, "head": 1.0, "gun": "knife"},
	"heavy": {"name": "Juggernaut", "hp": 1600.0, "speed": 1.9, "dmg": 7.0, "rpm": 700.0, "burst": [10, 18], "pause": [1.0, 1.8], "range": 32.0, "acc": 0.30, "reward": 500, "scale": 1.28, "head": 0.6, "gun": "lmg"},
}

## `after` = number of completed waves before the item unlocks.
const SHOP := [
	{"id": "w_smg", "cat": "weapons", "name": "Wasp SMG", "desc": "Fast-firing, great up close", "price": 1000, "after": 0, "weapon": "smg"},
	{"id": "w_shotgun", "cat": "weapons", "name": "Breacher 12G", "desc": "Pump shotgun, devastating at short range", "price": 1200, "after": 0, "weapon": "shotgun"},
	{"id": "w_ar", "cat": "weapons", "name": "Ranger AR", "desc": "Accurate all-round assault rifle", "price": 2200, "after": 2, "weapon": "ar"},
	{"id": "w_dmr", "cat": "weapons", "name": "Longbow DMR", "desc": "Scoped semi-auto, huge headshot damage", "price": 3000, "after": 6, "weapon": "dmr"},
	{"id": "w_lmg", "cat": "weapons", "name": "Bulwark LMG", "desc": "100-round belt of sustained fire", "price": 4500, "after": 8, "weapon": "lmg"},
	{"id": "w_launcher", "cat": "weapons", "name": "Ravager RL", "desc": "High-explosive rockets", "price": 5500, "after": 10, "weapon": "launcher"},

	{"id": "e_ammo", "cat": "equipment", "name": "Ammo Refill", "desc": "Tops up reserve ammo for all weapons", "price": 350, "after": 0},
	{"id": "e_frag", "cat": "equipment", "name": "Frag Grenades x2", "desc": "Throw with G (max 4)", "price": 400, "after": 0},
	{"id": "e_armor", "cat": "equipment", "name": "Body Armor", "desc": "100 armor that soaks damage", "price": 800, "after": 2},
	{"id": "e_mine", "cat": "equipment", "name": "Claymores x2", "desc": "Place with 4 (max 4)", "price": 700, "after": 4},
	{"id": "e_revive", "cat": "equipment", "name": "Self-Revive Kit", "desc": "Get back up once when downed", "price": 1500, "after": 4},
	{"id": "e_harmor", "cat": "equipment", "name": "Heavy Armor", "desc": "250 armor plate carrier", "price": 2000, "after": 6},
	{"id": "e_turret", "cat": "equipment", "name": "Sentry Gun", "desc": "Auto-turret, place with 5, lasts 90s", "price": 2500, "after": 6},

	{"id": "a_strike", "cat": "air", "name": "Precision Airstrike", "desc": "Line of bombs on your marker (6)", "price": 2000, "after": 4},
	{"id": "a_drone", "cat": "air", "name": "Gunship", "desc": "Orbiting gunship for 45s (7)", "price": 4000, "after": 8},
	{"id": "a_carpet", "cat": "air", "name": "Carpet Bombing", "desc": "Three bombing runs across the yard (8)", "price": 6000, "after": 12},
]

const CAT_NAMES := {"weapons": "WEAPON ARMORY", "equipment": "EQUIPMENT ARMORY", "air": "AIR SUPPORT ARMORY"}
const CAT_COLORS := {"weapons": Color(1.0, 0.54, 0.16), "equipment": Color(0.31, 0.82, 0.42), "air": Color(0.29, 0.66, 1.0)}
const COMBO_NAMES := ["", "", "DOUBLE KILL", "TRIPLE KILL", "MULTI KILL", "RAMPAGE", "UNSTOPPABLE", "MASSACRE"]

const START_MONEY := 500
const MAX_FRAGS := 4
const MAX_MINES := 4
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

## Collision layers
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_HITBOX := 8


func wave_bonus(wave: int) -> int:
	return 250 + 50 * wave


func damage_at(w: Dictionary, dist: float) -> float:
	var f: Array = w.falloff
	if dist <= f[0]:
		return w.dmg
	if dist >= f[1]:
		return w.dmg * f[2]
	return w.dmg * (1.0 - (1.0 - f[2]) * (dist - f[0]) / (f[1] - f[0]))


func shop_item(id: String) -> Dictionary:
	for it in SHOP:
		if it.id == id:
			return it
	return {}
