class_name LiekeblomBuilder
extends RefCounted
## Builds the "De Liekeblom" map (Leek, NL) from res://assets/maps/liekeblom.json, which
## tools/build_liekeblom.py generates from open data (BAG, 3D BAG, OpenStreetMap).
## Exterior: real 3D building shapes. Mall: real footprint, corridors, entrances and shop units,
## glass-roofed main hall with a white space-frame like the real one.

const DATA := "res://assets/maps/liekeblom.json"
const PLAY_MARGIN := 14.0       # metres of street around the mall that are playable
const SIGNS := {"supermarket": "SUPERMARKET", "books": "BOOKSHOP", "photo": "PHOTO", "clothes": "FASHION", "mobile_phone": "PHONES",
	"jewelry": "JEWELLER", "fast_food": "PIZZA", "retail": "SHOP", "vacant": "FOR RENT", "florist": "FLOWERS", "chemist": "PHARMACY",
	"hairdresser": "HAIRDRESSER", "bank": "BANK", "optician": "OPTICIAN", "shoes": "SHOES"}

var m: GameMap
var d: Dictionary
var body: StaticBody3D          # one static body for all map collision
var theta := 0.0


func build(map: GameMap) -> void:
	m = map
	var txt := FileAccess.get_file_as_string(DATA)
	d = JSON.parse_string(txt)
	if d == null:
		push_error("Could not load " + DATA)
		return
	theta = float(d.mall.theta)
	m.set_meta("theta", theta)
	m.set_meta("entrances", d.mall.entrances)
	# playable area: the mall plus a strip of street around it (the rest of the data is scenery)
	var fb := Rect2(Vector2(d.mall.footprint[0][0], d.mall.footprint[0][1]), Vector2.ZERO)
	for p in d.mall.footprint:
		fb = fb.expand(Vector2(p[0], p[1]))
	m.bounds = fb.grow(PLAY_MARGIN)
	body = StaticBody3D.new()
	body.collision_layer = Defs.L_WORLD
	body.collision_mask = 0
	body.set_meta("surface", "concrete")
	m.static_root.add_child(body)
	var t0 := Time.get_ticks_msec()
	var steps := [_ground, _roads_and_areas, _buildings, _mall_shell, _mall_interior, _hall, _roof_access, _boundary, _gameplay_points,
		func(): Dressing.new().run(m, d, body),
		func(): if not Net.is_dedicated(): LeekBackdrop.new().build(m, m.quality)]
	var names := ["ground", "roads", "buildings", "shell", "interior", "hall", "roof", "boundary", "points", "dressing", "town backdrop"]
	for i in steps.size():
		steps[i].call()
		if OS.is_stdout_verbose() or Net.args.has("buildlog"):
			print("[map] %s done at %d ms" % [names[i], Time.get_ticks_msec() - t0])


# ------------------------------------------------------------------ helpers
func _v(p) -> Vector3:
	return Vector3(float(p[0]), 0.0, float(p[1]))


func _box_col(size: Vector3, xf: Transform3D, surface := "concrete") -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.transform = xf
	body.add_child(cs)


func _wall(mat: Material, a: Vector3, b: Vector3, y0: float, y1: float, thick: float, collide := true) -> void:
	var dir := b - a
	var L := dir.length()
	if L < 0.02 or y1 - y0 < 0.02:
		return
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
	var size := Vector3(thick, y1 - y0, L)
	var xf := Transform3D(basis, (a + b) * 0.5 + Vector3(0, (y0 + y1) * 0.5, 0))
	var bm := BoxMesh.new()
	bm.size = size
	m._merge_add(mat, bm, xf)
	if collide:
		_box_col(size, xf)


func _poly_mesh(mat: Material, pts: Array, y: float, flip := false) -> void:
	var p2 := PackedVector2Array()
	for p in pts:
		p2.append(Vector2(p[0], p[1]))
	if p2.size() > 3 and p2[0].distance_to(p2[p2.size() - 1]) < 0.01:
		p2.remove_at(p2.size() - 1)
	var idx := Geometry2D.triangulate_polygon(p2)
	if idx.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3.DOWN if flip else Vector3.UP
	for t in range(0, idx.size(), 3):
		var order := [idx[t], idx[t + 1], idx[t + 2]]
		var a := Vector3(p2[order[0]].x, y, p2[order[0]].y)
		var b := Vector3(p2[order[1]].x, y, p2[order[1]].y)
		var c := Vector3(p2[order[2]].x, y, p2[order[2]].y)
		var nn := (b - a).cross(c - a)
		var want_up := not flip
		# Godot front faces are clockwise seen from the front
		if (nn.y > 0) == want_up:
			order = [order[0], order[2], order[1]]
		for k in order:
			st.set_normal(n)
			st.set_uv(p2[k] * 0.25)
			st.add_vertex(Vector3(p2[k].x, y, p2[k].y))
	st.generate_tangents()
	m._merge_add(mat, st.commit(), Transform3D.IDENTITY)


func _strip(mat: Material, pts: Array, width: float, y: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a := _v(pts[i])
		var b := _v(pts[i + 1])
		var dir := b - a
		if dir.length() < 0.01:
			continue
		var side := Vector3(-dir.z, 0, dir.x).normalized() * width * 0.5
		var q := [a - side, a + side, b + side, b - side]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q[k].x, q[k].z) * 0.25)
			st.add_vertex(q[k] + Vector3(0, y, 0))
		# round joints
		var disc := CylinderMesh.new()
		disc.top_radius = width * 0.5
		disc.bottom_radius = width * 0.5
		disc.height = 0.01
		disc.radial_segments = 12
		m._merge_add(mat, disc, Transform3D(Basis(), b + Vector3(0, y - 0.004, 0)))
	st.generate_tangents()
	m._merge_add(mat, st.commit(), Transform3D.IDENTITY)


