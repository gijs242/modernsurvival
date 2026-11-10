class_name Enemy
extends CharacterBody3D
## Hostile soldier (or attack dog). On the server it runs AI: navmesh pathing, line of sight, burst fire,
## strafing, taking cover behind low walls and popping up to shoot, flanking through side routes,
## grenades at players who camp, snipers that paint their target with a laser first, melee rushers.
## On clients it is an interpolated puppet. Both have hitboxes for client-side hit detection
## (0 head / 1 torso / 2 legs / 3 riot shield).

enum { ADVANCE, TO_COVER, IN_COVER }

var id := 0
var type := "grunt"
var game: Game
var puppet := false
var hp := 100.0
var max_hp := 100.0
var hp_pct := 100
var alert := false
var st := 0          # 0 moving, 1 engaging, 2 melee strike, 3 crouched in cover, 4 aiming (sniper)
var moving := false
var model: Soldier
var def: Dictionary
var s := 1.0         # scale

# AI
var agent: NavigationAgent3D
var los := false
var los_t := 0.0
var seen := 0.0
var burst := 0
var cd := 1.0
var strafe := 1.0
var strafe_t := 0.0
var spd := 3.0
var repath_t := 0.0
var st_t := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var mode := ADVANCE
var role := "assault"   # "flank": takes a side route before engaging
var flank_side := 1.0
var flank_t := 0.0
var cover_pos := Vector3.ZERO
var peek_pos := Vector3.ZERO     # where to step out to shoot (== cover_pos for low cover you shoot over)
var cover_t := 0.0
var cover_search_t := 0.0
var lost_t := 0.0
var to_cover_t := 0.0
var aim_t := 0.0
var aim_pid := -1
var nade_cd := 0.0
var hitboxes: Array = []   # [CollisionShape3D, base y]
var _far := false
var act := 0              # timed action shown as the state: 2 bash, 5 reloading, 6 throwing, 7 staggered
var act_t := 0.0
var bursts_left := 4      # bursts until a reload
var bash_cd := 0.0
var _last_mv := Vector3.ZERO
var _last_speed := 0.0

# puppet interpolation
var buf: Array = []


func _ready() -> void:
	def = Defs.ENEMIES[type]
	s = def.scale
	spd = def.speed * randf_range(0.92, 1.08)
	cd = randf_range(0.5, 1.5)
	los_t = randf() * 0.3
	strafe = 1.0 if randf() < 0.5 else -1.0
	flank_side = 1.0 if randf() < 0.5 else -1.0
	nade_cd = randf_range(4.0, 9.0)
	model = Dog.new() if def.get("dog", false) else Soldier.new()
	model.setup(type, def.gun)
	model.scale = Vector3.ONE * s
	add_child(model)
	var bulk := 1.35 if type == "heavy" else 1.0
	if def.get("dog", false):
		_hitbox(0, _sphere(0.14), Vector3(0, 0.78, -0.5))
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.32, 0.36, 0.95)
		_hitbox(1, bx, Vector3(0, 0.56, 0))
		var lg := BoxShape3D.new()
		lg.size = Vector3(0.3, 0.38, 0.8)
		_hitbox(2, lg, Vector3(0, 0.2, 0))
	else:
		_hitbox(0, _sphere(0.15 * s), Vector3(0, 1.66 * s, 0))
		_hitbox(1, _capsule(0.27 * s * bulk, 0.75 * s), Vector3(0, 1.28 * s, 0))
		_hitbox(2, _capsule(0.2 * s * bulk, 0.95 * s), Vector3(0, 0.48 * s, 0))
	if def.get("shield", false):
		var sb := BoxShape3D.new()
		sb.size = Vector3(0.62, 1.04, 0.14) * s
		_hitbox(3, sb, Vector3(-0.06, 0.98, -0.46) * s)
	if puppet:
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
	else:
		collision_layer = Defs.L_ENEMY
		collision_mask = Defs.L_WORLD
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.36 * s
		cap.height = 1.8 * s
		cs.shape = cap
		cs.position.y = 0.9 * s
		add_child(cs)
		agent = NavigationAgent3D.new()
		agent.path_desired_distance = 0.9
		agent.target_desired_distance = 1.0
		agent.radius = 0.45
		agent.height = 1.8
		agent.path_max_distance = 3.0
		add_child(agent)
		floor_snap_length = 0.4


