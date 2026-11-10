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
	"sniper": {"camo": [Color(0.4, 0.42, 0.3), Color(0.3, 0.31, 0.21), Color(0.5, 0.48, 0.36), Color(0.2, 0.2, 0.15)], "vest": Color(0.3, 0.3, 0.22), "head": "cap", "face": "balaclava", "scarf": Color(0.32, 0.34, 0.24)},
	"shield": {"camo": [Color(0.12, 0.13, 0.17), Color(0.08, 0.09, 0.12), Color(0.18, 0.19, 0.23), Color(0.05, 0.05, 0.07)], "vest": Color(0.1, 0.1, 0.13), "head": "helmet", "face": "balaclava"},
	"grenadier": {"camo": [Color(0.45, 0.36, 0.25), Color(0.34, 0.26, 0.17), Color(0.56, 0.46, 0.33), Color(0.24, 0.18, 0.12)], "vest": Color(0.3, 0.24, 0.16), "head": "helmet", "face": "scarf", "scarf": Color(0.5, 0.4, 0.25)},
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
var crouch_k := 0.0
# ---- procedural animation state
var pivot: Node3D            # weapon carry pivot at the shoulders: both arms and the gun hang off it
var carry := 0.0             # 0 = low ready, 1 = shouldered / aiming
var hurt := false            # limping (badly wounded)
var _last_pos := Vector3.ZERO
var _has_last := false
var _lv := Vector3.ZERO      # smoothed local-space velocity
var _act := 0
var _act_t := 0.0            # time since the current state started
var _arm_base: Array = []    # rest rotations of [left sh, left el, right sh, right el]
var _hit_rot := Vector3.ZERO
var _hit_vel := Vector3.ZERO
var _head_rot := Vector3.ZERO
var _head_vel := Vector3.ZERO
var _buckle := 0.0
var _wounds := 0
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


func _rb(parent: Node3D, mat: Material, size: Vector3, pos: Vector3, radius := 0.02, rot := Vector3.ZERO) -> MeshInstance3D:
	return _part(parent, Shapes.rounded_box(size, radius), mat, pos, rot)


