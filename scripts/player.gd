class_name Player
extends CharacterBody3D
## The local player (first-person controller, weapons, viewmodel) or a remote teammate (puppet).

const WALK := 5.0
const SPRINT := 7.4
const CROUCH := 2.6
const ADS_SPEED := 3.0
const JUMP := 6.8
const GRAV := 20.0
const EYE := 1.62
const EYE_CR := 1.05
const EYE_DOWN := 0.45

const HIP := {"pistol": Vector3(0.14, -0.15, -0.3), "launcher": Vector3(0.2, -0.17, -0.32)}
const HIP_DEFAULT := Vector3(0.15, -0.16, -0.3)
const ADS := {"pistol": Vector3(0, -0.068, -0.3), "smg": Vector3(0, -0.11, -0.26), "shotgun": Vector3(0, -0.073, -0.3),
	"ar": Vector3(0, -0.117, -0.22), "dmr": Vector3(0, -0.12, -0.2), "lmg": Vector3(0, -0.133, -0.28),
	"launcher": Vector3(0.07, -0.13, -0.26), "designator": Vector3(0, -0.1, -0.25)}

var peer_id := 0
var game: Game
var is_local := false
var state := {}

# ---- remote puppet
var model: Soldier
var model_gun := ""
var tag: Label3D
var buf: Array = []

# ---- local controller
var cam: Camera3D
var vm_cam: Camera3D
var vm_view: SubViewportContainer
var vm_root: Node3D       # follows camera
var vm: Node3D            # current viewmodel
var vm_cache := {}
var muzzle_light: OmniLight3D
var shape: CollisionShape3D
var yaw := 0.0
var pitch := 0.0
var recoil := Vector2.ZERO
var crouch := false
var crouch_k := 0.0
var eye_h := EYE
var ads := 0.0
var sprinting := false
var on_floor_prev := true
var step_d := 0.0
var bob_t := 0.0
var sway := Vector2.ZERO
var kick := 0.0
var flinch := Vector2.ZERO

var ammo := {}            # weapon -> {mag, res}
var cur := "pistol"
var fire_cd := 0.0
var reloading := false
var reload_t := 0.0
var reload_total := 1.0
var reload_stage := 0
var swap_t := 0.0
var bloom := 0.0
var trigger_held := false
var designating := ""     # "", "strike"
var designate_point := Vector3.ZERO
var designate_ok := false
var melee_t := 0.0
var throw_t := 0.0
var downed := false
var dead := false
var tp_guard := 0.0
var state_t := 0.0
var revive_target := 0
var interact_prompt := ""
var sens := 1.0
var fov := 78.0
var hp_prev := 100
var heartbeat_t := 0.0
var flash_t := 0.0


# ======================================================================= setup
func _ready() -> void:
	if is_local:
		_setup_local()
	else:
		collision_layer = 0
		collision_mask = 0
		tag = Label3D.new()
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.position.y = 2.15
		tag.font_size = 40
		tag.outline_size = 8
		tag.modulate = Color(0.55, 0.78, 1.0)
		tag.pixel_size = 0.004
		tag.no_depth_test = true
		add_child(tag)


func _setup_local() -> void:
	collision_layer = Defs.L_PLAYER
	collision_mask = Defs.L_WORLD
	shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.8
	shape.shape = cap
	shape.position.y = 0.9
	add_child(shape)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	sens = float(Settings.get_val("sens", 1.0))
	fov = float(Settings.get_val("fov", 78.0))

	cam = Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = 1200.0
	cam.cull_mask = 0xFFFFF & ~2
	cam.current = true
	add_child(cam)

	# Viewmodel overlay: a second camera in a transparent SubViewport sharing the world,
	# rendering only layer 2, so the gun never clips into walls.
	vm_view = SubViewportContainer.new()
	vm_view.stretch = true
	vm_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	vm_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sv := SubViewport.new()
	sv.transparent_bg = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.use_taa = false
	sv.handle_input_locally = false
	sv.positional_shadow_atlas_size = 0
	vm_view.add_child(sv)
	vm_cam = Camera3D.new()
	vm_cam.fov = 58.0
	vm_cam.near = 0.01
	vm_cam.far = 10.0
	vm_cam.cull_mask = 2
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if game.map.env.sky else Environment.REFLECTION_SOURCE_DISABLED
	env.sky = game.map.env.sky
	env.tonemap_mode = game.map.env.tonemap_mode
	env.tonemap_white = game.map.env.tonemap_white
	env.adjustment_enabled = true
	env.adjustment_contrast = game.map.env.adjustment_contrast
	env.adjustment_saturation = game.map.env.adjustment_saturation
	vm_cam.environment = env
	sv.add_child(vm_cam)
	var layer: CanvasLayer = get_tree().root.get_node("Main/ViewLayer")
	layer.add_child(vm_view)

	vm_root = Node3D.new()
	vm_root.name = "VM"
	add_child(vm_root)
	vm_root.top_level = true
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.72, 0.4)
	muzzle_light.omni_range = 7.0
	muzzle_light.light_energy = 0.0
	muzzle_light.shadow_enabled = false
	add_child(muzzle_light)
	_sync_weapons(["pistol"])
	_equip("pistol", true)


