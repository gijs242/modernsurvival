class_name MallBuilder
extends RefCounted
## Builds the Mall map from res://assets/maps/mall.json (made by tools/build_mall.py from open data:
## BAG, 3D BAG, OpenStreetMap): real footprint, corridors, entrances and shop units, and a glass-roofed main
## hall with a white space frame. The whole map is indoors: each entrance opens onto a walled loading bay
## where the enemies arrive. Shops are stocked per type, and the corridors and hall get cover and clutter.

const DATA := "res://assets/maps/mall.json"
const BAY_DEPTH := 11.0         # loading bay outside each entrance (enemy spawns)
const BAY_H := 6.5
const SIGNS := {"supermarket": "SUPERMARKET", "books": "BOOKSHOP", "photo": "PHOTO", "clothes": "FASHION", "mobile_phone": "PHONES",
	"jewelry": "JEWELLER", "fast_food": "PIZZA", "retail": "HOME & GIFTS", "vacant": "FOR RENT", "florist": "FLOWERS", "chemist": "PHARMACY",
	"hairdresser": "HAIRDRESSER", "bank": "BANK", "optician": "OPTICIAN", "shoes": "SHOES"}
const PALETTE := [Color(0.75, 0.16, 0.13), Color(0.16, 0.36, 0.7), Color(0.92, 0.75, 0.2), Color(0.2, 0.52, 0.28), Color(0.9, 0.9, 0.88),
	Color(0.12, 0.12, 0.14), Color(0.85, 0.45, 0.15), Color(0.55, 0.25, 0.6), Color(0.45, 0.62, 0.78), Color(0.62, 0.5, 0.38)]

var m: GameMap
var d: Dictionary
var body: StaticBody3D          # one static body for all map collision
var theta := 0.0
var dress := Dressing.new()
var rng := RandomNumberGenerator.new()
var segs: Array = []            # [Vector2 a, Vector2 b] every wall, for clearance / line-of-reach tests
var taken: Array = []           # [Vector2 centre, radius] already used floor space
var hall_polys: Array = []      # PackedVector2Array strips of the main hall
var u_axis := Vector3.RIGHT     # the building's main axes
var v_axis := Vector3.BACK


func build(map: GameMap) -> void:
	m = map
	var txt := FileAccess.get_file_as_string(DATA)
	d = JSON.parse_string(txt)
	if d == null:
		push_error("Could not load " + DATA)
		return
	rng.seed = 935
	theta = float(d.mall.theta)
	var rot := Basis(Vector3.UP, -theta)
	u_axis = rot * Vector3.RIGHT
	v_axis = rot * Vector3.BACK
	m.set_meta("theta", theta)
	m.set_meta("entrances", d.mall.entrances)
	var fb := Rect2(Vector2(d.mall.footprint[0][0], d.mall.footprint[0][1]), Vector2.ZERO)
	for p in d.mall.footprint:
		fb = fb.expand(Vector2(p[0], p[1]))
	m.bounds = fb.grow(BAY_DEPTH + 1.5)
	body = StaticBody3D.new()
	body.collision_layer = Defs.L_WORLD
	body.collision_mask = 0
	body.set_meta("surface", "concrete")
	m.static_root.add_child(body)
	dress.setup(m, body)
	for w in d.mall.walls:
		segs.append([Vector2(w.a[0], w.a[1]), Vector2(w.b[0], w.b[1])])
	for s in d.mall.shell:
		segs.append([Vector2(s.a[0], s.a[1]), Vector2(s.b[0], s.b[1])])
	for o in d.mall.open:
		if o.hall:
			var poly := PackedVector2Array()
			for p in o.pts:
				poly.append(Vector2(p[0], p[1]))
			hall_polys.append(poly)
	var t0 := Time.get_ticks_msec()
	var steps := [_ground, _buildings, _mall_shell, _bays, _mall_interior, _hall, _boundary, _gameplay_points, _cover, dress.flush]
	var names := ["ground", "building", "shell", "bays", "interior", "hall", "boundary", "points", "cover", "props"]
	for i in steps.size():
		steps[i].call()
		if OS.is_stdout_verbose() or Net.args.has("buildlog"):
			print("[map] %s done at %d ms" % [names[i], Time.get_ticks_msec() - t0])


# ------------------------------------------------------------------ floor-space queries
func _clear(p: Vector2) -> float:
	var best := 1e9
	for s in segs:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p))
	return best


func _nearest_wall(p: Vector2) -> Vector2:
	var best := 1e9
	var q := p
	for s in segs:
		var c := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
		if c.distance_to(p) < best:
			best = c.distance_to(p)
			q = c
	return q


## True if a straight line from a to b crosses no wall (used to keep shop fittings inside their own shop).
func _reach(a: Vector2, b: Vector2) -> bool:
	for s in segs:
		if Geometry2D.segment_intersects_segment(a, b, s[0], s[1]) != null:
			return false
	return true


func _inside(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, _footprint2())


func _in_hall(p: Vector2) -> bool:
	for poly in hall_polys:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


func _free(p: Vector2, r: float, wall_gap := 0.25) -> bool:
	if not _inside(p) or _clear(p) < r + wall_gap:
		return false
	for t in taken:
		if (t[0] as Vector2).distance_to(p) < r + float(t[1]):
			return false
	return true


func _claim(p: Vector2, r: float) -> void:
	taken.append([p, r])


func _v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


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


