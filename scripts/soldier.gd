class_name Soldier
extends Node3D
## A soldier: procedural model with code-driven animation (walk, aim, melee, death).
## If res://assets/characters/<style>.glb|.fbx (or soldier.glb|.fbx) exists, a rigged Mixamo-style
## character is used instead, animated with clips from res://assets/characters/anims/. See README.
## The model faces -Z, feet at y = 0.

const STYLES := {
	"grunt": {"camo": [Color(0.55, 0.49, 0.37), Color(0.42, 0.36, 0.26), Color(0.66, 0.6, 0.47), Color(0.33, 0.29, 0.21)], "vest": Color(0.36, 0.32, 0.24), "head": "cap", "face": "scarf", "scarf": Color(0.42, 0.36, 0.28)},
	"rifleman": {"camo": [Color(0.32, 0.35, 0.24), Color(0.21, 0.23, 0.16), Color(0.42, 0.4, 0.29), Color(0.14, 0.13, 0.11)], "vest": Color(0.25, 0.27, 0.19), "head": "helmet", "face": "skin"},
	"shotgunner": {"camo": [Color(0.16, 0.16, 0.17), Color(0.11, 0.11, 0.12), Color(0.22, 0.22, 0.21), Color(0.08, 0.08, 0.09)], "vest": Color(0.12, 0.12, 0.13), "head": "helmet", "face": "balaclava"},
	"rusher": {"camo": [Color(0.27, 0.16, 0.14), Color(0.18, 0.12, 0.11), Color(0.36, 0.25, 0.2), Color(0.12, 0.09, 0.09)], "vest": Color(0.16, 0.11, 0.09), "head": "none", "face": "balaclava", "scarf": Color(0.45, 0.06, 0.06)},
	"heavy": {"camo": [Color(0.13, 0.13, 0.14), Color(0.09, 0.09, 0.1), Color(0.19, 0.19, 0.19), Color(0.07, 0.07, 0.08)], "vest": Color(0.1, 0.1, 0.11), "head": "jugg", "face": "visor", "heavy": true},
	"friendly": {"camo": [Color(0.31, 0.33, 0.35), Color(0.2, 0.21, 0.23), Color(0.44, 0.45, 0.46), Color(0.12, 0.12, 0.14)], "vest": Color(0.23, 0.25, 0.27), "head": "helmet", "face": "skin", "friendly": true},
}

static var _camo_shader: Shader
static var _camo_mats := {}

var style: String
var gun_id: String
var bulk := 1.0
var hips: Node3D
var torso: Node3D
var neck: Node3D
var legs: Array = []
var arms: Array = []
var gun: Node3D
var flash: Node3D
var flash_t := 0.0
var phase := 0.0
var leg_blend := 0.0
var knife := false
var dead := false
var death_t := 0.0
var death_dir := 1.0
var fling := Vector3.ZERO
var downed := false
# custom rigged character
var rig: Node3D
var anim: AnimationPlayer
var cur_anim := ""


func setup(p_style: String, p_gun: String) -> void:
	style = p_style
	gun_id = p_gun
	knife = p_gun == "knife"
	if not _try_custom():
		_build()