func _exit_tree() -> void:
	if vm_view and is_instance_valid(vm_view):
		vm_view.queue_free()


# ======================================================================= state from server
func apply_state(ps: Dictionary, now: float) -> void:
	state = ps
	if is_local:
		_sync_weapons(ps.w)
		downed = ps.dn
		dead = ps.dd
		if ps.tp and tp_guard <= 0.0:
			global_position = ps.p
			velocity = Vector3.ZERO
			tp_guard = 0.6
			game.send({"t": "tpok"})
		if hp_prev > ps.hp and ps.hp < 35:
			pass
		hp_prev = ps.hp
		return
	buf.append({"t": now, "p": ps.p, "y": ps.yaw})
	while buf.size() > 12:
		buf.pop_front()
	tag.text = ps.n + ("  [DOWN]" if ps.dn else "")
	tag.modulate = Color(1.0, 0.4, 0.3) if ps.dn else Color(0.55, 0.78, 1.0)
	visible = not ps.dd
	if model == null or model_gun != ps.cur:
		if model:
			model.queue_free()
		model = Soldier.new()
		model.setup("friendly", ps.cur)
		add_child(model)
		model_gun = ps.cur
	model.downed = ps.dn


func _sync_weapons(list: Array) -> void:
	for w in list:
		if not ammo.has(w):
			var d: Dictionary = Defs.WEAPONS[w]
			ammo[w] = {"mag": d.mag, "res": d.reserve}
	for w in ammo.keys():
		if not w in list:
			ammo.erase(w)
	if not cur in list and not list.is_empty():
		_equip(list[0])


# ======================================================================= remote puppet
func _process(dt: float) -> void:
	if not is_local:
		_puppet(dt)
		return
	_local_frame(dt)


func _puppet(dt: float) -> void:
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
	var np: Vector3 = a.p.lerp(b.p, k)
	var moved := np.distance_to(global_position)
	global_position = np
	rotation.y = lerp_angle(a.y, b.y, k)
	if model:
		model.animate(dt, moved > 0.01, moved / max(dt, 0.001), 1, game.time)


# ======================================================================= input
func _unhandled_input(ev: InputEvent) -> void:
	if not is_local or not _input_enabled():
		return
	if ev is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var zoom := lerpf(1.0, Defs.WEAPONS[cur].zoom, ads)
		var s := 0.0022 * sens / zoom
		yaw -= ev.relative.x * s
		pitch = clamp(pitch - ev.relative.y * s, -1.5, 1.5)
		sway += Vector2(ev.relative.x, ev.relative.y) * 0.00025
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon()
	if ev.is_action_pressed("fire"):
		trigger_held = true
		if designating != "":
			_call_strike()
		elif not Defs.WEAPONS[cur].auto:
			_try_fire()
	if ev.is_action_released("fire"):
		trigger_held = false
	if ev.is_action_pressed("aim") and designating != "":
		designating = ""
		_equip(cur, true)
	if ev.is_action_pressed("reload"):
		_start_reload()
	if ev.is_action_pressed("weapon1"):
		_select(0)
	if ev.is_action_pressed("weapon2"):
		_select(1)
	if ev.is_action_pressed("crouch") and not Settings.get_val("crouch_hold", false):
		crouch = not crouch
	if ev.is_action_pressed("jump") and is_on_floor() and not downed:
		velocity.y = JUMP
		crouch = false
	if ev.is_action_pressed("frag"):
		_throw()
	if ev.is_action_pressed("melee"):
		_melee()
	if ev.is_action_pressed("mine") and _can_act() and state.get("mi", 0) > 0:
		game.send({"t": "mine"})
		Sfx.play("beep", -8.0)
	if ev.is_action_pressed("turret") and _can_act() and state.get("tu", 0) > 0:
		game.send({"t": "turret"})
		Sfx.play("swap", -4.0)
	if ev.is_action_pressed("strike") and _can_act() and state.get("as", 0) > 0:
		designating = "strike"
		_set_viewmodel("designator")
		Sfx.play("beep", -6.0)
	if ev.is_action_pressed("drone") and _can_act() and state.get("dr", 0) > 0:
		game.send({"t": "drone"})
	if ev.is_action_pressed("carpet") and _can_act() and state.get("cb", 0) > 0:
		game.send({"t": "strike", "k": "carpet"})
	if ev.is_action_pressed("interact"):
		_interact()
	if ev.is_action_pressed("ready"):
		game.send({"t": "ready"})
		Sfx.play("ui", -6.0)