func _sphere(r: float) -> SphereShape3D:
	var sh := SphereShape3D.new()
	sh.radius = r
	return sh


func _capsule(r: float, h: float) -> CapsuleShape3D:
	var sh := CapsuleShape3D.new()
	sh.radius = r
	sh.height = max(h, r * 2.0)
	return sh


func _hitbox(zone: int, shape: Shape3D, pos: Vector3) -> void:
	var a := Area3D.new()
	a.collision_layer = Defs.L_HITBOX
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.set_meta("enemy_id", id)
	a.set_meta("zone", zone)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	a.add_child(cs)
	add_child(a)
	hitboxes.append([cs, pos.y])


# ------------------------------------------------------------------ puppet
func push_state(now: float, pos: Vector3, yaw: float, pct: int, p_st: int, mv: bool) -> void:
	buf.append({"t": now, "p": pos, "y": yaw})
	while buf.size() > 12:
		buf.pop_front()
	hp_pct = pct
	st = p_st
	moving = mv


func _interp() -> void:
	if buf.is_empty():
		return
	var rt := Time.get_ticks_msec() / 1000.0 - Game.INTERP
	var a: Dictionary = buf[0]
	var b: Dictionary = buf[buf.size() - 1]
	for i in range(buf.size() - 1, 0, -1):
		if buf[i - 1].t <= rt:
			a = buf[i - 1]
			b = buf[i]
			break
	var k: float = 1.0 if b.t == a.t else clamp((rt - a.t) / (b.t - a.t), 0.0, 1.0)
	global_position = a.p.lerp(b.p, k)
	rotation.y = lerp_angle(a.y, b.y, k)


func _process(dt: float) -> void:
	if puppet:
		_interp()
	else:
		hp_pct = roundi(100.0 * hp / max_hp)
	if model and not model.dead:
		model.hurt = hp_pct < 40
		model.animate(dt, moving, spd, st, game.time if game else 0.0)
	# crouched behind cover: the hitboxes drop with the body (except the shield, which stays put)
	var k := 0.66 if st == 3 and not moving else 1.0
	for h in hitboxes:
		var cs: CollisionShape3D = h[0]
		if (cs.get_parent() as Area3D).get_meta("zone") != 3:
			cs.position.y = lerpf(cs.position.y, float(h[1]) * k, min(1.0, dt * 10.0))