# ------------------------------------------------------------------ outdoor
func _ground() -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1200, 1, 1200)
	cs.shape = sh
	cs.position.y = -0.5
	body.add_child(cs)
	# paved ground covers the detailed area only; tools/build_leek_backdrop.py fills in the rest of Leek around it
	var plane := PlaneMesh.new()
	plane.size = Vector2(320, 310)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(-19.9, 0, -0.8)
	mi.material_override = Mat.world("sidewalk", Color(0.95, 0.95, 0.95), 0.5, 1.0, 0.0, 0.0)
	m.static_root.add_child(mi)


func _roads_and_areas() -> void:
	var asphalt := Mat.world("asphalt", Color(0.85, 0.85, 0.85), 0.25, 1.0, 0.0, 0.0)
	var bricks := Mat.world("klinkers", Color(1.1, 1.05, 1.0), 0.6, 1.0, 0.0, 0.0)
	var cycle := Mat.world("asphalt", Color(1.0, 0.45, 0.38), 0.25, 1.0, 0.0, 0.0)
	var grass := Mat.world("grass", Color(1, 1, 1), 0.4, 1.0, 0.0, 0.0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.12, 0.17, 0.16)
	water.metallic = 0.3
	water.roughness = 0.05
	for a in d.areas:
		match a.kind:
			"parking":
				_poly_mesh(asphalt, a.pts, 0.012)
			"grass", "forest":
				_poly_mesh(grass, a.pts, 0.008)
				var gp := PackedVector2Array()
				for q in a.pts:
					gp.append(Vector2(q[0], q[1]))
				m.grass_polys.append(gp)
			"water":
				_poly_mesh(water, a.pts, -0.25)
				# keep people out of the canal: low invisible fence along the bank
				for i in a.pts.size() - 1:
					var p0 := _v(a.pts[i])
					var p1 := _v(a.pts[i + 1])
					var dir := p1 - p0
					if dir.length() < 0.05:
						continue
					_box_col(Vector3(0.2, 1.2, dir.length()), Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (p0 + p1) * 0.5 + Vector3(0, 0.6, 0)))
	var widths := {"tertiary": 7.0, "residential": 5.5, "service": 4.0, "pedestrian": 6.0, "footway": 2.6, "cycleway": 2.4}
	for r in d.roads:
		if not widths.has(r.kind) or r.kind == "corridor":
			continue
		var mat: Material = asphalt
		if r.kind in ["pedestrian", "footway"]:
			mat = bricks
		elif r.kind == "cycleway":
			mat = cycle
		_strip(mat, r.pts, widths[r.kind], 0.02 if mat == asphalt else 0.015)