# ------------------------------------------------------------------ procedural model
static func _camo(key: String, cols: Array) -> ShaderMaterial:
	if _camo_mats.has(key):
		return _camo_mats[key]
	if _camo_shader == null:
		_camo_shader = load("res://scripts/camo.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _camo_shader
	m.set_shader_parameter("c0", cols[0])
	m.set_shader_parameter("c1", cols[1])
	m.set_shader_parameter("c2", cols[2])
	m.set_shader_parameter("c3", cols[3])
	if ResourceLoader.exists("res://assets/textures/fabric/normal.jpg"):
		m.set_shader_parameter("fabric_normal", load("res://assets/textures/fabric/normal.jpg"))
		m.set_shader_parameter("fabric_rough", load("res://assets/textures/fabric/roughness.jpg"))
	_camo_mats[key] = m
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = max(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 4
	return c


func _boxm(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _sphere(r: float, hemi := false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * (1.0 if hemi else 2.0)
	s.is_hemisphere = hemi
	s.radial_segments = 16
	s.rings = 8
	return s


func _build() -> void:
	var st: Dictionary = STYLES.get(style, STYLES.grunt)
	bulk = 1.35 if st.get("heavy", false) else 1.0
	var cloth := _camo(style, st.camo)
	var vest := Mat.pbr("burlap", st.vest, 0.9, 0.0, 3.0)
	var plate := Mat.pbr("painted_metal", Color(0.12, 0.12, 0.13) if bulk > 1 else st.vest, 0.6, 0.4)
	var skin := Mat.solid(Color(0.62, 0.46, 0.38), 0.6)
	var glove := Mat.pbr("fabric", Color(0.12, 0.12, 0.11), 0.9, 0.0, 4.0)
	var boot := Mat.pbr("fabric", Color(0.1, 0.085, 0.07), 0.7, 0.0, 4.0)
	var black := Mat.pbr("fabric", Color(0.05, 0.05, 0.05), 0.95, 0.0, 4.0)
	var helm_mat := Mat.pbr("burlap", st.camo[1] * 0.9, 0.85, 0.0, 2.0)

	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	hips = Node3D.new()
	hips.position.y = 0.95
	body.add_child(hips)
	_part(hips, _cap(0.17 * bulk, 0.4 * bulk), cloth, Vector3.ZERO, Vector3(0, 0, PI / 2))

	for s in [-1.0, 1.0]:
		var thigh := Node3D.new()
		thigh.position = Vector3(0.1 * s * bulk, 0, 0)
		_part(thigh, _cap(0.085 * bulk, 0.5), cloth, Vector3(0, -0.24, 0))
		if bulk > 1:
			_part(thigh, _boxm(Vector3(0.2, 0.32, 0.06)), plate, Vector3(0, -0.2, -0.11))
		var knee := Node3D.new()
		knee.position.y = -0.47
		_part(knee, _cap(0.07 * bulk, 0.46), cloth, Vector3(0, -0.22, 0))
		_part(knee, _boxm(Vector3(0.14 * bulk, 0.12, 0.06)), black, Vector3(0, -0.02, -0.07))
		_part(knee, _boxm(Vector3(0.12 * bulk, 0.11, 0.28)), boot, Vector3(0, -0.43, -0.05))
		thigh.add_child(knee)
		hips.add_child(thigh)
		legs.append({"thigh": thigh, "knee": knee})

	torso = Node3D.new()
	torso.position.y = 0.06
	hips.add_child(torso)
	_part(torso, _cap(0.19 * bulk, 0.6), cloth, Vector3(0, 0.28, 0))
	_part(torso, _boxm(Vector3(0.42 * bulk, 0.4, 0.29 * bulk)), vest, Vector3(0, 0.3, 0))
	if bulk == 1.0:
		for k in [-1, 0, 1]:
			_part(torso, _boxm(Vector3(0.085, 0.12, 0.06)), vest, Vector3(k * 0.11, 0.2, -0.16))
		_part(torso, _boxm(Vector3(0.12, 0.08, 0.05)), vest, Vector3(0.14, 0.42, -0.16))
	else:
		_part(torso, _boxm(Vector3(0.5 * bulk, 0.48, 0.07)), plate, Vector3(0, 0.32, -0.21))
		_part(torso, _boxm(Vector3(0.5 * bulk, 0.48, 0.07)), plate, Vector3(0, 0.32, 0.21))
		_part(torso, _boxm(Vector3(0.22, 0.15, 0.34)), plate, Vector3(0.34 * bulk, 0.5, 0))
		_part(torso, _boxm(Vector3(0.22, 0.15, 0.34)), plate, Vector3(-0.34 * bulk, 0.5, 0))
	if st.get("friendly", false):
		_part(torso, _boxm(Vector3(0.16, 0.06, 0.16)), Mat.emissive(Color(0.2, 0.5, 1.0), 1.5), Vector3(0.27, 0.42, 0))
	_part(torso, _boxm(Vector3(0.3, 0.36, 0.14)), vest, Vector3(0, 0.3, 0.19))    # pack

	neck = Node3D.new()
	neck.position.y = 0.56
	torso.add_child(neck)
	var head := Node3D.new()
	head.position.y = 0.12
	neck.add_child(head)
	var face_mat: Material = black if st.face == "balaclava" else skin
	var hm := _part(head, _sphere(0.11), face_mat, Vector3.ZERO)
	hm.scale = Vector3(0.92, 1.1, 1.0)
	if st.has("scarf"):
		_part(head, _cap(0.1, 0.22), Mat.pbr("fabric", st.scarf, 0.95, 0.0, 3.0), Vector3(0, -0.075, -0.01), Vector3(0, 0, PI / 2)).scale = Vector3(1, 1, 1.05)
	match st.face:
		"skin":
			_part(head, _boxm(Vector3(0.17, 0.035, 0.03)), Mat.solid(Color(0.02, 0.02, 0.02), 0.1, 0.8), Vector3(0, 0.02, -0.1))
		"balaclava":
			_part(head, _boxm(Vector3(0.12, 0.03, 0.02)), Mat.solid(Color(0.55, 0.42, 0.35), 0.6), Vector3(0, 0.02, -0.104))
	match st.head:
		"helmet":
			_part(head, _sphere(0.138, true), helm_mat, Vector3(0, 0.02, 0)).scale = Vector3(1, 1.05, 1.08)
			_part(head, _boxm(Vector3(0.07, 0.05, 0.04)), black, Vector3(0, 0.1, -0.12))
			_part(head, _boxm(Vector3(0.03, 0.06, 0.07)), black, Vector3(-0.14, 0.04, 0.0))
		"cap":
			_part(head, _sphere(0.122, true), cloth, Vector3(0, 0.03, 0))
			_part(head, _boxm(Vector3(0.16, 0.015, 0.1)), cloth, Vector3(0, 0.06, -0.12))
		"jugg":
			_part(head, _sphere(0.17), plate, Vector3.ZERO).scale = Vector3(1, 1.05, 1.05)
			_part(head, _boxm(Vector3(0.2, 0.06, 0.05)), Mat.solid(Color(0.05, 0.1, 0.12), 0.05, 1.0), Vector3(0, 0.02, -0.15))

	for s in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.24 * s * bulk, 0.5, 0)
		_part(sh, _cap(0.065 * bulk, 0.32), cloth, Vector3(0, -0.14, 0))
		var el := Node3D.new()
		el.position.y = -0.28
		_part(el, _cap(0.055 * bulk, 0.3), cloth, Vector3(0, -0.13, 0))
		_part(el, _boxm(Vector3(0.08, 0.09, 0.1)), glove, Vector3(0, -0.29, 0))
		sh.add_child(el)
		torso.add_child(sh)
		arms.append({"sh": sh, "el": el})

	if knife:
		arms[0].sh.rotation.x = 0.4
		arms[1].sh.rotation.x = -0.3
		arms[1].el.rotation.x = 1.2
		var k := WeaponModel.build("knife")
		k.position = Vector3(0, -0.3, -0.05)
		k.rotation.x = 1.4
		arms[1].el.add_child(k)
	else:
		gun = WeaponModel.build(gun_id)
		gun.scale = Vector3.ONE * 1.1
		gun.position = Vector3(0.06 * bulk, 0.34, -0.3) - (gun.get_meta("grip_r", Vector3.ZERO) as Vector3) * 1.1 + Vector3(0, 0, 0.08 if gun.has_meta("custom") else 0.0)
		torso.add_child(gun)
		arms[1].sh.rotation = Vector3(1.0, 0, -0.25)
		arms[1].el.rotation = Vector3(0.9, 0, 0)
		arms[0].sh.rotation = Vector3(1.2, 0, 0.5)
		arms[0].el.rotation = Vector3(0.5, 0, 0)
		_add_flash(gun.get_meta("muzzle"))
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _add_flash(muzzle: Node3D) -> void:
	flash = Effects.make_flash_sprite(0.45)
	muzzle.add_child(flash)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 3.0
	l.omni_range = 5.0
	l.name = "FlashLight"
	flash.add_child(l)
	flash.visible = false


# ------------------------------------------------------------------ custom rigged character
func _try_custom() -> bool:
	var path := ""
	for n in [style, "soldier"]:
		for ext in ["glb", "gltf", "fbx"]:
			var p := "res://assets/characters/%s.%s" % [n, ext]
			if ResourceLoader.exists(p):
				path = p
				break
		if path != "":
			break
	if path == "":
		return false
	rig = (load(path) as PackedScene).instantiate()
	add_child(rig)
	# normalise height to ~1.8 m * style scale and face -Z
	var aabb := _aabb(rig)
	if aabb.size.y > 0.01:
		rig.scale *= 1.8 / aabb.size.y
	rig.rotation.y = PI    # Mixamo characters face +Z
	anim = rig.find_child("AnimationPlayer", true, false)
	if anim == null:
		anim = AnimationPlayer.new()
		rig.add_child(anim)
	var lib := AnimationLibrary.new()
	for clip in ["idle", "walk", "run", "fire", "death", "melee"]:
		for ext in ["glb", "gltf", "fbx"]:
			var p := "res://assets/characters/anims/%s.%s" % [clip, ext]
			if not ResourceLoader.exists(p):
				continue
			var src: Node = (load(p) as PackedScene).instantiate()
			var ap: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
			if ap:
				for an in ap.get_animation_list():
					if an == "RESET":
						continue
					var a: Animation = ap.get_animation(an).duplicate()
					a.loop_mode = Animation.LOOP_NONE if clip in ["death", "melee"] else Animation.LOOP_LINEAR
					lib.add_animation(clip, a)
					break
			src.free()
			break
	if anim.has_animation_library("ms"):
		anim.remove_animation_library("ms")
	anim.add_animation_library("ms", lib)
	# attach weapon to right hand bone if present
	var skel: Skeleton3D = rig.find_child("Skeleton3D", true, false)
	if skel and not knife:
		var bone := -1
		for i in skel.get_bone_count():
			if skel.get_bone_name(i).to_lower().ends_with("righthand"):
				bone = i
		if bone >= 0:
			var att := BoneAttachment3D.new()
			att.bone_idx = bone
			skel.add_child(att)
			gun = WeaponModel.build(gun_id)
			gun.scale = Vector3.ONE * (1.0 / rig.scale.x) * 1.1
			gun.rotation = Vector3(0, PI / 2, PI / 2)
			att.add_child(gun)
			_add_flash(gun.get_meta("muzzle"))
	_play("idle")
	return true


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var a: AABB = m.global_transform * m.get_aabb() if m.is_inside_tree() else m.transform * m.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


func _play(clip: String, blend := 0.2) -> void:
	if anim == null or cur_anim == clip:
		return
	if anim.has_animation("ms/" + clip):
		anim.play("ms/" + clip, blend)
		cur_anim = clip


# ------------------------------------------------------------------ animation
## mv: moving, speed: m/s, state: 0 move, 1 aim/fire, 2 melee strike
func animate(dt: float, mv: bool, speed: float, state: int, t: float) -> void:
	if flash_t > 0.0:
		flash_t -= dt
		flash.visible = flash_t > 0.0
		if flash.visible:
			flash.rotation.z = randf() * TAU
	if dead:
		return   # death is animated by _process once the body is detached
	if rig:
		if downed:
			_play("death")
		elif state == 2:
			_play("melee", 0.05)
		elif mv:
			_play("run" if speed > 4.0 else "walk")
		elif state == 1:
			_play("fire" if anim.has_animation("ms/fire") else "idle")
		else:
			_play("idle")
		return
	phase += dt * (speed * 2.2 if mv else 0.0)
	leg_blend = move_toward(leg_blend, 1.0 if mv else 0.0, dt * 6.0)
	var a := 0.6 * leg_blend
	legs[0].thigh.rotation.x = sin(phase) * a
	legs[1].thigh.rotation.x = -sin(phase) * a
	legs[0].knee.rotation.x = -max(0.0, -sin(phase + 1.2)) * 0.9 * leg_blend
	legs[1].knee.rotation.x = -max(0.0, sin(phase + 1.2)) * 0.9 * leg_blend
	hips.position.y = 0.95 - abs(cos(phase)) * 0.04 * leg_blend
	torso.rotation.x = (-0.25 if knife else -0.08) * leg_blend - 0.02
	torso.rotation.y = sin(phase) * 0.06 * leg_blend
	if knife:
		arms[0].sh.rotation.x = sin(phase) * 0.8 * leg_blend + 0.2
		arms[1].sh.rotation.x = 2.2 if state == 2 else -sin(phase) * 0.8 * leg_blend + 0.2
	neck.rotation.x = sin(t * 1.3 + phase) * 0.02
	if downed:
		rotation.x = lerp(rotation.x, -1.35, dt * 6.0)
		position.y = lerp(position.y, 0.25, dt * 6.0)
	elif rotation.x != 0.0:
		rotation.x = lerp(rotation.x, 0.0, dt * 6.0)


func _process(dt: float) -> void:
	if dead:
		_animate_death(dt)


func muzzle_flash() -> void:
	if flash:
		flash_t = 0.05
		flash.visible = true
		flash.scale = Vector3.ONE * randf_range(0.7, 1.3)


func die(dir: Vector3, explosive: bool) -> void:
	dead = true
	death_t = 0.0
	var local := global_transform.basis.inverse() * dir
	death_dir = 1.0 if local.z > 0 else -1.0   # +x rotation tips the body backwards (+Z): fall away from the shot
	if explosive:
		fling = dir.normalized() * randf_range(3.0, 6.0) + Vector3.UP * randf_range(4.0, 7.0)
	if rig:
		_play("death", 0.1)
	if flash:
		flash.visible = false


func _animate_death(dt: float) -> void:
	death_t += dt
	if rig:
		if not anim.has_animation("ms/death"):
			rotation.x = lerp(rotation.x, death_dir * PI / 2, min(1.0, dt * 6.0))
		_sink(dt)
		return
	if fling != Vector3.ZERO:
		global_position += fling * dt
		fling.y -= 18.0 * dt
		rotation.x += death_dir * dt * 6.0
		if global_position.y <= 0.0:
			global_position.y = 0.0
			fling = Vector3.ZERO
	var k: float = min(1.0, death_t / 0.55)
	var e := k * k * (3.0 - 2.0 * k)
	if fling == Vector3.ZERO:
		rotation.x = lerp(rotation.x, death_dir * PI / 2 * 0.97, e)
		position.y = lerp(position.y, 0.12, e)
	legs[0].knee.rotation.x = -0.8 * e
	legs[1].knee.rotation.x = -0.3 * e
	if not knife:
		arms[0].sh.rotation.x = lerp(1.2, 2.6, e)
		arms[1].sh.rotation.x = lerp(1.0, 0.2, e)
	neck.rotation.x = 0.4 * e * death_dir
	_sink(dt)


func _sink(_dt: float) -> void:
	if death_t > 9.0:
		position.y -= _dt * 0.25
		if death_t > 12.0:
			queue_free()
