class_name GameMap
extends Node3D
## Builds the level: a walled industrial yard with buildings, shipping containers,
## cover, vehicles, and the Armory (the physical shop) on the north side.
## Coordinates: x = east, y = up, z = south. Units are metres.

const HALF := 42.0
const GATE := 7.0
const WT := 1.2
const WH := 5.5
const AZ := -22.0          # armory z
## Direction *towards* the sun, matched to the HDRI sky.
const SUN_DIR := Vector3(0.376, 0.743, -0.553)

const SPAWNS := [Vector3(0, 0, -51), Vector3(0, 0, 51), Vector3(-51, 0, 0), Vector3(51, 0, 0),
	Vector3(2, 0, -48), Vector3(-2, 0, 48), Vector3(-48, 0, 2), Vector3(48, 0, -2)]
const PLAYER_SPAWNS := [Vector3(0, 0, 4), Vector3(2.5, 0, 5), Vector3(-2.5, 0, 5), Vector3(0, 0, 7)]
const STATIONS := [
	{"cat": "weapons", "pos": Vector3(-4.6, 0, -25.1), "label": "WEAPON ARMORY"},
	{"cat": "equipment", "pos": Vector3(0, 0, -25.1), "label": "EQUIPMENT ARMORY"},
	{"cat": "air", "pos": Vector3(4.6, 0, -25.1), "label": "AIR SUPPORT ARMORY"},
]

var boxes: Array = []          # {kind, min:Vector3, max:Vector3, ...}
var nav_region: NavigationRegion3D
var static_root: Node3D
var _merge := {}               # Material -> SurfaceTool
var sun: DirectionalLight3D
var env: Environment


func _box(kind: String, cx: float, cz: float, w: float, d: float, h: float, y0 := 0.0, extra := {}) -> Dictionary:
	var b := {"kind": kind, "min": Vector3(cx - w / 2, y0, cz - d / 2), "max": Vector3(cx + w / 2, y0 + h, cz + d / 2)}
	b.merge(extra)
	boxes.append(b)
	return b


