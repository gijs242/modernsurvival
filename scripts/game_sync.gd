class_name GameSync
extends GameWaves
## Game session, part 4 of 5: building snapshots on the server and applying them on every peer.

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
		"sp": special, "mods": modifiers, "pw": power, "df": diff_id})


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
			node.game = self as Game
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
				e.game = self as Game
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