# ------------------------------------------------------------------ ground & the mall building itself
func _ground() -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(600, 1, 600)
	cs.shape = sh
	cs.position.y = -0.5
	body.add_child(cs)
	# plain dark ground under everything (only ever glimpsed past the loading-bay walls)
	var plane := PlaneMesh.new()
	plane.size = m.bounds.size + Vector2(20, 20)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(m.bounds.get_center().x, -0.01, m.bounds.get_center().y)
	mi.material_override = Mat.world("asphalt", Color(0.6, 0.6, 0.6), 0.25, 1.0, 0.0, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.static_root.add_child(mi)


## The mall's real 3D shape (3D BAG): outer walls, flat and pitched roofs, the hall's glass roof.
func _buildings() -> void:
	var flat := Mat.world("gravel", Color(0.8, 0.8, 0.8), 0.4, 1.0, 0.0, 0.0)
	var pitched := Mat.world("roof_dark", Color(0.9, 0.9, 0.9), 0.5, 1.0, 0.0, 0.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.85, 0.9, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.5
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mall_wall := Mat.world("bricks", Color(0.9, 0.85, 0.8), 0.5)
	var faces := PackedVector3Array()
	for b in d.buildings:
		if not b.mall:
			continue
		_tri_mesh(mall_wall, b.walls, faces)
		_tri_mesh(flat, b.roof_flat, faces)
		_tri_mesh(pitched, b.roof_slanted, faces)
		if b.has("roof_glass"):
			_tri_mesh(glass, b.roof_glass, PackedVector3Array(), false)
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
		_fm = Mat.world("mall_floor", Color(1.05, 1.03, 1.0), 0.42, 0.3, 0.0, 0.0, false)
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
			cyl.radial_segments = 10
			cyl.rings = 1
			cyl.top_radius = 0.28
			cyl.bottom_radius = 0.28
			cyl.height = h
			cyl.radial_segments = 16
			m._merge_add(white, cyl, Transform3D(Basis(), cp + Vector3(0, h / 2, 0)))
			_claim(_v2(cp), 0.45)
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
	# wooden floors in the shops (the supermarket keeps its tiles)
	if ResourceLoader.exists("res://assets/textures/shop_floor/albedo.jpg"):
		var wood_floor := Mat.world("shop_floor", Color(0.95, 0.92, 0.88), 0.35, 0.8, 0.0, 0.0)
		var sm_door := Vector2.INF
		for s2 in d.mall.shops:
			if s2.kind == "supermarket" and s2.door != null:
				sm_door = Vector2(s2.door[0] + s2.inward[0] * 0.6, s2.door[1] + s2.inward[1] * 0.6)
		for c in d.mall.ceilings:
			var cen := Vector2.ZERO
			for q in c.pts:
				cen += Vector2(q[0], q[1])
			cen /= c.pts.size()
			if sm_door != Vector2.INF and _reach(sm_door, cen):
				continue
			_poly_mesh(wood_floor, c.pts, 0.036)
	# shop contents, lights and the Armory
	for s in d.mall.shops:
		_shop(s, int(s.id) == armory_shop)


func _shop(s: Dictionary, armory: bool) -> void:
	var c := _v(s.center)
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
	# keep the shop door clear on both sides of the glass
	_claim(_v2(door - inward * 1.2), 2.0)
	_claim(_v2(door + inward * 1.4), 1.5)
	if armory:
		# vacant unit converted into the Armory: counters facing the door
		var depth: float = (c - door).dot(inward)
		var back: Vector3 = door + inward * clampf(depth * 1.35, 3.5, 7.0)
		var i := 0
		for cat in ["weapons", "gunsmith", "equipment", "air"]:
			var pos := back + side * (float(i) - 1.5) * 3.2
			m.stations.append({"cat": cat, "pos": pos, "facing": -inward, "label": Defs.CAT_NAMES[cat]})
			_claim(_v2(pos), 2.6)
			i += 1
		_claim(_v2(door + inward * 3.0), 3.0)
		var fill := OmniLight3D.new()
		fill.light_color = Color(1.0, 0.96, 0.9)
		fill.light_energy = 1.6
		fill.omni_range = 11.0
		fill.position = back - inward * 2.5 + Vector3(0, 2.9, 0)
		m.static_root.add_child(fill)
		m.add_light(fill, fill.position + Vector3(0, 0.12, 0))
		# the gun shop fit-out: crates of stock, a generator, ammo
		for k in [-1.0, 1.0]:
			_try_place(back + side * 7.6 * k - inward * 0.5, 0.8, func(p: Vector3): dress.place("wooden_military_crate", p, atan2(side.x, side.z), 1.0, "box"))
			_try_place(back + side * 7.0 * k - inward * 2.4, 0.7, func(p: Vector3): dress.place("old_military_crate", p, rng.randf() * TAU, 1.0, "box"))
		_try_place(back + side * 6.4 - inward * 4.2, 0.8, func(p: Vector3): dress.place("portable_generator", p, rng.randf() * TAU, 1.0, "box"))
		return
	m.set_meta("shop_views", m.get_meta("shop_views", []) + [[door - inward * 2.0, inward]])
	var depth: float = clampf(2.0 * (c - door).dot(inward), 4.0, 45.0)
	var width: float = clampf(float(s.area_game) / depth * 1.15, 5.0, 45.0)
	var f := {"door": door, "n": inward, "t": side, "depth": depth, "width": width}
	if s.kind != "supermarket" and float(s.area_game) > 90.0:
		for k in [0.3, 0.75]:
			var lp: Vector3 = door + inward * depth * k + Vector3(0, 2.75, 0)
			if _reach(_v2(door + inward * 0.6), _v2(lp)):
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.95, 0.86)
				l.light_energy = 1.25
				l.omni_range = clampf(width * 0.6, 6.0, 11.0)
				l.position = lp
				m.static_root.add_child(l)
				m.add_light(l, lp + Vector3(0, 0.17, 0))
	# till by the door
	var till := door + inward * 2.3 - side * 2.8
	if _fits(f, till, 1.2):
		_counter(till, side)
	match String(s.kind):
		"supermarket":
			_supermarket(f)
		"books":
			_mix(f, 2.9, 2.8, [[5, 2.6, func(p: Vector3): _bookcase(p, side, 2.6)], [2, 1.9, func(p: Vector3): _table_goods(p, side, "books")],
				[1, 1.0, func(p: Vector3): _boxes(p)]])
		"clothes":
			_mix(f, 2.6, 2.6, [[5, 2.3, func(p: Vector3): _rack(p, side, 2.2)], [3, 1.9, func(p: Vector3): _table_goods(p, side, "clothes")],
				[2, 0.8, func(p: Vector3): _mannequin(p, -inward)], [1, 1.0, func(p: Vector3): _boxes(p)]])
			_mix(f, 6.0, 6.0, [[1, 3.0, func(p: Vector3): _lounge(p, -inward)]], 1)
		"jewelry":
			_mix(f, 2.7, 2.6, [[6, 1.9, func(p: Vector3): _display_case(p, side)], [2, 0.7, func(p: Vector3): _bust(p, -inward)]])
		"mobile_phone":
			_mix(f, 2.4, 2.4, [[5, 2.0, func(p: Vector3): _phone_table(p, side)], [2, 1.5, func(p: Vector3): _tv_stand(p, -inward)],
				[1, 1.0, func(p: Vector3): _boxes(p)]])
		"photo":
			_mix(f, 2.4, 2.2, [[4, 1.0, func(p: Vector3): _easel(p, -inward)], [3, 1.9, func(p: Vector3): _table_goods(p, side, "photo")],
				[1, 1.5, func(p: Vector3): _tv_stand(p, -inward)]])
		_:
			_mix(f, 2.6, 2.6, [[4, 2.0, func(p: Vector3): _home_shelf(p, side)], [3, 1.9, func(p: Vector3): _table_goods(p, side, "home")],
				[1, 1.0, func(p: Vector3): _boxes(p)], [1, 1.2, func(p: Vector3): _desk(p, side)]])
			_mix(f, 6.0, 6.0, [[1, 3.0, func(p: Vector3): _lounge(p, -inward)]], 1)


## Fill a shop with a grid of fittings, picking one of `items` ([weight, footprint size, builder(p)]) for
## each spot at random, falling back to smaller ones where the bigger one doesn't fit.
func _mix(f: Dictionary, row: float, col: float, items: Array, limit := 999) -> void:
	var n: Vector3 = f.n
	var t: Vector3 = f.t
	var cells: Array = []
	var dist := 2.6
	while dist < float(f.depth) - 0.6:
		var off: float = -float(f.width) * 0.5 + 1.0
		while off < float(f.width) * 0.5 - 0.8:
			if not (absf(off) < 1.3 and dist < 4.0):              # walk-in lane from the door
				cells.append(f.door + n * dist + t * off)
			off += col
		dist += row
	cells.shuffle()
	var total := 0.0
	for it in items:
		total += float(it[0])
	var placed := 0
	for p in cells:
		if placed >= limit:
			break
		var pick := rng.randf() * total
		var order: Array = []
		for it in items:
			pick -= float(it[0])
			if pick <= 0.0 and order.is_empty():
				order.append(it)
		var rest := items.duplicate()
		rest.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		order.append_array(rest)
		var jit: Vector3 = p + t * rng.randf_range(-0.12, 0.12)
		for it in order:
			var size: float = it[1]
			var rad := minf(size * 0.5, minf(row, col) * 0.5 - 0.05)
			if _fits(f, jit, rad) and _clear(_v2(jit)) > size * 0.38 + 0.15:
				(it[2] as Callable).call(jit)
				_claim(_v2(jit), rad)
				placed += 1
				break
	if Net.args.has("buildlog"):
		print("[shop] %d cells, %d placed (depth %.1f width %.1f)" % [cells.size(), placed, f.depth, f.width])


func _desk(p: Vector3, along: Vector3) -> void:
	var name := "metal_office_desk" if rng.randf() < 0.5 else "drawer_cabinet"
	if Dressing.has_prop(name):
		dress.place(name, p, atan2(along.x, along.z), 1.0, "box")
		if name == "metal_office_desk":
			dress.place("side_table_01", p + along * 1.2, rng.randf() * TAU, 1.0)
	else:
		_boxes(p)


## Is p inside this shop (straight line from just inside its door, clear of walls) with room for radius r?
func _fits(f: Dictionary, p: Vector3, r: float) -> bool:
	return _free(_v2(p), r) and _reach(_v2(f.door + f.n * 0.6), _v2(p))


func _try_place(p: Vector3, r: float, fn: Callable) -> bool:
	if not _free(_v2(p), r):
		return false
	fn.call(p)
	_claim(_v2(p), r)
	return true


# ------------------------------------------------------------------ shop fittings
var _mats := {}
func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var mt: Material
	match key:
		"wood":
			mt = Mat.pbr("wood_fine", Color(0.85, 0.7, 0.55), 0.7, 0.0, 1.0) if ResourceLoader.exists("res://assets/textures/wood_fine/albedo.jpg") else Mat.solid(Color(0.55, 0.4, 0.28), 0.7)
		"dark_wood":
			mt = Mat.pbr("wood_fine", Color(0.38, 0.27, 0.2), 0.6, 0.0, 1.0) if ResourceLoader.exists("res://assets/textures/wood_fine/albedo.jpg") else Mat.solid(Color(0.25, 0.17, 0.12), 0.6)
		"white":
			mt = Mat.solid(Color(0.9, 0.9, 0.88), 0.35, 0.0)
		"chrome":
			mt = Mat.solid(Color(0.8, 0.8, 0.82), 0.15, 1.0)
		"black":
			mt = Mat.solid(Color(0.05, 0.05, 0.055), 0.4, 0.2)
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.7, 0.82, 0.85, 0.15)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.03
			g.metallic = 0.4
			mt = g
		"gold":
			mt = Mat.solid(Color(1.0, 0.78, 0.34), 0.25, 1.0)
		"silver":
			mt = Mat.solid(Color(0.92, 0.92, 0.95), 0.2, 1.0)
		"screen":
			mt = Mat.emissive(Color(0.45, 0.65, 1.0), 1.6)
		"denim":
			mt = Mat.pbr("denim", Color(1, 1, 1), 0.9, 0.0, 2.0)
		"leather":
			mt = Mat.pbr("leather", Color(0.36, 0.22, 0.14), 0.55, 0.0, 1.0)
		"steel":
			mt = Mat.pbr("metal_plate", Color(0.75, 0.76, 0.78), 0.5, 0.8, 1.0)
		"fridge_glow":
			mt = Mat.emissive(Color(0.75, 0.9, 1.0), 1.2)
		"soil":
			mt = Mat.solid(Color(0.16, 0.11, 0.07), 0.95)
		"leaf":
			mt = Mat.solid(Color(0.17, 0.38, 0.14), 0.75)
		"leaf2":
			mt = Mat.solid(Color(0.26, 0.48, 0.18), 0.75)
		"concrete":
			mt = Mat.world("concrete", Color(0.85, 0.84, 0.8), 0.5, 1.0, 0.0, 0.0)
		"burlap":
			mt = Mat.pbr("burlap", Color(0.62, 0.55, 0.4), 0.95)
		_:
			if key.begins_with("c"):
				mt = Mat.solid(PALETTE[int(key.substr(1)) % PALETTE.size()], 0.7)
	_mats[key] = mt
	return mt