func _ell(parent: Node3D, mat: Material, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := _part(parent, Shapes.ellipsoid(size), mat, pos, rot)
	mi.scale = size
	return mi


func _build() -> void:
	var st: Dictionary = STYLES.get(style, STYLES.grunt)
	bulk = 1.3 if st.get("heavy", false) else 1.0
	var cloth := _camo(style, st.camo)
	var vest := Mat.pbr("burlap", st.vest, 0.9, 0.0, 3.0)
	var webbing := Mat.pbr("fabric", st.vest * 0.8, 0.9, 0.0, 6.0)
	var plate := Mat.pbr("painted_metal", Color(0.12, 0.12, 0.13) if bulk > 1 else st.vest, 0.6, 0.4)
	var skin := Mat.solid(Color(0.6, 0.45, 0.37), 0.55)
	var glove := Mat.pbr("fabric", Color(0.14, 0.13, 0.12), 0.9, 0.0, 4.0)
	var boot := Mat.pbr("fabric", Color(0.12, 0.1, 0.08), 0.65, 0.0, 4.0)
	var sole := Mat.solid(Color(0.05, 0.05, 0.05), 0.9)
	var black := Mat.pbr("fabric", Color(0.05, 0.05, 0.05), 0.95, 0.0, 4.0)
	var helm_mat := Mat.pbr("burlap", st.camo[1] * 0.9, 0.85, 0.0, 2.0)
	var strap := Mat.solid(st.vest * 0.6, 0.9)
	var metal := Mat.solid(Color(0.15, 0.15, 0.15), 0.4, 0.8)

	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	hips = Node3D.new()
	hips.position.y = 0.95
	body.add_child(hips)
	# pelvis + belt with pouches and holster
	_ell(hips, cloth, Vector3(0.36, 0.22, 0.24) * Vector3(bulk, 1, bulk), Vector3(0, -0.02, 0))
	_rb(hips, webbing, Vector3(0.37 * bulk, 0.06, 0.25 * bulk), Vector3(0, 0.06, 0), 0.025)
	_rb(hips, webbing, Vector3(0.08, 0.1, 0.06), Vector3(-0.17 * bulk, 0.02, -0.08), 0.015)
	_rb(hips, webbing, Vector3(0.07, 0.09, 0.05), Vector3(0.0, 0.03, 0.14), 0.015)
	_rb(hips, black, Vector3(0.05, 0.16, 0.09), Vector3(0.2 * bulk, -0.05, 0.0), 0.015)          # holster
	for s in [-1.0, 1.0]:
		var thigh := Node3D.new()
		thigh.position = Vector3(0.1 * s * bulk, -0.02, 0)
		_part(thigh, Shapes.capsule(0.088 * bulk, 0.52), cloth, Vector3(0, -0.23, 0))
		_rb(thigh, webbing, Vector3(0.05, 0.12, 0.11), Vector3(0.09 * s * bulk, -0.18, 0.0), 0.015)   # cargo pocket
		if bulk > 1:
			_rb(thigh, plate, Vector3(0.2, 0.32, 0.07), Vector3(0, -0.2, -0.11), 0.02)
		var knee := Node3D.new()
		knee.position.y = -0.46
		_part(knee, Shapes.capsule(0.072 * bulk, 0.46), cloth, Vector3(0, -0.21, 0))
		_rb(knee, black, Vector3(0.13 * bulk, 0.13, 0.06), Vector3(0, -0.02, -0.07), 0.025)      # knee pad
		_rb(knee, boot, Vector3(0.12 * bulk, 0.13, 0.27), Vector3(0, -0.4, -0.04), 0.04)            # boot
		_rb(knee, sole, Vector3(0.125 * bulk, 0.035, 0.29), Vector3(0, -0.47, -0.045), 0.012)
		thigh.add_child(knee)
		hips.add_child(thigh)
		legs.append({"thigh": thigh, "knee": knee})

	torso = Node3D.new()
	torso.position.y = 0.08
	hips.add_child(torso)
	# shaped chest: waist, ribcage, shoulders
	_ell(torso, cloth, Vector3(0.34, 0.3, 0.22) * Vector3(bulk, 1, bulk), Vector3(0, 0.12, 0))
	_ell(torso, cloth, Vector3(0.42, 0.38, 0.25) * Vector3(bulk, 1, bulk), Vector3(0, 0.33, 0))
	_ell(torso, cloth, Vector3(0.48, 0.14, 0.2) * Vector3(bulk, 1, bulk), Vector3(0, 0.48, 0))
	# plate carrier: front & back plates, cummerbund, pouches, shoulder straps
	_rb(torso, vest, Vector3(0.36 * bulk, 0.36, 0.07), Vector3(0, 0.3, -0.135 * bulk), 0.03)
	_rb(torso, vest, Vector3(0.36 * bulk, 0.38, 0.07), Vector3(0, 0.31, 0.135 * bulk), 0.03)
	_rb(torso, webbing, Vector3(0.44 * bulk, 0.16, 0.26 * bulk), Vector3(0, 0.2, 0), 0.04)
	for x in [-0.12, 0.12]:
		_rb(torso, strap, Vector3(0.06, 0.05, 0.3 * bulk), Vector3(x * bulk, 0.5, 0), 0.015)
	if bulk == 1.0:
		for k in [-1, 0, 1]:
			_rb(torso, webbing, Vector3(0.085, 0.13, 0.055), Vector3(k * 0.105, 0.2, -0.19), 0.015)   # mag pouches
			_rb(torso, metal, Vector3(0.06, 0.03, 0.03), Vector3(k * 0.105, 0.28, -0.19), 0.008)      # mags peeking out
		_rb(torso, webbing, Vector3(0.14, 0.09, 0.05), Vector3(0.0, 0.38, -0.18), 0.015)               # admin pouch
		_rb(torso, black, Vector3(0.06, 0.12, 0.05), Vector3(-0.15, 0.4, -0.16), 0.015)                # radio
		_part(torso, Shapes.tube(0.004, 0.003, 0.35), black, Vector3(-0.16, 0.62, 0.1), Vector3(0.25, 0, 0))   # antenna
	else:
		_rb(torso, plate, Vector3(0.5 * bulk, 0.48, 0.08), Vector3(0, 0.32, -0.21), 0.03)
		_rb(torso, plate, Vector3(0.5 * bulk, 0.48, 0.08), Vector3(0, 0.32, 0.21), 0.03)
		_rb(torso, plate, Vector3(0.22, 0.15, 0.34), Vector3(0.33 * bulk, 0.5, 0), 0.04)
		_rb(torso, plate, Vector3(0.22, 0.15, 0.34), Vector3(-0.33 * bulk, 0.5, 0), 0.04)
		_rb(torso, plate, Vector3(0.36, 0.12, 0.3), Vector3(0, 0.62, 0), 0.04)                          # collar
	if st.get("friendly", false):
		_rb(torso, Mat.emissive(Color(0.2, 0.5, 1.0), 1.5), Vector3(0.16, 0.05, 0.16), Vector3(0.27, 0.42, 0), 0.02)
	_rb(torso, vest, Vector3(0.3, 0.38, 0.16), Vector3(0, 0.3, 0.24), 0.05)                            # pack
	_rb(torso, webbing, Vector3(0.22, 0.12, 0.06), Vector3(0, 0.12, 0.3), 0.02)

	neck = Node3D.new()
	neck.position.y = 0.56
	torso.add_child(neck)
	_part(neck, Shapes.capsule(0.055, 0.14), skin if st.face == "skin" else black, Vector3(0, 0.04, 0))
	var head := Node3D.new()
	head.position.y = 0.13
	neck.add_child(head)
	var face_mat: Material = black if st.face == "balaclava" else skin
	_ell(head, face_mat, Vector3(0.19, 0.24, 0.22), Vector3.ZERO)
	_ell(head, face_mat, Vector3(0.12, 0.1, 0.1), Vector3(0, -0.07, -0.05))                            # jaw
	if st.face != "balaclava":
		_ell(head, skin, Vector3(0.03, 0.05, 0.05), Vector3(0, 0.0, -0.11))                            # nose
		for x in [-0.098, 0.098]:
			_ell(head, skin, Vector3(0.02, 0.06, 0.04), Vector3(x, 0.0, 0.0))                          # ears
	if st.has("scarf"):
		_ell(head, Mat.pbr("fabric", st.scarf, 0.95, 0.0, 3.0), Vector3(0.22, 0.1, 0.22), Vector3(0, -0.09, -0.01))
	match st.face:
		"skin", "scarf":
			_rb(head, Mat.solid(Color(0.02, 0.02, 0.02), 0.1, 0.8), Vector3(0.17, 0.04, 0.03), Vector3(0, 0.025, -0.1), 0.012)
		"balaclava":
			_rb(head, Mat.solid(Color(0.5, 0.38, 0.32), 0.6), Vector3(0.12, 0.035, 0.02), Vector3(0, 0.025, -0.104), 0.01)
	match st.head:
		"helmet":
			var h := _part(head, _sphere(0.14, true), helm_mat, Vector3(0, 0.02, 0))
			h.scale = Vector3(1.05, 1.0, 1.12)
			_part(head, Shapes.tube(0.148, 0.148, 0.025, 20), helm_mat, Vector3(0, 0.02, 0.0)).scale = Vector3(1.0, 1.0, 1.08)
			_rb(head, black, Vector3(0.07, 0.045, 0.04), Vector3(0, 0.1, -0.13), 0.01)                   # NVG mount
			_rb(head, Mat.solid(Color(0.08, 0.08, 0.08), 0.2, 0.6), Vector3(0.17, 0.05, 0.05), Vector3(0, 0.08, -0.115), 0.02)   # goggles on helmet
			_rb(head, black, Vector3(0.03, 0.06, 0.08), Vector3(-0.145, 0.04, 0.0), 0.01)                # light/strobe
			for x in [-0.1, 0.1]:
				_part(head, Shapes.tube(0.006, 0.006, 0.14), strap, Vector3(x, -0.05, -0.02), Vector3(0, 0, 0.3 * sign(x)))    # chin strap
		"cap":
			_part(head, _sphere(0.122, true), cloth, Vector3(0, 0.03, 0))
			_rb(head, cloth, Vector3(0.16, 0.015, 0.1), Vector3(0, 0.06, -0.12), 0.006)
		"jugg":
			_part(head, _sphere(0.17), plate, Vector3.ZERO).scale = Vector3(1, 1.05, 1.05)
			_rb(head, Mat.solid(Color(0.05, 0.1, 0.12), 0.05, 1.0), Vector3(0.2, 0.06, 0.05), Vector3(0, 0.02, -0.15), 0.02)

	for s in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.235 * s * bulk, 0.5, 0)
		_part(sh, Shapes.capsule(0.07 * bulk, 0.33), cloth, Vector3(0, -0.14, 0))
		_rb(sh, webbing, Vector3(0.08, 0.06, 0.1), Vector3(0.05 * s, -0.08, 0), 0.015)              # shoulder pocket / patch
		var el := Node3D.new()
		el.position.y = -0.28
		_part(el, Shapes.capsule(0.058 * bulk, 0.3), cloth, Vector3(0, -0.13, 0))
		_part(el, Shapes.capsule(0.05, 0.11), glove, Vector3(0, -0.29, 0))
		_rb(el, glove, Vector3(0.07, 0.03, 0.09), Vector3(0, -0.33, -0.02), 0.012)                    # fingers
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
		# sling from the gun to the shoulder
		_part(torso, Shapes.tube(0.008, 0.008, 0.5), strap, Vector3(-0.08, 0.42, -0.1), Vector3(0.9, 0, 0.6))
	_make_pivot()
	if style == "shield":
		_build_shield(torso)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Arms and gun hang off one pivot at the shoulders, so lowering / raising / tilting the weapon moves the