func _input_enabled() -> bool:
	return game.hud == null or not game.hud.blocking()


func _can_act() -> bool:
	return not downed and not dead and game.snap.get("state", "") != "over"


# ======================================================================= frame
func _local_frame(dt: float) -> void:
	tp_guard -= dt
	if dead:
		_spectate(dt)
		return
	var w: Dictionary = Defs.WEAPONS[cur]
	var input_ok := _input_enabled() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# ADS
	var want_ads: bool = input_ok and Input.is_action_pressed("aim") and not sprinting and not reloading and designating == "" and swap_t <= 0.0
	ads = move_toward(ads, 1.0 if want_ads else 0.0, dt * (6.0 if cur != "dmr" else 4.5))
	# weapon timers
	fire_cd -= dt
	swap_t = max(0.0, swap_t - dt)
	melee_t = max(0.0, melee_t - dt)
	throw_t = max(0.0, throw_t - dt)
	bloom = max(0.0, bloom - dt * 0.12)
	if reloading:
		reload_t -= dt
		var k := 1.0 - reload_t / reload_total
		if reload_stage == 0 and k > 0.2:
			reload_stage = 1
			Sfx.play("mag_out", -6.0)
		elif reload_stage == 1 and k > 0.6:
			reload_stage = 2
			Sfx.play("mag_in", -5.0)
		elif reload_stage == 2 and k > 0.85:
			reload_stage = 3
			Sfx.play("pump" if cur == "shotgun" else "bolt", -6.0)
		if reload_t <= 0.0:
			_finish_reload()
	if input_ok and trigger_held and w.auto and designating == "":
		_try_fire()
	if designating != "":
		_update_designator()
	# recoil recovery
	recoil = recoil.lerp(Vector2.ZERO, min(1.0, dt * 4.5))
	flinch = flinch.lerp(Vector2.ZERO, min(1.0, dt * 10.0))
	_move(dt, input_ok)
	_update_camera(dt)
	_update_viewmodel(dt)
	_update_interaction()
	_send_state(dt)
	# low-health heartbeat
	if state.get("hp", 100) < 35 and not downed:
		heartbeat_t -= dt
		if heartbeat_t <= 0.0:
			heartbeat_t = 0.9
			Sfx.play("heartbeat", -4.0, 1.0, 0.0)