func _pc() -> Material:
	return _mat("c%d" % (rng.randi() % PALETTE.size()))


## Box with its base centred at `pos`, local z along `along`, rotated `yaw` extra, merged into the static mesh.
func _part(mat: Material, size: Vector3, pos: Vector3, along: Vector3, y0 := 0.0) -> void:
	var basis := Basis.looking_at(along.normalized(), Vector3.UP)
	var bm := BoxMesh.new()
	bm.size = size
	m._merge_add(mat, bm, Transform3D(basis, pos + Vector3(0, y0 + size.y * 0.5, 0)))


func _col(size: Vector3, pos: Vector3, along: Vector3, y0 := 0.0) -> void:
	_box_col(size, Transform3D(Basis.looking_at(along.normalized(), Vector3.UP), pos + Vector3(0, y0 + size.y * 0.5, 0)))


func _counter(p: Vector3, along: Vector3) -> float:
	_part(_mat("dark_wood"), Vector3(0.75, 1.0, 2.2), p, along)
	_part(_mat("white"), Vector3(0.82, 0.04, 2.3), p, along, 1.0)
	_col(Vector3(0.75, 1.05, 2.2), p, along)
	var basis := Basis.looking_at(along, Vector3.UP)
	dress.place("CashRegister_01", p + basis * Vector3(0, 1.04, 0.5), atan2(along.x, along.z), 1.0)
	_claim(_v2(p), 1.3)
	return 2.4


func _bookcase(p: Vector3, along: Vector3, length: float) -> float:
	var basis := Basis.looking_at(along, Vector3.UP)
	_part(_mat("wood"), Vector3(0.5, 2.0, length), p, along)
	_col(Vector3(0.5, 2.0, length), p, along)
	for lvl in 5:
		for sd in [-1.0, 1.0]:
			var z := -length * 0.5 + 0.08
			while z < length * 0.5 - 0.12:
				var w := rng.randf_range(0.12, 0.34)
				var h := rng.randf_range(0.2, 0.3)
				w = minf(w, length * 0.5 - 0.06 - z)
				var bm := BoxMesh.new()
				bm.size = Vector3(0.2, h, w)
				m._merge_add(_pc(), bm, Transform3D(basis, p + basis * Vector3(sd * 0.16, 0.12 + lvl * 0.38 + h * 0.5, z + w * 0.5)))
				z += w + 0.01
	return length


func _rack(p: Vector3, along: Vector3, length: float) -> float:
	var basis := Basis.looking_at(along, Vector3.UP)
	var chrome := _mat("chrome")
	for z in [-length * 0.5, length * 0.5]:
		_part(chrome, Vector3(0.04, 1.5, 0.04), p + basis * Vector3(0, 0, z), along)
		_part(chrome, Vector3(0.55, 0.03, 0.05), p + basis * Vector3(0, 0, z), along)
	_part(chrome, Vector3(0.03, 0.03, length), p, along, 1.48)
	var base: Material = _mat("denim") if rng.randf() < 0.35 else _pc()
	var z := -length * 0.5 + 0.12
	while z < length * 0.5 - 0.1:
		var mat: Material = base if rng.randf() < 0.6 else _pc()
		var h := rng.randf_range(0.6, 0.95)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.48, h, 0.035)
		m._merge_add(mat, bm, Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)), p + basis * Vector3(0, 1.45 - h * 0.5, z)))
		z += rng.randf_range(0.07, 0.11)
	_col(Vector3(0.55, 1.5, length), p, along)
	return length


func _table_goods(p: Vector3, along: Vector3, kind: String) -> float:
	var basis := Basis.looking_at(along, Vector3.UP)
	_part(_mat("wood"), Vector3(0.9, 0.06, 1.7), p, along, 0.74)
	for k in 4:
		var q := basis * Vector3(0.36 * (1 if k % 2 else -1), 0, 0.75 * (1 if k < 2 else -1))
		_part(_mat("dark_wood"), Vector3(0.06, 0.74, 0.06), p + q, along)
	_col(Vector3(0.9, 0.8, 1.7), p, along)
	for i in 3:
		for j in 2:
			var q := p + basis * Vector3(-0.22 + j * 0.44, 0.8, -0.55 + i * 0.55)
			match kind:
				"clothes":                                       # stacks of folded shirts / jeans
					var mat: Material = _mat("denim") if (i + j) % 3 == 0 else _pc()
					for st in rng.randi_range(2, 5):
						_part(mat, Vector3(0.34, 0.045, 0.3), q, along, st * 0.05)
				"books":
					for st in rng.randi_range(1, 4):
						_part(_pc(), Vector3(0.24, 0.04, 0.17), q + Vector3(rng.randf_range(-0.03, 0.03), 0, 0), along, st * 0.042)
				"photo":                                         # cameras and lenses
					_part(_mat("black"), Vector3(0.12, 0.08, 0.06), q, along)
					var cy := CylinderMesh.new()
					cy.radial_segments = 10
					cy.rings = 1
					cy.top_radius = 0.03
					cy.bottom_radius = 0.035
					cy.height = 0.07
					m._merge_add(_mat("black"), cy, Transform3D(basis * Basis(Vector3.RIGHT, PI / 2), q + basis * Vector3(0, 0.04, -0.06)))
				_:                                               # home & gifts: vases, candles, boxes
					if rng.randf() < 0.5:
						var cy := CylinderMesh.new()
						cy.radial_segments = 10
						cy.rings = 1
						cy.top_radius = rng.randf_range(0.04, 0.08)
						cy.bottom_radius = cy.top_radius * 0.8
						cy.height = rng.randf_range(0.12, 0.3)
						m._merge_add(_pc(), cy, Transform3D(Basis(), q + Vector3(0, cy.height * 0.5, 0)))
					else:
						_part(_pc(), Vector3(0.2, rng.randf_range(0.08, 0.2), 0.2), q, along)
	return 1.8