## hands with it.
func _make_pivot() -> void:
	pivot = Node3D.new()
	pivot.name = "Carry"
	pivot.position = Vector3(0, 0.45, -0.02)
	torso.add_child(pivot)
	var kids: Array = [arms[0].sh, arms[1].sh]
	if gun:
		kids.append(gun)
	for n in kids:
		torso.remove_child(n)
		pivot.add_child(n)
		(n as Node3D).position -= pivot.position
	_arm_base = [arms[0].sh.rotation, arms[0].el.rotation, arms[1].sh.rotation, arms[1].el.rotation]


## Ballistic shield held in front of the body, with a small armoured view port.
var shield: Node3D
func _build_shield(parent: Node3D) -> void:
	shield = Node3D.new()
	shield.name = "Shield"
	shield.position = Vector3(-0.06, -0.06, -0.42)
	parent.add_child(shield)
	var steel := Mat.pbr("painted_metal", Color(0.11, 0.12, 0.14), 0.55, 0.6)
	_rb(shield, steel, Vector3(0.58, 1.0, 0.05), Vector3.ZERO, 0.04)
	_rb(shield, Mat.solid(Color(0.1, 0.16, 0.2, 1.0), 0.05, 0.9), Vector3(0.26, 0.09, 0.02), Vector3(0, 0.36, -0.03), 0.01)
	var lbl := Label3D.new()
	lbl.text = "POLITIE"
	lbl.font_size = 48
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.85, 0.85, 0.8)
	lbl.position = Vector3(0, 0.15, -0.03)
	lbl.rotation.y = PI
	shield.add_child(lbl)
	arms[0].sh.rotation = Vector3(1.0, 0, 0.1)
	arms[0].el.rotation = Vector3(0.9, 0, 0)


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
	_animate_body(dt, mv, state, t)
	if downed:
		rotation.x = lerp(rotation.x, -1.35, dt * 6.0)
		position.y = lerp(position.y, 0.25, dt * 6.0)
	elif rotation.x != 0.0:
		rotation.x = lerp(rotation.x, 0.0, dt * 6.0)
		position.y = lerp(position.y, 0.0, dt * 6.0)


