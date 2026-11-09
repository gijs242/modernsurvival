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
				# Poly Haven service pistol: barrel along +X, ~24 cm long.
				model.rotation.y = PI / 2
				model.position = Vector3(0, 0.0, 0.03)
				model.scale = Vector3.ONE * 0.95
				g.add_child(model)
				muzzle.position = Vector3(0, 0.05, -0.17)
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
	if mag:
		g.set_meta("mag_pos", mag.position)
	return g


static func _gltf(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate()


## Drop-in custom weapon: res://assets/weapons/<id>.glb|.gltf, with optional child nodes
## named "Muzzle", "Mag", "Eject". Model must point down -Z with the grip at the origin.
static func _custom(id: String) -> Node3D:
	for ext in ["glb", "gltf"]:
		var path := "res://assets/weapons/%s.%s" % [id, ext]
		if ResourceLoader.exists(path):
			var root := Node3D.new()
			root.name = id
			var model := _gltf(path)
			root.add_child(model)
			var muzzle: Node3D = model.find_child("Muzzle", true, false)
			if muzzle == null:
				muzzle = Node3D.new()
				muzzle.position = Vector3(0, 0.05, -0.6)
				root.add_child(muzzle)
			var eject: Node3D = model.find_child("Eject", true, false)
			if eject == null:
				eject = Node3D.new()
				eject.position = Vector3(0.03, 0.06, -0.05)
				root.add_child(eject)
			var mag: Node3D = model.find_child("Mag", true, false)
			root.set_meta("muzzle", muzzle)
			root.set_meta("eject", eject)
			root.set_meta("mag", mag)
			if mag:
				root.set_meta("mag_pos", mag.position)
			return root
	return null