func _layout() -> void:
	var seg := HALF - GATE / 2
	for s in [-1.0, 1.0]:
		_box("wall", -(GATE / 2 + (seg + WT) / 2), s * (HALF + WT / 2), seg + WT, WT, WH)
		_box("wall", (GATE / 2 + (seg + WT) / 2), s * (HALF + WT / 2), seg + WT, WT, WH)
		_box("wall", s * (HALF + WT / 2), -(GATE / 2 + (seg + WT) / 2), WT, seg + WT, WH)
		_box("wall", s * (HALF + WT / 2), (GATE / 2 + (seg + WT) / 2), WT, seg + WT, WH)
		var A := 11.0   # spawn alleys behind each gate
		_box("wall", -(GATE / 2 + 0.6), s * (HALF + WT + A / 2), 1.2, A, WH)
		_box("wall", (GATE / 2 + 0.6), s * (HALF + WT + A / 2), 1.2, A, WH)
		_box("wall", 0, s * (HALF + WT + A + 0.6), GATE + 2.4, 1.2, WH)
		_box("wall", s * (HALF + WT + A / 2), -(GATE / 2 + 0.6), A, 1.2, WH)
		_box("wall", s * (HALF + WT + A / 2), (GATE / 2 + 0.6), A, 1.2, WH)
		_box("wall", s * (HALF + WT + A + 0.6), 0, 1.2, GATE + 2.4, WH)

	# Armory bunker (open to the south)
	_box("bunker", 0, AZ - 4.25, 15, 0.5, 3.4)
	_box("bunker", -7.25, AZ - 1, 0.5, 6, 3.4)
	_box("bunker", 7.25, AZ - 1, 0.5, 6, 3.4)
	_box("roof", 0, AZ - 0.9, 16, 7.6, 0.35, 3.4)
	_box("bunker", -7.25, AZ + 2.4, 0.5, 0.5, 3.4)
	_box("bunker", 7.25, AZ + 2.4, 0.5, 0.5, 3.4)
	for st in STATIONS:
		_box("counter", st.pos.x, st.pos.z, 2.6, 1.0, 1.0)

	# Buildings
	_box("building", -27, -25, 16, 14, 8, 0, {"tint": 0})
	_box("building", 27, -26, 14, 12, 10.5, 0, {"tint": 1})
	_box("building", -28, 26, 14, 16, 7, 0, {"tint": 2})
	_box("building", 26, 27, 18, 12, 9, 0, {"tint": 3})
	_box("building", -24.5, -14.5, 6, 7, 4, 0, {"tint": 1})
	_box("building", 31, 17.5, 7, 7, 4.5, 0, {"tint": 0})

	# Shipping containers
	var C := [[-11, 9, 0, 0, 0.0], [-11, 11.6, 0, 1, 0.0], [-10.5, 10.3, 0, 2, 2.6], [13, -5, 1, 3, 0.0], [15.6, -6, 1, 0, 0.0],
		[9, 17, 0, 2, 0.0], [-19, -4, 1, 1, 0.0], [21, 6, 0, 4, 0.0], [-3, 25, 0, 3, 0.0], [-3, 27.6, 0, 0, 0.0],
		[0, -36, 0, 4, 0.0], [-36, 6, 1, 2, 0.0], [36, -8, 1, 1, 0.0]]
	for c in C:
		var rot: bool = c[2] == 1
		_box("container", c[0], c[1], 2.44 if rot else 6.1, 6.1 if rot else 2.44, 2.6, c[4], {"rot": rot, "c": c[3]})

	# Jersey barriers
	for b in [[-4, 0, 0], [4, 0, 0], [0, 12, 0], [-6, 14, 1], [6, 14, 1], [-14, -10, 0], [14, 8, 1], [18, -16, 0], [-20, 14, 0], [-8, -14, 1],
			[8, -14, 1], [26, -2, 1], [-30, 0, 1], [0, 34, 0], [-12, 30, 1], [14, 30, 1], [-3, -34, 1], [3, -34, 1], [32, 4, 0], [-32, -6, 0]]:
		var rot: bool = b[2] == 1
		_box("barrier", b[0], b[1], 0.65 if rot else 2.4, 2.4 if rot else 0.65, 0.95, 0, {"rot": rot})

	# Sandbag walls
	for s in [[0, -6, 5, 0.9], [-2.9, -4.6, 0.9, 2.2], [2.9, -4.6, 0.9, 2.2], [-16, 20, 4, 0.9], [18, 18, 0.9, 4], [20, -10, 4, 0.9], [-22, 4, 0.9, 4]]:
		_box("sandbag", s[0], s[1], s[2], s[3], 1.0)

	# Crates (wooden military crates, stacked)
	for c in [[-7.2, 9, 1.24, 0.0], [-14.6, 11.6, 1.24, 0.0], [16.5, -1.2, 1.24, 0.0], [12.6, 17, 1.24, 0.0], [5.4, 16.6, 1.24, 0.0],
			[-19, 0, 1.24, 0.0], [24.6, 6, 1.24, 0.0], [-6.8, 25, 1.24, 0.0], [-6.8, 25, 1.24, 0.42], [9, -20, 1.24, 0.0],
			[-10, -21, 1.24, 0.0], [34, 34, 1.24, 0.0], [-35, -36, 1.24, 0.0], [-35, 36, 1.24, 0.0], [36, -37, 1.24, 0.0]]:
		_box("crate", c[0], c[1], c[2], 0.75, 0.42, c[3])

	# Vehicles (covered cars + a military truck)
	for v in [[8, 5, 0], [-16, -18, 1], [22, -20, 0], [-24, 10, 1], [16, 36, 0], [-10, -30, 0]]:
		var rot: bool = v[2] == 1
		_box("car", v[0], v[1], 1.8 if rot else 4.4, 4.4 if rot else 1.8, 1.4, 0, {"rot": rot})
	_box("truck", -1, 18.5, 7.2, 2.6, 2.9, 0)

	# Barrels
	for b in [[-8.4, 10.6], [-8.0, 11.5], [15, -3.2], [10.5, 18.6], [-20.4, -6], [22.8, 4.6], [-4.6, 26.6], [33, 33], [-33, -34]]:
		_box("barrel", b[0], b[1], 0.64, 0.64, 0.93)

	# Street lamps
	for l in [[-12, -12], [12, -12], [-12, 20], [12, 22], [-30, -8], [30, -12], [30, 10], [-32, 16]]:
		_box("lamp", l[0], l[1], 0.3, 0.3, 6.2)