## States: 0 move / idle, 1 aim, 2 melee (knife / shield bash), 3 crouched, 4 aiming (sniper),
## 5 reloading, 6 throwing a grenade, 7 staggered.
func _animate_body(dt: float, mv: bool, state: int, t: float) -> void:
	if state != _act:
		_act = state
		_act_t = 0.0
	_act_t += dt
	# velocity in the body's own frame (works the same for server enemies and client puppets)
	var gp := global_position
	var v := (gp - _last_pos) / maxf(dt, 0.001) if _has_last else Vector3.ZERO
	_last_pos = gp
	_has_last = true
	if v.length() > 14.0:
		v = Vector3.ZERO                                   # teleport / spawn
	var lv := global_transform.basis.orthonormalized().inverse() * Vector3(v.x, 0, v.z)
	_lv = _lv.lerp(lv, min(1.0, dt * 8.0))
	var sp := Vector2(_lv.x, _lv.z).length()
	var moving := sp > 0.35 and mv
	var run := sp > 4.3
	var fwd := -_lv.z / maxf(sp, 0.001)                   # +1 forwards, -1 backwards
	var side := _lv.x / maxf(sp, 0.001)                   # +1 strafing right
	phase += dt * sp * (1.75 if run else 2.25)
	leg_blend = move_toward(leg_blend, 1.0 if moving else 0.0, dt * 6.0)
	var amp := (0.85 if run else 0.55) * leg_blend
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		var limp := 0.45 if hurt and i == 1 else 1.0
		var sw := sin(phase) * sgn
		legs[i].thigh.rotation.x = sw * amp * fwd * limp
		legs[i].thigh.rotation.z = sw * amp * 0.45 * side * limp + (0.05 * sgn * leg_blend * abs(side))
		legs[i].knee.rotation.x = -max(0.0, -sin(phase + 1.2) * sgn) * (1.25 if run else 0.9) * leg_blend * limp
	var bob := absf(cos(phase)) * (0.075 if run else 0.04) * leg_blend
	hips.position.y = 0.95 - bob - (0.05 if hurt and sin(phase) < 0.0 else 0.0) * leg_blend - _buckle * 0.25
	var lean := (0.24 if run else 0.07) * leg_blend * maxf(fwd, 0.0)
	torso.rotation = Vector3(-lean - 0.02, sin(phase) * 0.07 * leg_blend, (0.06 if hurt else 0.0) - side * 0.05 * leg_blend)
	neck.rotation = Vector3(sin(t * 1.3 + phase) * 0.02, 0, 0)
	# crouch (state 3) keeps the legs folded
	crouch_k = move_toward(crouch_k, 1.0 if state == 3 and not moving else 0.0, dt * 5.0)
	if crouch_k > 0.0:
		hips.position.y -= 0.38 * crouch_k
		for i in 2:
			legs[i].thigh.rotation.x = lerpf(legs[i].thigh.rotation.x, -1.25 if i == 0 else -0.35, crouch_k)
			legs[i].knee.rotation.x = lerpf(legs[i].knee.rotation.x, 1.9 if i == 0 else 1.6, crouch_k)
		torso.rotation.x += 0.15 * crouch_k
	# hit reactions: damped springs on the torso and head
	_hit_vel += (-_hit_rot * 140.0 - _hit_vel * 13.0) * dt
	_hit_rot += _hit_vel * dt
	_head_vel += (-_head_rot * 160.0 - _head_vel * 12.0) * dt
	_head_rot += _head_vel * dt
	_buckle = move_toward(_buckle, 0.0, dt * 2.5)
	torso.rotation += _hit_rot
	neck.rotation += _head_rot
	# staggered: rocked back on the heels
	if state == 7:
		var e := sin(clampf(_act_t / 0.55, 0.0, 1.0) * PI)
		torso.rotation.x += 0.35 * e
		neck.rotation.x += 0.25 * e
		hips.position.z = 0.08 * e
	else:
		hips.position.z = 0.0
	if knife:
		arms[0].sh.rotation.x = sin(phase) * 0.8 * leg_blend + 0.2
		arms[1].sh.rotation.x = 2.2 if state == 2 else -sin(phase) * 0.8 * leg_blend + 0.2
		return
	if pivot == null:
		return
	# weapon carry: shouldered when aiming, low ready when moving or idle, high when sprinting
	var want := 1.0 if state in [1, 4] else (0.55 if state == 3 else 0.12)
	carry = move_toward(carry, want, dt * 4.0)
	var prot := Vector3(lerpf(-0.6, 0.0, carry) - (0.12 if run and carry < 0.5 else 0.0), lerpf(0.45, 0.0, carry), 0.0)
	var ppos := Vector3(sin(phase) * 0.012 * leg_blend, -bob * 0.3, 0)
	for i in 4:
		var n: Node3D = arms[i / 2].sh if i % 2 == 0 else arms[i / 2].el
		n.rotation = n.rotation.lerp(_arm_base[i], min(1.0, dt * 10.0))
	match state:
		5:   # reload: tilt the gun, left hand down to the belt for a fresh mag and back
			var k := clampf(_act_t / 2.0, 0.0, 1.0)
			var e := sin(k * PI)
			prot += Vector3(-0.3 * e, 0.2 * e, 0.55 * e)
			var down := smoothstep(0.1, 0.35, k) * (1.0 - smoothstep(0.55, 0.8, k))
			arms[0].sh.rotation = (_arm_base[0] as Vector3).lerp(Vector3(0.25, 0.0, 0.35), down)
			arms[0].el.rotation = (_arm_base[1] as Vector3).lerp(Vector3(0.6, 0, 0), down)
			var mag = gun.get_meta("mag", null) if gun else null
			if mag:
				(mag as Node3D).visible = k < 0.2 or k > 0.55
		6:   # grenade: right arm winds up overhead and throws, gun dropped to the left hand
			var k := clampf(_act_t / 0.6, 0.0, 1.0)
			var swing := lerpf(3.2, 1.0, smoothstep(0.45, 0.75, k)) if k > 0.15 else lerpf(_arm_base[2].x, 3.2, k / 0.15)
			arms[1].sh.rotation = Vector3(swing, 0.0, -0.2)
			arms[1].el.rotation = Vector3(0.4, 0, 0)
			prot += Vector3(-0.5, 0.6, 0.0)
		2:   # shield bash / rifle butt: shove forward
			var e := sin(clampf(_act_t / 0.35, 0.0, 1.0) * PI)
			ppos.z -= 0.3 * e
			torso.rotation.x -= 0.2 * e
	pivot.rotation = pivot.rotation.lerp(prot, min(1.0, dt * 12.0))
	pivot.position = Vector3(0, 0.45, -0.02) + ppos