func _mannequin(p: Vector3, face: Vector3) -> float:
	var white := _mat("white")
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 10
	cyl.rings = 1
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.2
	cyl.height = 0.03
	m._merge_add(_mat("chrome"), cyl, Transform3D(Basis(), p + Vector3(0, 0.015, 0)))
	_part(_mat("chrome"), Vector3(0.03, 0.9, 0.03), p, face)
	var torso := CapsuleMesh.new()
	torso.radial_segments = 10
	torso.rings = 2
	torso.radius = 0.17
	torso.height = 0.75
	var basis := Basis.looking_at(face, Vector3.UP)
	var outfit: Material = _mat("denim") if rng.randf() < 0.3 else _pc()
	m._merge_add(outfit, torso, Transform3D(basis.scaled(Vector3(1.0, 1.0, 0.6)), p + Vector3(0, 1.25, 0)))
	var head := SphereMesh.new()
	head.radial_segments = 10
	head.rings = 5
	head.radius = 0.11
	head.height = 0.25
	m._merge_add(white, head, Transform3D(Basis(), p + Vector3(0, 1.75, 0)))
	_box_col(Vector3(0.4, 1.8, 0.3), Transform3D(basis, p + Vector3(0, 0.9, 0)))
	return 0.8


func _bust(p: Vector3, face: Vector3) -> float:
	_part(_mat("dark_wood"), Vector3(0.45, 1.0, 0.45), p, face)
	var neck := CapsuleMesh.new()
	neck.radial_segments = 10
	neck.rings = 2
	neck.radius = 0.08
	neck.height = 0.42
	m._merge_add(_mat("black"), neck, Transform3D(Basis(), p + Vector3(0, 1.2, 0)))
	var tor := TorusMesh.new()
	tor.rings = 12
	tor.ring_segments = 6
	tor.inner_radius = 0.07
	tor.outer_radius = 0.085
	m._merge_add(_mat("gold"), tor, Transform3D(Basis(Vector3.RIGHT, 0.4), p + Vector3(0, 1.18, 0.02)))
	_col(Vector3(0.45, 1.4, 0.45), p, face)
	return 0.7


func _display_case(p: Vector3, along: Vector3) -> float:
	var basis := Basis.looking_at(along, Vector3.UP)
	_part(_mat("dark_wood"), Vector3(0.7, 0.85, 1.8), p, along)
	_part(_mat("black"), Vector3(0.62, 0.02, 1.72), p, along, 0.85)
	_part(_mat("glass"), Vector3(0.7, 0.3, 1.8), p, along, 0.86)
	_part(_mat("chrome"), Vector3(0.72, 0.015, 1.82), p, along, 1.16)
	_col(Vector3(0.7, 1.17, 1.8), p, along)
	for k in 8:
		var q := p + basis * Vector3(rng.randf_range(-0.22, 0.22), 0.89, rng.randf_range(-0.8, 0.8))
		if rng.randf() < 0.5:
			var tor := TorusMesh.new()
			tor.rings = 12
			tor.ring_segments = 6
			tor.inner_radius = 0.012
			tor.outer_radius = 0.02
			m._merge_add(_mat("gold") if k % 2 else _mat("silver"), tor, Transform3D(Basis(), q + Vector3(0, 0.006, 0)))
		else:
			_part(_mat("black"), Vector3(0.09, 0.05, 0.09), q, along)
			var sp := SphereMesh.new()
			sp.radial_segments = 10
			sp.rings = 5
			sp.radius = 0.016
			sp.height = 0.03
			m._merge_add(_mat("silver") if k % 3 else _mat("gold"), sp, Transform3D(Basis(), q + Vector3(0, 0.065, 0)))
	return 1.9


func _phone_table(p: Vector3, along: Vector3) -> float:
	var basis := Basis.looking_at(along, Vector3.UP)
	_part(_mat("white"), Vector3(0.9, 0.9, 1.9), p, along)
	_part(_mat("dark_wood"), Vector3(0.95, 0.04, 1.95), p, along, 0.9)
	_col(Vector3(0.9, 0.95, 1.9), p, along)
	for k in 6:
		for sd in [-1.0, 1.0]:
			var q := p + basis * Vector3(sd * 0.25, 0.94, -0.75 + k * 0.3)
			var tilt := Basis.looking_at(along, Vector3.UP) * Basis(Vector3.FORWARD, 0.0) * Basis(Vector3.RIGHT, -0.25 * sd)
			var ph := BoxMesh.new()
			ph.size = Vector3(0.08, 0.008, 0.16)
			m._merge_add(_mat("black"), ph, Transform3D(tilt, q + Vector3(0, 0.03, 0)))
			var sc := BoxMesh.new()
			sc.size = Vector3(0.07, 0.002, 0.145)
			m._merge_add(_mat("screen"), sc, Transform3D(tilt, q + Vector3(0, 0.036, 0)))
			_part(_mat("chrome"), Vector3(0.03, 0.03, 0.03), q, along)
	return 2.0


func _tv_stand(p: Vector3, face: Vector3) -> float:
	var cab := "painted_wooden_cabinet" if Dressing.has_prop("painted_wooden_cabinet") else ""
	if cab != "":
		var h := dress.size_of(cab).y
		dress.place(cab, p, atan2(face.x, face.z), 1.0, "box")
		dress.place("Television_01", p + Vector3(0, h, 0), atan2(face.x, face.z), 1.0)
	else:
		_part(_mat("dark_wood"), Vector3(0.5, 0.8, 1.4), p, Vector3(-face.z, 0, face.x))
		_col(Vector3(0.5, 0.8, 1.4), p, Vector3(-face.z, 0, face.x))
	return 1.6


func _easel(p: Vector3, face: Vector3) -> float:
	var basis := Basis.looking_at(-face, Vector3.UP)
	var wood := _mat("dark_wood")
	_part(wood, Vector3(0.6, 0.04, 0.5), p, -face)
	for k in 2:
		var w := rng.randf_range(0.5, 0.8)
		var h := rng.randf_range(0.4, 0.6)
		var y := 0.9 + k * 0.62
		var q := p + basis * Vector3(0, 0, 0)
		_part(wood, Vector3(w + 0.08, h + 0.08, 0.04), q, -face, y)
		var pic := BoxMesh.new()
		pic.size = Vector3(w, h, 0.01)
		var col: Color = PALETTE[rng.randi() % PALETTE.size()].lerp(Color(0.4, 0.55, 0.75), rng.randf() * 0.6)
		m._merge_add(Mat.emissive(col, 0.35), pic, Transform3D(basis, q + basis * Vector3(0, 0, 0.026) + Vector3(0, y + (h + 0.08) * 0.5, 0)))
	_part(wood, Vector3(0.05, 2.0, 0.05), p + basis * Vector3(0, 0, -0.06), -face)
	_col(Vector3(0.9, 2.0, 0.5), p, Vector3(-face.z, 0, face.x))
	return 1.0


func _home_shelf(p: Vector3, along: Vector3) -> float:
	var name := "painted_wooden_shelves" if rng.randf() < 0.5 else "Shelf_01"
	if Dressing.has_prop(name):
		dress.place(name, p, atan2(along.x, along.z), 1.0, "box")
		var sz := dress.size_of(name)
		if rng.randf() < 0.4:
			dress.place(["cardboard_box_01", "plastic_crate_03"][rng.randi() % 2], p + Vector3(0, sz.y + 0.01, 0), rng.randf() * TAU, 0.6)
		return maxf(sz.x, sz.z) + 0.3
	_shelf(Mat.solid(Color(0.85, 0.85, 0.83), 0.6, 0.2), p, along, 2.5)
	return 2.5


func _lounge(p: Vector3, face: Vector3) -> float:
	var yaw := atan2(face.x, face.z)
	var side := Vector3(-face.z, 0, face.x)
	dress.place("Sofa_01", p + face * 0.9, yaw + PI, 1.0, "box")
	dress.place("modern_coffee_table_01", p, yaw, 1.0, "box")
	dress.place(["ArmChair_01", "modern_arm_chair_01"][rng.randi() % 2], p + side * 1.3, yaw - PI / 2, 1.0, "box")
	return 3.0


