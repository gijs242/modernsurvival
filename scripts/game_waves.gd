class_name GameWaves
extends GameCombat
## Game session, part 3 of 5 (server): players, waves and spawning, the server tick, projectiles,
## support items and the enemy helicopter.

## Build one of every enemy body (and its weapon) during the level load, so the first sniper or breacher
## of a run doesn't stall the game for a few hundred ms while its model loads from disk.
func _warm_up() -> void:
	for t in Defs.ENEMIES:
		var d: Dictionary = Defs.ENEMIES[t]
		var m: Soldier = Dog.new() if d.get("dog", false) else Soldier.new()
		m.setup(t, d.gun)
		m.free()
	Props.helicopter().free()


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
	e.game = self as Game
	e.max_hp = Defs.ENEMIES[type].hp * hp_mul * diff.hp
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


func _spawn_heli() -> void:
	var drop: Vector3 = map.spawns[randi() % map.spawns.size()]
	var away := Vector3(drop.x, 0, drop.z)
	away = away.normalized() if away.length() > 1.0 else Vector3.FORWARD
	var from := drop + away * 260.0 + Vector3(0, 55, 0)
	var hp: float = Defs.HELI.hp * (1.0 + wave * 0.03 + (P.size() - 1) * 0.25) * diff.hp
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
				damage_player(tgt, Defs.HELI.dmg * (1.0 + wave * 0.02) * diff.dmg, gun)
			else:
				end += Vector3(randf_range(-2, 2), randf_range(-1.2, 0.5), randf_range(-2, 2))
			ev({"t": "shot", "pid": -1, "w": "heli_gun", "o": gun, "e": end, "hit": hit})