func _move(dt: float, input_ok: bool) -> void:
	var dir := Vector2.ZERO
	if input_ok and not downed:
		dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	sprinting = input_ok and Input.is_action_pressed("sprint") and dir.y < -0.3 and not downed and ads < 0.5 and not crouch
	if sprinting and reloading:
		pass
	if Settings.get_val("crouch_hold", false):
		crouch = input_ok and Input.is_action_pressed("crouch")
	crouch_k = move_toward(crouch_k, 1.0 if crouch else 0.0, dt * 6.0)
	var w: Dictionary = Defs.WEAPONS[cur]
	var speed := WALK
	if sprinting:
		speed = SPRINT
	elif crouch:
		speed = CROUCH
	elif ads > 0.5:
		speed = ADS_SPEED
	speed *= w.move
	var basis := Basis(Vector3.UP, yaw)
	var wish := basis * Vector3(dir.x, 0, dir.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = lerpf(velocity.x, wish.x * speed, min(1.0, accel * dt))
	velocity.z = lerpf(velocity.z, wish.z * speed, min(1.0, accel * dt))
	if not is_on_floor():
		velocity.y -= GRAV * dt
	(shape.shape as CapsuleShape3D).height = lerpf(1.8, 1.25, crouch_k)
	shape.position.y = (shape.shape as CapsuleShape3D).height / 2.0
	move_and_slide()
	if is_on_floor() and not on_floor_prev and velocity.y < -3.0:
		Sfx.play("land", -6.0)
		kick += 0.4
	on_floor_prev = is_on_floor()
	var hv := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hv > 0.5:
		step_d += hv * dt
		bob_t += hv * dt
		var stride := 2.6 if sprinting else 2.0
		if step_d > stride:
			step_d = 0.0
			Sfx.play("step", -16.0 if crouch else -10.0 if not sprinting else -7.0, 1.0, 0.12)
	if global_position.y < -5.0:
		global_position = Vector3(0, 1, 4)


func _update_camera(dt: float) -> void:
	var target_eye := EYE_DOWN if downed else lerpf(EYE, EYE_CR, crouch_k)
	eye_h = lerpf(eye_h, target_eye, min(1.0, dt * 10.0))
	var hv := Vector2(velocity.x, velocity.z).length()
	var bob_amt: float = (0.0 if not is_on_floor() else clamp(hv / 6.0, 0.0, 1.2)) * (1.0 - ads * 0.85)
	var bob := Vector3(sin(bob_t * 1.4) * 0.025, abs(cos(bob_t * 1.4)) * 0.035, 0) * bob_amt
	var shake: float = game.fx.shake
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.06
	cam.position = Vector3(0, eye_h, 0) + bob + sh
	cam.rotation = Vector3(pitch + recoil.y + flinch.y + sh.y, yaw + recoil.x + flinch.x, sh.x * 0.5)
	var zoom := lerpf(1.0, Defs.WEAPONS[cur].zoom, ads)
	cam.fov = lerpf(cam.fov, (fov / zoom) + (6.0 if sprinting else 0.0), min(1.0, dt * 12.0))
	vm_cam.global_transform = cam.global_transform
	vm_root.global_transform = cam.global_transform
	vm_cam.fov = lerpf(58.0, 48.0, ads)
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			muzzle_light.light_energy = 0.0
	Sfx.start_ambience()


# ======================================================================= weapons
func _equip(w: String, instant := false) -> void:
	if not ammo.has(w) and w != "designator":
		return
	if w != cur:
		Sfx.play("swap", -6.0)
	cur = w
	reloading = false
	swap_t = 0.0 if instant else 0.35
	_set_viewmodel(w)


func _set_viewmodel(w: String) -> void:
	if vm:
		vm.visible = false
	if not vm_cache.has(w):
		vm_cache[w] = _build_vm(w)
	vm = vm_cache[w]
	vm.visible = true


func _build_vm(w: String) -> Node3D:
	var root := Node3D.new()
	var gun := WeaponModel.build(w)
	root.add_child(gun)
	var sleeve := Mat.pbr("fabric", Color(0.38, 0.39, 0.35), 0.95, 0.0, 3.0)
	var glove := Mat.pbr("fabric", Color(0.36, 0.31, 0.23), 0.9, 0.0, 4.0)
	var cap := func(r: float, h: float) -> CapsuleMesh:
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = h
		return c
	var boxm := func(s: Vector3) -> BoxMesh:
		var b := BoxMesh.new()
		b.size = s
		return b
	# Hands sit on the gun's grip markers; forearms angle back/down out of the frame.
	var custom := gun.has_meta("custom")
	var grip_r: Vector3 = gun.get_meta("grip_r", Vector3.ZERO)
	var lz: float = {"pistol": 0.01, "smg": -0.22, "shotgun": -0.4, "ar": -0.33, "dmr": -0.36, "lmg": -0.38, "launcher": -0.3, "designator": -0.08}.get(w, -0.3)
	var grip_l: Vector3 = gun.get_meta("grip_l") if custom else Vector3(-0.01, -0.01 if w == "pistol" else 0.03, lz)
	var make_arm := func(hand: Vector3, back: Vector3, glove_size: Vector3) -> Node3D:
		var arm := Node3D.new()
		arm.position = hand
		var g := MeshInstance3D.new()
		var hm := CapsuleMesh.new()
		hm.radius = glove_size.x * 0.55
		hm.height = glove_size.z * 1.1
		g.mesh = hm
		g.rotation.x = PI / 2
		g.material_override = glove
		arm.add_child(g)
		var dir := back.normalized()
		var sl := MeshInstance3D.new()
		sl.mesh = cap.call(0.042, 0.5)
		sl.material_override = sleeve
		var y := dir
		var x := y.cross(Vector3.FORWARD).normalized()
		if x.length() < 0.1:
			x = Vector3.RIGHT
		var z := x.cross(y).normalized()
		sl.transform = Transform3D(Basis(x, y, z), dir * 0.27)
		arm.add_child(sl)
		root.add_child(arm)
		return arm
	make_arm.call(grip_r + Vector3(0.0, -0.01, 0.01), Vector3(0.3, -0.5, 0.85), Vector3(0.05, 0.08, 0.09))
	var l_arm: Node3D = make_arm.call(grip_l + Vector3(-0.012, -0.012, 0), Vector3(-0.55, -0.55, 0.62), Vector3(0.06, 0.05, 0.11))
	root.set_meta("gun", gun)
	root.set_meta("l_arm", l_arm)
	root.set_meta("l_base", l_arm.position)
	var flash := Effects.make_flash_sprite(0.32)
	flash.visible = false
	(gun.get_meta("muzzle") as Node3D).add_child(flash)
	root.set_meta("flash", flash)
	vm_root.add_child(root)
	for n in root.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 2
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _cycle_weapon() -> void:
	var list: Array = state.get("w", ammo.keys())
	if list.size() < 2 or downed:
		return
	var i := list.find(cur)
	_equip(list[(i + 1) % list.size()])


func _select(i: int) -> void:
	var list: Array = state.get("w", [])
	if i < list.size() and list[i] != cur and not downed:
		designating = ""
		_equip(list[i])


func _try_fire() -> void:
	if fire_cd > 0.0 or reloading or swap_t > 0.0 or melee_t > 0.0 or throw_t > 0.0 or not _input_enabled():
		return
	if dead or (downed and cur != "pistol") or game.snap.get("state", "") == "over":
		return
	var w: Dictionary = Defs.WEAPONS[cur]
	var a: Dictionary = ammo[cur]
	if a.mag <= 0:
		Sfx.play("dry", -6.0)
		fire_cd = 0.25
		_start_reload()
		return
	a.mag -= 1
	fire_cd = 60.0 / w.rpm
	sprinting = false
	var origin := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var muzzle_pos := _muzzle_world()
	Sfx.play(cur, -1.0, 1.0, 0.04)
	_muzzle_fx(muzzle_pos, fwd)
	# recoil & kick
	var rec: float = w.recoil * (0.6 if ads > 0.5 else 1.0) * (0.8 if crouch else 1.0)
	recoil.y += rec * 0.028                                  # camera kick (recovers)
	recoil.x += randf_range(-1.0, 1.0) * rec * 0.012
	pitch += rec * 0.009                                     # muzzle climb you have to pull down
	yaw += randf_range(-0.6, 1.0) * rec * 0.0035
	kick += rec * 0.9
	game.fx.shake = max(game.fx.shake, rec * 0.06)
	if w.get("rocket", false):
		game.send({"t": "rocket", "o": origin + fwd * 0.9, "d": fwd})
		return
	var space := get_world_3d().direct_space_state
	var moving := Vector2(velocity.x, velocity.z).length() > 1.0
	var spread: float = lerpf(w.spread, w.ads_spread, ads) * (1.6 if moving else 1.0) * (0.8 if crouch else 1.0) + bloom
	bloom = min(0.05, bloom + w.bloom)
	var hits := []
	var first_end := origin + fwd * 200.0
	var any_hit := false
	var head_hit := false
	for i in max(1, int(w.pellets)):
		var d := _spread_dir(fwd, spread)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * 300.0, Defs.L_WORLD | Defs.L_HITBOX)
		q.collide_with_areas = true
		q.exclude = [get_rid()]
		var r := space.intersect_ray(q)
		var end: Vector3 = origin + d * 300.0
		if r:
			end = r.position
			var col: Object = r.collider
			if col is Area3D and col.has_meta("enemy_id"):
				var zone: int = col.get_meta("zone")
				hits.append({"eid": col.get_meta("enemy_id"), "zone": zone, "dist": origin.distance_to(end)})
				any_hit = true
				head_hit = head_hit or zone == 0
				game.fx.blood(end, d, zone == 0, space)
				if zone == 0:
					Sfx.play_at("impact_flesh", end, -2.0)
			else:
				var surf: String = col.get_meta("surface", "concrete") if col else "concrete"
				game.fx.impact(end, r.normal, surf)
				if randf() < 0.35:
					Sfx.play_at("impact_metal" if surf == "metal" else "impact", end, -8.0)
		if i == 0:
			first_end = end
		if i == 0 or randf() < 0.3:
			game.fx.tracer(muzzle_pos, end, Color(4.0, 3.0, 1.6, 0.6), 0.012)
	if not hits.is_empty():
		game.send({"t": "hits", "w": cur, "hits": hits})
	if any_hit and game.hud:
		game.hud.hitmarker(head_hit, false)
		Sfx.play("hit_head" if head_hit else "hit", -2.0, 1.0, 0.03)
	if multiplayer.get_peers().size() > 0:
		game.send({"t": "fire", "w": cur, "o": muzzle_pos, "e": first_end})
	# shell casing
	if cur != "launcher" and cur != "shotgun" or (cur == "shotgun" and false):
		var right := cam.global_transform.basis.x
		game.fx.casing(muzzle_pos - fwd * 0.45 + right * 0.08, right * randf_range(1.6, 2.6) + Vector3.UP * randf_range(1.5, 2.5) - fwd * 0.3)
		if randf() < 0.4:
			get_tree().create_timer(0.35).timeout.connect(func(): Sfx.play("casing", -18.0))
	if cur == "shotgun" or cur == "dmr":
		get_tree().create_timer(0.3).timeout.connect(func(): Sfx.play("pump" if cur == "shotgun" else "bolt", -8.0))
	if a.mag == 0:
		get_tree().create_timer(0.2).timeout.connect(_start_reload)