func _boxes(p: Vector3) -> float:
	var n := rng.randi_range(1, 3)
	for k in n:
		dress.place("cardboard_box_01", p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)), rng.randf() * TAU, rng.randf_range(0.8, 1.1), "box" if k == 0 else "")
	return 1.0


# ------------------------------------------------------------------ supermarket
func _supermarket(f: Dictionary) -> void:
	var n: Vector3 = f.n
	var t: Vector3 = f.t
	var door: Vector3 = f.door
	var shelf_mat := Mat.solid(Color(0.85, 0.85, 0.83), 0.6, 0.2)
	# checkout lanes near the entrance
	for k in range(-3, 4):
		var p: Vector3 = door + n * 3.6 + t * (k * 2.8 + 1.4)
		if _fits(f, p, 1.1):
			_part(Mat.solid(Color(0.25, 0.25, 0.27), 0.4, 0.3), Vector3(0.8, 0.9, 2.2), p, n)
			_part(_mat("black"), Vector3(0.6, 0.02, 1.4), p - n * 0.2, n, 0.9)
			_col(Vector3(0.8, 0.95, 2.2), p, n)
			var basis := Basis.looking_at(n, Vector3.UP)
			dress.place("CashRegister_01", p + basis * Vector3(0, 0.9, 0.7), atan2(t.x, t.z), 1.0)
			_claim(_v2(p), 1.2)
	# long aisles of groceries, fridges along the far side, produce stands, pallets and trolleys
	var rows := 0
	var off: float = -f.width * 0.5 + 2.0
	while off < f.width * 0.5 - 2.0:
		var p: Vector3 = door + n * 12.5 + t * off
		var kind := rows % 5
		if kind == 4:
			if _fits(f, p, 1.6):
				_fridge(p, n, 7.0)
				_claim(_v2(p), 1.0)
				_claim(_v2(p + n * 3.0), 1.0)
				_claim(_v2(p - n * 3.0), 1.0)
		else:
			for seg in [-1.0, 1.0]:
				var q: Vector3 = p + n * seg * 2.3
				if _fits(f, q, 1.4):
					_shelf(shelf_mat, q, n, 4.2)
					_claim(_v2(q), 1.6)
		off += 3.3
		rows += 1
	_mix(f, 3.2, 3.2, [[3, 2.2, func(p: Vector3): _produce(p, t)], [3, 1.6, func(p: Vector3): _pallet(p)], [3, 1.1, func(p: Vector3): _trolley(p, rng.randf() * TAU)]], 18)
	var l2 := OmniLight3D.new()
	l2.light_energy = 1.4
	l2.omni_range = 12.0
	l2.position = door + n * 14.0 + Vector3(0, 2.7, 0)
	m.static_root.add_child(l2)
	m.add_light(l2, l2.position + Vector3(0, 0.17, 0))


func _fridge(p: Vector3, along: Vector3, length: float) -> void:
	var basis := Basis.looking_at(along, Vector3.UP)
	_part(_mat("white"), Vector3(0.9, 2.0, length), p, along)
	_col(Vector3(0.9, 2.0, length), p, along)
	for sd in [-1.0, 1.0]:
		_part(_mat("fridge_glow"), Vector3(0.02, 0.05, length - 0.1), p + basis * Vector3(sd * 0.46, 0, 0), along, 1.85)
		for lvl in 4:
			var z := -length * 0.5 + 0.1
			while z < length * 0.5 - 0.25:
				var w := rng.randf_range(0.18, 0.4)
				var bm := BoxMesh.new()
				bm.size = Vector3(0.25, rng.randf_range(0.18, 0.3), w)
				m._merge_add(_pc(), bm, Transform3D(basis, p + basis * Vector3(sd * 0.32, 0.35 + lvl * 0.4 + bm.size.y * 0.5, z + w * 0.5)))
				z += w + 0.03
		_part(_mat("glass"), Vector3(0.02, 1.7, length - 0.05), p + basis * Vector3(sd * 0.47, 0, 0), along, 0.2)


func _produce(p: Vector3, along: Vector3) -> float:
	var basis := Basis.looking_at(along, Vector3.UP)
	_part(_mat("wood"), Vector3(1.2, 0.75, 2.0), p, along)
	_col(Vector3(1.2, 0.8, 2.0), p, along)
	var fruit := [Color(0.85, 0.1, 0.08), Color(0.95, 0.75, 0.1), Color(0.95, 0.5, 0.1), Color(0.35, 0.6, 0.15), Color(0.5, 0.15, 0.35)]
	for k in 4:
		var q := p + basis * Vector3(-0.28 + (k % 2) * 0.56, 0.75, -0.5 + (k / 2) * 1.0)
		_part(_mat("wood"), Vector3(0.5, 0.12, 0.9), q, along)
		var mat := Mat.solid(fruit[rng.randi() % fruit.size()], 0.55)
		for i in 14:
			var sp := SphereMesh.new()
			sp.radial_segments = 10
			sp.rings = 5
			sp.radius = 0.045
			sp.height = 0.09
			sp.radial_segments = 8
			sp.rings = 4
			m._merge_add(mat, sp, Transform3D(Basis(), q + basis * Vector3(rng.randf_range(-0.2, 0.2), 0.16 + rng.randf() * 0.06, rng.randf_range(-0.4, 0.4))))
	return 2.2


func _pallet(p: Vector3) -> float:
	var yaw := rng.randf() * TAU
	var basis := Basis(Vector3.UP, yaw)
	_part(_mat("wood"), Vector3(1.2, 0.14, 1.0), p, basis.z)
	var h := 0.14
	for lvl in rng.randi_range(2, 4):
		for k in 4:
			var q := p + basis * Vector3(-0.3 + (k % 2) * 0.6, 0, -0.25 + (k / 2) * 0.5)
			_part(Mat.solid(Color(0.62, 0.48, 0.32), 0.85), Vector3(0.56, 0.38, 0.46), q, basis.z, h)
		h += 0.4
	_col(Vector3(1.2, h, 1.0), p, basis.z)
	return 1.6


func _trolley(p: Vector3, yaw: float) -> float:
	var basis := Basis(Vector3.UP, yaw)
	var chrome := _mat("chrome")
	var z := basis.z
	for y in [0.45, 0.95]:
		for sd in [-1.0, 1.0]:
			_part(chrome, Vector3(0.015, 0.015, 0.85), p + basis * Vector3(sd * 0.25, 0, 0), z, y)
			_part(chrome, Vector3(0.5, 0.015, 0.015), p + basis * Vector3(0, 0, sd * 0.42), z, y)
	for k in 5:
		_part(chrome, Vector3(0.01, 0.5, 0.01), p + basis * Vector3(-0.25 + k * 0.125, 0, 0.42), z, 0.45)
		_part(chrome, Vector3(0.01, 0.5, 0.01), p + basis * Vector3(-0.25 + k * 0.125, 0, -0.42), z, 0.45)
	_part(Mat.solid(Color(0.8, 0.12, 0.1), 0.5), Vector3(0.52, 0.03, 0.03), p + basis * Vector3(0, 0, 0.5), z, 1.02)
	for sd in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part(_mat("black"), Vector3(0.03, 0.1, 0.08), p + basis * Vector3(sd * 0.22, 0, sz * 0.35), z)
	return 1.1


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
	tube.radial_segments = 10
	tube.rings = 1
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
			if Dressing.has_prop("round_wooden_table_01"):
				dress.place("round_wooden_table_01", tp, rng.randf() * TAU, 1.0, "cyl")
				for s2 in [-1.0, 1.0]:
					dress.place("plastic_monobloc_chair_01", tp + u_axis * 0.75 * s2, atan2(-u_axis.x * s2, -u_axis.z * s2) + rng.randf_range(-0.4, 0.4), 1.0)
			else:
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
				sp.radial_segments = 10
				sp.rings = 5
				sp.radius = 0.18
				sp.height = 0.32
				var fp := tp + u_axis * (f * 0.28 - 0.56) + v_axis * (0.25 if f % 2 else -0.25) + Vector3(0, 0.95, 0)
				m._merge_add(green, sp, Transform3D(Basis(), fp))
				var bl := SphereMesh.new()
				bl.radial_segments = 10
				bl.rings = 5
				bl.radius = 0.1
				bl.height = 0.16
				m._merge_add(Mat.solid(petals[(i + j * 3 + f) % petals.size()], 0.6), bl, Transform3D(Basis(), fp + Vector3(0, 0.17, 0)))
	# benches from OpenStreetMap
	for p in d.mall.pois:
		if p.kind == "bench":
			_box(wood, Vector3(1.8, 0.45, 0.5), _v(p.pos), u_axis, true)