func _buildings() -> void:
	var wall_mats := [Mat.world("bricks", Color(1, 1, 1), 0.5), Mat.world("bricks", Color(0.82, 0.74, 0.7), 0.5),
		Mat.world("bricks", Color(1.15, 1.05, 0.95), 0.5), Mat.world("plaster", Color(0.95, 0.93, 0.9), 0.35)]
	var roof_mats := [Mat.world("roof_dark", Color(0.9, 0.9, 0.9), 0.5, 1.0, 0.0, 0.0), Mat.world("roof_red", Color(1, 1, 1), 0.5, 1.0, 0.0, 0.0)]
	var flat := Mat.world("gravel", Color(0.8, 0.8, 0.8), 0.4, 1.0, 0.0, 0.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.85, 0.9, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.5
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mall_wall := Mat.world("bricks", Color(0.9, 0.85, 0.8), 0.5)
	var faces := PackedVector3Array()
	for b in d.buildings:
		var h := String(b.id).hash()
		var wm: Material = mall_wall if b.mall else wall_mats[abs(h) % wall_mats.size()]
		_tri_mesh(wm, b.walls, faces)
		_tri_mesh(flat, b.roof_flat, faces)
		_tri_mesh(roof_mats[abs(h >> 3) % 2], b.roof_slanted, faces)
		if b.has("roof_glass"):
			_tri_mesh(glass, b.roof_glass, PackedVector3Array(), false)
		if b.footprint and not b.mall:
			var poly := PackedVector2Array()
			for p in b.footprint:
				poly.append(Vector2(p[0], p[1]))
			m.minimap_polys.append([poly, Color(0.55, 0.55, 0.52, 0.75)])
	_flush_tris()
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	cs.shape = sh
	body.add_child(cs)


var _tri_tools := {}       # Material -> [SurfaceTool, shadows]

func _tri_mesh(mat: Material, arr: Array, faces: PackedVector3Array, shadows := true) -> void:
	if arr.size() < 9:
		return
	if not _tri_tools.has(mat):
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tri_tools[mat] = [t, shadows]
	var st: SurfaceTool = _tri_tools[mat][0]
	for t in range(0, arr.size(), 9):
		var a := Vector3(arr[t], arr[t + 1], arr[t + 2])
		var b := Vector3(arr[t + 3], arr[t + 4], arr[t + 5])
		var c := Vector3(arr[t + 6], arr[t + 7], arr[t + 8])
		# source data is outward-facing counter-clockwise; Godot wants clockwise front faces
		var n := (b - a).cross(c - a).normalized()
		for p in [a, c, b]:
			st.set_normal(n)
			st.add_vertex(p)
		faces.append_array([a, b, c])


func _flush_tris() -> void:
	for mat in _tri_tools:
		var mi := MeshInstance3D.new()
		mi.mesh = (_tri_tools[mat][0] as SurfaceTool).commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _tri_tools[mat][1] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.static_root.add_child(mi)
	_tri_tools.clear()


# ------------------------------------------------------------------ mall
var door_list: Array = []      # [centre, outward normal, width] of every door cut into the mall shell
var _fp2: PackedVector2Array

func _footprint2() -> PackedVector2Array:
	if _fp2.is_empty():
		for p in d.mall.footprint:
			_fp2.append(Vector2(p[0], p[1]))
	return _fp2


func _mall_shell() -> void:
	var outer := Mat.world("bricks", Color(0.9, 0.85, 0.8), 0.5)
	var gf: float = d.ground_floor_h
	for s in d.mall.shell:
		var a := _v(s.a)
		var b := _v(s.b)
		var h: float = s.h
		var L := a.distance_to(b)
		var dir := (b - a) / maxf(L, 0.001)
		var cuts: Array = s.doors.duplicate()
		cuts.sort()
		var t := 0.0
		for c in cuts:
			var d0: float = max(t, float(c) - 1.6)
			var d1: float = min(L, float(c) + 1.6)
			var dc := a + dir * ((d0 + d1) * 0.5)
			var dn := Vector3(-dir.z, 0, dir.x)
			if Geometry2D.is_point_in_polygon(Vector2(dc.x + dn.x, dc.z + dn.z), _footprint2()):
				dn = -dn
			door_list.append([dc, dn, d1 - d0])
			_wall(outer, a + dir * t, a + dir * d0, 0.0, h, 0.35)
			_wall(outer, a + dir * d0, a + dir * d1, 2.7, h, 0.35)        # lintel over the doors
			# glass entrance doors (open)
			_wall(_glass_mat(), a + dir * d0, a + dir * (d0 + 0.6), 0.0, 2.7, 0.08, false)
			_wall(_glass_mat(), a + dir * (d1 - 0.6), a + dir * d1, 0.0, 2.7, 0.08, false)
			t = d1
		_wall(outer, a + dir * t, b, 0.0, h, 0.35)
		if h < gf - 0.05:
			pass
	m.set_meta("doors", door_list)
	var poly := _footprint2()
	m.minimap_polys.append([poly, Color(0.42, 0.42, 0.4, 0.75)])
	m.indoor_polys.append(poly)
	# floor of the whole mall
	_poly_mesh(_floor_mat(), d.mall.footprint, 0.03)


## Shop window glazing as separate panes (~2.5 m, between the mullions), each its own body so it can shatter.
func _glass_panes(a: Vector3, b: Vector3, y0: float, y1: float, thick: float) -> void:
	var L := a.distance_to(b)
	var n := maxi(1, int(L / 2.5))
	var dir := (b - a) / maxf(L, 0.001)
	for k in n:
		var p0 := a + dir * (L * k / n)
		var p1 := a + dir * (L * (k + 1) / n)
		var size := Vector3(thick, y1 - y0, p0.distance_to(p1) - 0.04)
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), (p0 + p1) * 0.5 + Vector3(0, (y0 + y1) * 0.5, 0))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = _glass_mat()
		mi.transform = xf
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.static_root.add_child(mi)
		var gb := StaticBody3D.new()
		gb.collision_layer = Defs.L_WORLD
		gb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		gb.add_child(cs)
		gb.transform = xf
		m.static_root.add_child(gb)
		m.add_glass(mi, gb, xf.origin)


var _gm: StandardMaterial3D
func _glass_mat() -> StandardMaterial3D:
	if _gm == null:
		_gm = StandardMaterial3D.new()
		_gm.albedo_color = Color(0.6, 0.72, 0.75, 0.22)
		_gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gm.roughness = 0.03
		_gm.metallic = 0.6
	return _gm


var _fm: Material
func _floor_mat() -> Material:
	if _fm == null:
		_fm = Mat.world("mall_floor", Color(0.93, 0.93, 0.93), 0.75, 0.22, 0.0, 0.0, false)
	return _fm