func _spread_dir(fwd: Vector3, spread: float) -> Vector3:
	var basis := cam.global_transform.basis
	var a := randf() * TAU
	var r := sqrt(randf()) * spread
	return (fwd + basis.x * cos(a) * r + basis.y * sin(a) * r).normalized()


func _muzzle_world() -> Vector3:
	# The viewmodel camera has a different FOV, so map the muzzle into a world point in front of the eye.
	var b := cam.global_transform.basis
	var off := lerpf(0.11, 0.0, ads)
	return cam.global_position - b.z * 0.8 + b.x * off - b.y * lerpf(0.09, 0.04, ads)


func _muzzle_fx(pos: Vector3, fwd: Vector3) -> void:
	var f: Sprite3D = vm.get_meta("flash")
	if f:
		f.visible = true
		f.rotation.z = randf() * TAU
		f.scale = Vector3.ONE * randf_range(0.8, 1.3) * (2.0 if cur == "shotgun" or cur == "launcher" else 1.0)
		get_tree().create_timer(0.045).timeout.connect(func(): f.visible = false)
	muzzle_light.global_position = pos
	muzzle_light.light_energy = 2.5
	flash_t = 0.05
	game.fx.muzzle_smoke(pos, fwd)


func _start_reload() -> void:
	if reloading or designating != "" or not ammo.has(cur):
		return
	var w: Dictionary = Defs.WEAPONS[cur]
	var a: Dictionary = ammo[cur]
	if a.mag >= w.mag or (a.res == 0):
		return
	reloading = true
	reload_total = w.reload
	reload_t = w.reload
	reload_stage = 0
	trigger_held = false


