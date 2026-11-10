class_name WeaponModel
extends RefCounted
## Procedural weapon meshes. Built pointing down -Z with the grip at the origin.
## If res://assets/weapons/<id>.glb (or .gltf) exists it is used instead — see README.
## Returned node has metadata: "muzzle" (Node3D), "mag" (Node3D or null), "eject" (Node3D).

static var _gm: StandardMaterial3D
static var _poly: StandardMaterial3D
static var _tan: StandardMaterial3D
static var _olive: StandardMaterial3D
static var _wood: StandardMaterial3D
static var _glass: StandardMaterial3D
static var _red: StandardMaterial3D


static func _mats() -> void:
	if _gm:
		return
	_gm = Mat.pbr("painted_metal", Color(0.11, 0.115, 0.12), 0.5, 0.75)
	_poly = Mat.pbr("fabric", Color(0.09, 0.09, 0.095), 0.85, 0.0, 3.0)
	_tan = Mat.pbr("fabric", Color(0.45, 0.39, 0.29), 0.8, 0.0, 3.0)
	_olive = Mat.pbr("painted_metal", Color(0.25, 0.27, 0.19), 0.7, 0.3)
	_wood = Mat.pbr("planks", Color(0.75, 0.6, 0.5), 0.6, 0.0, 0.5)
	_glass = Mat.solid(Color(0.05, 0.15, 0.2), 0.05, 1.0)
	_red = Mat.emissive(Color(1, 0.1, 0.05), 6.0)