func _mall_interior() -> void:
	var plaster := Mat.world("plaster", Color(1.0, 1.0, 0.98), 0.35, 1.0, 0.0, 0.25)
	var dark := Mat.solid(Color(0.14, 0.15, 0.17), 0.45, 0.5)
	var frame := Mat.solid(Color(0.12, 0.2, 0.42), 0.4, 0.6)
	var ceiling := Mat.world("plaster", Color(1.05, 1.05, 1.05), 0.6, 1.0, 0.0, 0.0)
	var white := Mat.solid(Color(0.92, 0.92, 0.9), 0.35, 0.1)
	var shop_by_id := {}
	for s in d.mall.shops:
		shop_by_id[int(s.id)] = s
	var armory_shop := -1
	for s in d.mall.shops:
		if s.kind == "vacant" and s.door != null:
			armory_shop = int(s.id)
			break
	for w in d.mall.walls:
		var a := _v(w.a)
		var b := _v(w.b)
		var h: float = w.h
		m.minimap_lines.append([Vector2(a.x, a.z), Vector2(b.x, b.z), Color(0.75, 0.75, 0.72, 0.9)])
		if w.kind == "partition":
			_wall(plaster, a, b, 0.0, h, 0.15)
			continue
		# shop front: glazing in a dark frame, bulkhead above, one door opening
		var L := a.distance_to(b)
		var dir := (b - a) / maxf(L, 0.001)
		var n := Vector3(w.open_n[0], 0, w.open_n[1])
		var door := float(w.door) if w.has("door") else -100.0
		var segs := [[0.0, L]]
		if door > 0:
			segs = [[0.0, door - 1.3], [door + 1.3, L]]
		_wall(white, a, b, 2.9, h, 0.2)                                   # bulkhead
		if door > 0:
			pass
		for sg in segs:
			var p0: Vector3 = a + dir * max(0.0, sg[0])
			var p1: Vector3 = a + dir * min(L, sg[1])
			if p0.distance_to(p1) < 0.1:
				continue
			_wall(dark, p0, p1, 0.0, 0.35, 0.18)                          # plinth
			_glass_panes(p0, p1, 0.35, 2.9, 0.06)                         # shop window: breakable panes
			# mullions every ~2.5 m
			var seg_len := p0.distance_to(p1)
			var count := int(seg_len / 2.5)
			for k in range(0, count + 1):
				var q := p0 + dir * (seg_len * k / maxi(count, 1))
				_wall(frame, q - dir * 0.04, q + dir * 0.04, 0.35, 2.9, 0.1, false)
		if door > 0:
			var dp := a + dir * door
			_wall(frame, dp - dir * 1.35, dp - dir * 1.25, 0.0, 2.9, 0.14)
			_wall(frame, dp + dir * 1.25, dp + dir * 1.35, 0.0, 2.9, 0.14)
			var shop: Dictionary = shop_by_id.get(int(w.shop), {})
			var text: String = "ARMORY" if int(w.shop) == armory_shop else SIGNS.get(shop.get("kind", "retail"), "SHOP")
			var lbl := Label3D.new()
			lbl.text = text
			lbl.font_size = 110
			lbl.pixel_size = 0.0045
			lbl.shaded = false
			lbl.modulate = Color(1.0, 0.75, 0.3) * 1.8 if text == "ARMORY" else Color(0.95, 0.95, 0.98) * 1.5
			lbl.outline_size = 12
			lbl.outline_modulate = Color(0.05, 0.1, 0.25)
			lbl.global_transform = Transform3D(Basis.looking_at(-n, Vector3.UP), dp + Vector3(0, min(h - 0.45, 3.35), 0) + n * 0.13)
			m.static_root.add_child(lbl)
		# white round columns on the open side, like the real hall
		var cols := int(L / 7.0)
		for k in range(1, cols + 1):
			var cp := a + dir * (L * k / (cols + 1)) + n * 0.55
			if door > 0 and abs(L * k / (cols + 1) - door) < 2.0:
				continue
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.28
			cyl.bottom_radius = 0.28
			cyl.height = h
			cyl.radial_segments = 16
			m._merge_add(white, cyl, Transform3D(Basis(), cp + Vector3(0, h / 2, 0)))
			var ccs := CollisionShape3D.new()
			var csh := CylinderShape3D.new()
			csh.radius = 0.28
			csh.height = h
			ccs.shape = csh
			ccs.position = cp + Vector3(0, h / 2, 0)
			body.add_child(ccs)
	# suspended ceilings over the shops
	for c in d.mall.ceilings:
		_poly_mesh(ceiling, c.pts, float(c.h), true)
	# shop contents, lights and the Armory
	for s in d.mall.shops:
		_shop(s, int(s.id) == armory_shop)


func _shop(s: Dictionary, armory: bool) -> void:
	var c := _v(s.center)
	var kind: String = s.kind
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.96, 0.9)
	light.light_energy = 1.4
	light.omni_range = clamp(sqrt(float(s.area_game)) * 0.75, 5.0, 12.0)
	light.position = c + Vector3(0, 2.7, 0)
	m.static_root.add_child(light)
	m.add_light(light, light.position + Vector3(0, 0.17, 0))
	if s.door == null:
		return
	var door := _v(s.door)
	var inward := Vector3(s.inward[0], 0, s.inward[1]).normalized()
	var side := Vector3(-inward.z, 0, inward.x)
	if armory:
		# vacant unit converted into the Armory: three counters facing the door
		var depth: float = (c - door).dot(inward)
		var back: Vector3 = door + inward * clampf(depth * 1.35, 3.5, 7.0)
		var i := 0
		for cat in ["weapons", "gunsmith", "equipment", "air"]:
			var pos := back + side * (float(i) - 1.5) * 3.2
			m.stations.append({"cat": cat, "pos": pos, "facing": -inward, "label": Defs.CAT_NAMES[cat]})
			i += 1
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.96, 0.9)
		fill.light_energy = 1.6
		fill.omni_range = 11.0
		fill.position = back - inward * 2.5 + Vector3(0, 2.9, 0)
		m.static_root.add_child(fill)
		m.add_light(fill, fill.position + Vector3(0, 0.12, 0))
		return
	var shelf_mat := Mat.solid(Color(0.85, 0.85, 0.83), 0.6, 0.2)
	var area: float = s.area_game
	if kind == "supermarket":
		# aisles of shelving and checkout lanes near the entrance
		for row in range(-5, 6):
			var p := door + inward * 12.0 + side * (row * 3.2)
			_shelf(shelf_mat, p, inward, 9.0)
		for k in range(-2, 3):
			var p := door + inward * 3.5 + side * (k * 2.6 + 1.3)
			_box(Mat.solid(Color(0.25, 0.25, 0.27), 0.4, 0.3), Vector3(0.8, 0.9, 2.2), p, inward, true)
		var l2 := OmniLight3D.new()
		l2.light_energy = 1.4
		l2.omni_range = 12.0
		l2.position = door + inward * 14.0 + Vector3(0, 2.7, 0)
		m.static_root.add_child(l2)
		m.add_light(l2, l2.position + Vector3(0, 0.17, 0))
		return
	if area > 60:
		var rows := int(clamp(area / 70.0, 1, 4))
		for r in rows:
			var p := door + inward * (4.0 + r * 3.0) + side * 2.0
			_shelf(shelf_mat, p, side, 3.5)
		_box(Mat.solid(Color(0.3, 0.22, 0.16), 0.5), Vector3(2.2, 1.0, 0.7), door + inward * 2.2 - side * 2.6, inward, true)   # till