func _finish_reload() -> void:
	reloading = false
	var w: Dictionary = Defs.WEAPONS[cur]
	var a: Dictionary = ammo[cur]
	var need: int = w.mag - a.mag
	if a.res < 0:
		a.mag = w.mag
	else:
		var take: int = min(need, a.res)
		a.mag += take
		a.res -= take


func _throw() -> void:
	if not _can_act() or state.get("fr", 0) <= 0 or throw_t > 0.0:
		return
	throw_t = 0.6
	reloading = false
	var fwd := -cam.global_transform.basis.z
	var o := cam.global_position + fwd * 0.5 + Vector3(0, -0.1, 0)
	game.send({"t": "throw", "o": o, "v": fwd * 17.0 + Vector3(0, 4.0, 0) + velocity * 0.6})
	Sfx.play("melee", -8.0, 1.2)


func _melee() -> void:
	if not _can_act() or melee_t > 0.0:
		return
	melee_t = 0.5
	Sfx.play("melee", -4.0)
	var fwd := -cam.global_transform.basis.z
	var best: Enemy = null
	var bd := 2.6
	for e in game.enemies.values():
		var to: Vector3 = e.global_position + Vector3(0, 1, 0) - cam.global_position
		var d := to.length()
		if d < bd and to.normalized().dot(fwd) > 0.5:
			bd = d
			best = e
	if best:
		game.send({"t": "melee", "eid": best.id})
		Sfx.play("stab", -2.0)
		if game.hud:
			game.hud.hitmarker(false, false)


