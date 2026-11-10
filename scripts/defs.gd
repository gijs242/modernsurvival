extends Node
## Shared game data: weapons, enemies, shop catalogue, economy. Autoloaded as `Defs`.

const WEAPONS := {
	"pistol": {"name": "P38 Service Pistol", "cls": "Sidearm", "dmg": 30.0, "rpm": 420.0, "auto": false, "mag": 15, "reserve": -1,
		"reload": 1.3, "spread": 0.010, "ads_spread": 0.002, "bloom": 0.012, "recoil": 1.1, "pellets": 1, "head": 2.2,
		"falloff": [18.0, 45.0, 0.6], "zoom": 1.2, "move": 1.0},
	"smg": {"name": "Mk II SMG", "cls": "Submachine gun", "dmg": 24.0, "rpm": 880.0, "auto": true, "mag": 32, "reserve": 224,
		"reload": 1.9, "spread": 0.022, "ads_spread": 0.006, "bloom": 0.006, "recoil": 0.55, "pellets": 1, "head": 1.8,
		"falloff": [14.0, 35.0, 0.5], "zoom": 1.3, "move": 1.0},
	"shotgun": {"name": "Pump Shotgun", "cls": "Shotgun", "dmg": 22.0, "rpm": 78.0, "auto": false, "mag": 7, "reserve": 49,
		"reload": 2.6, "spread": 0.075, "ads_spread": 0.055, "bloom": 0.0, "recoil": 3.2, "pellets": 9, "head": 1.4,
		"falloff": [7.0, 22.0, 0.2], "zoom": 1.15, "move": 0.96},
	"ar": {"name": "M4 Carbine", "cls": "Assault rifle", "dmg": 36.0, "rpm": 680.0, "auto": true, "mag": 30, "reserve": 210,
		"reload": 2.2, "spread": 0.016, "ads_spread": 0.0025, "bloom": 0.005, "recoil": 0.8, "pellets": 1, "head": 2.0,
		"falloff": [30.0, 70.0, 0.7], "zoom": 1.45, "move": 0.95},
	"dmr": {"name": "Bolt-Action Sniper", "cls": "Sniper rifle", "dmg": 165.0, "rpm": 48.0, "auto": false, "mag": 5, "reserve": 45,
		"reload": 3.0, "spread": 0.04, "ads_spread": 0.0003, "bloom": 0.03, "recoil": 3.0, "pellets": 1, "head": 2.6,
		"falloff": [60.0, 120.0, 0.85], "zoom": 6.0, "move": 0.92, "scope": true},
	"lmg": {"name": "M60 LMG", "cls": "Light machine gun", "dmg": 40.0, "rpm": 760.0, "auto": true, "mag": 100, "reserve": 300,
		"reload": 4.6, "spread": 0.024, "ads_spread": 0.006, "bloom": 0.004, "recoil": 0.75, "pellets": 1, "head": 1.8,
		"falloff": [35.0, 80.0, 0.75], "zoom": 1.4, "move": 0.85},
	"launcher": {"name": "RPG-7", "cls": "Rocket launcher", "dmg": 0.0, "rpm": 40.0, "auto": false, "mag": 1, "reserve": 7,
		"reload": 3.0, "spread": 0.01, "ads_spread": 0.001, "bloom": 0.0, "recoil": 4.0, "pellets": 0, "head": 1.0,
		"falloff": [999.0, 999.0, 1.0], "zoom": 1.3, "move": 0.85, "rocket": true},
	# ---- tiered additions (unlock later, each better than the last)
	"m9": {"name": "M9", "cls": "Pistol", "dmg": 34.0, "rpm": 460.0, "auto": false, "mag": 15, "reserve": 120,
		"reload": 1.2, "spread": 0.009, "ads_spread": 0.0018, "bloom": 0.01, "recoil": 1.0, "pellets": 1, "head": 2.3,
		"falloff": [20.0, 45.0, 0.6], "zoom": 1.2, "move": 1.0, "pistol": true},
	"m1911": {"name": "M1911 .45", "cls": "Pistol", "dmg": 52.0, "rpm": 380.0, "auto": false, "mag": 8, "reserve": 80,
		"reload": 1.3, "spread": 0.009, "ads_spread": 0.0016, "bloom": 0.016, "recoil": 1.7, "pellets": 1, "head": 2.3,
		"falloff": [20.0, 45.0, 0.6], "zoom": 1.2, "move": 1.0, "pistol": true},
	"ak47": {"name": "AK-47", "cls": "Assault rifle", "dmg": 44.0, "rpm": 600.0, "auto": true, "mag": 30, "reserve": 240,
		"reload": 2.3, "spread": 0.018, "ads_spread": 0.003, "bloom": 0.006, "recoil": 0.95, "pellets": 1, "head": 2.0,
		"falloff": [30.0, 70.0, 0.7], "zoom": 1.35, "move": 0.95},
	"mosin": {"name": "Mosin-Nagant", "cls": "Bolt-action rifle", "dmg": 150.0, "rpm": 45.0, "auto": false, "mag": 5, "reserve": 45,
		"reload": 2.8, "spread": 0.03, "ads_spread": 0.0005, "bloom": 0.02, "recoil": 2.8, "pellets": 1, "head": 2.6,
		"falloff": [80.0, 150.0, 0.85], "zoom": 1.6, "move": 0.93, "bolt": true},
	"l85": {"name": "L85A1", "cls": "Assault rifle", "dmg": 40.0, "rpm": 700.0, "auto": true, "mag": 30, "reserve": 270,
		"reload": 2.2, "spread": 0.013, "ads_spread": 0.0016, "bloom": 0.004, "recoil": 0.6, "pellets": 1, "head": 2.0,
		"falloff": [35.0, 80.0, 0.72], "zoom": 1.5, "move": 0.96},
	"g3a3": {"name": "G3A3", "cls": "Battle rifle", "dmg": 58.0, "rpm": 560.0, "auto": true, "mag": 20, "reserve": 180,
		"reload": 2.4, "spread": 0.015, "ads_spread": 0.0016, "bloom": 0.007, "recoil": 1.15, "pellets": 1, "head": 2.1,
		"falloff": [45.0, 100.0, 0.8], "zoom": 1.45, "move": 0.93},
	"scar": {"name": "SCAR-H", "cls": "Battle rifle", "dmg": 56.0, "rpm": 640.0, "auto": true, "mag": 25, "reserve": 250,
		"reload": 2.1, "spread": 0.012, "ads_spread": 0.0013, "bloom": 0.004, "recoil": 0.78, "pellets": 1, "head": 2.1,
		"falloff": [45.0, 100.0, 0.8], "zoom": 1.45, "move": 0.95, "holo": true},
	"svd": {"name": "Dragunov SVD", "cls": "Marksman rifle", "dmg": 135.0, "rpm": 170.0, "auto": false, "mag": 10, "reserve": 80,
		"reload": 2.6, "spread": 0.03, "ads_spread": 0.0003, "bloom": 0.02, "recoil": 2.0, "pellets": 1, "head": 2.6,
		"falloff": [80.0, 150.0, 0.9], "zoom": 4.0, "move": 0.92, "scope": true},
	"mg250": {"name": "MG-M-250", "cls": "Light machine gun", "dmg": 50.0, "rpm": 850.0, "auto": true, "mag": 150, "reserve": 450,
		"reload": 4.2, "spread": 0.02, "ads_spread": 0.004, "bloom": 0.003, "recoil": 0.7, "pellets": 1, "head": 1.9,
		"falloff": [40.0, 90.0, 0.78], "zoom": 1.4, "move": 0.86},
}

