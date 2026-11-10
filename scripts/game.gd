class_name Game
extends Node3D
## Game session. On the server (host / singleplayer / dedicated) this runs the authoritative
## simulation: waves, enemy AI, money, shop, support items. Every peer (server included) renders
## from the same events + snapshots, so singleplayer and co-op share one code path.

signal game_over(stats: Array, wave: int)

const SNAP_HZ := 20.0
const INTERP := 0.1

var is_server := false
var local_id := 1
var quality := 2
var map: GameMap
var fx: Effects
var hud: Hud
var players_root: Node3D
var enemies_root: Node3D
var objects_root: Node3D
var player_nodes := {}       # peer id -> Player
var enemies := {}            # id -> Enemy
var dying := {}              # id -> Enemy killed this tick (server), consumed by the kill event
var me := {}                 # my state from the latest snapshot
var snap := {}               # latest snapshot
var time := 0.0

# ---- server state
var P := {}                  # peer id -> state dict
var wave := 0
var cleared := 0
var special := ""            # special wave type: "", "night", "smoke", "rushers", "snipers"
var modifiers: Array = []    # endless-mode modifiers: "armored", "volatile"
var state := "inter"
var timer := 15.0
var spawn_queue: Array = []
var spawn_t := 0.0
var next_id := 1
var projectiles := {}        # id -> {k, pos, vel, fuse, owner}
var mines := {}
var turrets := {}
var drones := {}
var strikes: Array = []
var helis := {}              # id -> enemy transport helicopter
var glass_broken := {}       # map glass pane id -> true
var lights_out := {}         # map light id -> true
var power := true            # mall lights on (night waves cut it)
var wave_t := 0.0
var cut_at := -1.0           # seconds into the wave when the power goes (night waves, some late waves)
var lasers := {}             # client: enemy id -> {pid, t, node}
var nade_cd := 0.0           # global spacing between enemy grenades
var nades_thrown := 0
var approach := -1           # index into map.spawns the next wave mostly comes from (announced by a convoy)
var convoy_sent := false
var events: Array = []
var snap_t := 0.0
var _snap_n := 0

# ---- client-side visuals for objects
var obj_nodes := {}          # "kind:id" -> Node3D


func setup(p_quality: int, p_map := "yard") -> void:
	quality = p_quality
	is_server = multiplayer.is_server()
	local_id = multiplayer.get_unique_id()
	map = GameMap.new()
	map.name = "Map"
	add_child(map)
	map.build(is_server, quality, p_map)
	fx = Effects.new()
	fx.name = "Effects"
	add_child(fx)
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)
	objects_root = Node3D.new()
	objects_root.name = "Objects"
	add_child(objects_root)
	_warm_up()
	if is_server:
		multiplayer.peer_disconnected.connect(_on_peer_left)
		reset()


## Build one of every enemy body (and its weapon) during the level load, so the first sniper or breacher
## of a run doesn't stall the game for a few hundred ms while its model loads from disk.
func _warm_up() -> void:
	for t in Defs.ENEMIES:
		var d: Dictionary = Defs.ENEMIES[t]
		var m: Soldier = Dog.new() if d.get("dog", false) else Soldier.new()
		m.setup(t, d.gun)
		m.free()
	Props.helicopter().free()


# =========================================================================== networking
## Client -> server reliable command.
func send(m: Dictionary) -> void:
	if is_server:
		_handle(local_id, m)
	else:
		s_cmd.rpc_id(1, m)


## Client -> server state (unreliable, high rate).
func send_state(m: Dictionary) -> void:
	if is_server:
		_handle(local_id, m)
	else:
		s_state.rpc_id(1, m)


@rpc("any_peer", "call_remote", "reliable")
func s_cmd(m: Dictionary) -> void:
	if is_server:
		_handle(multiplayer.get_remote_sender_id(), m)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func s_state(m: Dictionary) -> void:
	if is_server:
		_handle(multiplayer.get_remote_sender_id(), m)


@rpc("authority", "call_remote", "reliable")
func c_events(list: Array) -> void:
	for e in list:
		_on_event(e)


var _snaps_rx := 0

@rpc("authority", "call_remote", "unreliable_ordered")
func c_snap(s: Dictionary) -> void:
	_snaps_rx += 1
	if _snaps_rx == 1 and Net.args.has("buildlog"):
		print("[game] first snapshot received")
	_apply_snapshot(s)


func _on_peer_left(id: int) -> void:
	if P.has(id):
		ev({"t": "msg", "text": "%s left" % P[id].name})
		P.erase(id)


# =========================================================================== server: players
func reset() -> void:
	for id in enemies.keys():
		enemies[id].queue_free()
	enemies.clear()
	for c in enemies_root.get_children():
		c.queue_free()
	projectiles.clear()
	mines.clear()
	turrets.clear()
	drones.clear()
	strikes.clear()
	wave = 0
	cleared = 0
	special = ""
	modifiers = []
	state = "inter"
	timer = 20.0
	approach = randi() % max(1, map.spawns.size())
	convoy_sent = false
	if Net.args.has("startwave"):            # dev / testing: begin at a later wave
		wave = int(Net.args.startwave) - 1
		cleared = wave
	spawn_queue.clear()
	var i := 0
	for id in P:
		_init_player(P[id], i)
		i += 1


func _init_player(p: Dictionary, idx: int) -> void:
	var s: Vector3 = map.player_spawns[idx % map.player_spawns.size()]
	p.merge({"pos": s, "yaw": 0.0, "pitch": 0.0, "cr": false, "hp": 100.0, "armor": 0.0, "money": Defs.START_MONEY,
		"weapons": ["pistol"], "cur": "pistol", "frags": 2, "mines": 0, "turrets": 0, "self_revive": 0, "strikes": 0,
		"drones": 0, "carpets": 0, "downed": false, "dead": false, "down_t": 0.0, "rev_p": 0.0, "rev": 0, "last_dmg": -99.0,
		"kills": 0, "heads": 0, "earned": 0, "downs": 0, "combo": 0, "combo_t": 0.0, "ready": false, "flawless": true, "tp": 1,
		"att": {}, "camp_at": s, "camp_t": 0.0, "nvg": 0}, true)


func _add_player(id: int, name: String) -> void:
	if P.has(id) or P.size() >= Defs.MAX_PLAYERS:
		return
	var p := {"id": id, "name": name.substr(0, 16) if name != "" else "Soldier"}
	_init_player(p, P.size())
	P[id] = p
	ev({"t": "msg", "text": "%s joined the squad" % p.name})


func ev(e: Dictionary) -> void:
	events.append(e)


func _unlocked(item: Dictionary) -> bool:
	return cleared >= item.after