func _update_designator() -> void:
	var space := get_world_3d().direct_space_state
	var fwd := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + fwd * 250.0, Defs.L_WORLD)
	var r := space.intersect_ray(q)
	designate_ok = not r.is_empty()
	if designate_ok:
		designate_point = r.position
		if randf() < 0.5:
			game.fx.particle(true, designate_point + r.normal * 0.05, Vector3.ZERO, 0.25, 0.25, 0.05, Color(6, 0.3, 0.2, 1))


func _call_strike() -> void:
	if not designate_ok:
		Sfx.play("deny", -8.0)
		return
	game.send({"t": "strike", "k": "strike", "pos": designate_point})
	designating = ""
	_equip(cur, true)


# ======================================================================= viewmodel animation
func _update_viewmodel(dt: float) -> void:
	if vm == null:
		return
	var w := designating if designating != "" else cur
	var hip: Vector3 = HIP.get(w, HIP_DEFAULT)
	var adsp: Vector3 = ADS.get(w, Vector3(0, -0.11, -0.25))
	if (vm.get_meta("gun") as Node3D).has_meta("custom"):
		hip = Vector3(0.13, -0.105, -0.3) if w != "launcher" else Vector3(0.16, -0.12, -0.15)
		adsp = {"shotgun": Vector3(0, 0, -0.16), "launcher": Vector3(0, 0, -0.1), "dmr": Vector3(0, 0, -0.1), "lmg": Vector3(0, 0, -0.14)}.get(w, Vector3(0, 0, -0.2))
	var pos := hip.lerp(adsp, ads)
	var rot := Vector3.ZERO
	var hv := Vector2(velocity.x, velocity.z).length()
	var bob_amt: float = clamp(hv / 6.0, 0.0, 1.3) * (1.0 - ads * 0.9) * (1.0 if is_on_floor() else 0.2)
	pos += Vector3(sin(bob_t * 1.4) * 0.012, -abs(cos(bob_t * 1.4)) * 0.012, 0) * bob_amt
	# idle breathing
	pos.y += sin(game.time * 1.6) * 0.0018 * (1.0 - ads * 0.8)
	sway = sway.lerp(Vector2.ZERO, min(1.0, dt * 8.0))
	pos.x -= sway.x * 0.6 * (1.0 - ads * 0.8)
	pos.y += sway.y * 0.6 * (1.0 - ads * 0.8)
	rot.y += sway.x * 2.0
	rot.x += sway.y * 2.0
	kick = lerpf(kick, 0.0, min(1.0, dt * 11.0))
	pos.z += kick * 0.05
	pos.y += kick * 0.008
	rot.x += kick * 0.09
	rot.z += kick * randf_range(-0.02, 0.02)
	if sprinting:
		pos += Vector3(-0.05, -0.05, 0.02)
		rot += Vector3(-0.35, 0.65, 0.25)
	if crouch_k > 0.0 and ads < 0.5:
		rot.z += 0.12 * crouch_k
	if reloading:
		var k := 1.0 - reload_t / reload_total
		var dip := sin(k * PI)
		rot.x -= dip * 0.5
		rot.z += dip * 0.35
		pos.y -= dip * 0.05
		var mag: Node3D = (vm.get_meta("gun") as Node3D).get_meta("mag")
		if mag:
			var base: Vector3 = (vm.get_meta("gun") as Node3D).get_meta("mag_pos")
			var out := 0.0
			if k > 0.15 and k < 0.65:
				out = sin((k - 0.15) / 0.5 * PI)
			mag.position = base + Vector3(0, -0.22 * out, 0.05 * out)
			mag.visible = out < 0.9
		var la: Node3D = vm.get_meta("l_arm")
		la.position = (vm.get_meta("l_base") as Vector3) + Vector3(0.02, -0.12 * sin(clamp(k * 1.4, 0.0, 1.0) * PI), 0.08)
	else:
		var la: Node3D = vm.get_meta("l_arm")
		la.position = la.position.lerp(vm.get_meta("l_base"), min(1.0, dt * 10.0))
	if swap_t > 0.0:
		pos.y -= swap_t * 0.5
		rot.x -= swap_t * 1.5
	if melee_t > 0.0:
		var k := 1.0 - melee_t / 0.5
		var s := sin(k * PI)
		pos += Vector3(-0.08 * s, 0.02 * s, -0.12 * s)
		rot += Vector3(-0.2 * s, 0.6 * s, -0.4 * s)
	if throw_t > 0.0:
		var k := 1.0 - throw_t / 0.6
		pos.y -= sin(k * PI) * 0.2
	if downed:
		pos += Vector3(-0.02, -0.04, 0.03)
		rot.z += 0.25
	var target := Transform3D(Basis.from_euler(rot), pos)
	vm.transform = vm.transform.interpolate_with(target, min(1.0, dt * 22.0))
	var gun_n: Node3D = vm.get_meta("gun")
	if gun_n.has_meta("reticle"):
		(gun_n.get_meta("reticle") as Sprite3D).visible = ads > 0.6
	# scope: hide the gun when fully scoped in on the DMR
	vm.visible = not (cur == "dmr" and ads > 0.92 and designating == "")


