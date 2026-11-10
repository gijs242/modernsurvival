class_name Game
extends GameSync
## Game session. On the server (host / singleplayer / dedicated) this runs the authoritative
## simulation: waves, enemy AI, money, shop, support items. Every peer (server included) renders
## from the same events + snapshots, so singleplayer and co-op share one code path.
## (part 5 of 5: setup, networking, player commands, the physics / process loop and client-side events;
## state, combat, waves and snapshots live in game_state.gd, game_combat.gd, game_waves.gd, game_sync.gd)

const SNAP_HZ := 20.0
const INTERP := 0.1
var _snaps_rx := 0


func setup(p_quality: int, p_map := "yard") -> void:
	quality = p_quality
	diff_id = Net.difficulty if Defs.DIFFICULTY.has(Net.difficulty) else "regular"
	diff = Defs.DIFFICULTY[diff_id]
	is_server = multiplayer.is_server()
	local_id = multiplayer.get_unique_id()
	map = GameMap.new()
	map.name = "Map"
	add_child(map)
	map.build(is_server, quality, p_map)
	reset_local_stats()
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
	if e.pid == local_id:
		var w: String = e.get("w", "")
		if w == "":
			w = e.get("src", "") if e.get("src", "") != "" else ("melee" if e.get("melee", false) else "explosives")
		local_stats.kills_w[w] = int(local_stats.kills_w.get(w, 0)) + 1
		local_stats.best_combo = max(int(local_stats.best_combo), int(e.get("combo", 0)))
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


## Every peer: the body flinches (head snap / leg buckle), gets a wound mark, and blood hits the wall behind it.
func _hit_fx(e: Dictionary, mine: bool) -> void:
	var en: Enemy = enemies.get(e.get("eid", -1))
	if en == null or not is_instance_valid(en) or en.model == null or not e.has("from"):
		return
	var chest := en.global_position + Vector3(0, 1.2 * en.s, 0)
	var dir: Vector3 = chest - (e.from as Vector3) - Vector3(0, 1.5, 0)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var zone: int = e.get("zone", 1)
	en.model.hit_react(dir, zone, float(e.dmg) / 40.0)
	if e.get("src", "") == "":
		en.model.add_wound(dir, zone)
		if not mine:                      # the shooter already splattered the wall locally
			fx.blood(chest, dir, zone == 0, get_world_3d().direct_space_state)


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