## Alive players / enemy list, built once per physics tick (every enemy asks for them every tick).
var _alive_cache: Array = []
var _alive_frame := -1
var _enemy_list: Array = []
var _enemy_frame := -1

func enemy_list() -> Array:
	var f := Engine.get_physics_frames()
	if f != _enemy_frame:
		_enemy_frame = f
		_enemy_list = enemies.values()
	return _enemy_list


func _alive_players() -> Array:
	var f := Engine.get_physics_frames()
	if f == _alive_frame:
		return _alive_cache
	_alive_frame = f
	var out := []
	for id in P:
		var p: Dictionary = P[id]
		if not p.dead and not p.downed:
			out.append(p)
	_alive_cache = out
	return out


func _handle(id: int, m: Dictionary) -> void:
	if id == 0:
		id = local_id
	var t: String = m.get("t", "")
	if t == "join":
		if Net.args.has("buildlog"):
			print("[game] join from %d" % id)
		_add_player(id, str(m.get("name", "Soldier")))
		return
	if not P.has(id):
		return
	var p: Dictionary = P[id]
	var able: bool = not p.downed and not p.dead
	match t:
		"st":
			if p.dead or p.tp:
				pass
			elif not p.downed:
				p.pos = m.get("pos", p.pos)
				p.cr = bool(m.get("cr", false))
			p.yaw = float(m.get("yaw", 0.0))
			p.pitch = float(m.get("pitch", 0.0))
			if m.get("cur", "") in p.weapons:
				p.cur = m.cur
			p.rev = int(m.get("rev", 0))
		"tpok":
			p.tp = 0
		"fire":
			if not p.dead:
				ev({"t": "shot", "pid": id, "w": m.get("w", ""), "o": m.get("o"), "e": m.get("e")})
		"hits":
			_player_hits(p, m)
		"melee":
			var e: Enemy = enemies.get(int(m.get("eid", -1)))
			if e and able and e.global_position.distance_to(p.pos) < 3.2:
				_damage_enemy(e, 150.0, p, {"melee": true})
		"throw":
			if able and p.frags > 0:
				p.frags -= 1
				_add_projectile("frag", m.o, m.v, 2.6, id)
		"rocket":
			if able and "launcher" in p.weapons:
				_add_projectile("rocket", m.o, (m.d as Vector3).normalized() * 55.0, 5.0, id)
		"mine":
			if able and p.mines > 0:
				p.mines -= 1
				var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
				mines[next_id] = {"pos": p.pos + fwd * 1.0, "arm": 1.2, "owner": id, "yaw": p.yaw}
				next_id += 1
		"turret":
			if able and p.turrets > 0:
				p.turrets -= 1
				var fwd := Vector3(-sin(p.yaw), 0, -cos(p.yaw))
				turrets[next_id] = {"pos": p.pos + fwd * 1.3, "yaw": p.yaw, "life": 90.0, "cd": 0.0, "owner": id}
				next_id += 1
		"strike":
			if not able:
				return
			if m.get("k", "") == "carpet":
				if p.carpets <= 0:
					return
				p.carpets -= 1
				for i in [-1, 0, 1]:
					_add_strike(Vector3(i * 22 + randf_range(-3, 3), 0, randf_range(-4, 4)), 0.0, 3.5 + (i + 1) * 1.6, id, 9, 9.0)
				ev({"t": "announce", "text": "CARPET BOMBING INBOUND", "sub": "%s called it in — take cover!" % p.name, "snd": "radio"})
			else:
				if p.strikes <= 0:
					return
				p.strikes -= 1
				var tgt: Vector3 = m.pos
				var d: Vector3 = tgt - p.pos
				_add_strike(tgt, atan2(d.x, d.z) + PI / 2, 3.2, id, 7, 6.5)
				ev({"t": "announce", "text": "AIRSTRIKE INBOUND", "sub": "Marked by %s" % p.name, "snd": "radio"})
		"drone":
			if able and p.drones > 0:
				p.drones -= 1
				drones[next_id] = {"a": randf() * TAU, "life": 45.0, "cd": 1.5, "owner": id, "pos": Vector3(0, 30, 0), "burst": 0}
				next_id += 1
				ev({"t": "announce", "text": "GUNSHIP ON STATION", "sub": "Called in by %s" % p.name, "snd": "radio"})
		"buy":
			_buy(p, str(m.get("item", "")))
		"buy_att":
			_buy_att(p, str(m.get("w", "")), str(m.get("a", "")))
		"ready":
			if state == "inter":
				p.ready = true
				var all := true
				for q in P.values():
					if not q.ready:
						all = false
				if all and timer > 3.0:
					timer = 3.0
		"restart":
			if state == "over":
				reset()
				ev({"t": "restart"})


func _add_projectile(k: String, o: Vector3, v: Vector3, fuse: float, owner: int) -> void:
	projectiles[next_id] = {"k": k, "pos": o, "vel": v, "fuse": fuse, "owner": owner}
	next_id += 1


func _add_strike(center: Vector3, ang: float, delay: float, owner: int, count: int, spacing: float) -> void:
	strikes.append({"pos": center, "ang": ang, "t": delay, "n": 0, "count": count, "spacing": spacing, "gap": 0.0, "owner": owner})
	ev({"t": "strike_mark", "pos": center, "ang": ang, "delay": delay, "len": count * spacing})


func _buy_att(p: Dictionary, wid: String, aid: String) -> void:
	var a: Dictionary = Defs.ATTACH.get(aid, {})
	var fail := func(why: String): ev({"t": "buy", "to": p.id, "ok": false, "why": why})
	if a.is_empty() or p.dead or p.downed:
		return
	if not wid in p.weapons:
		fail.call("You don't own that weapon")
		return
	if not Defs.attach_fits(wid, aid):
		fail.call("Doesn't fit this weapon")
		return
	if cleared < a.after:
		fail.call("Locked")
		return
	var cur: Dictionary = p.att.get(wid, {})
	if cur.get(a.slot, "") == aid:
		fail.call("Already fitted")
		return
	if p.money < a.price:
		fail.call("Not enough cash")
		return
	p.money -= a.price
	cur[a.slot] = aid
	p.att[wid] = cur
	ev({"t": "buy", "to": p.id, "ok": true, "item": aid, "name": "%s on %s" % [a.name, Defs.WEAPONS[wid].name], "price": a.price, "att": aid, "w": wid})