func _shelf(mat: Material, center: Vector3, along: Vector3, length: float) -> void:
	_box(mat, Vector3(0.9, 1.8, length), center, along, true)
	var colors := [Color(0.8, 0.2, 0.15), Color(0.2, 0.45, 0.8), Color(0.95, 0.8, 0.2), Color(0.25, 0.6, 0.3), Color(0.9, 0.9, 0.9)]
	var basis := Basis.looking_at(along.normalized(), Vector3.UP)
	for lvl in 3:
		for k in int(length / 0.9):
			var off := -length / 2 + 0.45 + k * 0.9
			var bm := BoxMesh.new()
			bm.size = Vector3(0.95, 0.28, 0.8)
			var col: Color = colors[(k * 7 + lvl * 3 + int(center.x * 10)) % colors.size()]
			m._merge_add(Mat.solid(col, 0.7), bm, Transform3D(basis, center + basis * Vector3(0, 0.4 + lvl * 0.5, -off)))


func _box(mat: Material, size: Vector3, pos: Vector3, along: Vector3, collide: bool) -> void:
	var basis := Basis.looking_at(along.normalized(), Vector3.UP)
	var xf := Transform3D(basis, pos + Vector3(0, size.y / 2, 0))
	var bm := BoxMesh.new()
	bm.size = size
	m._merge_add(mat, bm, xf)
	if collide:
		_box_col(size, xf)