static func _box(p: Node3D, m: Material, s: Vector3, pos: Vector3, rx := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation.x = rx
	p.add_child(mi)
	return mi


static func _cyl(p: Node3D, m: Material, r: float, length: float, pos: Vector3, seg := 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation.x = PI / 2
	p.add_child(mi)
	return mi


static func build(id: String) -> Node3D:
	_mats()
	var custom := _custom(id)
	if custom:
		return custom
	var g := Node3D.new()
	g.name = id
	var muzzle := Node3D.new()
	var eject := Node3D.new()
	var mag: Node3D = null
	match id:
		"pistol":
			var model := _gltf("res://assets/props/service_pistol/service_pistol.gltf")
			if model:
				# Poly Haven service pistol: the file holds two variants side by side plus loose parts.
				# Keep the wood-grip variant (*_b, offset +0.15 m in Y), barrel along +X.
				for c in model.get_children():
					var n := String(c.name)
					if not n.ends_with("_b") and n != "service_pistol_magazine_loaded":
						c.queue_free()
				var mg: Node3D = model.get_node_or_null("service_pistol_magazine_loaded")
				if mg:
					mg.position = Vector3(-0.012, 0.142, 0)
					mg.rotation.z = 0.22
					mag = mg
				model.rotation.y = PI / 2
				model.position = Vector3(0, -0.15, 0.0)
				g.add_child(model)
				muzzle.position = Vector3(0, 0.062, -0.18)
			else:
				_box(g, _gm, Vector3(0.034, 0.036, 0.2), Vector3(0, 0.055, -0.06))
				_box(g, _poly, Vector3(0.032, 0.03, 0.17), Vector3(0, 0.026, -0.05))
				_box(g, _poly, Vector3(0.03, 0.11, 0.045), Vector3(0, -0.03, 0.02), 0.25)
				muzzle.position = Vector3(0, 0.055, -0.17)
			mag = Node3D.new()
			eject.position = Vector3(0.02, 0.06, -0.03)
		"smg":
			_box(g, _poly, Vector3(0.05, 0.07, 0.34), Vector3(0, 0.04, -0.1))
			_cyl(g, _gm, 0.014, 0.12, Vector3(0, 0.05, -0.32))
			_box(g, _poly, Vector3(0.035, 0.1, 0.045), Vector3(0, -0.04, 0.0), 0.2)
			_box(g, _gm, Vector3(0.02, 0.02, 0.24), Vector3(0, 0.085, -0.12))
			_box(g, _poly, Vector3(0.04, 0.05, 0.18), Vector3(0, 0.03, 0.17))
			_box(g, _gm, Vector3(0.03, 0.035, 0.05), Vector3(0, 0.11, -0.05))
			_box(g, _glass, Vector3(0.022, 0.022, 0.005), Vector3(0, 0.11, -0.076))
			mag = _box(g, _gm, Vector3(0.026, 0.16, 0.035), Vector3(0, -0.06, -0.12), 0.05)
			muzzle.position = Vector3(0, 0.05, -0.39)
			eject.position = Vector3(0.03, 0.06, -0.06)
		"shotgun":
			_box(g, _gm, Vector3(0.05, 0.07, 0.3), Vector3(0, 0.04, -0.05))
			_cyl(g, _gm, 0.016, 0.6, Vector3(0, 0.065, -0.45))
			_cyl(g, _gm, 0.014, 0.5, Vector3(0, 0.032, -0.42))
			var pump := _box(g, _poly, Vector3(0.055, 0.05, 0.18), Vector3(0, 0.032, -0.4))
			g.set_meta("pump", pump)
			_box(g, _poly, Vector3(0.035, 0.1, 0.045), Vector3(0, -0.04, 0.05), 0.2)
			_box(g, _wood, Vector3(0.045, 0.08, 0.3), Vector3(0, 0.0, 0.25))
			muzzle.position = Vector3(0, 0.065, -0.76)
			eject.position = Vector3(0.03, 0.06, -0.08)
		"ar", "dmr":
			var furn := _tan if id == "dmr" else _poly
			_box(g, _gm, Vector3(0.05, 0.065, 0.3), Vector3(0, 0.045, -0.06))
			_box(g, furn, Vector3(0.055, 0.06, 0.26), Vector3(0, 0.045, -0.33))
			_cyl(g, _gm, 0.012, 0.36 if id == "dmr" else 0.2, Vector3(0, 0.05, -0.6 if id == "dmr" else -0.54))
			_box(g, _gm, Vector3(0.024, 0.02, 0.06), Vector3(0, 0.05, -0.78 if id == "dmr" else -0.64))
			_box(g, furn, Vector3(0.035, 0.1, 0.045), Vector3(0, -0.03, 0.03), 0.25)
			_box(g, furn, Vector3(0.045, 0.08, 0.22), Vector3(0, 0.03, 0.2))
			_box(g, _gm, Vector3(0.022, 0.012, 0.36), Vector3(0, 0.083, -0.15))
			if id == "dmr":
				_cyl(g, _gm, 0.024, 0.28, Vector3(0, 0.12, -0.1), 18)
				_cyl(g, _gm, 0.03, 0.06, Vector3(0, 0.12, -0.27), 18)
				_cyl(g, _gm, 0.028, 0.05, Vector3(0, 0.12, 0.05), 18)
				_box(g, _gm, Vector3(0.02, 0.04, 0.02), Vector3(0, 0.098, -0.18))
				_box(g, _gm, Vector3(0.02, 0.04, 0.02), Vector3(0, 0.098, -0.03))
				mag = _box(g, _gm, Vector3(0.03, 0.09, 0.07), Vector3(0, -0.03, -0.1))
				muzzle.position = Vector3(0, 0.05, -0.82)
			else:
				_box(g, _gm, Vector3(0.04, 0.045, 0.07), Vector3(0, 0.11, -0.06))
				_box(g, _glass, Vector3(0.028, 0.028, 0.004), Vector3(0, 0.115, -0.096))
				_box(g, _red, Vector3(0.004, 0.004, 0.002), Vector3(0, 0.118, -0.03))
				mag = _box(g, _gm, Vector3(0.028, 0.15, 0.06), Vector3(0, -0.06, -0.1), 0.18)
				muzzle.position = Vector3(0, 0.05, -0.68)
			eject.position = Vector3(0.03, 0.06, -0.05)
		"lmg":
			_box(g, _gm, Vector3(0.07, 0.1, 0.4), Vector3(0, 0.05, -0.05))
			_box(g, _poly, Vector3(0.07, 0.07, 0.25), Vector3(0, 0.04, -0.38))
			_cyl(g, _gm, 0.016, 0.42, Vector3(0, 0.055, -0.68))
			mag = _box(g, _olive, Vector3(0.12, 0.12, 0.13), Vector3(0.0, -0.06, -0.1))
			_box(g, _poly, Vector3(0.035, 0.1, 0.045), Vector3(0, -0.04, 0.12), 0.25)
			_box(g, _poly, Vector3(0.05, 0.1, 0.24), Vector3(0, 0.03, 0.3))
			_box(g, _gm, Vector3(0.012, 0.18, 0.012), Vector3(0.02, -0.05, -0.62))
			_box(g, _gm, Vector3(0.012, 0.18, 0.012), Vector3(-0.02, -0.05, -0.62))
			_box(g, _gm, Vector3(0.04, 0.045, 0.07), Vector3(0, 0.13, -0.06))
			muzzle.position = Vector3(0, 0.055, -0.9)
			eject.position = Vector3(0.04, 0.06, -0.05)
		"launcher":
			_cyl(g, _olive, 0.055, 1.0, Vector3(0, 0.08, -0.15), 18)
			_cyl(g, _gm, 0.06, 0.06, Vector3(0, 0.08, -0.65), 18)
			_cyl(g, _gm, 0.06, 0.06, Vector3(0, 0.08, 0.35), 18)
			_box(g, _poly, Vector3(0.035, 0.1, 0.045), Vector3(0, -0.02, 0.0), 0.2)
			_box(g, _poly, Vector3(0.035, 0.1, 0.045), Vector3(0, -0.02, -0.3))
			_box(g, _gm, Vector3(0.04, 0.06, 0.1), Vector3(-0.07, 0.12, -0.1))
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.05
			cm.height = 0.16
			cone.mesh = cm
			cone.material_override = _olive
			cone.rotation.x = -PI / 2
			cone.position = Vector3(0, 0.08, -0.72)
			g.add_child(cone)
			mag = cone
			muzzle.position = Vector3(0, 0.08, -0.7)
			eject.position = Vector3(0, 0.08, 0.4)
		"knife":
			_box(g, Mat.solid(Color(0.1, 0.09, 0.08), 0.8), Vector3(0.025, 0.03, 0.12), Vector3.ZERO)
			_box(g, Mat.solid(Color(0.6, 0.6, 0.62), 0.25, 1.0), Vector3(0.006, 0.035, 0.18), Vector3(0, 0.004, -0.15))
		"designator":
			_box(g, _poly, Vector3(0.12, 0.08, 0.16), Vector3(0, 0.04, -0.05))
			_cyl(g, _gm, 0.03, 0.08, Vector3(0.03, 0.05, -0.16))
			_cyl(g, _gm, 0.03, 0.08, Vector3(-0.03, 0.05, -0.16))
			_box(g, _red, Vector3(0.01, 0.01, 0.01), Vector3(0.045, 0.085, -0.02))
			muzzle.position = Vector3(0, 0.05, -0.2)
	g.add_child(muzzle)
	g.add_child(eject)
	g.set_meta("muzzle", muzzle)
	g.set_meta("eject", eject)
	g.set_meta("mag", mag)
	g.set_meta("grip_r", Vector3.ZERO)
	if mag:
		g.set_meta("mag_pos", mag.position)
	return g


static func _gltf(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate()


## Custom weapon model: res://assets/weapons/<id>.glb|.gltf (made by tools/convert_weapons.py, or your own).
## Convention: barrel down -Z, +Y up, metres, origin on the sight line above the grip.
## Optional child nodes: Muzzle, Mag, Eject, GripR, GripL. Materials named gun_metal / gun_polymer / gun_wood
## are replaced with the game's PBR gun materials.
static var _gun_mats := {}
static var _reticle: ImageTexture


## EOTech-style holographic reticle: 65 MOA ring with a centre dot.
static func _reticle_tex() -> ImageTexture:
	if _reticle:
		return _reticle
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n / 2.0 + 0.5, y - n / 2.0 + 0.5).length()
			var a := 0.0
			a = max(a, clamp(1.0 - abs(d - 52.0) / 3.0, 0.0, 1.0))
			a = max(a, clamp(1.0 - d / 4.0, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_reticle = ImageTexture.create_from_image(img)
	return _reticle

static func _gun_mat(kind: String) -> StandardMaterial3D:
	if _gun_mats.has(kind):
		return _gun_mats[kind]
	var m: StandardMaterial3D
	match kind:
		"gun_polymer":
			m = Mat.pbr("fabric", Color(0.075, 0.075, 0.08), 0.8).duplicate()
			m.uv1_scale = Vector3.ONE * 14.0
		"gun_wood":
			m = Mat.pbr("planks", Color(0.7, 0.55, 0.42), 0.6).duplicate()
			m.uv1_scale = Vector3.ONE * 2.0
		_:
			m = Mat.pbr("painted_metal", Color(0.06, 0.062, 0.066), 0.6, 0.0).duplicate()
			m.albedo_texture = null           # keep only the roughness/normal micro-detail, no green paint
			m.metallic = 0.65
			m.uv1_scale = Vector3.ONE * 3.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_triplanar_sharpness = 4.0
	_gun_mats[kind] = m
	return m


## Models with a bulky built-in sight we strip off (region in model space, AABB) so the gun gets plain iron
## sights instead; the second value is how far the new sight line sits below the model's original one.
## Top of the front sight post (model space) on guns whose iron-sight picture is trimmed when aiming
## (player.gd ADS_TRIM): this point, not the bore line, is what lines up with the screen centre.
const FRONT_SIGHT := {"pistol": Vector3(0, 0, -0.15), "m9": Vector3(0, 0, -0.145), "m1911": Vector3(0, 0, -0.145)}
const SIGHT_CUT := {"smg": [AABB(Vector3(-0.06, -0.057, -0.41), Vector3(0.12, 0.2, 0.37)), 0.028]}


## Simple flip-up iron sights: rear aperture at the back of the receiver, hooded front post near the muzzle.
static func _irons(y: float, front_z: float) -> Node3D:
	_mats()
	var n := Node3D.new()
	n.name = "Irons"
	var metal := _gun_mat("gun_metal")
	var ring := TorusMesh.new()
	ring.inner_radius = 0.0035
	ring.outer_radius = 0.0075
	ring.rings = 16
	ring.ring_segments = 8
	var rear := MeshInstance3D.new()
	rear.mesh = ring
	rear.material_override = metal
	rear.rotation.x = PI / 2
	rear.position = Vector3(0, y, -0.03)
	n.add_child(rear)
	_box(n, metal, Vector3(0.012, 0.012, 0.012), Vector3(0, y - 0.013, -0.03))
	_box(n, metal, Vector3(0.0025, 0.012, 0.004), Vector3(0, y - 0.006, front_z))      # front post, top on the sight line
	var hood := TorusMesh.new()
	hood.inner_radius = 0.011
	hood.outer_radius = 0.0135
	hood.rings = 16
	hood.ring_segments = 6
	var h := MeshInstance3D.new()
	h.mesh = hood
	h.material_override = metal
	h.rotation.x = PI / 2
	h.position = Vector3(0, y - 0.001, front_z)
	n.add_child(h)
	_box(n, metal, Vector3(0.01, 0.014, 0.012), Vector3(0, y - 0.019, front_z))
	return n


static func _cut_sight(model: Node3D, box: AABB) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == "Mag" or m.get_parent().name == "Mag":
			continue
		var src := m.mesh
		var out := ArrayMesh.new()
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
			var keep := PackedInt32Array()
			for t in range(0, idx.size(), 3):
				var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
				if not box.has_point(c):
					keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
			arr[Mesh.ARRAY_INDEX] = keep
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(si))
		m.mesh = out


static func _custom(id: String) -> Node3D:
	for ext in ["glb", "gltf"]:
		var path := "res://assets/weapons/%s.%s" % [id, ext]
		if not ResourceLoader.exists(path):
			continue
		var root := Node3D.new()
		root.name = id
		var model := _gltf(path)
		root.add_child(model)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i)
				if mat and String(mat.resource_name).begins_with("gun_"):
					m.set_surface_override_material(i, _gun_mat(String(mat.resource_name).get_slice(".", 0)))
		if SIGHT_CUT.has(id):
			_cut_sight(model, SIGHT_CUT[id][0])
			root.set_meta("sight_drop", SIGHT_CUT[id][1])
			root.add_child(_irons(-float(SIGHT_CUT[id][1]), -0.36))
		if FRONT_SIGHT.has(id):
			root.set_meta("front_sight", FRONT_SIGHT[id])
		if SIGHT_CUT.has(id):
			root.set_meta("front_sight", Vector3(0, -float(SIGHT_CUT[id][1]), -0.36))
		var muzzle: Node3D = model.find_child("Muzzle", true, false)
		if muzzle == null:
			muzzle = Node3D.new()
			muzzle.position = Vector3(0, -0.03, -0.6)
			root.add_child(muzzle)
		var eject: Node3D = model.find_child("Eject", true, false)
		if eject == null:
			eject = Node3D.new()
			eject.position = Vector3(0.03, -0.02, -0.05)
			root.add_child(eject)
		var mag: Node3D = model.find_child("Mag", true, false)
		var gr: Node3D = model.find_child("GripR", true, false)
		var gl: Node3D = model.find_child("GripL", true, false)
		var ret: Node3D = model.find_child("Reticle", true, false)
		if ret:
			var dot := Sprite3D.new()
			dot.texture = _reticle_tex()
			dot.pixel_size = 0.00012
			dot.shaded = false
			dot.modulate = Color(3.0, 0.25, 0.15)
			dot.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			dot.visible = false
			ret.add_child(dot)
			root.set_meta("reticle", dot)
		root.set_meta("muzzle", muzzle)
		root.set_meta("eject", eject)
		root.set_meta("mag", mag)
		root.set_meta("custom", true)
		root.set_meta("grip_r", gr.position if gr else Vector3(0, -0.08, 0))
		root.set_meta("grip_l", gl.position if gl else Vector3(0, -0.05, -0.3))
		if mag:
			root.set_meta("mag_pos", mag.position)
		return root
	return null


# ============================================================================ attachments
## Adds attachment meshes to a weapon node built by build(). Optics are centred on the sight line
## (y = 0 for converted models), so aiming down sights through them lines up exactly.
static func add_attachments(gun: Node3D, weapon: String, atts: Dictionary) -> void:
	if atts.is_empty():
		return
	_mats()
	var metal := _gun_mat("gun_metal")
	var poly := _gun_mat("gun_polymer")
	var custom := gun.has_meta("custom")
	var pistol: bool = Defs.WEAPONS.get(weapon, {}).get("pistol", false) or weapon == "pistol"
	var muzzle: Node3D = gun.get_meta("muzzle")
	var grip_l: Vector3 = gun.get_meta("grip_l", Vector3(0, -0.04, -0.3))
	var sight_y: float = (0.0 if custom else 0.11) - float(gun.get_meta("sight_drop", 0.0))
	var optic_z := -0.05 if pistol else -0.1
	for slot in atts:
		var id: String = atts[slot]
		var a := Node3D.new()
		a.name = "Att_" + slot
		gun.add_child(a)
		match id:
			"reddot", "holo", "acog", "sniper_scope":
				if gun.find_child("Irons", false, false):
					(gun.find_child("Irons", false, false) as Node3D).visible = false
		match id:
			"reddot":
				# open tube: you look straight through it at a red dot on the lens
				a.position = Vector3(0, sight_y, optic_z)
				_tube(a, 0.017, 0.045, Vector3.ZERO)
				_box(a, metal, Vector3(0.022, 0.012, 0.04), Vector3(0, -0.023, 0))
				_lens(a, 0.0155, Vector3(0, 0, -0.018))
				_dot(a, 0.0009, Vector3(0, 0, -0.017))
			"holo":
				a.position = Vector3(0, sight_y, optic_z)
				_box(a, poly, Vector3(0.042, 0.016, 0.085), Vector3(0, -0.03, 0.01))
				for x in [-0.019, 0.019]:
					_box(a, poly, Vector3(0.006, 0.042, 0.03), Vector3(x, -0.004, -0.02))
				_box(a, poly, Vector3(0.044, 0.006, 0.03), Vector3(0, 0.018, -0.02))
				_lens(a, 0.018, Vector3(0, 0, -0.02))
				var r := Sprite3D.new()
				r.texture = _reticle_tex()
				r.pixel_size = 0.00012
				r.shaded = false
				r.modulate = Color(3.0, 0.25, 0.15)
				r.position = Vector3(0, 0, -0.025)
				a.add_child(r)
			"acog":
				# hollow scope body; the eyepiece shows a magnified picture (rendered by the player's lens camera)
				a.position = Vector3(0, sight_y, optic_z + 0.02)
				_tube(a, 0.019, 0.12, Vector3.ZERO)
				_tube(a, 0.023, 0.03, Vector3(0, 0, -0.07))
				_tube(a, 0.021, 0.02, Vector3(0, 0, 0.065))
				_box(a, metal, Vector3(0.03, 0.018, 0.08), Vector3(0, -0.027, 0))
				_box(a, metal, Vector3(0.012, 0.012, 0.03), Vector3(0, 0.024, -0.02))
				var eye := Node3D.new()
				eye.name = "PipLens"
				eye.position = Vector3(0, 0, 0.074)
				a.add_child(eye)
				gun.set_meta("pip_lens", eye)
				gun.set_meta("pip_r", 0.0195)
			"sniper_scope":
				a.position = Vector3(0, sight_y, optic_z + 0.03)
				_tube(a, 0.015, 0.26, Vector3.ZERO)
				_tube(a, 0.025, 0.07, Vector3(0, 0, -0.15))
				_tube(a, 0.02, 0.05, Vector3(0, 0, 0.14))
				_box(a, metal, Vector3(0.02, 0.022, 0.02), Vector3(0, 0.02, 0))
				_box(a, metal, Vector3(0.022, 0.02, 0.02), Vector3(0.02, 0, 0))
				for z in [-0.06, 0.07]:
					_box(a, metal, Vector3(0.026, 0.02, 0.018), Vector3(0, -0.024, z))
				_lens(a, 0.024, Vector3(0, 0, -0.186))
			"suppressor":
				var len := 0.12 if pistol else 0.17
				a.position = muzzle.position + Vector3(0, 0, -len * 0.5)
				_cyl_z(a, metal, 0.017 if pistol else 0.02, len, Vector3.ZERO)
				_cyl_z(a, metal, 0.012, 0.01, Vector3(0, 0, -len * 0.5))
				muzzle.position += Vector3(0, 0, -len)
			"compensator":
				a.position = muzzle.position + Vector3(0, 0, -0.025)
				_cyl_z(a, metal, 0.016, 0.05, Vector3.ZERO)
				for k in 3:
					_box(a, _gun_mat("gun_polymer"), Vector3(0.034, 0.004, 0.006), Vector3(0, 0.0, -0.015 + k * 0.012))
				muzzle.position += Vector3(0, 0, -0.05)
			"foregrip":
				a.position = grip_l + Vector3(0, -0.055, 0)
				var c := MeshInstance3D.new()
				var cm := CapsuleMesh.new()
				cm.radius = 0.017
				cm.height = 0.1
				c.mesh = cm
				c.material_override = poly
				a.add_child(c)
				gun.set_meta("grip_l", grip_l + Vector3(0, -0.07, 0.01))
			"laser":
				var lp: Vector3 = (muzzle.position + Vector3(0.0, -0.035, 0.12)) if pistol else (grip_l + Vector3(0.028, 0.0, -0.04))
				a.position = lp
				_box(a, poly, Vector3(0.024, 0.024, 0.06), Vector3.ZERO)
				_box(a, Mat.emissive(Color(1, 0.05, 0.02), 8.0), Vector3(0.008, 0.008, 0.002), Vector3(0, 0, -0.031))
			"ext_mag":
				var mag: Node3D = gun.get_meta("mag")
				if mag:
					mag.scale.y *= 1.45
					mag.position.y -= 0.03
					gun.set_meta("mag_pos", mag.position)
				else:
					_box(a, metal, Vector3(0.03, 0.07, 0.06), Vector3(0, -0.12, -0.06))
	for n in gun.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _cyl_z(p: Node3D, m: Material, r: float, length: float, pos: Vector3) -> MeshInstance3D:
	var mi := _cyl(p, m, r, length, pos, 20)
	return mi


static var _tube_m: StandardMaterial3D

## Open-ended optic tube (no end caps, both faces drawn) so you can see through it.
static func _tube(p: Node3D, r: float, length: float, pos: Vector3) -> MeshInstance3D:
	if _tube_m == null:
		_tube_m = _gun_mat("gun_metal").duplicate()
		_tube_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = length
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	mi.material_override = _tube_m
	mi.position = pos
	mi.rotation.x = PI / 2
	p.add_child(mi)
	return mi


static func _lens(p: Node3D, r: float, pos: Vector3) -> void:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.55, 0.7, 0.75, 0.08)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.metallic = 0.9
	g.roughness = 0.02
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.002
	mi.mesh = cm
	mi.material_override = g
	mi.rotation.x = PI / 2
	mi.position = pos
	p.add_child(mi)


static func _dot(p: Node3D, r: float, pos: Vector3) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = Mat.emissive(Color(1.0, 0.08, 0.04), 10.0)
	mi.position = pos
	p.add_child(mi)