func _buy(p: Dictionary, item_id: String) -> void:
	var it := Defs.shop_item(item_id)
	if it.is_empty() or p.dead or p.downed:
		return
	var fail := func(why: String): ev({"t": "buy", "to": p.id, "ok": false, "why": why})
	if not _unlocked(it):
		fail.call("Locked")
		return
	if p.money < it.price:
		fail.call("Not enough cash")
		return
	var grant := {}
	match item_id:
		"e_ammo":
			grant.ammo = true
		"e_frag":
			if p.frags >= Defs.MAX_FRAGS:
				fail.call("Grenades full")
				return
			p.frags = min(Defs.MAX_FRAGS, p.frags + 2)
		"e_mine":
			if p.mines >= Defs.MAX_MINES:
				fail.call("Claymores full")
				return
			p.mines = min(Defs.MAX_MINES, p.mines + 2)
		"e_armor":
			if p.armor >= 100:
				fail.call("Armor already full")
				return
			p.armor = 100.0
		"e_harmor":
			if p.armor >= 250:
				fail.call("Armor already full")
				return
			p.armor = 250.0
		"e_revive":
			if p.self_revive >= 1:
				fail.call("Already carrying one")
				return
			p.self_revive = 1
		"e_turret":
			if p.turrets >= 2:
				fail.call("Carrying max")
				return
			p.turrets += 1
		"a_strike":
			if p.strikes >= 2:
				fail.call("Carrying max")
				return
			p.strikes += 1
		"a_drone":
			if p.drones >= 1:
				fail.call("Carrying max")
				return
			p.drones += 1
		"a_carpet":
			if p.carpets >= 1:
				fail.call("Carrying max")
				return
			p.carpets += 1
		_:
			if it.has("weapon"):
				var w: String = it.weapon
				if w in p.weapons:
					fail.call("Already owned — buy ammo instead")
					return
				var dropped := ""
				if p.weapons.size() >= 2:
					var idx: int = max(0, p.weapons.find(p.cur))
					dropped = p.weapons[idx]
					p.weapons[idx] = w
					p.att.erase(dropped)
				else:
					p.weapons.append(w)
				p.cur = w
				grant = {"weapon": w, "dropped": dropped}
	p.money -= it.price
	var e := {"t": "buy", "to": p.id, "ok": true, "item": item_id, "name": it.name, "price": it.price}
	e.merge(grant)
	ev(e)


# =========================================================================== server: combat
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
		if p:
			ev({"t": "hit", "to": p.id, "eid": e.id, "dmg": roundi(dmg), "head": o.get("head", false), "src": o.get("src", "")})
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


## How far enemies can see a player (reduced in smoke waves).
func sight_range() -> float:
	return 22.0 if special == "smoke" else 70.0


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


func _blocked(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, Defs.L_WORLD)
	return not space.intersect_ray(q).is_empty()


# =========================================================================== server: waves
func _start_wave() -> void:
	wave += 1
	state = "active"
	var n: int = max(1, P.size())
	special = _special_for(wave)
	modifiers = []
	if wave > 20:
		modifiers.append("armored")
	if wave > 25:
		modifiers.append("volatile")
	var count := roundi((5 + wave * 2.2 + min(12.0, wave * 0.4)) * (1.0 + 0.6 * (n - 1)))
	if special == "rushers":
		count = roundi(count * 1.3)
	var q := []
	var snipers := 0
	for i in count:
		var t := _pick_enemy(wave)
		if special == "rushers":
			t = "dog" if randf() < 0.4 else "rusher"
		elif special == "snipers":
			t = "sniper" if randf() < 0.35 else ("rifleman" if randf() < 0.6 else "grunt")
		elif t == "sniper":
			snipers += 1
			if snipers > 2 + wave / 10:
				t = "rifleman"
		q.append(t)
	if wave % 5 == 0:
		for i in ceili(wave / 10.0) + int((n - 1) / 2):
			q.insert(int(q.size() * randf_range(0.3, 0.8)), "heavy")
	elif wave > 6 and randf() < 0.35:
		q.append("heavy")
	# troop helicopter from wave 8, every 4th wave (two from wave 20)
	if wave >= 8 and wave % 4 == 0:
		for i in (2 if wave >= 20 else 1):
			q.insert(int(q.size() * randf_range(0.25, 0.6)), "HELI")
	spawn_queue = q
	spawn_t = 1.5
	wave_t = 0.0
	cut_at = randf_range(12.0, 25.0) if special == "night" or (wave >= 12 and randf() < 0.25) else -1.0
	for p in P.values():
		p.ready = false
		p.flawless = true
	ev({"t": "wave", "n": wave, "count": q.size(), "boss": wave % 5 == 0, "special": special, "mods": modifiers})


## Regular wave mix: new enemy types join as the waves go on.
func _pick_enemy(w: int) -> String:
	var r := randf()
	if w >= 7 and r < 0.07:
		return "sniper"
	if w >= 6 and r < 0.15:
		return "shield"
	if w >= 5 and r < 0.25:
		return "grenadier"
	r = randf()
	if w >= 2 and r < min(0.4, 0.1 + w * 0.03):
		return "rifleman"
	if w >= 3 and r < min(0.6, 0.25 + w * 0.035):
		return "dog" if w >= 4 and randf() < 0.4 else "rusher"
	if w >= 4 and r < min(0.78, 0.33 + w * 0.045):
		return "shotgunner"
	return "grunt"


## Every few waves something different: night (with a power cut in the mall), smoke, a rush or a sniper wave.
func _special_for(w: int) -> String:
	if w < 4 or w % 5 == 0 or w % 3 != 1:
		return ""
	return ["smoke", "rushers", "night", "snipers"][(w / 3 - 1) % 4]


func _end_wave() -> void:
	cleared = wave
	state = "inter"
	timer = 30.0
	approach = randi() % max(1, map.spawns.size())
	convoy_sent = false
	_set_power(true)
	var bonus := Defs.wave_bonus(wave)
	var i := 0
	for p in P.values():
		if p.dead or p.downed:
			_respawn(p, i)
		i += 1
		var fl := 150 if p.flawless else 0
		p.money += bonus + fl
		p.earned += bonus + fl
		p.ready = false
		ev({"t": "money", "to": p.id, "amt": bonus, "label": "WAVE SURVIVED"})
		if fl:
			ev({"t": "money", "to": p.id, "amt": fl, "label": "FLAWLESS"})
	var unl := []
	for it in Defs.SHOP:
		if it.after == cleared:
			unl.append(it.name)
	ev({"t": "wave_end", "n": wave, "bonus": bonus, "unlocks": unl})


func _respawn(p: Dictionary, idx: int) -> void:
	var s: Vector3 = map.player_spawns[idx % map.player_spawns.size()]
	p.dead = false
	p.downed = false
	p.hp = 100.0
	p.pos = s
	p.tp = 1
	ev({"t": "respawn", "to": p.id})