# ------------------------------------------------------------------ main hall: space frame, café, flower stall
func _hall() -> void:
	var white := Mat.solid(Color(0.95, 0.95, 0.94), 0.35, 0.3)
	var beige := Mat.solid(Color(0.86, 0.74, 0.58), 0.85)
	var rot := Basis(Vector3.UP, -theta)     # u along the building's main axis
	var u_axis := rot * Vector3.RIGHT
	var v_axis := rot * Vector3.BACK
	var hall_pts: Array = []
	var roof_min := 99.0
	for o in d.mall.open:
		if not o.hall:
			continue
		roof_min = min(roof_min, float(o.roof))
		for p in o.pts:
			hall_pts.append(_v(p))
	if hall_pts.is_empty():
		return
	var umin := 1e9
	var umax := -1e9
	var vmin := 1e9
	var vmax := -1e9
	for p in hall_pts:
		umin = min(umin, p.dot(u_axis))
		umax = max(umax, p.dot(u_axis))
		vmin = min(vmin, p.dot(v_axis))
		vmax = max(vmax, p.dot(v_axis))
	var y: float = clamp(roof_min - 0.5, 4.0, 9.0)
	var step := 3.6
	var tube := CylinderMesh.new()
	tube.top_radius = 0.045
	tube.bottom_radius = 0.045
	tube.height = 1.0
	tube.radial_segments = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tube
	var xforms: Array[Transform3D] = []
	var put := func(a: Vector3, b: Vector3) -> void:
		var dv := b - a
		var len := dv.length()
		var up := dv / len
		var x := up.cross(Vector3.FORWARD if abs(up.z) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(up)
		xforms.append(Transform3D(Basis(x, up * len, z), (a + b) * 0.5))
	var nu := int((umax - umin) / step)
	var nv := int((vmax - vmin) / step)
	for i in nu + 1:
		for j in nv + 1:
			var p := u_axis * (umin + i * step) + v_axis * (vmin + j * step) + Vector3(0, y, 0)
			var top := p + Vector3(0, 0.9, 0)
			if i < nu:
				put.call(p, p + u_axis * step)
			if j < nv:
				put.call(p, p + v_axis * step)
			if i < nu and j < nv:
				var c := p + (u_axis + v_axis) * step * 0.5 + Vector3(0, 0.9, 0)
				for q in [p, p + u_axis * step, p + v_axis * step, p + (u_axis + v_axis) * step]:
					put.call(q, c)
				# beige diamond ceiling panels on a checker, glass in between (daylight comes through)
				if (i + j) % 3 != 0:
					var panel := BoxMesh.new()
					panel.size = Vector3(step * 0.68, 0.03, step * 0.68)
					m._merge_add(beige, panel, Transform3D(rot * Basis(Vector3.UP, PI / 4), c + Vector3(0, 0.08, 0)))
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = white
	m.static_root.add_child(mmi)
	# hanging spotlights
	for k in 4:
		var l := OmniLight3D.new()
		l.light_energy = 1.2
		l.omni_range = 14.0
		l.light_color = Color(1.0, 0.95, 0.88)
		l.position = _v(d.mall.hall_center) + u_axis * ((k % 2) * 10.0 - 5.0) + v_axis * ((k / 2) * 10.0 - 5.0) + Vector3(0, y - 0.6, 0)
		m.static_root.add_child(l)
		m.add_light(l, l.position + Vector3(0, 0.2, 0))
	# café terrace with a black railing and orange chairs, next to a flower stall (as in the real hall)
	var hc := _v(d.mall.hall_center)
	var black := Mat.solid(Color(0.05, 0.05, 0.05), 0.4, 0.6)
	var orange := Mat.solid(Color(0.85, 0.42, 0.12), 0.6)
	var wood := Mat.pbr("planks", Color(0.8, 0.65, 0.5))
	var cafe := hc - u_axis * 4.0
	var hw := 4.0
	var hd := 2.8
	var corners := [cafe - u_axis * hw - v_axis * hd, cafe + u_axis * hw - v_axis * hd, cafe + u_axis * hw + v_axis * hd, cafe - u_axis * hw + v_axis * hd]
	for k in 4:
		var a0: Vector3 = corners[k]
		var b0: Vector3 = corners[(k + 1) % 4]
		var runs := [[a0, b0]]
		if k == 2:
			var mid := (a0 + b0) * 0.5
			runs = [[a0, mid + (a0 - mid).normalized() * 0.8], [mid + (b0 - mid).normalized() * 0.8, b0]]
		for rn in runs:
			var r0: Vector3 = rn[0]
			var r1: Vector3 = rn[1]
			_wall(black, r0, r1, 0.92, 0.97, 0.05, false)                 # top rail
			_wall(black, r0, r1, 0.12, 0.16, 0.04, false)                 # bottom rail
			var dist := r0.distance_to(r1)
			for q in int(dist / 0.12) + 1:                                 # balusters
				var pp := r0.lerp(r1, q * 0.12 / max(dist, 0.01))
				var bar := BoxMesh.new()
				bar.size = Vector3(0.02, 0.8, 0.02)
				m._merge_add(black, bar, Transform3D(Basis(), pp + Vector3(0, 0.55, 0)))
			_box_col(Vector3(0.08, 1.0, dist), Transform3D(Basis.looking_at((r1 - r0).normalized(), Vector3.UP), (r0 + r1) * 0.5 + Vector3(0, 0.5, 0)))
	for i in 3:
		for j in 2:
			var tp := cafe + u_axis * (i * 2.6 - 2.6) + v_axis * (j * 2.4 - 1.2)
			_box(wood, Vector3(0.8, 0.75, 0.8), tp, v_axis, true)
			for s2 in [-1.0, 1.0]:
				_box(orange, Vector3(0.45, 0.85, 0.45), tp + u_axis * 0.7 * s2, v_axis, false)
	# flower stall
	var stall := hc + u_axis * 4.5
	var green := Mat.solid(Color(0.2, 0.45, 0.18), 0.8)
	var petals := [Color(0.95, 0.2, 0.35), Color(1.0, 0.85, 0.2), Color(0.85, 0.4, 0.9), Color(1, 1, 1), Color(1.0, 0.5, 0.2)]
	for i in 3:
		for j in 2:
			var tp := stall + u_axis * (i * 1.8 - 1.8) + v_axis * (j * 1.6 - 0.8)
			_box(Mat.solid(Color(0.25, 0.25, 0.25), 0.5), Vector3(1.4, 0.8, 1.2), tp, v_axis, true)
			for f in 5:
				var sp := SphereMesh.new()
				sp.radius = 0.18
				sp.height = 0.32
				var fp := tp + u_axis * (f * 0.28 - 0.56) + v_axis * (0.25 if f % 2 else -0.25) + Vector3(0, 0.95, 0)
				m._merge_add(green, sp, Transform3D(Basis(), fp))
				var bl := SphereMesh.new()
				bl.radius = 0.1
				bl.height = 0.16
				m._merge_add(Mat.solid(petals[(i + j * 3 + f) % petals.size()], 0.6), bl, Transform3D(Basis(), fp + Vector3(0, 0.17, 0)))
	# benches from OpenStreetMap
	for p in d.mall.pois:
		if p.kind == "bench":
			_box(wood, Vector3(1.8, 0.45, 0.5), _v(p.pos), u_axis, true)


# ------------------------------------------------------------------ roof access
## An exterior steel staircase up to the mall's flat roof (~4 m, from 3D BAG), placed automatically next to the
## biggest flat roof section that reaches an outside wall, with a sandbagged sniper nest up top. The stairs have a
## ramp collider underneath, so players and enemies (navmesh) can both use them.
func _roof_access() -> void:
	var mall: Dictionary = {}
	for b in d.buildings:
		if b.mall:
			mall = b
	if mall.is_empty():
		return
	var fp := PackedVector2Array()
	for p in d.mall.footprint:
		fp.append(Vector2(p[0], p[1]))
	var rf: Array = mall.roof_flat
	var best := {}
	var best_score := -1.0
	for t in range(0, rf.size(), 9):
		var a := Vector3(rf[t], rf[t + 1], rf[t + 2])
		var b := Vector3(rf[t + 3], rf[t + 4], rf[t + 5])
		var c := Vector3(rf[t + 6], rf[t + 7], rf[t + 8])
		var hy := (a.y + b.y + c.y) / 3.0
		if hy < 3.5 or hy > 4.6 or absf(a.y - b.y) > 0.15 or absf(a.y - c.y) > 0.15:
			continue
		var area := (b - a).cross(c - a).length() * 0.5
		if area < 6.0:
			continue
		var cen := (a + b + c) / 3.0
		var c2 := Vector2(cen.x, cen.z)
		for i in fp.size():
			var p0: Vector2 = fp[i]
			var p1: Vector2 = fp[(i + 1) % fp.size()]
			if p0.distance_to(p1) < 10.0:
				continue
			var q := Geometry2D.get_closest_point_to_segment(c2, p0, p1)
			var dist := q.distance_to(c2)
			if dist > 4.0:
				continue
			var near_door := false                         # keep the stairs (≈7 m along the wall) clear of entrances
			for en in d.mall.entrances:
				if Vector2(en[0], en[1]).distance_to(q) < 10.0:
					near_door = true
			if near_door:
				continue
			var score := area - dist * 2.0
			if score > best_score:
				best_score = score
				best = {"h": hy, "c": cen, "p0": p0, "p1": p1, "q": q}
	if best.is_empty():
		return
	var h: float = best.h
	var u2: Vector2 = ((best.p1 as Vector2) - (best.p0 as Vector2)).normalized()
	var n2 := Vector2(-u2.y, u2.x)
	var mid: Vector2 = ((best.p0 as Vector2) + (best.p1 as Vector2)) * 0.5
	if Geometry2D.is_point_in_polygon(mid + n2 * 0.6, fp):
		n2 = -n2                                           # outward
	var u := Vector3(u2.x, 0, u2.y)
	var n := Vector3(n2.x, 0, n2.y)
	var q3 := Vector3(best.q.x, 0, best.q.y)
	var run := h / tan(deg_to_rad(33.0))
	# run along the wall in whichever direction has room
	var room_neg: float = (best.q as Vector2).distance_to(best.p0)
	var dirv := -u if room_neg > run + 1.5 else u
	var top := q3 + n * 1.3                                # top of the flight, 1.3 m off the wall
	var bottom := top + dirv * run
	var steel := Mat.pbr("painted_metal", Color(0.18, 0.2, 0.22), 0.55, 0.6)
	var tread := Mat.pbr("painted_metal", Color(0.3, 0.3, 0.3), 0.7, 0.7)
	# ramp collider (walkable slope) under the visual steps
	var slope_len := sqrt(run * run + h * h)
	var ramp_dir := ((top + Vector3(0, h, 0)) - bottom).normalized()
	var rn := n.cross(ramp_dir).normalized()              # the ramp surface's normal
	if rn.y < 0.0:
		rn = -rn
	_box_col(Vector3(1.8, 0.12, slope_len), Transform3D(Basis.looking_at(-ramp_dir, rn), (bottom + top + Vector3(0, h, 0)) * 0.5 - rn * 0.06))
	var steps_n := ceili(h / 0.2)
	for k in steps_n:
		var f := (k + 0.5) / steps_n
		var pos := bottom.lerp(top, f) + Vector3(0, h * f - 0.02, 0)
		_box(tread, Vector3(1.8, 0.05, run / steps_n + 0.04), pos, dirv, false)
	for sd in [-0.93, 0.93]:                               # stringers + hand rails
		var off: Vector3 = n * sd
		var a3: Vector3 = bottom + off
		var b3: Vector3 = top + off + Vector3(0, h, 0)
		var sm := BoxMesh.new()
		sm.size = Vector3(0.05, 0.22, a3.distance_to(b3))
		m._merge_add(steel, sm, Transform3D(Basis.looking_at((b3 - a3).normalized(), Vector3.UP), (a3 + b3) * 0.5))
		var rm := BoxMesh.new()
		rm.size = Vector3(0.04, 0.04, a3.distance_to(b3))
		m._merge_add(steel, rm, Transform3D(Basis.looking_at((b3 - a3).normalized(), Vector3.UP), (a3 + b3) * 0.5 + Vector3(0, 0.95, 0)))
		for k in 4:
			var pp: Vector3 = a3.lerp(b3, (k + 0.5) / 4.0)
			var post := BoxMesh.new()
			post.size = Vector3(0.04, 0.95, 0.04)
			m._merge_add(steel, post, Transform3D(Basis(), pp + Vector3(0, 0.47, 0)))
	# landing that bridges over the parapet onto the roof
	# continues past the top of the flight (so it doesn't overhang the last steps) and over the wall
	var land := q3 + n * 0.6 - dirv * 1.05 + Vector3(0, h, 0)
	_box(tread, Vector3(2.1, 0.1, 2.9), land - Vector3(0, 0.1, 0), n, true)
	# steel walkway across the roof from the landing to the nest, ending in a platform (a clean walkable route
	# over the roof's ridges and the interior walls poking through it)
	# nest: on the flat roof just inside the edge, past the top of the stairs, looking out over the street
	var nest: Vector3 = best.c
	var on_roof := func(pt: Vector2) -> bool:
		for t in range(0, rf.size(), 9):
			if absf(rf[t + 1] - h) > 0.2 or absf(rf[t + 4] - h) > 0.2 or absf(rf[t + 7] - h) > 0.2:
				continue
			if Geometry2D.point_is_inside_triangle(pt, Vector2(rf[t], rf[t + 2]), Vector2(rf[t + 3], rf[t + 5]), Vector2(rf[t + 6], rf[t + 8])):
				return true
		return false
	var nest_found := false
	for along in [3.5, 4.5, 2.8, 5.5]:
		for inward in [2.6, 3.2, 2.2]:
			var cand: Vector3 = q3 - dirv * along - n * inward
			var ok := true
			for corner in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1), Vector3.ZERO]:
				var cp: Vector3 = cand + u * corner.x * 2.0 + n * corner.z * 2.0
				if not on_roof.call(Vector2(cp.x, cp.z)):
					ok = false
			if ok:
				nest = Vector3(cand.x, h, cand.z)
				nest_found = true
				break
		if nest_found:
			break
	var grate := Mat.pbr("painted_metal", Color(0.26, 0.27, 0.28), 0.6, 0.7)
	var w_from := q3 - n * 0.6 - dirv * 1.05 + Vector3(0, h, 0)
	var w_to := Vector3(nest.x, h, nest.z)
	var wl := Vector2(w_to.x - w_from.x, w_to.z - w_from.z).length()
	if wl > 0.5:
		var wdir := Vector3(w_to.x - w_from.x, 0, w_to.z - w_from.z).normalized()
		_box(grate, Vector3(2.0, 0.12, wl + 1.0), (w_from + w_to) * 0.5 + Vector3(0, -0.02, 0), wdir, true)
	_box(grate, Vector3(4.6, 0.12, 4.6), w_to + Vector3(0, -0.02, 0), n, true)
	nest = w_to + Vector3(0, 0.1, 0)
	# sniper nest: sandbags along the roof edge facing out, an ammo crate
	var bag := Mat.pbr("burlap", Color(0.62, 0.55, 0.4), 0.95)
	var face := n if nest_found else Vector3(w_to.x - w_from.x, 0, w_to.z - w_from.z).normalized()   # the street (or away from the walkway)
	var side := Vector3(-face.z, 0, face.x)
	for k in range(-2, 3):
		for lvl in 2:
			_box(bag, Vector3(0.7, 0.32, 0.45), nest + face * 1.6 + side * (k * 0.68 - (0.5 if nest_found else 0.0)) + Vector3(0, lvl * 0.3 - 0.02, 0), face, lvl == 0)
	_box_col(Vector3(3.4, 0.7, 0.5), Transform3D(Basis.looking_at(face, Vector3.UP), nest + face * 1.6 - side * (0.5 if nest_found else 0.0) + Vector3(0, 0.33, 0)))
	_box(Mat.pbr("planks", Color(0.5, 0.45, 0.32)), Vector3(0.8, 0.45, 0.5), nest - face * 0.8 + side * 1.2, side, true)
	m.set_meta("roof_nest", nest)
	m.set_meta("roof_stairs", bottom)
	m.set_meta("roof_top", top + Vector3(0, h, 0))
	if OS.is_stdout_verbose() or Net.args.has("buildlog"):
		print("[map] roof access: stairs at %s up to %.1f m, nest at %s" % [bottom, h, nest])