## Attachments: slot, unlock (waves cleared), price, and what they change.
const ATTACH := {
	"reddot": {"name": "Red Dot Sight", "slot": "optic", "after": 1, "price": 600, "desc": "Clean sight picture, slightly tighter aim", "ads_spread": 0.85, "zoom": 1.3},
	"holo": {"name": "Holographic Sight", "slot": "optic", "after": 3, "price": 900, "desc": "Wide window, fast target acquisition", "ads_spread": 0.8, "zoom": 1.25},
	"acog": {"name": "ACOG 4x Scope", "slot": "optic", "after": 5, "price": 1600, "desc": "4x magnified lens, you keep your side vision", "ads_spread": 0.6, "zoom": 1.35, "pip": 4.0},
	"sniper_scope": {"name": "Sniper Scope 6x", "slot": "optic", "after": 8, "price": 2500, "desc": "6x magnification for long range", "ads_spread": 0.4, "zoom": 6.0, "scope": true},
	"compensator": {"name": "Compensator", "slot": "muzzle", "after": 2, "price": 800, "desc": "-30% recoil", "recoil": 0.7},
	"suppressor": {"name": "Suppressor", "slot": "muzzle", "after": 4, "price": 1200, "desc": "Quiet shots, no muzzle flash, -10% recoil, shorter range", "recoil": 0.9, "range": 0.85, "quiet": true},
	"foregrip": {"name": "Foregrip", "slot": "under", "after": 2, "price": 900, "desc": "-25% recoil", "recoil": 0.75},
	"laser": {"name": "Laser Sight", "slot": "under", "after": 1, "price": 700, "desc": "-40% hip-fire spread", "spread": 0.6},
	"ext_mag": {"name": "Extended Magazine", "slot": "mag", "after": 3, "price": 1000, "desc": "+50% magazine size", "mag": 1.5},
}