## A bullet hit from world-space direction `from_dir` (shooter -> body): flinch, snap the head on headshots,
## buckle on leg hits.
func hit_react(from_dir: Vector3, zone: int, strength := 1.0) -> void:
	if dead:
		return
	var d := global_transform.basis.orthonormalized().inverse() * from_dir.normalized()
	var k := clampf(strength, 0.3, 2.0)
	if zone == 0:
		_head_vel += Vector3(d.z * -9.0, randf_range(-4, 4), d.x * 9.0) * k
	elif zone == 2:
		_buckle = minf(1.0, _buckle + 0.6 * k)
		_hit_vel += Vector3(-2.0, 0, d.x * 3.0) * k
	else:
		_hit_vel += Vector3(-d.z * 6.0, randf_range(-3, 3), d.x * 6.0) * k


## A small blood mark on the body part that was hit, facing the shooter (max 5 per body).
func add_wound(from_dir: Vector3, zone: int) -> void:
	if dead or _wounds >= 5 or rig:
		return
	_wounds += 1
	var part: Node3D = neck if zone == 0 else (legs[randi() % 2].thigh if zone == 2 else torso)
	var dcl := Decal.new()
	dcl.texture_albedo = Effects.textures().blood
	dcl.size = Vector3(0.16, 0.5, 0.16) * (0.7 if zone == 0 else 1.0)
	dcl.modulate = Color(0.55, 0.05, 0.04, 0.95)
	dcl.normal_fade = 0.3
	part.add_child(dcl)
	var up := -from_dir.normalized()                 # decal projects along its -Y: into the body from the shooter
	var ref := Vector3.RIGHT if abs(up.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := ref.cross(up).normalized()
	var off: Vector3 = {0: Vector3(0, 0.16, 0), 2: Vector3(0, -0.25, 0)}.get(zone, Vector3(0, 0.3, 0))
	dcl.global_transform = Transform3D(Basis(x, up, x.cross(up)), part.global_transform * off + up * 0.2)


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
	if shield:
		shield.visible = false
	death_t = 0.0
	if flash:
		flash.visible = false
	if rig:
		_play("death", 0.1)
		return
	_ragdoll(dir, explosive)


## Turn the soldier into a physics ragdoll: rigid bodies for pelvis, chest, head, upper/lower arms and legs,
## joined with cone-twist joints at the real joint positions, with an impulse from the shot or blast.
var ragdoll: Array = []

func _ragdoll(dir: Vector3, explosive: bool) -> void:
	var parts := [["pelvis", hips, Vector3(0, 0, 0), 0.14, 0.25, null],
		["chest", torso, Vector3(0, 0.3, 0), 0.17, 0.5, "pelvis"],
		["head", neck, Vector3(0, 0.13, 0), 0.12, 0.26, "chest"]]
	for i in 2:
		var side := "l" if i == 0 else "r"
		parts.append(["uarm_" + side, arms[i].sh, Vector3(0, -0.14, 0), 0.06, 0.32, "chest"])
		parts.append(["farm_" + side, arms[i].el, Vector3(0, -0.15, 0), 0.055, 0.34, "uarm_" + side])
		parts.append(["thigh_" + side, legs[i].thigh, Vector3(0, -0.23, 0), 0.085, 0.5, "pelvis"])
		parts.append(["shin_" + side, legs[i].knee, Vector3(0, -0.23, 0), 0.075, 0.5, "thigh_" + side])
	var root_parent := get_parent()
	var bodies := {}
	var mass := {"pelvis": 14.0, "chest": 22.0, "head": 5.0}
	# freeze the current pose: remember global transforms of every part first
	var xfs := {}
	for pd in parts:
		xfs[pd[0]] = (pd[1] as Node3D).global_transform
	if gun:
		var gxf := gun.global_transform
		gun.get_parent().remove_child(gun)
		root_parent.add_child(gun)
		gun.global_transform = gxf
		var gb := RigidBody3D.new()
		gb.collision_layer = 16
		gb.collision_mask = Defs.L_WORLD
		gb.mass = 3.5
		root_parent.add_child(gb)
		gb.global_transform = gxf
		var gc := CollisionShape3D.new()
		var gs := BoxShape3D.new()
		gs.size = Vector3(0.06, 0.15, 0.7)
		gc.shape = gs
		gc.position = Vector3(0, 0.02, -0.25)
		gb.add_child(gc)
		gun.reparent(gb, true)
		gb.linear_velocity = dir * randf_range(1.0, 2.5) + Vector3.UP * 1.5
		gb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		ragdoll.append(gb)
	for pd in parts:
		var name: String = pd[0]
		var node: Node3D = pd[1]
		var rb := RigidBody3D.new()
		rb.name = "RD_" + name
		rb.collision_layer = 16
		rb.collision_mask = Defs.L_WORLD | 16
		rb.mass = mass.get(name, 4.0) * bulk
		rb.linear_damp = 0.3
		rb.angular_damp = 2.0
		rb.continuous_cd = true
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = pd[3] * bulk * scale.x
		cap.height = max(pd[4] * scale.x, cap.radius * 2.0)
		cs.shape = cap
		cs.position = (pd[2] as Vector3) * scale.x
		rb.add_child(cs)
		root_parent.add_child(rb)
		rb.global_transform = xfs[name].orthonormalized()
		bodies[name] = rb
		ragdoll.append(rb)
	# move the visual parts under their bodies (children that belong to another body stay with it)
	for pd in parts:
		var node: Node3D = pd[1]
		var gxf: Transform3D = node.global_transform
		node.get_parent().remove_child(node)
		bodies[pd[0]].add_child(node)
		node.global_transform = gxf
	for pd in parts:
		for c in (pd[1] as Node3D).get_children():
			for other in parts:
				if other[1] == c:
					var cxf: Transform3D = xfs[other[0]]
					(pd[1] as Node3D).remove_child(c)
					bodies[other[0]].add_child(c)
					c.global_transform = cxf
	# joints at the parts' pivots
	for pd in parts:
		if pd[5] == null:
			continue
		var j := ConeTwistJoint3D.new()
		root_parent.add_child(j)
		j.global_position = (xfs[pd[0]] as Transform3D).origin
		j.node_a = bodies[pd[5]].get_path()
		j.node_b = bodies[pd[0]].get_path()
		var name: String = pd[0]
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(25 if name.begins_with("shin") or name.begins_with("farm") else 50 if name == "head" else 70))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(20 if name == "head" else 35))
		ragdoll.append(j)
	# shot / blast impulse
	var push := dir.normalized() * (randf_range(9.0, 14.0) if explosive else randf_range(2.0, 4.0))
	if explosive:
		push += Vector3.UP * randf_range(5.0, 8.0)
	for name in bodies:
		var k := 1.0 if name in ["chest", "head"] else 0.6
		(bodies[name] as RigidBody3D).linear_velocity = push * k
	(bodies["chest"] as RigidBody3D).angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	visible = false     # the original root is now empty


func _animate_death(dt: float) -> void:
	death_t += dt
	if rig:
		if not anim.has_animation("ms/death"):
			rotation.x = lerp(rotation.x, death_dir * PI / 2, min(1.0, dt * 6.0))
		_sink(dt)
		return
	# let the ragdoll settle, then freeze it to save CPU; sink and remove after a while
	if death_t > 5.0 and death_t - dt <= 5.0:
		for r in ragdoll:
			if r is RigidBody3D and is_instance_valid(r):
				(r as RigidBody3D).freeze = true
	if death_t > 10.0:
		for r in ragdoll:
			if r is RigidBody3D and is_instance_valid(r):
				(r as RigidBody3D).global_position.y -= dt * 0.25
	if death_t > 12.5:
		for r in ragdoll:
			if is_instance_valid(r):
				r.queue_free()
		queue_free()


func _sink(_dt: float) -> void:
	if death_t > 9.0:
		position.y -= _dt * 0.25
		if death_t > 12.0:
			queue_free()