# ------------------------------------------------------------------ server AI
func _physics_process(dt: float) -> void:
	if puppet or game == null:
		return
	# far away and out of sight: think every third tick (keep moving every tick)
	var think := true
	if not los and lost_t > 1.0 and mode == ADVANCE and _far:
		think = (Engine.get_physics_frames() + id) % 3 == 0
	if not think:
		_move(dt, _last_mv, _last_speed)
		return
	var players := game._alive_players()
	var tgt = null
	var td := 1e9
	for p in players:
		var d: float = (p.pos as Vector3).distance_to(global_position)
		if d < td:
			td = d
			tgt = p
	if tgt == null:
		st = 0
		moving = false
		_cancel_aim()
		velocity = Vector3(0, velocity.y - 20.0 * dt, 0)
		move_and_slide()
		return
	var pos := global_position
	var tpos: Vector3 = tgt.pos
	_far = td > 25.0
	var eye := pos + Vector3(0, 1.45 * s, 0)
	var teye := tpos + Vector3(0, 0.8 if tgt.cr else 1.35, 0)
	var space := get_world_3d().direct_space_state
	var sight: float = game.sight_range()
	los_t -= dt
	if los_t <= 0.0:
		los_t = 0.22
		los = td < sight and game._blocked(space, eye, teye) == false
		if not los:
			seen = 0.0
	if los:
		seen += dt
		lost_t = 0.0
	else:
		lost_t += dt
	var to_t := Vector3(tpos.x - pos.x, 0, tpos.z - pos.z)
	var dir_t := to_t.normalized() if to_t.length() > 0.01 else Vector3.FORWARD
	var mv := Vector3.ZERO
	var speed := spd
	var in_yard: bool = game.map.map_id != "yard" or (abs(pos.x) < GameMap.HALF - 1.0 and abs(pos.z) < GameMap.HALF - 1.0)
	st_t -= dt
	if st_t <= 0.0 and st == 2:
		st = 0
	nade_cd -= dt
	act_t -= dt
	bash_cd -= dt

	if def.get("melee", false):
		_path_to(tpos, dt)
		var dir: Vector3 = dir_t if (los and td < 6.0) else _nav_dir(dir_t)
		if td > 1.1:
			mv = dir
		cd -= dt
		if td < def.range and abs(tpos.y - pos.y) < 1.7 and cd <= 0.0:
			cd = 0.85
			st = 2
			st_t = 0.35
			game.damage_player(tgt, def.dmg * game.diff.dmg, pos)
			game.ev({"t": "shot", "pid": -1, "eid": id, "w": "dog" if def.get("dog", false) else "knife", "o": eye, "e": tpos + Vector3(0, 1.2, 0), "hit": true})
		if td < 3.0:
			_face(dir_t, dt, 20.0)
	else:
		var engage: bool = los and td < def.range and in_yard
		if def.get("sniper", false):
			mv = _sniper(dt, tgt, td, engage, dir_t, eye, space)
		else:
			mv = _rifleman(dt, tgt, td, engage, dir_t, teye, eye, space)
			if mv != Vector3.ZERO and mode == TO_COVER:
				speed *= 1.15
			elif engage and mode == ADVANCE and td <= def.range * 0.55:
				speed *= 0.35
			elif engage and mode == ADVANCE:
				speed *= 0.6
		_maybe_grenade(tgt, td, eye)
	if _far and not los and mode == ADVANCE and act_t <= 0.0 and not def.get("melee", false):
		speed *= 1.45                                      # jog in until contact
	if hp < max_hp * 0.4 and not def.get("dog", false):
		speed *= 0.75                                      # badly wounded: limping
	if act_t > 0.0:
		st = act
		if act == 7:
			speed *= 0.15
		elif act == 5:
			speed *= 0.6
	_last_mv = mv
	_last_speed = speed
	_move(dt, mv, speed)


func _move(dt: float, mv: Vector3, speed: float) -> void:
	var pos := global_position
	# far away and out of sight: just follow the navmesh path (it already avoids walls), no collision solve
	if _far and not los and mode == ADVANCE and act_t <= 0.0 and is_on_floor() and stuck_t <= 0.0:
		var step := mv.limit_length(1.0) * speed
		moving = step.length() > 0.05
		if moving:
			_face(step.normalized(), dt, 10.0)
		global_position += Vector3(step.x, 0, step.z) * dt
		return
	# separation from other enemies
	for o in game.enemy_list():
		if o == self:
			continue
		var d: Vector3 = pos - o.global_position
		d.y = 0
		var l := d.length()
		if l < 0.85 and l > 0.001:
			mv += d / l * (0.85 - l) * 2.5
	moving = mv.length() > 0.05
	if moving and st != 1 and st != 4:
		_face(mv.normalized(), dt, 10.0)
	var v := mv.limit_length(1.0) * speed
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * dt
	move_and_slide()
	# unstick: if we barely moved for a while, jitter sideways
	stuck_t = stuck_t + dt if moving and pos.distance_to(global_position) < speed * dt * 0.2 else 0.0
	if stuck_t > 1.0:
		stuck_t = 0.0
		global_position += Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
		if mode == TO_COVER:
			mode = ADVANCE