const ENEMIES := {
	"grunt": {"name": "Militia", "hp": 70.0, "speed": 3.3, "dmg": 5.0, "rpm": 300.0, "burst": [2, 4], "pause": [0.8, 1.8], "range": 24.0, "acc": 0.30, "reward": 50, "scale": 1.0, "head": 1.0, "gun": "ar"},
	"rifleman": {"name": "Rifleman", "hp": 105.0, "speed": 3.1, "dmg": 8.0, "rpm": 520.0, "burst": [3, 5], "pause": [0.7, 1.5], "range": 38.0, "acc": 0.36, "reward": 75, "scale": 1.0, "head": 1.0, "gun": "ar"},
	"shotgunner": {"name": "Breacher", "hp": 140.0, "speed": 4.0, "dmg": 20.0, "rpm": 60.0, "burst": [1, 1], "pause": [0.9, 1.3], "range": 10.0, "acc": 0.65, "reward": 80, "scale": 1.04, "head": 1.0, "gun": "shotgun"},
	"rusher": {"name": "Rusher", "hp": 60.0, "speed": 6.2, "dmg": 24.0, "melee": true, "range": 1.7, "acc": 1.0, "reward": 60, "scale": 0.97, "head": 1.0, "gun": "knife"},
	"heavy": {"name": "Juggernaut", "hp": 1600.0, "speed": 1.9, "dmg": 7.0, "rpm": 700.0, "burst": [10, 18], "pause": [1.0, 1.8], "range": 32.0, "acc": 0.30, "reward": 500, "scale": 1.28, "head": 0.6, "gun": "lmg"},
	# long range, holds position, paints you with a laser before every shot
	"sniper": {"name": "Sniper", "hp": 90.0, "speed": 2.8, "dmg": 42.0, "rpm": 30.0, "burst": [1, 1], "pause": [3.0, 4.5], "range": 95.0, "acc": 0.7, "reward": 130, "scale": 1.0, "head": 1.0, "gun": "dmr", "sniper": true, "aim": 1.5},
	# ballistic shield: frontal hits are absorbed, flank it or use explosives
	"shield": {"name": "Riot Shield", "hp": 200.0, "speed": 2.7, "dmg": 9.0, "rpm": 380.0, "burst": [2, 3], "pause": [1.0, 1.8], "range": 16.0, "acc": 0.38, "reward": 140, "scale": 1.04, "head": 1.0, "gun": "pistol", "shield": true},
	# lobs grenades at anyone holding still
	"grenadier": {"name": "Grenadier", "hp": 115.0, "speed": 3.0, "dmg": 6.0, "rpm": 420.0, "burst": [2, 3], "pause": [1.2, 2.0], "range": 26.0, "acc": 0.28, "reward": 110, "scale": 1.0, "head": 1.0, "gun": "ar", "nades": true},
	# attack dog: fast, low and hard to hit
	"dog": {"name": "Attack Dog", "hp": 55.0, "speed": 7.6, "dmg": 15.0, "melee": true, "range": 1.5, "acc": 1.0, "reward": 70, "scale": 1.0, "head": 1.0, "gun": "none", "dog": true},
}