func build(is_server: bool, quality: int) -> void:
	_layout()
	_build_environment(quality)
	static_root = Node3D.new()
	static_root.name = "Static"
	if is_server:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "Nav"
		add_child(nav_region)
		nav_region.add_child(static_root)
	else:
		add_child(static_root)
	_build_ground()
	for b in boxes:
		_build_box(b)
	_flush_merge()
	_build_armory()
	_build_backdrop()
	_scatter_decor()
	if is_server:
		_bake_nav()


# ---------------------------------------------------------------- environment
func _build_environment(quality: int) -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var hdr_path := "res://assets/hdri/sky.hdr"
	if ResourceLoader.exists(hdr_path):
		var pm := PanoramaSkyMaterial.new()
		pm.panorama = load(hdr_path)
		pm.energy_multiplier = 1.0
		sky.sky_material = pm
	else:
		var ps := ProceduralSkyMaterial.new()
		ps.sky_top_color = Color(0.32, 0.44, 0.62)
		ps.sky_horizon_color = Color(0.7, 0.7, 0.68)
		ps.ground_horizon_color = Color(0.5, 0.47, 0.42)
		sky.sky_material = ps
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.92
	env.tonemap_white = 6.0
	# Screen-space effects (scaled by quality: 0 low .. 3 ultra)
	env.ssao_enabled = quality >= 1
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = quality >= 2
	env.ssil_intensity = 0.8
	env.ssr_enabled = quality >= 3
	env.sdfgi_enabled = quality >= 2
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.sdfgi_energy = 0.9
	env.glow_enabled = quality >= 1
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Atmospheric haze
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.64, 0.68)
	env.fog_density = 0.0011
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.15
	env.fog_aerial_perspective = 0.25
	env.volumetric_fog_enabled = quality >= 2
	env.volumetric_fog_density = 0.0025
	env.volumetric_fog_albedo = Color(0.85, 0.82, 0.78)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.3
	# Colour grade: a little cooler and more contrasty, MW-style
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.14
	env.adjustment_saturation = 0.95
	env.adjustment_brightness = 1.0
	we.environment = env
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = false
	we.camera_attributes = ca
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 3.0
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0 if quality >= 2 else 90.0
	sun.light_volumetric_fog_energy = 1.0
	add_child(sun)
	sun.look_at_from_position(SUN_DIR * 100.0, Vector3.ZERO, Vector3.UP)


# ---------------------------------------------------------------- geometry helpers
func _merge_add(mat: Material, mesh: Mesh, xf: Transform3D) -> void:
	if not _merge.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_merge[mat] = st
	(_merge[mat] as SurfaceTool).append_from(mesh, 0, xf)