# ------------------------------------------------------------------ gameplay
func _boundary() -> void:
	var r := m.bounds
	var corners := [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]
	var concrete := Mat.pbr("concrete", Color(0.78, 0.77, 0.74), 0.9)
	var stripe := Mat.solid(Color(0.85, 0.2, 0.12), 0.7)
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var dir := b - a
		_box_col(Vector3(0.5, 30, dir.length()), Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (a + b) * 0.5 + Vector3(0, 15, 0)))
		# visible edge of the play area: a line of concrete road barriers
		var n := int(dir.length() / 2.1)
		for i in n:
			var c := a.lerp(b, (i + 0.5) / n)
			var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
			var lo := BoxMesh.new()
			lo.size = Vector3(0.62, 0.35, 1.95)
			m._merge_add(concrete, lo, Transform3D(basis, c + Vector3(0, 0.175, 0)))
			var hi := BoxMesh.new()
			hi.size = Vector3(0.28, 0.6, 1.95)
			m._merge_add(concrete, hi, Transform3D(basis, c + Vector3(0, 0.65, 0)))
			if i % 2 == 0:
				var st := BoxMesh.new()
				st.size = Vector3(0.3, 0.12, 1.96)
				m._merge_add(stripe, st, Transform3D(basis, c + Vector3(0, 0.82, 0)))


func _gameplay_points() -> void:
	# enemies come in from the street just outside each mall entrance, and along the sides of the play area
	var hc := _v(d.mall.hall_center)
	var inner := m.bounds.grow(-3.0)
	for dd in m.get_meta("doors", []):
		var ep: Vector3 = dd[0]
		var out: Vector3 = dd[1]
		var side := Vector3(-out.z, 0, out.x)
		for off in [Vector3.ZERO, side * 7.0, -side * 7.0]:
			var sp: Vector3 = ep + out * 8.0 + off
			m.spawns.append(Vector3(clampf(sp.x, inner.position.x, inner.end.x), 0.05, clampf(sp.z, inner.position.y, inner.end.y)))
	var rot := Basis(Vector3.UP, -theta)
	for off in [Vector3(0, 0, 5), Vector3(2.5, 0, 5.5), Vector3(-2.5, 0, 5.5), Vector3(0, 0, 7.5)]:
		m.player_spawns.append(hc + rot * off + Vector3(0, 0.1, 0))