## Enemy transport helicopter: drops a squad, door gunner, can be shot down.
const HELI := {"hp": 2600.0, "reward": 1000, "troops": 5, "dmg": 6.0}

## `after` = number of completed waves before the item unlocks.
const SHOP := [
	{"id": "w_smg", "cat": "weapons", "name": "Mk II SMG", "desc": "Fast-firing, great up close", "price": 1000, "after": 0, "weapon": "smg"},
	{"id": "w_shotgun", "cat": "weapons", "name": "Pump Shotgun", "desc": "Pump shotgun, devastating at short range", "price": 1200, "after": 0, "weapon": "shotgun"},
	{"id": "w_ar", "cat": "weapons", "name": "M4 Carbine", "desc": "Accurate all-round assault rifle with holographic sight", "price": 2200, "after": 2, "weapon": "ar"},
	{"id": "w_dmr", "cat": "weapons", "name": "Bolt-Action Sniper", "desc": "Scoped rifle, one-shot headshots", "price": 3000, "after": 6, "weapon": "dmr"},
	{"id": "w_lmg", "cat": "weapons", "name": "M60 LMG", "desc": "100-round belt of sustained fire", "price": 4500, "after": 8, "weapon": "lmg"},
	{"id": "w_launcher", "cat": "weapons", "name": "RPG-7", "desc": "High-explosive rockets", "price": 5500, "after": 10, "weapon": "launcher"},

	{"id": "w_m9", "cat": "weapons", "name": "M9", "desc": "Reliable 15-round pistol", "price": 700, "after": 1, "weapon": "m9"},
	{"id": "w_m1911", "cat": "weapons", "name": "M1911 .45", "desc": "Hard-hitting heavy pistol", "price": 1300, "after": 2, "weapon": "m1911"},
	{"id": "w_ak47", "cat": "weapons", "name": "AK-47", "desc": "Powerful 7.62 assault rifle", "price": 2600, "after": 3, "weapon": "ak47"},
	{"id": "w_mosin", "cat": "weapons", "name": "Mosin-Nagant", "desc": "Bolt-action, kills in one hit", "price": 2400, "after": 4, "weapon": "mosin"},
	{"id": "w_l85", "cat": "weapons", "name": "L85A1", "desc": "Accurate bullpup rifle, low recoil", "price": 3200, "after": 5, "weapon": "l85"},
	{"id": "w_g3a3", "cat": "weapons", "name": "G3A3", "desc": "Heavy-hitting battle rifle", "price": 3800, "after": 7, "weapon": "g3a3"},
	{"id": "w_scar", "cat": "weapons", "name": "SCAR-H", "desc": "Top-tier battle rifle with holo sight", "price": 5000, "after": 9, "weapon": "scar"},
	{"id": "w_svd", "cat": "weapons", "name": "Dragunov SVD", "desc": "Semi-auto 4x marksman rifle", "price": 5800, "after": 11, "weapon": "svd"},
	{"id": "w_mg250", "cat": "weapons", "name": "MG-M-250", "desc": "150-round belt, the best LMG", "price": 7000, "after": 13, "weapon": "mg250"},

	{"id": "e_ammo", "cat": "equipment", "name": "Ammo Refill", "desc": "Tops up reserve ammo for all weapons", "price": 350, "after": 0},
	{"id": "e_frag", "cat": "equipment", "name": "Frag Grenades x2", "desc": "Throw with G (max 4)", "price": 400, "after": 0},
	{"id": "e_armor", "cat": "equipment", "name": "Body Armor", "desc": "100 armor that soaks damage", "price": 800, "after": 2},
	{"id": "e_mine", "cat": "equipment", "name": "Claymores x2", "desc": "Place with 4 (max 4)", "price": 700, "after": 4},
	{"id": "e_revive", "cat": "equipment", "name": "Self-Revive Kit", "desc": "Get back up once when downed", "price": 1500, "after": 4},
	{"id": "e_harmor", "cat": "equipment", "name": "Heavy Armor", "desc": "250 armor plate carrier", "price": 2000, "after": 6},
	{"id": "e_nvg", "cat": "equipment", "name": "Night Vision", "desc": "Toggle with N — for night waves and power cuts", "price": 1500, "after": 3},
	{"id": "e_turret", "cat": "equipment", "name": "Sentry Gun", "desc": "Auto-turret, place with 5, lasts 90s", "price": 2500, "after": 6},

	{"id": "a_strike", "cat": "air", "name": "Precision Airstrike", "desc": "Line of bombs on your marker (6)", "price": 2000, "after": 4},
	{"id": "a_drone", "cat": "air", "name": "Gunship", "desc": "Orbiting gunship for 45s (7)", "price": 4000, "after": 8},
	{"id": "a_carpet", "cat": "air", "name": "Carpet Bombing", "desc": "Three bombing runs across the yard (8)", "price": 6000, "after": 12},
]