func _merge_box(mat: Material, size: Vector3, center: Vector3, rot_y := 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_merge_add(mat, bm, Transform3D(Basis(Vector3.UP, rot_y), center))


func _flush_merge() -> void:
	for mat in _merge:
		var st: SurfaceTool = _merge[mat]
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		static_root.add_child(mi)
	_merge.clear()


func _collider(b: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Defs.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = b.max - b.min
	cs.shape = sh
	body.add_child(cs)
	body.position = (b.min + b.max) * 0.5
	body.set_meta("surface", _surface_for(b.kind))
	static_root.add_child(body)


func _surface_for(kind: String) -> String:
	match kind:
		"container", "car", "truck", "lamp", "counter", "barrel":
			return "metal"
		"crate":
			return "wood"
		"sandbag":
			return "dirt"
	return "concrete"


func _prop(name: String, pos: Vector3, rot_y := 0.0, scale := Vector3.ONE) -> Node3D:
	var path := "res://assets/props/%s/%s.gltf" % [name, name]
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	var n: Node3D = ps.instantiate()
	n.position = pos
	n.rotation.y = rot_y
	n.scale = scale
	static_root.add_child(n)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return n


# ---------------------------------------------------------------- build
func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Defs.L_WORLD
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	cs.position.y = -0.5
	body.add_child(cs)
	body.set_meta("surface", "ground")
	static_root.add_child(body)
	# Yard: asphalt; outside: dirt
	var yard := PlaneMesh.new()
	yard.size = Vector2(HALF * 2 + 2, HALF * 2 + 2)
	var ym := MeshInstance3D.new()
	ym.mesh = yard
	ym.material_override = Mat.world("asphalt", Color(0.72, 0.71, 0.69), 0.22)
	ym.position.y = 0.002
	static_root.add_child(ym)
	var outer := PlaneMesh.new()
	outer.size = Vector2(1200, 1200)
	var om := MeshInstance3D.new()
	om.mesh = outer
	om.material_override = Mat.world("dirt", Color(0.95, 0.9, 0.82), 0.18)
	static_root.add_child(om)
	# Painted lines
	var paint := Mat.solid(Color(0.78, 0.68, 0.32), 0.7)
	for z in range(-40, 40, 5):
		_merge_box(paint, Vector3(0.18, 0.01, 2.6), Vector3(0, 0.006, z))
	for x in range(-40, 40, 5):
		if abs(x) > 3:
			_merge_box(paint, Vector3(2.6, 0.01, 0.18), Vector3(x, 0.006, 0))
	# Armory pad
	_merge_box(Mat.world("concrete", Color(0.55, 0.54, 0.52), 0.3), Vector3(18, 0.06, 11), Vector3(0, 0.03, -21))


func _build_box(b: Dictionary) -> void:
	var size: Vector3 = b.max - b.min
	var c: Vector3 = (b.min + b.max) * 0.5
	var kind: String = b.kind
	var add_collision := true
	match kind:
		"wall":
			var m := Mat.world("concrete_wall", Color(0.62, 0.6, 0.57), 0.22)
			_merge_box(m, size, c)
			_merge_box(Mat.world("concrete", Color(0.55, 0.54, 0.52), 0.3), Vector3(size.x + 0.25, 0.25, size.z + 0.25), Vector3(c.x, b.max.y + 0.12, c.z))
			var along_x: bool = size.x > size.z
			var length: float = max(size.x, size.z)
			var t := -length / 2 + 2
			while t < length / 2 - 1:
				var bs := Vector3(0.5, size.y, size.z + 0.5) if along_x else Vector3(size.x + 0.5, size.y, 0.5)
				_merge_box(m, bs, c + (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t)))
				t += 8.0
		"bunker", "roof":
			_merge_box(Mat.world("concrete", Color(0.5, 0.5, 0.48), 0.3), size, c)
		"building":
			var tint: Color = [Color(0.92, 0.88, 0.8), Color(1, 1, 1), Color(0.82, 0.8, 0.76), Color(0.9, 0.85, 0.78)][b.tint]
			var mat := Mat.world("bricks", Color(1, 1, 1), 0.33) if b.tint % 2 == 1 else Mat.world("plaster", tint, 0.25)
			_merge_box(mat, size, c)
			var trim := Mat.world("concrete", Color(0.5, 0.5, 0.48), 0.3)
			_merge_box(trim, Vector3(size.x + 0.3, 0.6, 0.3), Vector3(c.x, b.max.y + 0.3, b.min.z))
			_merge_box(trim, Vector3(size.x + 0.3, 0.6, 0.3), Vector3(c.x, b.max.y + 0.3, b.max.z))
			_merge_box(trim, Vector3(0.3, 0.6, size.z), Vector3(b.min.x, b.max.y + 0.3, c.z))
			_merge_box(trim, Vector3(0.3, 0.6, size.z), Vector3(b.max.x, b.max.y + 0.3, c.z))
			var floors: int = max(1, roundi(size.y / 3.5))
			for f in range(1, floors):
				_merge_box(trim, Vector3(size.x + 0.2, 0.18, size.z + 0.2), Vector3(c.x, b.min.y + f * size.y / floors, c.z))
			_windows(b, floors)
			if size.x > 8:
				_prop("utility_box_01", Vector3(c.x - size.x / 4, b.max.y, c.z), 0, Vector3(2, 1.2, 2))
		"container":
			var cols := [Color(0.55, 0.16, 0.11), Color(0.12, 0.3, 0.5), Color(0.2, 0.36, 0.22), Color(0.72, 0.38, 0.12), Color(0.45, 0.46, 0.47)]
			var cm := Mat.pbr("corrugated", cols[b.c % cols.size()], 0.7, 0.6)
			var rot: bool = b.rot
			_container_mesh(cm, c, rot)
		"counter":
			_merge_box(Mat.pbr("painted_metal", Color(0.3, 0.32, 0.3), 0.6, 0.6), size, c)
			_merge_box(Mat.solid(Color(0.25, 0.26, 0.27), 0.35, 0.9), Vector3(size.x + 0.1, 0.05, size.z + 0.1), Vector3(c.x, b.max.y + 0.025, c.z))
		"barrier":
			var rot: bool = b.rot
			var n := _prop("concrete_road_barrier", Vector3(c.x, 0, c.z), PI / 2 if rot else 0.0, Vector3(1.55, 1.15, 1.05))
			if n == null:
				_merge_box(Mat.world("concrete", Color.WHITE), size, c)
		"sandbag":
			_sandbags(b)
		"crate":
			var n := _prop("wooden_military_crate", Vector3(c.x, b.min.y - 0.02, c.z), randf_range(-0.06, 0.06))
			if n == null:
				_merge_box(Mat.pbr("planks"), size, c)
		"car":
			var rot: bool = b.rot
			var n := _prop("covered_car", Vector3(c.x, 0.3, c.z), (PI / 2 if rot else 0.0) + PI / 2 + randf_range(-0.05, 0.05))
			if n == null:
				_merge_box(Mat.pbr("painted_metal"), size, c)
		"truck":
			_truck(b)
		"barrel":
			var n := _prop("barrel_03", Vector3(c.x, 0, c.z), randf() * TAU)
			if n == null:
				_merge_box(Mat.pbr("rust"), size, c)
		"lamp":
			var n := _prop("street_lamp_01", Vector3(c.x, 0, c.z), randf() * TAU, Vector3.ONE * 1.6)
			if n == null:
				_merge_box(Mat.solid(Color(0.3, 0.3, 0.3), 0.5, 0.8), size, c)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.65)
			l.light_energy = 0.0   # daytime: off. (Set >0 for a night map.)
			l.position = Vector3(c.x, 5.9, c.z)
			static_root.add_child(l)
	if add_collision:
		_collider(b)