## Repath the nav agent toward `goal` a few times a second.
func _path_to(goal: Vector3, dt: float) -> void:
	repath_t -= dt
	if repath_t <= 0.0:
		repath_t = 1.2 if _far and not los else 0.4       # far away the target barely moves relative to us
		agent.target_position = goal


## Riflemen, breachers, grenadiers, shields, juggernauts: advance (or flank), take cover, pop up and fire.
func _rifleman(dt: float, tgt: Dictionary, td: float, engage: bool, dir_t: Vector3, teye: Vector3, eye: Vector3, space: PhysicsDirectSpaceState3D) -> Vector3:
	var tpos: Vector3 = tgt.pos
	var mv := Vector3.ZERO
	var can_cover: bool = not def.get("shield", false) and type != "heavy" and type != "shotgunner"
	match mode:
		ADVANCE:
			if role == "flank":
				var fp := _flank_point(tpos)
				_path_to(fp, dt)
				flank_t += dt
				if global_position.distance_to(fp) < 4.0 or td < 13.0 or flank_t > 22.0 or (engage and flank_t > 8.0):
					role = "assault"
			else:
				_path_to(tpos, dt)
			if not engage or (td > def.range * 0.55 and burst <= 0):
				mv = _nav_dir(dir_t)
			else:
				strafe_t -= dt
				if strafe_t <= 0.0:
					strafe_t = randf_range(0.8, 2.2)
					strafe = 0.0 if randf() < 0.3 else (1.0 if randf() < 0.5 else -1.0)
				mv = Vector3(dir_t.z, 0, -dir_t.x) * strafe
			if engage and can_cover and td > 6.0:
				cover_search_t -= dt
				if cover_search_t <= 0.0:
					cover_search_t = randf_range(2.0, 4.0)
					if _find_cover(teye, space):
						mode = TO_COVER
						to_cover_t = 0.0
						agent.target_position = cover_pos
		TO_COVER:
			to_cover_t += dt
			mv = _nav_dir((cover_pos - global_position).normalized())
			if Vector2(global_position.x - cover_pos.x, global_position.z - cover_pos.z).length() < 0.7:
				mode = IN_COVER
				cover_t = randf_range(7.0, 14.0)
				mv = Vector3.ZERO
			elif to_cover_t > 5.0:
				mode = ADVANCE
		IN_COVER:
			cover_t -= dt
			# step out of the corner just before firing, back in while pausing between bursts
			var firing: bool = burst > 0 or cd < 0.45
			var goal: Vector3 = peek_pos if firing else cover_pos
			var off := Vector3(goal.x - global_position.x, 0, goal.z - global_position.z)
			if off.length() > 0.15:
				mv = off.normalized() * min(1.0, off.length() * 2.0)
			if td < 5.0 or cover_t <= 0.0 or lost_t > 4.0:
				mode = ADVANCE
				cover_search_t = randf_range(3.0, 5.0)
	# fire control (shoots on the move too; the timer also runs while hidden so they pop out on cue)
	cd -= dt
	var busy := act_t > 0.0
	if def.get("shield", false) and td < 2.2 and bash_cd <= 0.0 and not busy:
		bash_cd = 1.5
		act = 2
		act_t = 0.35
		game.damage_player(tgt, 16.0 * game.diff.dmg, global_position)
		game.ev({"t": "shot", "pid": -1, "eid": id, "w": "bash", "o": eye, "e": tpos + Vector3(0, 1.2, 0), "hit": true})
	if engage:
		_face(dir_t, dt, 14.0)
		if seen > 0.45 and cd <= 0.0 and not busy:
			if burst <= 0:
				burst = randi_range(def.burst[0], def.burst[1])
			burst -= 1
			cd = 60.0 / def.rpm if burst > 0 else randf_range(def.pause[0], def.pause[1])
			_fire(tgt, td, eye, space)
			if burst <= 0:
				bursts_left -= 1
				if bursts_left <= 0:                       # out of ammo: reload (a window to push them)
					bursts_left = randi_range(3, 5)
					act = 5
					act_t = 2.6 if type == "shotgunner" else (3.2 if type == "heavy" else 2.0)
					cd = max(cd, act_t)
	else:
		burst = 0
		cd = max(cd, 0.0)
	# in cover: duck between bursts, stand up just before firing
	if mode == IN_COVER:
		st = 3 if (burst <= 0 and cd > 0.35) or not engage else 1
		if not engage and lost_t > 0.6:
			_face(dir_t, dt, 6.0)
	else:
		st = 1 if engage else 0
	return mv