# ------------------------------------------------------------------ loading bays (enemy entry)
var bays: Array = []            # {door, out, side, hw}

## A high-walled, open-topped loading bay outside every entrance: this is where the enemies come in
## (and where the troop helicopter drops its squad). Nothing else of the outside world is built.
func _bays() -> void:
	var wall := Mat.world("concrete_wall", Color(0.82, 0.8, 0.77), 0.3, 1.0, 0.0, 1.4)
	var floor_name := "bay_floor" if ResourceLoader.exists("res://assets/textures/bay_floor/albedo.jpg") else "concrete"
	var floor_mat := Mat.world(floor_name, Color(0.9, 0.9, 0.9), 0.3, 1.0, 0.0, 0.0)
	var coping := Mat.solid(Color(0.35, 0.36, 0.37), 0.6, 0.4)
	var stripe := Mat.solid(Color(0.95, 0.75, 0.1), 0.6)
	for dd in m.get_meta("doors", []):
		var dc: Vector3 = dd[0]
		var out: Vector3 = (dd[1] as Vector3).normalized()
		var side := Vector3(-out.z, 0, out.x)
		# as wide as possible without the side walls running into the building
		var hw := 2.4
		for cand in [5.0, 4.5, 4.0, 3.5, 3.0]:
			var ok := true
			for s in [-1.0, 1.0]:
				for k in 7:
					if _inside(_v2(dc + side * cand * s + out * (0.6 + k * (BAY_DEPTH - 0.6) / 6.0))):
						ok = false
			if ok:
				hw = cand
				break
		var corners: Array = []
		for s in [-1.0, 1.0]:
			# start each side wall where it meets the building (step back inwards until we're in the shell)
			var start: Vector3 = dc + side * hw * s
			var k := 0
			while not _inside(_v2(start)) and k < 30:
				start -= out * 0.1
				k += 1
			var end: Vector3 = dc + side * hw * s + out * BAY_DEPTH
			_wall(wall, start, end, 0.0, BAY_H, 0.4)
			_wall(coping, start, end, BAY_H, BAY_H + 0.12, 0.5, false)
			segs.append([_v2(start), _v2(end)])
			corners.append(end)
		_wall(wall, corners[0], corners[1], 0.0, BAY_H, 0.4)
		_wall(coping, corners[0], corners[1], BAY_H, BAY_H + 0.12, 0.5, false)
		segs.append([_v2(corners[0]), _v2(corners[1])])
		var quad := []
		for q in [dc - side * hw - out * 0.5, dc + side * hw - out * 0.5, dc + side * hw + out * BAY_DEPTH, dc - side * hw + out * BAY_DEPTH]:
			quad.append([q.x, q.z])
		_poly_mesh(floor_mat, quad, 0.02)
		# painted kerb lines on the bay floor
		for s in [-1.0, 1.0]:
			_box(stripe, Vector3(0.12, 0.01, BAY_DEPTH - 1.2), dc + side * (hw - 0.6) * s + out * (BAY_DEPTH * 0.5 + 0.3) + Vector3(0, 0.02, 0), out, false)
		bays.append({"door": dc, "out": out, "side": side, "hw": hw})
		# roller shutters on the back wall, work lights, cover along the side walls
		var back := dc + out * (BAY_DEPTH - 0.25)
		for s in [-1.0, 1.0]:
			if hw >= 3.4:
				dress.place("rollershutter_door", back + side * (hw * 0.5) * s, atan2(-out.x, -out.z), 1.0)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.86, 0.6)
		l.light_energy = 1.3
		l.omni_range = 13.0
		l.position = back - out * 0.6 + Vector3(0, 4.6, 0)
		m.static_root.add_child(l)
		m.add_light(l, l.position + Vector3(0, 0.15, 0))
		var cover_items := ["wooden_crate_02", "plastic_crate_03", "barrel_03", "old_military_crate", "industrial_storage_cart", "metal_tool_chest"]
		for s in [-1.0, 1.0]:
			var p: Vector3 = dc + out * rng.randf_range(4.0, 6.5) + side * (hw - 0.8) * s
			dress.place(cover_items[rng.randi() % cover_items.size()], p, rng.randf() * TAU, 1.0, "box")
			var p2: Vector3 = dc + out * rng.randf_range(7.5, 9.5) + side * (hw - 0.7) * s
			dress.place(["cardboard_box_01", "trashbag", "plastic_crate_02", "cement_bag"][rng.randi() % 4], p2, rng.randf() * TAU, 1.0)
			dress.place("trashbag", p2 + out * 0.7, rng.randf() * TAU, 0.9)
		dress.place("hand_truck", back - out * 0.6 + side * (hw - 0.7), atan2(out.x, out.z), 1.0)
		dress.decal("stain", dc + out * 5.0 + side * rng.randf_range(-1.5, 1.5), 2.6, rng.randf() * TAU)


func _boundary() -> void:
	# invisible safety walls around the whole map (nothing should get past the bays, this just makes sure)
	var r := m.bounds
	var corners := [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var dir := b - a
		_box_col(Vector3(0.5, 30, dir.length()), Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (a + b) * 0.5 + Vector3(0, 15, 0)))


func _gameplay_points() -> void:
	# enemies arrive at the back of each loading bay
	for b in bays:
		var dc: Vector3 = b.door
		var out: Vector3 = b.out
		var side: Vector3 = b.side
		for off in [-1.6, 0.0, 1.6]:
			m.spawns.append(dc + out * (BAY_DEPTH - 2.6) + side * off * minf(1.0, float(b.hw) / 3.0) + Vector3(0, 0.05, 0))
	var hc := _v(d.mall.hall_center)
	var rot := Basis(Vector3.UP, -theta)
	for off in [Vector3(0, 0, 5), Vector3(2.5, 0, 5.5), Vector3(-2.5, 0, 5.5), Vector3(0, 0, 7.5)]:
		m.player_spawns.append(hc + rot * off + Vector3(0, 0.1, 0))
		_claim(_v2(hc + rot * off), 1.6)