func _windows(b: Dictionary, floors: int) -> void:
	var glass := Mat.solid(Color(0.05, 0.07, 0.08), 0.08, 0.6)
	var frame := Mat.solid(Color(0.18, 0.18, 0.18), 0.6, 0.4)
	var size: Vector3 = b.max - b.min
	var fh: float = size.y / floors
	for f in floors:
		var y: float = b.min.y + f * fh + fh * 0.55
		# along x faces
		var nx := int(size.x / 3.2)
		for i in nx:
			var x: float = b.min.x + (i + 0.5) * size.x / nx
			for z in [b.min.z - 0.02, b.max.z + 0.02]:
				_merge_box(frame, Vector3(1.3, 1.6, 0.06), Vector3(x, y, z))
				_merge_box(glass, Vector3(1.15, 1.45, 0.08), Vector3(x, y, z))
				_merge_box(frame, Vector3(1.5, 0.08, 0.2), Vector3(x, y - 0.84, z))
		var nz := int(size.z / 3.2)
		for i in nz:
			var z: float = b.min.z + (i + 0.5) * size.z / nz
			for x in [b.min.x - 0.02, b.max.x + 0.02]:
				_merge_box(frame, Vector3(0.06, 1.6, 1.3), Vector3(x, y, z))
				_merge_box(glass, Vector3(0.08, 1.45, 1.15), Vector3(x, y, z))
				_merge_box(frame, Vector3(0.2, 0.08, 1.5), Vector3(x, y - 0.84, z))