func _spawn_enemy(type: String, at = null) -> void:
	if type == "HELI":
		_spawn_heli()
		return
	var best: Vector3 = map.spawns[0]
	var bs := -1.0
	for k in 3:
		var s: Vector3 = map.spawns[randi() % map.spawns.size()]
		var d := 1e9
		for p in P.values():
			d = min(d, s.distance_to(p.pos))
		var score: float = min(d, 30.0) + randf() * 10.0
		if approach >= 0 and approach < map.spawns.size():
			score -= s.distance_to(map.spawns[approach]) * 0.35     # most come the way the convoy arrived
		if score > bs:
			bs = score
			best = s
	if at != null:
		best = at
	var hp_mul: float = 1.0 + max(0, wave - 1) * 0.045 + (P.size() - 1) * 0.15
	var e := Enemy.new()
	e.id = next_id
	next_id += 1
	e.type = type
	e.game = self
	e.max_hp = Defs.ENEMIES[type].hp * hp_mul
	e.hp = e.max_hp
	if not Defs.ENEMIES[type].get("melee", false) and enemies.size() >= 3 and randf() < 0.3:
		e.role = "flank"
	e.name = "E%d" % e.id
	enemies[e.id] = e
	enemies_root.add_child(e)
	e.global_position = best + Vector3(randf_range(-1.5, 1.5), 0.05, randf_range(-1.5, 1.5))


func _game_over() -> void:
	state = "over"
	var stats := []
	for p in P.values():
		stats.append({"id": p.id, "name": p.name, "kills": p.kills, "heads": p.heads, "earned": p.earned, "downs": p.downs})
	ev({"t": "gameover", "wave": wave, "stats": stats})


# =========================================================================== server tick
func _physics_process(dt: float) -> void:
	time += dt
	if is_server:
		_server_tick(dt)
		if not events.is_empty():
			var list := events
			events = []
			for e in list:
				_on_event(e)
			for pid in _remote_joined():
				c_events.rpc_id(pid, list)
		snap_t -= dt
		if snap_t <= 0.0:
			snap_t = 1.0 / SNAP_HZ
			var s := _snapshot()
			_apply_snapshot(s)
			for pid in _remote_joined():
				c_snap.rpc_id(pid, s)


## Remote peers that have finished loading the map and joined (only they receive game traffic;
## sending to a peer still building the level breaks Godot's RPC path cache for that node).
func _remote_joined() -> Array:
	var out := []
	var peers := multiplayer.get_peers()
	for id in P:
		if id != local_id and id in peers:
			out.append(id)
	return out


func _server_tick(dt: float) -> void:
	var any_up := false
	nade_cd -= dt
	for p in P.values():
		if (p.pos as Vector3).distance_to(p.camp_at) > 4.0:
			p.camp_at = p.pos
			p.camp_t = 0.0
		else:
			p.camp_t += dt
		if p.combo_t > 0.0:
			p.combo_t -= dt
			if p.combo_t <= 0.0:
				p.combo = 0
		if p.dead:
			continue
		if p.downed:
			p.down_t -= dt
			var helper = null
			for q in P.values():
				if q != p and not q.downed and not q.dead and q.rev == p.id and q.pos.distance_to(p.pos) < 3.0:
					helper = q
			if helper:
				p.rev_p += dt / 3.0
				p.down_t += dt
			else:
				p.rev_p = max(0.0, p.rev_p - dt)
			if p.rev_p >= 1.0:
				p.downed = false
				p.hp = 40.0
				p.last_dmg = time - 3.0
				ev({"t": "revived", "pid": p.id, "by": helper.id})
				helper.money += 100
				helper.earned += 100
				ev({"t": "money", "to": helper.id, "amt": 100, "label": "REVIVE"})
			elif p.down_t <= 0.0:
				if p.self_revive:
					p.self_revive = 0
					p.downed = false
					p.hp = 60.0
					p.last_dmg = time - 2.0
					ev({"t": "revived", "pid": p.id, "by": p.id})
				else:
					p.dead = true
					ev({"t": "died", "pid": p.id})
		elif p.hp < 100.0 and time - p.last_dmg > 5.0:
			p.hp = min(100.0, p.hp + 30.0 * dt)
		if not p.dead and (not p.downed or p.self_revive):
			any_up = true
	if state != "over" and P.size() > 0 and _alive_players().is_empty() and not any_up:
		_game_over()

	if state == "inter":
		if P.size() > 0:
			timer -= dt
		# trucks pull up and doors slam where the next wave will come from
		if timer < 9.0 and not convoy_sent and approach >= 0 and approach < map.spawns.size():
			convoy_sent = true
			ev({"t": "convoy", "pos": map.spawns[approach]})
		if timer <= 0.0:
			_start_wave()
	elif state == "active":
		wave_t += dt
		if cut_at > 0.0 and wave_t > cut_at and power:
			_set_power(false)
			ev({"t": "announce", "text": "THEY CUT THE POWER", "sub": "Night vision is in the Equipment Armory", "snd": "radio"})
		spawn_t -= dt
		var cap: int = min(30, 12 + wave + (P.size() - 1) * 4)
		if not spawn_queue.is_empty() and spawn_t <= 0.0 and enemies.size() < cap:
			_spawn_enemy(spawn_queue.pop_front())
			spawn_t = randf_range(0.35, 1.2) * max(0.45, 1.0 - wave * 0.03)
		if spawn_queue.is_empty() and enemies.is_empty():
			_end_wave()
	if state != "over":
		_tick_projectiles(dt)
		_tick_support(dt)
		_tick_helis(dt)


