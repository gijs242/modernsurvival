class_name GameCombat
extends GameState
## Game session, part 2 of 5 (server): damage, explosions, breakable glass / lights / power.

func _player_hits(p: Dictionary, m: Dictionary) -> void:
	var wid: String = m.get("w", "")
	if p.dead or (p.downed and wid != "pistol") or not Defs.WEAPONS.has(wid) or not wid in p.weapons:
		return
	var w: Dictionary = Defs.stats(wid, p.att.get(wid, {}))
	var per := {}
	var hits: Array = m.get("hits", [])
	for h in hits.slice(0, 12):
		var e: Enemy = enemies.get(int(h.eid))
		if e == null:
			continue
		if int(h.zone) == 3:
			continue                 # riot shield soaks it
		var d: float = Defs.damage_at(w, float(h.dist)) * clamp(float(h.get("mul", 1.0)), 0.2, 1.0)
		var head: bool = int(h.zone) == 0
		if "armored" in modifiers and not head:
			d *= 0.7
		if head:
			d *= 1.0 + (w.head - 1.0) * Defs.ENEMIES[e.type].head
		elif int(h.zone) == 2:
			d *= 0.75
		if not per.has(e):
			per[e] = {"d": 0.0, "head": false}
		per[e].d += d
		per[e].head = per[e].head or head
	for e in per:
		_damage_enemy(e, per[e].d, p, {"head": per[e].head})


func _damage_enemy(e: Enemy, dmg: float, p, o := {}) -> void:
	if e.hp <= 0.0:
		return
	e.hp -= dmg
	e.alert = true
	if e.hp > 0.0:
		e.stagger(dmg)
		if p:
			ev({"t": "hit", "to": p.id, "eid": e.id, "dmg": roundi(dmg), "head": o.get("head", false), "src": o.get("src", ""),
				"zone": int(o.get("zone", 1)), "from": p.pos})
		return
	var def: Dictionary = Defs.ENEMIES[e.type]
	enemies.erase(e.id)
	var money := 0
	var combo := 0
	var bonus := 0
	if p:
		p.kills += 1
		if o.get("head", false):
			p.heads += 1
		p.combo = p.combo + 1 if p.combo_t > 0.0 else 1
		p.combo_t = 4.0
		combo = p.combo
		money = int(def.reward) + (25 if o.get("head", false) else 0) + (50 if o.get("melee", false) else 0)
		bonus = min(300, 25 * (combo - 1)) if combo >= 2 else 0
		p.money += money + bonus
		p.earned += money + bonus
	var from: Vector3 = p.pos if p else e.global_position + Vector3(0, 0, 1)
	ev({"t": "kill", "pid": p.id if p else 0, "eid": e.id, "et": e.type, "pos": e.global_position, "yaw": e.rotation.y,
		"dir": (e.global_position - from).normalized(), "head": o.get("head", false), "melee": o.get("melee", false),
		"src": o.get("src", ""), "expl": o.get("expl", false), "money": money, "combo": combo, "bonus": bonus})
	dying[e.id] = e
	e.set_physics_process(false)
	e._cancel_aim()
	if "volatile" in modifiers:
		_enemy_blast(e.global_position + Vector3(0, 0.8, 0), 3.5, 40.0)


func damage_player(p: Dictionary, dmg: float, from: Vector3) -> void:
	if p.dead or p.downed or state == "over":
		return
	p.last_dmg = time
	p.flawless = false
	if p.armor > 0.0:
		var a: float = min(p.armor, dmg)
		p.armor -= a
		dmg -= a * 0.9
	p.hp -= dmg
	ev({"t": "dmg", "to": p.id, "from": from, "amt": roundi(dmg)})
	if p.hp <= 0.0:
		p.hp = 0.0
		p.downed = true
		p.downs += 1
		p.rev_p = 0.0
		p.down_t = 5.0 if p.self_revive else 35.0
		ev({"t": "down", "pid": p.id, "self": p.self_revive > 0})


func _explode(pos: Vector3, r: float, dmg: float, owner: int, src: String) -> void:
	ev({"t": "explode", "pos": pos, "r": r})
	var p = P.get(owner)
	_break_glass_near(pos, r)
	for hid in helis.keys():
		var hd: float = (helis[hid].pos as Vector3).distance_to(pos)
		if hd < r + 4.0:
			_damage_heli(hid, dmg * (1.0 - 0.6 * hd / (r + 4.0)), p)
	for e in enemies.values():
		var d: float = (e.global_position + Vector3(0, 0.9, 0)).distance_to(pos)
		if d < r:
			_damage_enemy(e, dmg * (1.0 - 0.75 * d / r), p, {"expl": true, "src": src})
	var space := get_world_3d().direct_space_state
	for q in P.values():
		var qp: Vector3 = q.pos + Vector3(0, 1.0, 0)
		var d: float = qp.distance_to(pos)
		if d < r * 0.8 and not _blocked(space, pos + Vector3(0, 0.3, 0), qp):
			damage_player(q, dmg * 0.22 * (1.0 - d / (r * 0.8)) * (1.0 if q.id == owner else 0.5), pos)


# ---- breakable glass and lights (server decides, every peer mirrors it)
func _break_glass_near(pos: Vector3, r: float) -> void:
	for gid in map.glass_near(pos, r):
		_break_glass(gid)


func _break_glass(gid: int) -> void:
	if glass_broken.has(gid) or gid < 0 or gid >= map.glass.size():
		return
	glass_broken[gid] = true
	ev({"t": "glass", "id": gid})


func _shoot_light(lid: int) -> void:
	if lights_out.has(lid) or lid < 0 or lid >= map.lights.size():
		return
	lights_out[lid] = true
	ev({"t": "light", "id": lid})


func _set_power(on: bool) -> void:
	if power == on:
		return
	power = on
	ev({"t": "power", "on": on})


## Enemy explosive (grenade, volatile death): hurts players only.
func _enemy_blast(pos: Vector3, r: float, dmg: float) -> void:
	ev({"t": "explode", "pos": pos, "r": r})
	var space := get_world_3d().direct_space_state
	for q in P.values():
		var qp: Vector3 = q.pos + Vector3(0, 1.0, 0)
		var d: float = qp.distance_to(pos)
		if d < r and not _blocked(space, pos + Vector3(0, 0.3, 0), qp):
			damage_player(q, dmg * (1.0 - d / r), pos)
	_break_glass_near(pos, r)


func _damage_heli(id: int, dmg: float, p) -> void:
	var h: Dictionary = helis.get(id, {})
	if h.is_empty():
		return
	h.hp -= dmg
	if p:
		ev({"t": "hit", "to": p.id, "eid": -1, "dmg": roundi(dmg), "head": false, "src": "heli"})
	if h.hp > 0.0:
		return
	helis.erase(id)
	ev({"t": "heli_down", "pos": h.pos, "yaw": h.yaw})
	ev({"t": "explode", "pos": h.pos, "r": 9.0})
	if p:
		p.money += Defs.HELI.reward
		p.earned += Defs.HELI.reward
		p.kills += 1
		ev({"t": "money", "to": p.id, "amt": Defs.HELI.reward, "label": "HELICOPTER DOWN"})
		ev({"t": "msg", "text": "%s shot down the helicopter!" % p.name})