const CAT_NAMES := {"weapons": "WEAPON ARMORY", "equipment": "EQUIPMENT ARMORY", "air": "AIR SUPPORT ARMORY", "gunsmith": "GUNSMITH"}
const CAT_COLORS := {"weapons": Color(1.0, 0.54, 0.16), "equipment": Color(0.31, 0.82, 0.42), "air": Color(0.29, 0.66, 1.0), "gunsmith": Color(0.8, 0.45, 1.0)}
const COMBO_NAMES := ["", "", "DOUBLE KILL", "TRIPLE KILL", "MULTI KILL", "RAMPAGE", "UNSTOPPABLE", "MASSACRE"]

## Difficulty: multipliers on enemy damage, accuracy and health, and on the score (for the high-score table).
const DIFFICULTY := {
	"recruit": {"name": "Recruit", "dmg": 0.6, "acc": 0.8, "hp": 0.85, "score": 0.75},
	"regular": {"name": "Regular", "dmg": 1.0, "acc": 1.0, "hp": 1.0, "score": 1.0},
	"veteran": {"name": "Veteran", "dmg": 1.4, "acc": 1.15, "hp": 1.2, "score": 1.5},
}

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


## Which attachments fit which weapon.
func attach_fits(weapon: String, att: String) -> bool:
	var w: Dictionary = WEAPONS.get(weapon, {})
	var a: Dictionary = ATTACH.get(att, {})
	if w.is_empty() or a.is_empty() or w.get("rocket", false):
		return false
	if w.get("pistol", false) or weapon == "pistol":
		return att in ["reddot", "suppressor", "ext_mag", "laser", "compensator"]
	if a.slot == "optic" and (w.get("scope", false) or w.get("holo", false) or weapon == "ar"):
		return false            # built-in optic
	if weapon == "shotgun":
		return att in ["reddot", "holo", "ext_mag", "laser", "foregrip"]
	return true


## Weapon stats after attachments. `atts` = {slot: attachment_id}.
func stats(weapon: String, atts: Dictionary) -> Dictionary:
	var w: Dictionary = WEAPONS[weapon].duplicate()
	for slot in atts:
		var a: Dictionary = ATTACH.get(atts[slot], {})
		if a.is_empty():
			continue
		if a.has("recoil"):
			w.recoil *= a.recoil
		if a.has("ads_spread"):
			w.ads_spread *= a.ads_spread
		if a.has("spread"):
			w.spread *= a.spread
		if a.has("zoom"):
			w.zoom = a.zoom
		if a.get("scope", false):
			w.scope = true
		if a.has("pip"):
			w.pip = a.pip          # magnification seen through the lens (picture-in-picture)
		if a.has("mag"):
			w.mag = int(ceil(w.mag * a.mag))
			if w.reserve > 0:
				w.reserve = int(ceil(w.reserve * a.mag))
		if a.has("range"):
			w.falloff = [w.falloff[0] * a.range, w.falloff[1] * a.range, w.falloff[2]]
		if a.get("quiet", false):
			w.quiet = true
	return w


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