# ------------------------------------------------------------------ corridor & hall cover, clutter
## Cover and furniture in the public areas: planters, kiosks, benches, vending machines, lounge seating and
## improvised barricades in the middle of wide spots (always leaving a walkable lane on both sides); bins,
## extinguishers and boxes along the walls; litter and grime on the floor.
func _cover() -> void:
	# keep entrances, the café, the flower stall and the armory approach clear
	for dd in m.get_meta("doors", []):
		_claim(_v2(dd[0] - dd[1] * 1.5), 3.5)
	var hc := _v(d.mall.hall_center)
	_claim(_v2(hc - u_axis * 4.0), 5.2)
	_claim(_v2(hc + u_axis * 4.5), 3.4)
	for st in m.stations:
		_claim(_v2(st.pos + (st.facing as Vector3) * 2.5), 2.0)
	for p in d.mall.pois:
		if p.kind == "bench":
			_claim(Vector2(p.pos[0], p.pos[1]), 1.2)
	# OpenStreetMap fixtures: vending machine, parcel lockers, ATM
	for p in d.mall.pois:
		var v := _v(p.pos)
		var w := _nearest_wall(_v2(v))
		var to_wall := Vector3(w.x - v.x, 0, w.y - v.z)
		if to_wall.length() < 0.01:
			continue
		var face := -to_wall.normalized()
		var at := Vector3(w.x, 0, w.y) + face * 0.5
		match String(p.kind):
			"vending_machine":
				_vending(at, face)
				_claim(_v2(at), 1.0)
			"parcel_locker":
				_lockers(at, face)
				_claim(_v2(at), 1.6)
			"atm":
				_atm(at, face)
				_claim(_v2(at), 0.8)
	# walk the corridors' centre lines
	var centre := []
	for line in d.mall.corridors:
		for i in line.size() - 1:
			var a := Vector2(line[i][0], line[i][1])
			var b := Vector2(line[i + 1][0], line[i + 1][1])
			var L := a.distance_to(b)
			var t := 3.0
			while t < L - 2.0:
				centre.append(a.lerp(b, t / L))
				t += rng.randf_range(4.5, 6.5)
	# and a jittered grid over the hall
	var hall_pts := []
	for poly in hall_polys:
		for q in poly:
			hall_pts.append(q)
	if not hall_pts.is_empty():
		var umin := 1e9
		var umax := -1e9
		var vmin := 1e9
		var vmax := -1e9
		for q in hall_pts:
			var p3 := Vector3(q.x, 0, q.y)
			umin = minf(umin, p3.dot(u_axis))
			umax = maxf(umax, p3.dot(u_axis))
			vmin = minf(vmin, p3.dot(v_axis))
			vmax = maxf(vmax, p3.dot(v_axis))
		var uu := umin + 3.0
		while uu < umax - 2.0:
			var vv := vmin + 3.0
			while vv < vmax - 2.0:
				var p3 := u_axis * (uu + rng.randf_range(-1.2, 1.2)) + v_axis * (vv + rng.randf_range(-1.2, 1.2))
				if _in_hall(_v2(p3)):
					centre.append(_v2(p3))
				vv += 6.5
			uu += 6.5
	centre.shuffle()
	var made := 0
	for c2 in centre:
		var c3 := Vector3(c2.x, 0, c2.y)
		var room := _clear(c2)
		var wq := _nearest_wall(c2)
		var to_wall := Vector3(wq.x - c3.x, 0, wq.y - c3.z).normalized()
		var along := Vector3(-to_wall.z, 0, to_wall.x)          # parallel to the nearest wall
		# free-standing pieces (about a metre wide, laid along the corridor) need a 1.3 m lane on both sides;
		# the bigger ones (kiosks, lounge seating) only go where it's wider, i.e. mostly in the hall
		if room >= 2.65 and rng.randf() < 0.85:
			var wide := room >= 3.3
			var pick := rng.randi() % (7 if wide else 4)
			if _free(c2, 1.5, 1.15):
				match pick:
					0:
						_planter(c3, along)
					1:
						_bench_pair(c3, along)
					2:
						_barricade(c3, along)
					3:
						if rng.randf() < 0.5:
							_vending_pair(c3, along)
						else:
							_planter(c3, along)
					4:
						_kiosk(c3, along)
					5:
						_lounge_public(c3, along)
					6:
						_barricade(c3, along)
				_claim(c2, 1.9)
				made += 1
				continue
		if room >= 1.6:
			# against the wall, out of the way
			var at := Vector3(wq.x, 0, wq.y) - to_wall * 0.6
			if _free(_v2(at), 0.5, 0.0):
				_wall_item(at, -to_wall)
				_claim(_v2(at), 0.9)
				made += 1
	# loose clutter and grime everywhere people panicked through
	for k in 160:
		var c2: Vector2 = centre[rng.randi() % centre.size()] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)) if not centre.is_empty() else Vector2.ZERO
		if not _free(c2, 0.35, 0.1):
			continue
		var c3 := Vector3(c2.x, 0, c2.y)
		match rng.randi() % 9:
			0, 1:
				dress.decal("litter", c3, rng.randf_range(1.0, 2.0), rng.randf() * TAU)
			2:
				dress.decal("stain", c3, rng.randf_range(1.2, 2.6), rng.randf() * TAU)
			3:
				dress.decal("scuff", c3, rng.randf_range(2.0, 3.5), rng.randf() * TAU)
			4:
				dress.place("trashbag", c3, rng.randf() * TAU, rng.randf_range(0.8, 1.1))
			5:
				dress.place("cardboard_box_01", c3, rng.randf() * TAU, rng.randf_range(0.7, 1.0))
			6:
				dress.place("WetFloorSign_01", c3, rng.randf() * TAU, 1.0)
			7:
				dress.place("plastic_monobloc_chair_01", c3, rng.randf() * TAU, 1.0)
			8:
				dress.decal("crack", c3, rng.randf_range(1.2, 2.4), rng.randf() * TAU)
	if OS.is_stdout_verbose() or Net.args.has("buildlog"):
		print("[map] cover clusters: %d" % made)


func _planter(p: Vector3, along: Vector3) -> void:
	var basis := Basis.looking_at(along, Vector3.UP)
	var L := rng.randf_range(2.2, 3.0)
	_part(_mat("concrete"), Vector3(1.0, 0.75, L), p, along)
	_part(_mat("dark_wood"), Vector3(1.08, 0.06, L + 0.08), p, along, 0.75)
	_part(_mat("soil"), Vector3(0.86, 0.05, L - 0.14), p, along, 0.72)
	_col(Vector3(1.08, 0.82, L + 0.08), p, along)
	# shrubs: clusters of leafy blobs, sometimes a small tree
	var n := int(L / 0.45)
	for k in n:
		var q := p + basis * Vector3(rng.randf_range(-0.25, 0.25), 0.8, -L * 0.5 + 0.25 + k * (L - 0.5) / maxf(1, n - 1))
		for j in 3:
			var sp := SphereMesh.new()
			sp.radial_segments = 10
			sp.rings = 5
			sp.radius = rng.randf_range(0.18, 0.3)
			sp.height = sp.radius * 1.6
			sp.radial_segments = 10
			sp.rings = 5
			m._merge_add(_mat("leaf") if (k + j) % 2 else _mat("leaf2"), sp, Transform3D(Basis(), q + Vector3(rng.randf_range(-0.15, 0.15), sp.radius * 0.6 + j * 0.08, rng.randf_range(-0.15, 0.15))))
	if rng.randf() < 0.5:
		var trunk := CylinderMesh.new()
		trunk.radial_segments = 10
		trunk.rings = 1
		trunk.top_radius = 0.04
		trunk.bottom_radius = 0.06
		trunk.height = 1.6
		m._merge_add(_mat("dark_wood"), trunk, Transform3D(Basis(), p + Vector3(0, 1.55, 0)))
		for j in 4:
			var sp := SphereMesh.new()
			sp.radial_segments = 10
			sp.rings = 5
			sp.radius = rng.randf_range(0.45, 0.65)
			sp.height = sp.radius * 1.7
			m._merge_add(_mat("leaf2"), sp, Transform3D(Basis(), p + Vector3(rng.randf_range(-0.35, 0.35), 2.4 + rng.randf_range(-0.2, 0.3), rng.randf_range(-0.35, 0.35))))
	if rng.randf() < 0.5:
		dress.place("metal_trash_can", p + basis * Vector3(0.95, 0, L * 0.5 - 0.3), rng.randf() * TAU, 1.0, "cyl")


func _kiosk(p: Vector3, along: Vector3) -> void:
	var basis := Basis.looking_at(along, Vector3.UP)
	var col: Material = _pc()
	# U-shaped counter (crouch-high cover) around a clerk space, canopy on four posts
	_part(_mat("white"), Vector3(1.6, 1.05, 0.3), p + basis * Vector3(0, 0, -1.1), along)
	_part(_mat("white"), Vector3(1.6, 1.05, 0.3), p + basis * Vector3(0, 0, 1.1), along)
	_part(_mat("white"), Vector3(0.3, 1.05, 2.5), p + basis * Vector3(0.65, 0, 0), along)
	_part(col, Vector3(1.66, 0.06, 2.56), p, along, 1.05)
	_col(Vector3(1.6, 1.1, 0.3), p + basis * Vector3(0, 0, -1.1), along)
	_col(Vector3(1.6, 1.1, 0.3), p + basis * Vector3(0, 0, 1.1), along)
	_col(Vector3(0.3, 1.1, 2.5), p + basis * Vector3(0.65, 0, 0), along)
	for k in 4:
		_part(_mat("chrome"), Vector3(0.05, 2.4, 0.05), p + basis * Vector3(-0.75 + (k % 2) * 1.5, 0, -1.2 + (k / 2) * 2.4), along)
	_part(col, Vector3(1.9, 0.08, 2.8), p, along, 2.4)
	_part(_mat("black"), Vector3(0.05, 0.4, 1.6), p + basis * Vector3(0.9, 0, 0), along, 2.0)
	var lbl := Label3D.new()
	lbl.text = ["COFFEE", "PHONE CASES", "SUNGLASSES", "CANDY", "KEYS CUT", "PERFUME", "TOYS"][rng.randi() % 7]
	lbl.font_size = 64
	lbl.pixel_size = 0.004
	lbl.modulate = Color(1, 1, 1) * 1.4
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0, 0, 0)
	lbl.global_transform = Transform3D(Basis.looking_at(-basis.x, Vector3.UP), p + basis * Vector3(0.93, 0, 0) + Vector3(0, 2.2, 0))
	m.static_root.add_child(lbl)
	for k in 6:
		_part(_pc(), Vector3(0.18, rng.randf_range(0.08, 0.25), 0.18), p + basis * Vector3(rng.randf_range(-0.4, 0.5), 0, rng.randf_range(-1.0, 1.0)), along, 1.11)