## Snipers advance until they can see a player, then hold position and paint them with a laser
## for def.aim seconds before every shot. Breaking line of sight cancels the shot.
func _sniper(dt: float, tgt: Dictionary, td: float, engage: bool, dir_t: Vector3, eye: Vector3, space: PhysicsDirectSpaceState3D) -> Vector3:
	var mv := Vector3.ZERO
	_path_to(tgt.pos, dt)
	if aim_t > 0.0:
		_face(dir_t, dt, 10.0)
		st = 4
		if not engage or aim_pid != int(tgt.id):
			_cancel_aim()
			cd = 1.2
			return mv
		aim_t -= dt
		if aim_t <= 0.0:
			aim_t = 0.0
			aim_pid = -1
			cd = randf_range(def.pause[0], def.pause[1])
			_fire(tgt, td, eye, space)
		return mv
	if engage:
		_face(dir_t, dt, 10.0)
		st = 1
		cd -= dt
		if seen > 0.8 and cd <= 0.0:
			aim_t = def.aim
			aim_pid = int(tgt.id)
			game.ev({"t": "laser", "eid": id, "pid": aim_pid, "d": def.aim})
	elif lost_t > 4.0 or td > def.range:
		st = 0
		mv = _nav_dir(dir_t)
	return mv


## Big hits (shotgun blast, rifle round) rock the soldier back for a moment: no shooting, barely moving.
func stagger(dmg: float) -> void:
	if type == "heavy" or def.get("dog", false):
		return
	if dmg >= maxf(55.0, max_hp * 0.3):
		_cancel_aim()
		act = 7
		act_t = 0.55
		burst = 0


func _cancel_aim() -> void:
	if aim_t > 0.0:
		aim_t = 0.0
		game.ev({"t": "laser", "eid": id, "pid": -1, "d": 0.0})
	aim_pid = -1


## A spot on the side of the target, so flankers come round a different street or corridor.
func _flank_point(tpos: Vector3) -> Vector3:
	var away := Vector3(global_position.x - tpos.x, 0, global_position.z - tpos.z)
	if away.length() < 0.1:
		away = Vector3.FORWARD
	away = away.normalized()
	var side := Vector3(-away.z, 0, away.x) * flank_side
	var fp := tpos + away * 7.0 + side * 17.0
	var nav := get_world_3d().navigation_map
	var c := NavigationServer3D.map_get_closest_point(nav, fp)
	return c if c.distance_to(fp) < 12.0 else tpos


## Look for a spot within ~8 m that hides a crouching body from the target and lets it shoot back:
## either low cover it can stand up behind, or a corner it can step out from.
func _find_cover(threat: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var nav := get_world_3d().navigation_map
	var pos := global_position
	var best_s := 1e9
	var found := false
	for k in 14:
		var a := randf() * TAU
		var c := NavigationServer3D.map_get_closest_point(nav, pos + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 8.0))
		if c.distance_to(pos) > 9.0 or abs(c.y - pos.y) > 1.0:
			continue
		if not game._blocked(space, threat, c + Vector3(0, 0.95, 0)):
			continue                                     # not hidden when crouched
		var peek := c
		var extra := 0.0
		if game._blocked(space, threat, c + Vector3(0, 1.5 * s, 0)):
			# full cover: is there a corner to lean out of?
			var to := Vector3(threat.x - c.x, 0, threat.z - c.z).normalized()
			var side := Vector3(-to.z, 0, to.x)
			var ok := false
			for sd in [1.1, -1.1, 1.8, -1.8]:
				var p := NavigationServer3D.map_get_closest_point(nav, c + side * sd)
				if p.distance_to(c + side * sd) < 0.4 and not game._blocked(space, threat, p + Vector3(0, 1.45 * s, 0)):
					peek = p
					ok = true
					break
			if not ok:
				continue
			extra = 1.5
		var score: float = c.distance_to(pos) + extra + abs(c.distance_to(threat) - def.range * 0.55) * 0.15
		if score < best_s:
			best_s = score
			cover_pos = c
			peek_pos = peek
			found = true
	return found