func _container_mesh(m: Material, c: Vector3, rot: bool) -> void:
	var r := PI / 2 if rot else 0.0
	var basis := Basis(Vector3.UP, r)
	# corrugated walls: body + ribs for silhouette
	_merge_box(m, Vector3(6.06, 2.5, 2.36), c, r)
	var ribs := 22
	for i in ribs:
		var x := -2.9 + i * 5.8 / (ribs - 1)
		_merge_box(m, Vector3(0.08, 2.3, 2.44), c + basis * Vector3(x, 0, 0), r)
	var frame := Mat.solid(Color(0.12, 0.12, 0.12), 0.6, 0.7)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_merge_box(frame, Vector3(0.18, 0.18, 2.44), c + basis * Vector3(sx * 2.97, sy * 1.21, 0), r)
		for sz in [-1.0, 1.0]:
			_merge_box(frame, Vector3(0.18, 2.6, 0.18), c + basis * Vector3(sx * 2.97, 0, sz * 1.13), r)
	for sz in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			_merge_box(frame, Vector3(6.1, 0.15, 0.15), c + basis * Vector3(0, sy * 1.22, sz * 1.14), r)
	# door locking bars on one end
	var steel := Mat.solid(Color(0.4, 0.4, 0.4), 0.4, 0.9)
	for k in 4:
		_merge_box(steel, Vector3(0.05, 2.3, 0.05), c + basis * Vector3(3.08, 0, -0.85 + k * 0.57), r)


func _sandbags(b: Dictionary) -> void:
	var m := Mat.pbr("burlap", Color(0.62, 0.55, 0.4), 1.0, 0.0, 2.0)
	var size: Vector3 = b.max - b.min
	var along_x: bool = size.x >= size.z
	var length: float = max(size.x, size.z)
	var depth: float = min(size.x, size.z)
	var c: Vector3 = (b.min + b.max) * 0.5
	var bag := CapsuleMesh.new()
	bag.radius = 0.17
	bag.height = 0.62
	bag.radial_segments = 10
	bag.rings = 4
	for row in 4:
		var y: float = 0.13 + row * 0.24
		var n := int(length / 0.58)
		var off: float = 0.29 if row % 2 == 1 else 0.0
		for i in n:
			var t: float = -length / 2 + 0.29 + i * 0.58 + off
			if t > length / 2 - 0.2:
				continue
			for k in max(1, int(depth / 0.42)):
				var dpos: float = -depth / 2 + 0.21 + k * 0.42
				var p := c + (Vector3(t, 0, dpos) if along_x else Vector3(dpos, 0, t))
				p.y = y
				var basis := Basis(Vector3.FORWARD, PI / 2) if along_x else Basis(Vector3.RIGHT, PI / 2)
				basis = basis.scaled(Vector3(1.0, 1.0, 0.55)) if along_x else basis.scaled(Vector3(0.55, 1.0, 1.0))
				basis = Basis(Vector3.UP, randf_range(-0.08, 0.08)) * basis
				_merge_add(m, bag, Transform3D(basis, p))