# ======================================================================= interaction
func _update_interaction() -> void:
	interact_prompt = ""
	revive_target = 0
	if dead or downed:
		return
	for pn in game.player_nodes.values():
		if pn == self or not pn.state.get("dn", false):
			continue
		if pn.global_position.distance_to(global_position) < 2.6:
			interact_prompt = "Hold [E] to revive %s" % pn.state.n
			if Input.is_action_pressed("interact") and _input_enabled():
				revive_target = pn.peer_id
			return
	var st := game.map.station_near(global_position, 2.2)
	if not st.is_empty():
		interact_prompt = "Press [E] to open the %s" % Defs.CAT_NAMES[st.cat]


func _interact() -> void:
	if dead or downed:
		return
	var st := game.map.station_near(global_position, 2.2)
	if not st.is_empty() and game.hud:
		game.hud.open_shop(st.cat)
		get_viewport().set_input_as_handled()   # otherwise main.gd sees the same E press and closes it again


func _send_state(dt: float) -> void:
	state_t -= dt
	if state_t > 0.0:
		return
	state_t = 1.0 / 30.0
	game.send_state({"t": "st", "pos": global_position, "yaw": yaw, "pitch": pitch, "cr": crouch, "cur": cur, "rev": revive_target})


func _spectate(dt: float) -> void:
	for pn in game.player_nodes.values():
		if pn != self and not pn.state.get("dd", true):
			var back := Basis(Vector3.UP, pn.rotation.y) * Vector3(0, 0, 3.2)
			cam.global_position = cam.global_position.lerp(pn.global_position + back + Vector3(0, 2.4, 0), min(1.0, dt * 4.0))
			cam.look_at(pn.global_position + Vector3(0, 1.4, 0), Vector3.UP)
			break
	if vm:
		vm.visible = false


# ======================================================================= events
func on_damaged(from: Vector3, amt: int) -> void:
	Sfx.play("hurt", -4.0)
	game.fx.shake = max(game.fx.shake, 0.25)
	flinch += Vector2(randf_range(-0.02, 0.02), 0.025)
	if game.hud:
		var to := from - global_position
		var ang := (yaw + PI) - atan2(to.x, to.z)   # 0 = in front, + = to the right
		game.hud.damage_dir(ang)


func on_downed() -> void:
	crouch = false
	if ammo.has("pistol"):
		_equip("pistol", true)
	designating = ""


func on_revived() -> void:
	pass


func on_respawn() -> void:
	tp_guard = 0.0
	if vm:
		vm.visible = true


func on_buy(e: Dictionary) -> void:
	if not e.ok:
		return
	if e.has("weapon"):
		var w: String = e.weapon
		ammo[w] = {"mag": Defs.WEAPONS[w].mag, "res": Defs.WEAPONS[w].reserve}
		if e.get("dropped", "") != "":
			ammo.erase(e.dropped)
		_equip(w)
	if e.get("ammo", false):
		for w in ammo:
			ammo[w].res = Defs.WEAPONS[w].reserve
			if w == "launcher":
				ammo[w].mag = 1


func on_restart() -> void:
	ammo.clear()
	_sync_weapons(["pistol"])
	_equip("pistol", true)
	tp_guard = 0.0
	designating = ""