## Grenadiers lob regularly; everyone else only throws at players who have been camping in one spot.
func _maybe_grenade(tgt: Dictionary, td: float, eye: Vector3) -> void:
	if nade_cd > 0.0 or game.nade_cd > 0.0 or td < 7.0 or td > 30.0:
		return
	var nades: bool = def.get("nades", false)
	var camping: bool = float(tgt.get("camp_t", 0.0)) >= 9.0
	if lost_t > 4.0 and not camping:
		return                                     # no idea where they are (campers give themselves away)
	if not nades and not camping:
		return
	if not nades and randf() > 0.25:
		nade_cd = 3.0
		return
	var goal: Vector3 = tgt.pos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	var o := eye + (goal - eye).normalized() * 0.5
	var flat := Vector3(goal.x - o.x, 0, goal.z - o.z)
	var t: float = clamp(flat.length() / 15.0, 0.7, 1.7)
	var v := flat / t
	v.y = (goal.y + 0.2 - o.y + 0.5 * 16.0 * t * t) / t
	game._add_projectile("efrag", o, v, t + 1.0, -1)
	game.nades_thrown += 1
	nade_cd = randf_range(7.0, 11.0) if nades else randf_range(18.0, 30.0)
	game.nade_cd = 2.5
	act = 6
	act_t = 0.6


func _nav_dir(fallback: Vector3) -> Vector3:
	if agent.is_navigation_finished():
		return fallback
	var nxt := agent.get_next_path_position()
	var d := Vector3(nxt.x - global_position.x, 0, nxt.z - global_position.z)
	if d.length() < 0.05:
		return fallback
	return d.normalized()


func _face(dir: Vector3, dt: float, rate: float) -> void:
	var want := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, want, min(1.0, dt * rate))


func _fire(tgt: Dictionary, td: float, eye: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	var acc_mul: float = min(1.6, 1.0 + game.wave * 0.025)
	var acc: float = def.acc * game.diff.acc * acc_mul * (1.0 - 0.6 * min(1.0, td / (def.range * 1.3)))
	if tgt.cr:
		acc *= 0.75
	var hit := randf() < acc
	var muzzle := eye + Vector3(-sin(rotation.y), 0, -cos(rotation.y)) * 0.6 - Vector3(0, 0.1, 0)
	if model and model.gun:
		muzzle = (model.gun.get_meta("muzzle") as Node3D).global_position
	var end: Vector3
	var tp: Vector3 = tgt.pos
	if hit:
		end = tp + Vector3(0, 0.7 if tgt.cr else 1.2, 0)
		game.damage_player(tgt, def.dmg * (1.0 + game.wave * 0.02) * game.diff.dmg, global_position)
	else:
		var aim := (tp + Vector3(randf_range(-1.2, 1.2), 1.3 + randf_range(-0.6, 0.9), randf_range(-1.2, 1.2)) - muzzle).normalized()
		end = muzzle + aim * 90.0
		var q := PhysicsRayQueryParameters3D.create(muzzle, end, Defs.L_WORLD)
		var r := space.intersect_ray(q)
		if r:
			end = r.position
	game.ev({"t": "shot", "pid": -1, "eid": id, "w": def.gun, "o": muzzle, "e": end, "hit": hit})