func _truck(b: Dictionary) -> void:
	var c: Vector3 = (b.min + b.max) * 0.5
	var olive := Mat.pbr("painted_metal", Color(0.3, 0.33, 0.22), 0.7, 0.4)
	var dark := Mat.solid(Color(0.08, 0.08, 0.08), 0.9)
	var glass := Mat.solid(Color(0.04, 0.06, 0.07), 0.05, 0.8)
	_merge_box(olive, Vector3(2.2, 1.6, 2.4), c + Vector3(-2.4, 0.15, 0))
	_merge_box(glass, Vector3(0.06, 0.7, 2.0), c + Vector3(-3.52, 0.55, 0))
	_merge_box(olive, Vector3(4.8, 0.3, 2.5), c + Vector3(1.1, -0.4, 0))
	_merge_box(olive, Vector3(4.8, 0.9, 0.08), c + Vector3(1.1, 0.15, 1.22))
	_merge_box(olive, Vector3(4.8, 0.9, 0.08), c + Vector3(1.1, 0.15, -1.22))
	_merge_box(Mat.pbr("burlap", Color(0.35, 0.37, 0.25)), Vector3(4.6, 1.8, 2.5), c + Vector3(1.1, 1.1, 0))   # canvas cover
	_merge_box(dark, Vector3(7, 0.3, 1.4), c + Vector3(-0.2, -0.75, 0))
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.48
	wheel.bottom_radius = 0.48
	wheel.height = 0.32
	for w in [[-2.5, -1.1], [-2.5, 1.1], [1.2, -1.1], [1.2, 1.1], [2.5, -1.1], [2.5, 1.1]]:
		_merge_add(dark, wheel, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(c.x + w[0], 0.48, c.z + w[1])))


func _build_armory() -> void:
	for st in STATIONS:
		var p: Vector3 = st.pos
		var col: Color = Defs.CAT_COLORS[st.cat]
		# Lit sign on the back wall
		var sign := Label3D.new()
		sign.text = st.label
		sign.font_size = 96
		sign.outline_size = 0
		sign.modulate = col * 2.5
		sign.pixel_size = 0.0036
		sign.position = p + Vector3(0, 2.55, -0.62)
		sign.shaded = false
		sign.double_sided = false
		static_root.add_child(sign)
		var sub := Label3D.new()
		sub.text = "[ E ]"
		sub.font_size = 48
		sub.modulate = Color(0.9, 0.9, 0.9)
		sub.pixel_size = 0.004
		sub.position = p + Vector3(0, 2.25, -0.62)
		static_root.add_child(sub)
		_merge_box(Mat.solid(Color(0.06, 0.06, 0.07), 0.5), Vector3(2.7, 0.8, 0.05), p + Vector3(0, 2.42, -0.66))
		_merge_box(Mat.emissive(col, 5.0), Vector3(2.6, 0.04, 0.04), p + Vector3(0, 1.0, 0.52))
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.6
		light.omni_range = 6.0
		light.position = p + Vector3(0, 2.3, 0.9)
		static_root.add_child(light)
		# Floor ring to stand on
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.75
		tm.outer_radius = 0.85
		ring.mesh = tm
		ring.scale = Vector3(1, 0.05, 1)
		ring.material_override = Mat.emissive(col, 2.0)
		ring.position = p + Vector3(0, 0.07, 1.6)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		static_root.add_child(ring)
		# Display props on the counters
		match st.cat:
			"weapons":
				var pistol := _prop("service_pistol", p + Vector3(-0.6, 1.06, 0.1), 0.4, Vector3.ONE * 1.3)
				if pistol:
					pistol.rotation.x = PI / 2
				_prop("ammo_box", p + Vector3(0.7, 1.05, 0.0), 0.3, Vector3.ONE * 1.6)
				_merge_box(Mat.solid(Color(0.15, 0.15, 0.16), 0.5, 0.8), Vector3(2.4, 1.3, 0.1), p + Vector3(0, 1.8, -0.62))
			"equipment":
				_prop("old_military_crate", p + Vector3(0.2, 1.05, -0.05), 0.1)
				_prop("metal_jerrycan_green", p + Vector3(-0.9, 1.05, 0.0), 0.5)
			"air":
				_merge_box(Mat.emissive(Color(0.1, 0.35, 0.6), 1.5), Vector3(0.9, 0.6, 0.05), p + Vector3(0, 1.55, -0.55))
				_merge_box(Mat.solid(Color(0.1, 0.1, 0.1), 0.4, 0.6), Vector3(1.0, 0.7, 0.04), p + Vector3(0, 1.55, -0.58))
	# Big ARMORY sign above the bunker
	var big := Label3D.new()
	big.text = "ARMORY"
	big.font_size = 120
	big.modulate = Color(1.0, 0.85, 0.45) * 1.4
	big.pixel_size = 0.006
	big.shaded = false
	big.position = Vector3(0, 4.3, AZ + 2.96)
	static_root.add_child(big)
	_merge_box(Mat.solid(Color(0.08, 0.08, 0.08), 0.5, 0.6), Vector3(6.4, 1.4, 0.12), Vector3(0, 4.3, AZ + 2.88))
	for x in [-4.6, 0.0, 4.6]:
		_merge_box(Mat.emissive(Color(1.0, 0.95, 0.85), 3.0), Vector3(1.4, 0.05, 0.2), Vector3(x, 3.37, AZ - 1.0))
	var fill := OmniLight3D.new()
	fill.light_energy = 1.4
	fill.omni_range = 11.0
	fill.light_color = Color(1.0, 0.93, 0.8)
	fill.position = Vector3(0, 3.0, AZ - 1.0)
	fill.shadow_enabled = true
	static_root.add_child(fill)