func _tick_projectiles(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for id in projectiles.keys():
		var p: Dictionary = projectiles[id]
		p.fuse -= dt
		var boom: bool = p.fuse <= 0.0
		var from: Vector3 = p.pos
		if p.k == "frag":
			p.vel.y -= 16.0 * dt
			var to: Vector3 = from + p.vel * dt
			var q := PhysicsRayQueryParameters3D.create(from, to, Defs.L_WORLD)
			var r := space.intersect_ray(q)
			if r:
				var n: Vector3 = r.normal
				p.vel = p.vel.bounce(n) * 0.4
				p.pos = r.position + n * 0.06
				if n.y > 0.7 and p.vel.length() < 1.0:
					p.vel = Vector3.ZERO
			else:
				p.pos = to
		else:
			var to: Vector3 = from + p.vel * dt
			var q := PhysicsRayQueryParameters3D.create(from, to, Defs.L_WORLD | Defs.L_HITBOX)
			q.collide_with_areas = true
			var r := space.intersect_ray(q)
			if r:
				p.pos = r.position
				boom = true
			else:
				p.pos = to
			if abs(p.pos.x) > 120 or abs(p.pos.z) > 120 or p.pos.y > 80:
				boom = true
		if boom:
			projectiles.erase(id)
			if p.k == "frag":
				_explode(p.pos + Vector3(0, 0.2, 0), 7.0, 260.0, p.owner, "frag")
			else:
				_explode(p.pos, 6.5, 420.0, p.owner, "rocket")
	for id in mines.keys():
		var m: Dictionary = mines[id]
		if m.arm > 0.0:
			m.arm -= dt
			continue
		for e in enemies.values():
			if e.global_position.distance_to(m.pos) < 2.4:
				mines.erase(id)
				_explode(m.pos + Vector3(0, 0.3, 0), 6.0, 320.0, m.owner, "mine")
				break


func _tick_support(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for id in turrets.keys():
		var t: Dictionary = turrets[id]
		t.life -= dt
		t.cd -= dt
		if t.life <= 0.0:
			turrets.erase(id)
			continue
		var tgt: Enemy = null
		var td := 32.0
		var eye: Vector3 = t.pos + Vector3(0, 1.1, 0)
		for e in enemies.values():
			var d: float = e.global_position.distance_to(t.pos)
			if d < td and not _blocked(space, eye, e.global_position + Vector3(0, 1.2, 0)):
				td = d
				tgt = e
		if tgt:
			var dv: Vector3 = tgt.global_position - t.pos
			var want := atan2(-dv.x, -dv.z)
			var diff := wrapf(want - t.yaw, -PI, PI)
			t.yaw += clamp(diff, -dt * 5.0, dt * 5.0)
			if abs(diff) < 0.25 and t.cd <= 0.0:
				t.cd = 0.11
				var hit := randf() < 0.8
				var end: Vector3 = tgt.global_position + Vector3(0, 1.2, 0) + (Vector3.ZERO if hit else Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
				ev({"t": "shot", "pid": 0, "w": "turret", "tid": id, "o": eye + Vector3(-sin(t.yaw), 0, -cos(t.yaw)) * 0.7, "e": end})
				if hit:
					_damage_enemy(tgt, 22.0, P.get(t.owner), {"src": "turret"})
	for id in drones.keys():
		var d: Dictionary = drones[id]
		d.life -= dt
		d.cd -= dt
		d.a += dt * 0.35
		d.pos = Vector3(sin(d.a) * 30.0, 30.0, cos(d.a) * 30.0)
		if d.life <= 0.0:
			drones.erase(id)
			ev({"t": "msg", "text": "Gunship leaving the area"})
			continue
		if d.cd <= 0.0 and not enemies.is_empty():
			var tgt: Enemy = null
			var list := enemies.values()
			for k in 6:
				var e: Enemy = list[randi() % list.size()]
				if not _blocked(space, d.pos, e.global_position + Vector3(0, 1.2, 0)):
					tgt = e
					break
			d.cd = 0.13 if tgt else 0.4
			if tgt:
				d.burst += 1
				if d.burst > 14:
					d.burst = 0
					d.cd = 1.1
				var hit := randf() < 0.7
				var end: Vector3 = tgt.global_position + Vector3(0, 1.0, 0) + (Vector3.ZERO if hit else Vector3(randf_range(-1.5, 1.5), -1.0, randf_range(-1.5, 1.5)))
				ev({"t": "shot", "pid": 0, "w": "gunship", "o": d.pos - Vector3(0, 1, 0), "e": end})
				if hit:
					_damage_enemy(tgt, 55.0, P.get(d.owner), {"src": "drone"})
	var i := strikes.size() - 1
	while i >= 0:
		var s: Dictionary = strikes[i]
		s.t -= dt
		if s.t <= 0.0:
			s.gap -= dt
			while s.gap <= 0.0 and s.n < s.count:
				var off: float = (s.n - (s.count - 1) / 2.0) * s.spacing
				var pos: Vector3 = s.pos + Vector3(sin(s.ang), 0, cos(s.ang)) * off + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
				_explode(pos, 9.5, 700.0, s.owner, "strike")
				s.n += 1
				s.gap += 0.14
			if s.n >= s.count:
				strikes.remove_at(i)
		i -= 1


# =========================================================================== server: enemy helicopter
func _spawn_heli() -> void:
	var drop: Vector3 = map.spawns[randi() % map.spawns.size()]
	var away := Vector3(drop.x, 0, drop.z)
	away = away.normalized() if away.length() > 1.0 else Vector3.FORWARD
	var from := drop + away * 260.0 + Vector3(0, 55, 0)
	var hp: float = Defs.HELI.hp * (1.0 + wave * 0.03 + (P.size() - 1) * 0.25)
	helis[next_id] = {"pos": from, "yaw": atan2(-(drop - from).x, -(drop - from).z), "hp": hp, "max": hp, "ph": "in", "t": 0.0,
		"drop": drop, "from": from, "troops": Defs.HELI.troops + wave / 8, "cd": 2.0, "burst": 0}
	next_id += 1
	ev({"t": "announce", "text": "ENEMY HELICOPTER", "sub": "Troop transport inbound — shoot it down", "snd": "radio"})


func _tick_helis(dt: float) -> void:
	var space := get_world_3d().direct_space_state
	for id in helis.keys():
		var h: Dictionary = helis[id]
		h.t += dt
		var hover: Vector3 = h.drop + Vector3(0, 15.0, 0)
		match h.ph:
			"in":
				var to: Vector3 = hover - h.pos
				if to.length() < 1.5:
					h.ph = "drop"
					h.t = 0.0
				else:
					h.pos += to.normalized() * min(to.length(), 30.0 * dt * clamp(to.length() / 25.0, 0.3, 1.0))
					h.yaw = lerp_angle(h.yaw, atan2(-to.x, -to.z), min(1.0, dt * 2.0))
			"drop":
				h.pos = hover + Vector3(sin(h.t * 1.3) * 0.4, sin(h.t * 0.9) * 0.3, 0)
				if h.troops > 0 and fmod(h.t, 1.1) < dt and h.t > 1.0:
					h.troops -= 1
					_spawn_enemy("rifleman" if randf() < 0.6 else "grunt", (h.drop as Vector3) + Vector3(randf_range(-2.5, 2.5), 0.1, randf_range(-2.5, 2.5)))
				if h.troops <= 0 and h.t > 3.0:
					h.ph = "out"
			"out":
				var to: Vector3 = (h.from as Vector3) - h.pos
				h.pos += to.normalized() * 32.0 * dt
				h.yaw = lerp_angle(h.yaw, atan2(-to.x, -to.z), min(1.0, dt * 1.5))
				if to.length() < 5.0:
					helis.erase(id)
					continue
		# door gunner
		h.cd -= dt
		if h.cd <= 0.0 and h.ph != "out":
			var gun: Vector3 = h.pos - Vector3(0, 1.6, 0)
			var tgt = null
			var td := 90.0
			for p in _alive_players():
				var d: float = (p.pos as Vector3).distance_to(gun)
				if d < td and not _blocked(space, gun, p.pos + Vector3(0, 1.2, 0)):
					td = d
					tgt = p
			if tgt == null:
				h.cd = 0.5
				continue
			h.burst += 1
			h.cd = 0.11 if h.burst < 12 else randf_range(1.5, 2.5)
			if h.burst >= 12:
				h.burst = 0
			var hit := randf() < 0.22
			var end: Vector3 = tgt.pos + Vector3(0, 1.1, 0)
			if hit:
				damage_player(tgt, Defs.HELI.dmg * (1.0 + wave * 0.02), gun)
			else:
				end += Vector3(randf_range(-2, 2), randf_range(-1.2, 0.5), randf_range(-2, 2))
			ev({"t": "shot", "pid": -1, "w": "heli_gun", "o": gun, "e": end, "hit": hit})


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


# =========================================================================== snapshot
func _snapshot() -> Dictionary:
	var pl := []
	for p in P.values():
		pl.append({"id": p.id, "n": p.name, "p": p.pos, "yaw": p.yaw, "pitch": p.pitch, "cr": p.cr, "hp": ceili(p.hp), "ar": ceili(p.armor),
			"m": p.money, "w": p.weapons.duplicate(), "cur": p.cur, "fr": p.frags, "mi": p.mines, "tu": p.turrets, "sr": p.self_revive,
			"as": p.strikes, "dr": p.drones, "cb": p.carpets, "dn": p.downed, "dd": p.dead, "dt": p.down_t, "rp": p.rev_p,
			"k": p.kills, "h": p.heads, "e": p.earned, "rd": p.ready, "co": p.combo, "tp": p.tp, "at": p.att.duplicate(true), "nv": p.nvg})
	var en := []
	for e in enemies.values():
		en.append([e.id, e.type, e.global_position, e.rotation.y, roundi(100.0 * e.hp / e.max_hp), e.st, e.moving])
	var pr := []
	for id in projectiles:
		pr.append([id, projectiles[id].k, projectiles[id].pos])
	var mi := []
	for id in mines:
		mi.append([id, mines[id].pos, mines[id].yaw, mines[id].arm <= 0.0])
	var tu := []
	for id in turrets:
		tu.append([id, turrets[id].pos, turrets[id].yaw, ceili(turrets[id].life)])
	var dr := []
	for id in drones:
		dr.append([id, drones[id].pos, drones[id].a])
	var he := []
	for id in helis:
		he.append([id, helis[id].pos, helis[id].yaw, roundi(100.0 * helis[id].hp / helis[id].max)])
	_snap_n += 1
	var extra := {}
	if _snap_n % 20 == 0:          # full glass / light state once a second, for late joiners (changes go out as events)
		extra = {"gb": glass_broken.keys(), "lo": lights_out.keys()}
	return extra.merged({"wave": wave, "cleared": cleared, "state": state, "timer": ceili(timer), "left": enemies.size() + spawn_queue.size(),
		"players": pl, "enemies": en, "proj": pr, "mines": mi, "turrets": tu, "drones": dr, "helis": he, "time": time,
		"sp": special, "mods": modifiers, "pw": power})


func _apply_snapshot(s: Dictionary) -> void:
	snap = s
	var now := Time.get_ticks_msec() / 1000.0
	# players
	var seen := {}
	for ps in s.players:
		var id: int = ps.id
		seen[id] = true
		if id == local_id:
			me = ps
		var node: Player = player_nodes.get(id)
		if node == null:
			node = Player.new()
			node.peer_id = id
			node.game = self
			node.is_local = id == local_id
			node.name = "P%d" % id
			players_root.add_child(node)
			player_nodes[id] = node
		node.apply_state(ps, now)
	for id in player_nodes.keys():
		if not seen.has(id):
			player_nodes[id].queue_free()
			player_nodes.erase(id)
	# enemies (clients build interpolated puppets; the server's enemies are the real thing)
	if not is_server:
		var eseen := {}
		for a in s.enemies:
			var id: int = a[0]
			eseen[id] = true
			var e: Enemy = enemies.get(id)
			if e == null:
				e = Enemy.new()
				e.id = id
				e.type = a[1]
				e.game = self
				e.puppet = true
				e.name = "E%d" % id
				enemies[id] = e
				enemies_root.add_child(e)
				e.global_position = a[2]
			e.push_state(now, a[2], a[3], a[4], a[5], a[6])
		for id in enemies.keys():
			if not eseen.has(id):
				var e: Enemy = enemies[id]
				enemies.erase(id)
				if not e.model.dead:
					e.queue_free()
	_sync_objects(s)
	if hud:
		hud.on_snapshot(s, me)


func _obj(key: String, make: Callable) -> Node3D:
	var n: Node3D = obj_nodes.get(key)
	if n == null:
		n = make.call()
		objects_root.add_child(n)
		obj_nodes[key] = n
	n.set_meta("seen", true)
	return n


func _sync_objects(s: Dictionary) -> void:
	for n in obj_nodes.values():
		n.set_meta("seen", false)
	for a in s.proj:
		var n := _obj("p%d" % a[0], func(): return Props.frag() if a[1] == "frag" or a[1] == "efrag" else Props.rocket())
		if not n.has_meta("prev"):
			n.global_position = a[2]
		var prev: Vector3 = n.get_meta("prev", a[2])
		n.set_meta("target", a[2])
		n.set_meta("prev", a[2])
		if a[1] == "rocket" and prev.distance_to(a[2]) > 0.01:
			n.look_at_from_position(a[2], a[2] + (a[2] - prev), Vector3.UP)
		elif a[1] != "rocket":
			n.global_position = a[2]
	for a in s.mines:
		var n := _obj("m%d" % a[0], func(): return Props.claymore())
		n.global_position = a[1]
		n.rotation.y = a[2]
		n.set_meta("armed", a[3])
	for a in s.turrets:
		var n := _obj("t%d" % a[0], func(): return Props.turret())
		n.global_position = a[1]
		(n.get_meta("head") as Node3D).rotation.y = lerp_angle((n.get_meta("head") as Node3D).rotation.y, a[2], 0.5)
	for a in s.drones:
		var n := _obj("d%d" % a[0], func(): return Props.gunship())
		if not n.has_meta("target"):
			n.global_position = a[1]
		n.set_meta("target", a[1])
		n.set_meta("ang", a[2])
	for a in s.get("helis", []):
		var hid: int = a[0]
		var n := _obj("h%d" % hid, func(): return _make_heli(hid))
		if not n.has_meta("target"):
			n.global_position = a[1]
		n.set_meta("target", a[1])
		n.set_meta("yaw", a[2])
	# breakable glass / lights / power, mirrored from the server (covers late joiners too)
	for gid in s.get("gb", []):
		map.break_glass(int(gid), false)
	for lid in s.get("lo", []):
		map.shoot_light(int(lid), false)
	map.set_power(bool(s.get("pw", true)))
	for k in obj_nodes.keys():
		var n: Node3D = obj_nodes[k]
		if not n.get_meta("seen"):
			n.queue_free()
			obj_nodes.erase(k)


func _make_heli(hid: int) -> Node3D:
	var n := Props.helicopter()
	(n.get_meta("hitbox") as Area3D).set_meta("heli_id", hid)
	var snd := AudioStreamPlayer3D.new()
	snd.stream = Sfx.streams.get("rotor")
	snd.bus = "World"
	snd.unit_size = 25.0
	snd.max_distance = 500.0
	snd.volume_db = 4.0
	n.add_child(snd)
	snd.autoplay = true
	return n


func _process(dt: float) -> void:
	_update_lasers(dt)
	if map and not snap.is_empty():
		map.update_daylight(int(snap.get("wave", 0)), str(snap.get("sp", "")), str(snap.get("state", "")), dt)
	# Smooth object visuals between snapshots
	for k in obj_nodes:
		var n: Node3D = obj_nodes[k]
		if k.begins_with("h"):
			var t: Vector3 = n.get_meta("target")
			n.global_position = n.global_position.lerp(t, min(1.0, dt * 6.0))
			n.rotation.y = lerp_angle(n.rotation.y, float(n.get_meta("yaw")), min(1.0, dt * 4.0))
			(n.get_meta("rotor") as Node3D).rotate_y(dt * 28.0)
			(n.get_meta("tail_rotor") as Node3D).rotate_x(dt * 40.0)
			continue
		if n.has_meta("target"):
			var t: Vector3 = n.get_meta("target")
			if k.begins_with("p"):
				var v: Vector3 = t - n.global_position
				n.global_position = n.global_position.lerp(t, min(1.0, dt * 18.0))
				if v.length() > 0.05 and k.begins_with("p") and n.has_meta("rocket"):
					fx.trail(n.global_position)
			elif k.begins_with("d"):
				n.global_position = n.global_position.lerp(t, min(1.0, dt * 4.0))
				var a: float = n.get_meta("ang")
				var dir := Vector3(cos(a), 0, -sin(a))
				n.look_at(n.global_position + dir, Vector3.UP)
				n.rotation.z = -0.35
		if k.begins_with("m"):
			var led: Node3D = n.get_meta("led")
			led.visible = n.get_meta("armed") and fmod(time * 2.0, 1.0) < 0.15


# =========================================================================== events (all peers)
func _on_event(e: Dictionary) -> void:
	var lp: Player = player_nodes.get(local_id)
	var mine: bool = e.get("to", -1) == local_id
	match e.t:
		"msg":
			if hud: hud.feed(e.text)
		"shot":
			_on_shot(e, lp)
		"hit":
			if mine and hud and e.get("src", "") in ["frag", "rocket", "mine", "strike"]:
				hud.hitmarker(false, false)
		"kill":
			_on_kill(e)
		"dmg":
			if mine and lp:
				lp.on_damaged(e.from, e.amt)
		"down":
			var name := _pname(e.pid)
			if hud: hud.feed("<%s is down!>" % name if e.pid != local_id else "You are down!")
			if e.pid == local_id and lp: lp.on_downed()
		"revived":
			if hud: hud.feed("%s is back up" % _pname(e.pid))
			if e.pid == local_id and lp: lp.on_revived()
		"died":
			if hud: hud.feed("%s was killed in action" % _pname(e.pid))
		"respawn":
			if mine and lp: lp.on_respawn()
		"wave":
			Sfx.play("wave_start", -2.0, 1.0, 0.0)
			if hud: hud.announce("WAVE %d" % e.n, ("JUGGERNAUT INCOMING — %d hostiles" if e.boss else "%d hostiles inbound") % e.count, 3.0)
		"wave_end":
			Sfx.play("wave_end", -4.0, 1.0, 0.0)
			var sub := "+$%d   ·   Armory restocked" % e.bonus
			if not e.unlocks.is_empty():
				sub += "\nNEW UNLOCKS: " + ", ".join(e.unlocks)
				get_tree().create_timer(1.0).timeout.connect(func(): Sfx.play("unlock", -4.0, 1.0, 0.0))
			if hud: hud.announce("WAVE %d SURVIVED" % e.n, sub, 4.5)
		"money":
			if mine and hud:
				hud.money_pop(e.amt, e.label)
				Sfx.play("money", -10.0)
		"buy":
			if mine:
				if lp: lp.on_buy(e)
				if hud: hud.on_buy(e)
		"explode":
			fx.explosion(e.pos, e.r)
			Sfx.play_at("explosion", e.pos, 6.0, 1.0 if e.r < 8 else 0.8, 400.0)
			if lp:
				var d: float = lp.global_position.distance_to(e.pos)
				fx.shake = max(fx.shake, clamp(1.0 - d / 45.0, 0.0, 1.0) * 1.2)
		"strike_mark":
			_jet_run(e.pos, e.ang, e.delay, e.len)
		"announce":
			if e.has("snd"): Sfx.play(e.snd, -4.0, 1.0, 0.0)
			if hud: hud.announce(e.text, e.sub, 2.5)
		"gameover":
			if hud: hud.feed("Mission failed")
			game_over.emit(e.stats, e.wave)
		"restart":
			for id in enemies.keys():
				enemies[id].queue_free()
			enemies.clear()
			if lp: lp.on_restart()
			if hud: hud.on_restart()


func _pname(id: int) -> String:
	for ps in snap.get("players", []):
		if ps.id == id:
			return ps.n
	return "Soldier"


func _on_shot(e: Dictionary, lp: Player) -> void:
	var o: Vector3 = e.o
	var end: Vector3 = e.e
	var w: String = e.w
	if e.pid == local_id:
		return
	match w:
		"turret":
			fx.tracer(o, end, Color(4, 3, 1.6, 0.8), 0.018)
			Sfx.play_at("turret", o, -2.0)
			var n: Node3D = obj_nodes.get("t%d" % e.get("tid", -1))
			if n: (n.get_meta("flash") as Node3D).visible = true
			if n: get_tree().create_timer(0.05).timeout.connect(func(): if is_instance_valid(n): (n.get_meta("flash") as Node3D).visible = false)
		"gunship":
			fx.tracer(o, end, Color(5, 2.2, 1.2, 0.9), 0.06, 300.0)
			Sfx.play_at("gunship", o, 8.0, 1.0, 400.0)
			fx.impact(end, Vector3.UP, "ground")
		"knife":
			Sfx.play_at("stab", end, 0.0)
		_:
			if e.has("eid"):
				var en: Enemy = enemies.get(e.eid)
				if en: en.model.muzzle_flash()
				var snd := "enemy_shotgun" if e.w == "shotgun" else "enemy_lmg" if e.w == "lmg" else "enemy_rifle"
				Sfx.play_at(snd, o, 0.0)
				fx.tracer(o, end, Color(4, 2.6, 1.2, 0.8), 0.018, 320.0)
				if lp and not e.get("hit", false):
					var cam := lp.global_position + Vector3(0, 1.6, 0)
					var seg := end - o
					var t: float = clamp((cam - o).dot(seg) / max(0.001, seg.length_squared()), 0.0, 1.0)
					if (o + seg * t).distance_to(cam) < 2.0:
						Sfx.play_at("whiz", o + seg * t, -4.0)
					else:
						fx.impact(end, (o - end).normalized(), "concrete")
			else:
				var pn: Player = player_nodes.get(e.pid)
				if pn and pn.model and not e.get("q", false): pn.model.muzzle_flash()
				Sfx.play_gun(w, o, e.get("q", false))
				if not e.get("q", false):
					fx.tracer(o, end)


func _on_kill(e: Dictionary) -> void:
	var en: Enemy = enemies.get(e.eid)
	if en == null:
		en = dying.get(e.eid)
	dying.erase(e.eid)
	enemies.erase(e.eid)
	if not is_instance_valid(en):
		en = null
	# Ragdoll-ish death body: reuse the enemy's model (detach from the freed enemy node)
	var model: Soldier = null
	if en and en.model:
		model = en.model
		var xf := model.global_transform
		en.remove_child(model)
		enemies_root.add_child(model)
		model.global_transform = xf
	if en:
		en.queue_free()
	if model:
		model.die(e.dir, e.expl)
		var corpses := enemies_root.get_children().filter(func(c): return c is Soldier)
		if corpses.size() > 24:
			corpses[0].queue_free()
	Sfx.play_at("impact_flesh", e.pos + Vector3(0, 1, 0), 0.0)
	if e.pid == local_id and hud:
		hud.on_kill(e)
	elif hud:
		hud.feed("%s  ✕  %s" % [_pname(e.pid) if e.pid else "Support", Defs.ENEMIES[e.et].name])


func _jet_run(center: Vector3, ang: float, delay: float, length: float) -> void:
	var dir := Vector3(sin(ang), 0, cos(ang))
	var jet := Props.jet()
	objects_root.add_child(jet)
	var speed := 130.0
	var start := center - dir * speed * delay + Vector3(0, 55, 0)
	jet.global_position = start
	jet.look_at(start + dir, Vector3.UP)
	var tw := create_tween()
	tw.tween_property(jet, "global_position", start + dir * speed * (delay + 3.0), delay + 3.0)
	tw.tween_callback(jet.queue_free)
	get_tree().create_timer(max(0.0, delay - 1.6)).timeout.connect(func(): Sfx.play("jet", 2.0, 1.0, 0.0))
	# red smoke on the target
	for i in 10:
		get_tree().create_timer(i * 0.3).timeout.connect(func(): fx.particle(false, center + Vector3(0, 0.3, 0), Vector3(randf_range(-0.3, 0.3), 1.5, randf_range(-0.3, 0.3)), 0.5, 3.0, 3.0, Color(0.8, 0.12, 0.08, 0.6)))


# =========================================================================== client effects for the new threats
## Sniper laser: a red beam from the sniper to the player it is aiming at, for the aim duration.
func _on_laser(e: Dictionary) -> void:
	var old: Dictionary = lasers.get(e.eid, {})
	if not old.is_empty():
		(old.node as Node3D).queue_free()
		lasers.erase(e.eid)
	if int(e.pid) < 0:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	mi.mesh = cyl
	mi.material_override = Mat.emissive(Color(1.0, 0.05, 0.03), 6.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	objects_root.add_child(mi)
	lasers[e.eid] = {"pid": int(e.pid), "t": float(e.d), "node": mi}
	if int(e.pid) == local_id:
		Sfx.play("laser", -6.0, 1.0, 0.0)
		if hud: hud.feed("<Sniper has you in his sights!>")


func _update_lasers(dt: float) -> void:
	for eid in lasers.keys():
		var l: Dictionary = lasers[eid]
		l.t -= dt
		var en: Enemy = enemies.get(eid)
		var pn: Player = player_nodes.get(l.pid)
		if l.t <= -0.2 or en == null or pn == null or not is_instance_valid(en) or en.model == null or en.model.gun == null:
			(l.node as Node3D).queue_free()
			lasers.erase(eid)
			continue
		var a: Vector3 = (en.model.gun.get_meta("muzzle") as Node3D).global_position
		var b: Vector3 = pn.global_position + Vector3(0, 1.45 if not (pn.is_local and pn.crouch) else 0.95, 0)
		if pn.is_local:
			b = pn.cam.global_position + Vector3(0, -0.12, 0)     # aim it at the chest so it shows on screen
		var mi: MeshInstance3D = l.node
		var len := a.distance_to(b)
		mi.global_transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2), (a + b) * 0.5)
		mi.scale = Vector3(1, len, 1)
		mi.visible = fmod(time * 10.0, 1.0) < 0.85 or l.t > 0.6


## Before a wave: engines and door slams from the direction the next wave will mostly come from.
func _convoy(pos: Vector3) -> void:
	Sfx.play_at("engine", pos, 6.0, 1.0, 500.0)
	for i in 5:
		get_tree().create_timer(2.8 + i * randf_range(0.35, 0.7)).timeout.connect(func(): Sfx.play_at("door", pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), 2.0, randf_range(0.9, 1.1), 400.0))
	if hud: hud.feed("You hear vehicles pulling up…")


func _heli_wreck(pos: Vector3, yaw: float) -> void:
	var n := Props.helicopter()
	objects_root.add_child(n)
	n.global_position = pos
	n.rotation.y = yaw
	var ground := Vector3(pos.x, 0.6, pos.z)
	var tw := create_tween()
	tw.tween_property(n, "global_position", ground, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(n, "rotation", Vector3(0.5, yaw + 4.0, 0.7), 1.6)
	tw.tween_callback(func():
		fx.explosion(ground, 10.0)
		Sfx.play_at("explosion", ground, 8.0, 0.7, 500.0))
	for i in 30:
		get_tree().create_timer(1.6 + i * 0.5).timeout.connect(func(): if is_instance_valid(n): fx.particle(false, ground + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)), Vector3(0, 2.5, 0), 1.5, 4.0, 6.0, Color(0.1, 0.1, 0.1, 0.55)))
	get_tree().create_timer(18.0).timeout.connect(func(): if is_instance_valid(n): n.queue_free())
