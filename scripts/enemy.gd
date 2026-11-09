class_name Enemy
extends CharacterBody3D
## Hostile soldier. On the server it runs AI (navmesh pathing, line of sight, burst fire, strafing,
## melee rushers). On clients it is an interpolated puppet. Both have hitboxes for client-side hit
## detection (head / torso / legs).

var id := 0
var type := "grunt"
var game: Game
var puppet := false
var hp := 100.0
var max_hp := 100.0
var hp_pct := 100
var alert := false
var st := 0          # 0 moving, 1 engaging, 2 melee strike
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

# puppet interpolation
var buf: Array = []


func _ready() -> void:
	def = Defs.ENEMIES[type]
	s = def.scale
	spd = def.speed * randf_range(0.92, 1.08)
	cd = randf_range(0.5, 1.5)
	los_t = randf() * 0.3
	strafe = 1.0 if randf() < 0.5 else -1.0
	model = Soldier.new()
	model.setup(type, def.gun)
	model.scale = Vector3.ONE * s
	add_child(model)
	var bulk := 1.35 if type == "heavy" else 1.0
	_hitbox(0, _sphere(0.15 * s), Vector3(0, 1.66 * s, 0))
	_hitbox(1, _capsule(0.27 * s * bulk, 0.75 * s), Vector3(0, 1.28 * s, 0))
	_hitbox(2, _capsule(0.2 * s * bulk, 0.95 * s), Vector3(0, 0.48 * s, 0))
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
		model.animate(dt, moving, spd, st, game.time if game else 0.0)


# ------------------------------------------------------------------ server AI
func _physics_process(dt: float) -> void:
	if puppet or game == null:
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
		velocity = Vector3(0, velocity.y - 20.0 * dt, 0)
		move_and_slide()
		return
	var pos := global_position
	var tpos: Vector3 = tgt.pos
	var eye := pos + Vector3(0, 1.45 * s, 0)
	var space := get_world_3d().direct_space_state
	los_t -= dt
	if los_t <= 0.0:
		los_t = 0.22
		var teye := tpos + Vector3(0, 0.8 if tgt.cr else 1.35, 0)
		los = td < 70.0 and game._blocked(space, eye, teye) == false
		if not los:
			seen = 0.0
	if los:
		seen += dt
	var to_t := Vector3(tpos.x - pos.x, 0, tpos.z - pos.z)
	var dir_t := to_t.normalized() if to_t.length() > 0.01 else Vector3.FORWARD
	var mv := Vector3.ZERO
	var speed := spd
	var in_yard: bool = game.map.map_id != "yard" or (abs(pos.x) < GameMap.HALF - 1.0 and abs(pos.z) < GameMap.HALF - 1.0)
	repath_t -= dt
	if repath_t <= 0.0:
		repath_t = 0.4
		agent.target_position = tpos
	st_t -= dt
	if st_t <= 0.0 and st == 2:
		st = 0

	if def.get("melee", false):
		var dir: Vector3 = dir_t if (los and td < 6.0) else _nav_dir(dir_t)
		if td > 1.1:
			mv = dir
		cd -= dt
		if td < def.range and abs(tpos.y - pos.y) < 1.7 and cd <= 0.0:
			cd = 0.85
			st = 2
			st_t = 0.35
			game.damage_player(tgt, def.dmg, pos)
			game.ev({"t": "shot", "pid": -1, "eid": id, "w": "knife", "o": eye, "e": tpos + Vector3(0, 1.2, 0), "hit": true})
		if td < 3.0:
			_face(dir_t, dt, 20.0)
	else:
		var engage: bool = los and td < def.range and in_yard
		var too_far: bool = td > def.range * 0.55
		if not engage or (too_far and burst <= 0):
			mv = _nav_dir(dir_t)
			if engage:
				speed *= 0.6
		else:
			strafe_t -= dt
			if strafe_t <= 0.0:
				strafe_t = randf_range(0.8, 2.2)
				strafe = 0.0 if randf() < 0.3 else (1.0 if randf() < 0.5 else -1.0)
			mv = Vector3(dir_t.z, 0, -dir_t.x) * strafe
			speed *= 0.35
		st = 1 if engage else 0
		if engage:
			_face(dir_t, dt, 14.0)
			cd -= dt
			if seen > 0.45 and cd <= 0.0:
				if burst <= 0:
					burst = randi_range(def.burst[0], def.burst[1])
				burst -= 1
				cd = 60.0 / def.rpm if burst > 0 else randf_range(def.pause[0], def.pause[1])
				_fire(tgt, td, eye, space)
		else:
			burst = 0
	# separation from other enemies
	for o in game.enemies.values():
		if o == self:
			continue
		var d: Vector3 = pos - o.global_position
		d.y = 0
		var l := d.length()
		if l < 0.85 and l > 0.001:
			mv += d / l * (0.85 - l) * 2.5
	moving = mv.length() > 0.05
	if moving and st != 1:
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
	var acc: float = def.acc * acc_mul * (1.0 - 0.6 * min(1.0, td / (def.range * 1.3)))
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
		game.damage_player(tgt, def.dmg * (1.0 + game.wave * 0.02), global_position)
	else:
		var aim := (tp + Vector3(randf_range(-1.2, 1.2), 1.3 + randf_range(-0.6, 0.9), randf_range(-1.2, 1.2)) - muzzle).normalized()
		end = muzzle + aim * 90.0
		var q := PhysicsRayQueryParameters3D.create(muzzle, end, Defs.L_WORLD)
		var r := space.intersect_ray(q)
		if r:
			end = r.position
	game.ev({"t": "shot", "pid": -1, "eid": id, "w": def.gun, "o": muzzle, "e": end, "hit": hit})