func _build_backdrop() -> void:
	# Distant ruined city blocks beyond the walls. Fog does the rest.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var mats := [Mat.world("plaster", Color(0.75, 0.72, 0.68), 0.15), Mat.world("concrete_wall", Color(0.7, 0.7, 0.7), 0.15), Mat.world("bricks", Color(0.8, 0.8, 0.8), 0.2)]
	for i in 80:
		var a := rng.randf() * TAU
		var dist := rng.randf_range(80, 220)
		var p := Vector3(cos(a) * dist, 0, sin(a) * dist)
		if abs(p.x) < HALF + 22 and abs(p.z) < HALF + 22:
			continue
		var s := Vector3(rng.randf_range(8, 24), rng.randf_range(6, 34), rng.randf_range(8, 24))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s
		mi.mesh = bm
		mi.material_override = mats[i % 3]
		mi.position = p + Vector3(0, s.y / 2, 0)
		mi.rotation.y = rng.randf_range(-0.3, 0.3)
		static_root.add_child(mi)


func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Chain-link fences on top of some walls' inner side corners and jerrycans / crates around
	for p in [Vector3(-38, 0, -38), Vector3(38, 0, 38), Vector3(-38, 0, 30), Vector3(30, 0, -38)]:
		_prop("plastic_crate_01", p + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), rng.randf() * TAU)
		_prop("metal_jerrycan_green", p + Vector3(1.2, 0, 0.4), rng.randf() * TAU)
	for p in [Vector3(-6.3, 0, -19.5), Vector3(6.3, 0, -19.6), Vector3(-15.8, 0, 12.8), Vector3(14.6, 0, 7.3)]:
		_prop("ammo_box", p, rng.randf() * TAU, Vector3.ONE * 1.6)
		_prop("wooden_crate_01", p + Vector3(0.6, 0, 0.5), rng.randf() * TAU)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Defs.L_WORLD
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.filter_baking_aabb = AABB(Vector3(-62, -1, -62), Vector3(124, 8, 124))
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


# ---------------------------------------------------------------- queries
func station_near(pos: Vector3, radius := 1.7) -> Dictionary:
	for st in STATIONS:
		var p: Vector3 = st.pos + Vector3(0, 0, 1.6)
		if Vector2(pos.x - p.x, pos.z - p.z).length() < radius:
			return st
	return {}