func _bench_pair(p: Vector3, along: Vector3) -> void:
	var yaw := atan2(along.x, along.z)
	var side := Vector3(-along.z, 0, along.x)
	dress.place("painted_wooden_bench", p + side * 0.45, yaw + PI / 2, 1.0, "box")
	dress.place("painted_wooden_bench", p - side * 0.45, yaw - PI / 2, 1.0, "box")
	dress.place("metal_trash_can", p + along * 1.4, rng.randf() * TAU, 1.0, "cyl")
	_planter_small(p - along * 1.4)


func _planter_small(p: Vector3) -> void:
	dress.place(["potted_plant_02", "potted_plant_04", "planter_box_03"][rng.randi() % 3], p, rng.randf() * TAU, 1.2, "box")


func _barricade(p: Vector3, along: Vector3) -> void:
	# overturned tables, crates and sandbags thrown together by the defenders
	var basis := Basis.looking_at(along, Vector3.UP)
	var top := Basis.looking_at(along, Vector3.UP) * Basis(Vector3.FORWARD, PI / 2)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.05, 1.7)
	var q := p + basis * Vector3(0.25, 0, -0.6)
	m._merge_add(_mat("wood"), bm, Transform3D(top, q + Vector3(0, 0.45, 0)))
	for k in 2:
		_part(_mat("dark_wood"), Vector3(0.7, 0.06, 0.06), q + basis * Vector3(-0.35, 0.0, -0.7 + k * 1.4), along, 0.35)
	_col(Vector3(0.1, 0.9, 1.7), q, along)
	for k in 4:
		for lvl in 2:
			var sb := p + basis * Vector3(-0.1, 0, 0.6 + k * 0.42 - 0.6)
			_part(_mat("burlap"), Vector3(0.45, 0.28, 0.4), sb + basis * Vector3(0, 0, (lvl % 2) * 0.2), along, lvl * 0.27)
	_col(Vector3(0.5, 0.55, 1.7), p + basis * Vector3(-0.1, 0, 0.6), along)
	dress.place(["wooden_crate_02", "plastic_crate_03", "old_military_crate"][rng.randi() % 3], p + basis * Vector3(0.6, 0, 1.1), rng.randf() * TAU, 1.0, "box")
	dress.place("plastic_monobloc_chair_01", p + basis * Vector3(-0.9, 0, -0.3), rng.randf() * TAU, 1.0)


func _lounge_public(p: Vector3, along: Vector3) -> void:
	var yaw := atan2(along.x, along.z)
	var side := Vector3(-along.z, 0, along.x)
	dress.place("Sofa_01", p + side * 0.9, yaw + PI / 2 + PI, 1.0, "box")
	dress.place("Sofa_01", p - side * 0.9, yaw + PI / 2, 1.0, "box")
	dress.place("modern_coffee_table_01", p, yaw, 1.0, "box")
	dress.place("korean_fire_extinguisher_01", p + along * 1.5, rng.randf() * TAU, 1.0)


func _vending(p: Vector3, face: Vector3) -> void:
	var along := Vector3(-face.z, 0, face.x)
	var basis := Basis.looking_at(face, Vector3.UP)
	var col: Color = [Color(0.75, 0.1, 0.1), Color(0.1, 0.3, 0.7), Color(0.1, 0.1, 0.12)][rng.randi() % 3]
	_part(Mat.solid(col, 0.4, 0.3), Vector3(0.9, 1.9, 0.8), p, face)
	_col(Vector3(0.9, 1.9, 0.8), p, face)
	var glow := BoxMesh.new()
	glow.size = Vector3(0.6, 1.2, 0.02)
	m._merge_add(Mat.emissive(Color(0.9, 0.95, 1.0), 1.4), glow, Transform3D(basis, p + basis * Vector3(-0.08, 0, -0.41) + Vector3(0, 1.15, 0)))
	for r in 5:
		for c in 4:
			var cm := CylinderMesh.new()
			cm.radial_segments = 10
			cm.rings = 1
			cm.top_radius = 0.03
			cm.bottom_radius = 0.03
			cm.height = 0.11
			m._merge_add(_pc(), cm, Transform3D(Basis(), p + basis * Vector3(-0.3 + c * 0.14, 0, -0.38) + Vector3(0, 0.66 + r * 0.22, 0)))
	_part(_mat("black"), Vector3(0.2, 0.5, 0.03), p + basis * Vector3(0.32, 0, -0.41), face, 0.95)


func _vending_pair(p: Vector3, along: Vector3) -> void:
	var side := Vector3(-along.z, 0, along.x)
	_vending(p + along * 0.5, side)
	_vending(p - along * 0.5, side)
	dress.place("metal_trash_can", p + along * 1.6, rng.randf() * TAU, 1.0, "cyl")


func _lockers(p: Vector3, face: Vector3) -> void:
	var along := Vector3(-face.z, 0, face.x)
	var basis := Basis.looking_at(face, Vector3.UP)
	_part(Mat.solid(Color(0.95, 0.75, 0.1), 0.5, 0.3), Vector3(2.6, 2.0, 0.6), p, along)
	_col(Vector3(2.6, 2.0, 0.6), p, along)
	for r in 5:
		for c in 6:
			_part(Mat.solid(Color(0.85, 0.65, 0.08), 0.45, 0.4), Vector3(0.4, 0.34, 0.02), p + basis * Vector3(-1.05 + c * 0.42, 0, -0.31), along, 0.15 + r * 0.37)


func _atm(p: Vector3, face: Vector3) -> void:
	var basis := Basis.looking_at(face, Vector3.UP)
	_part(Mat.solid(Color(0.2, 0.45, 0.25), 0.4, 0.4), Vector3(0.8, 1.6, 0.5), p, face)
	_col(Vector3(0.8, 1.6, 0.5), p, face)
	var sc := BoxMesh.new()
	sc.size = Vector3(0.35, 0.25, 0.02)
	m._merge_add(_mat("screen"), sc, Transform3D(basis, p + basis * Vector3(0, 0, -0.26) + Vector3(0, 1.3, 0)))


## Small things against a wall: bins, benches, extinguishers, a broken-down cart of stock.
func _wall_item(p: Vector3, face: Vector3) -> void:
	var yaw := atan2(face.x, face.z)
	match rng.randi() % 8:
		0:
			dress.place("metal_trash_can", p, rng.randf() * TAU, 1.0, "cyl")
		1:
			dress.place("painted_wooden_bench", p, yaw + PI / 2, 1.0, "box")
		2:
			dress.place("korean_fire_extinguisher_01", p + face * -0.3, yaw, 1.0)
			dress.place("cardboard_box_01", p + Vector3(-face.z, 0, face.x) * 0.7, rng.randf() * TAU, 1.0, "box")
		3:
			dress.place("industrial_storage_cart", p, yaw + PI / 2, 1.0, "box")
		4:
			_planter_small(p)
		5:
			_vending(p, face)
		6:
			dress.place("plastic_crate_03", p, rng.randf() * TAU, 1.0, "box")
			dress.place("plastic_crate_03", p + Vector3(0, 0.33, 0), rng.randf() * TAU, 1.0)
		7:
			dress.place("hand_truck", p, yaw, 1.0)
			dress.place("cardboard_box_01", p + face * 0.4, rng.randf() * TAU, 1.0, "box")
