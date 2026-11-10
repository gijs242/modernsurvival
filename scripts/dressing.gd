class_name Dressing
extends RefCounted
## Set dressing for the Liekeblom map: vegetation, street furniture, clutter, kerbs, bollards
## and ground decals. Everything repeated is drawn with MultiMesh instancing.

var m: GameMap
var d: Dictionary
var body: StaticBody3D
var rng := RandomNumberGenerator.new()
var blocked: Array = []        # PackedVector2Array building footprints (+ mall)
var road_segs: Array = []      # [Vector2 a, Vector2 b, half width]
var batches := {}              # prop name -> Array[Transform3D]
var colliders := {}            # prop name -> "box"/"cyl"/""
var mesh_cache := {}           # prop name -> Array[[Mesh, Transform3D, Material]]
var decal_tex := {}


func run(map: GameMap, data: Dictionary, static_body: StaticBody3D) -> void:
	m = map
	d = data
	body = static_body
	rng.seed = 4242
	for b in d.buildings:
		if b.footprint:
			var poly := PackedVector2Array()
			for p in b.footprint:
				poly.append(Vector2(p[0], p[1]))
			blocked.append(poly)
	var widths := {"tertiary": 7.0, "residential": 5.5, "service": 4.0, "pedestrian": 6.0, "footway": 2.6, "cycleway": 2.4}
	for r in d.roads:
		if not widths.has(r.kind):
			continue
		for i in r.pts.size() - 1:
			road_segs.append([Vector2(r.pts[i][0], r.pts[i][1]), Vector2(r.pts[i + 1][0], r.pts[i + 1][1]), widths[r.kind] * 0.5, r.kind])
	var t0 := Time.get_ticks_msec()
	var log := Net.args.has("buildlog")
	for step in [["kerbs", _kerbs], ["trees", _street_trees], ["green", _green_areas], ["weeds", _wall_weeds],
			["furniture", _street_furniture], ["clutter", _service_clutter], ["mall", _mall_props], ["flush", _flush], ["decals", _decals]]:
		step[1].call()
		if log:
			print("[dress] %s done at %d ms" % [step[0], Time.get_ticks_msec() - t0])
	if log:
		var counts := {}
		for k in batches:
			counts[k] = batches[k].size()
		print("[dress] placed: ", counts)


# ------------------------------------------------------------------ queries
func _in_building(p: Vector2, margin := 0.0) -> bool:
	for poly in blocked:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
		if margin > 0.0:
			for i in poly.size() - 1:
				if Geometry2D.get_closest_point_to_segment(p, poly[i], poly[i + 1]).distance_to(p) < margin:
					return true
	return false


func _on_road(p: Vector2, extra := 0.3) -> bool:
	for s in road_segs:
		if s[3] in ["footway", "pedestrian"]:
			continue
		if Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p) < s[2] + extra:
			return true
	return false


func _in_bounds(p: Vector2, margin := 2.0) -> bool:
	return m.bounds.grow(-margin).has_point(p)


func _free_spot(p: Vector2, building_margin := 0.6, road_extra := 0.4) -> bool:
	return _in_bounds(p) and not _in_building(p, building_margin) and not _on_road(p, road_extra)


# ------------------------------------------------------------------ prop instancing
func _meshes_of(name: String) -> Array:
	if mesh_cache.has(name):
		return mesh_cache[name]
	var out := []
	var path := "res://assets/props/%s/%s.gltf" % [name, name]
	if name.begins_with("tree:"):
		path = "res://assets/trees/%s.glb" % name.substr(5)
	if ResourceLoader.exists(path):
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var mm := mi as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var n: Node = mm
			while n and n != inst:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			out.append([mm.mesh, xf])
		inst.free()
	mesh_cache[name] = out
	return out


func place(name: String, pos: Vector3, yaw := 0.0, scale := 1.0, collider := "") -> void:
	if not batches.has(name):
		batches[name] = []
	batches[name].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos))
	if collider != "":
		colliders[name] = collider


func _flush() -> void:
	for name in batches:
		var parts := _meshes_of(name)
		var xfs: Array = batches[name]
		var aabb := AABB()
		var first := true
		for part in parts:
			var mesh: Mesh = part[0]
			var lxf: Transform3D = part[1]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i] * lxf)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			var small: bool = name.begins_with("grass") or name.begins_with("weed") or name.begins_with("fern") or name.begins_with("nettle")
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if name.begins_with("tree:") or name.begins_with("grass") or name.begins_with("weed") or name.begins_with("fern") or name.begins_with("nettle"):
				mmi.visibility_range_end = 140.0 if name.begins_with("tree:") else 45.0
				mmi.visibility_range_end_margin = 10.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			m.static_root.add_child(mmi)
			var a := lxf * mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		var kind: String = colliders.get(name, "")
		if kind == "" or first:
			continue
		for xf in xfs:
			var s: float = (xf as Transform3D).basis.get_scale().x
			var cs := CollisionShape3D.new()
			if kind == "cyl":
				var cy := CylinderShape3D.new()
				cy.radius = 0.22 * s
				cy.height = 3.0 * s
				cs.shape = cy
				cs.transform = Transform3D(Basis(), (xf as Transform3D).origin + Vector3(0, 1.5 * s, 0))
			else:
				var bx := BoxShape3D.new()
				bx.size = aabb.size * s
				cs.shape = bx
				cs.transform = Transform3D((xf as Transform3D).basis.orthonormalized(), (xf as Transform3D) * aabb.get_center())
			body.add_child(cs)


# ------------------------------------------------------------------ kerbs & bollards (rounded geometry)
func _kerbs() -> void:
	var kerb_mat := (Mat.pbr("concrete", Color(0.78, 0.78, 0.77), 0.9) as StandardMaterial3D).duplicate()
	kerb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	kerb_mat.uv1_triplanar = true
	kerb_mat.uv1_world_triplanar = true
	kerb_mat.uv1_scale = Vector3.ONE * 1.5
	var profile := PackedVector2Array([Vector2(0, 0), Vector2(0, 0.11), Vector2(0.03, 0.135), Vector2(0.07, 0.14), Vector2(0.15, 0.14), Vector2(0.15, 0)])
	for r in d.roads:
		if not r.kind in ["tertiary", "residential", "service"]:
			continue
		var hw: float = {"tertiary": 3.5, "residential": 2.75, "service": 2.0}[r.kind]
		for side in [-1.0, 1.0]:
			var pts := []
			for i in r.pts.size():
				var p := Vector2(r.pts[i][0], r.pts[i][1])
				var a := Vector2(r.pts[max(0, i - 1)][0], r.pts[max(0, i - 1)][1])
				var b := Vector2(r.pts[min(r.pts.size() - 1, i + 1)][0], r.pts[min(r.pts.size() - 1, i + 1)][1])
				var dir := (b - a).normalized()
				pts.append(p + Vector2(-dir.y, dir.x) * hw * side)
			_extrude(kerb_mat, pts, profile, side)


func _extrude(mat: Material, pts: Array, profile: PackedVector2Array, side: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var dir := b - a
		if dir.length() < 0.05:
			continue
		var out := Vector2(-dir.y, dir.x).normalized() * side
		for k in profile.size() - 1:
			var p0 := profile[k]
			var p1 := profile[k + 1]
			var q := [Vector3(a.x + out.x * p0.x, p0.y, a.y + out.y * p0.x), Vector3(b.x + out.x * p0.x, p0.y, b.y + out.y * p0.x),
				Vector3(b.x + out.x * p1.x, p1.y, b.y + out.y * p1.x), Vector3(a.x + out.x * p1.x, p1.y, a.y + out.y * p1.x)]
			var n: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
			if n.y < -0.01 or (abs(n.y) < 0.2 and n.dot(Vector3(out.x, 0, out.y)) < 0 and k == 0):
				n = -n
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n)
				st.add_vertex(q[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	(mi.material_override as Material)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	m.static_root.add_child(mi)
	# render both sides so winding never matters for these thin strips
	if mat is ShaderMaterial:
		pass


func _bollard_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.065
	cyl.bottom_radius = 0.075
	cyl.height = 0.85
	cyl.radial_segments = 16
	st.append_from(cyl, 0, Transform3D(Basis(), Vector3(0, 0.425, 0)))
	var cap := SphereMesh.new()
	cap.radius = 0.075
	cap.height = 0.15
	cap.radial_segments = 16
	cap.rings = 8
	st.append_from(cap, 0, Transform3D(Basis(), Vector3(0, 0.86, 0)))
	var ring := CylinderMesh.new()
	ring.top_radius = 0.08
	ring.bottom_radius = 0.08
	ring.height = 0.04
	ring.radial_segments = 16
	st.append_from(ring, 0, Transform3D(Basis(), Vector3(0, 0.72, 0)))
	return st.commit()


# ------------------------------------------------------------------ vegetation
func _street_trees() -> void:
	var types := ["tree:island_tree_02", "tree:tree_small_02"]
	for r in d.roads:
		if not r.kind in ["tertiary", "residential", "pedestrian"]:
			continue
		var hw: float = {"tertiary": 3.5, "residential": 2.75, "pedestrian": 3.0}[r.kind]
		var acc := rng.randf() * 10.0
		for i in r.pts.size() - 1:
			var a := Vector2(r.pts[i][0], r.pts[i][1])
			var b := Vector2(r.pts[i + 1][0], r.pts[i + 1][1])
			var L := a.distance_to(b)
			var dir := (b - a) / maxf(L, 0.01)
			var t := acc
			while t < L:
				var side := 1.0 if int(t / 13.0) % 2 == 0 else -1.0
				var p := a + dir * t + Vector2(-dir.y, dir.x) * (hw + 2.4) * side
				if _free_spot(p, 2.5, 1.5):
					var tp := Vector3(p.x, 0, p.y)
					place(types[rng.randi() % 2], tp, rng.randf() * TAU, rng.randf_range(1.35, 1.8), "cyl")
					_tree_pit(tp)
				t += rng.randf_range(11.0, 16.0)
			acc = t - L


func _tree_pit(p: Vector3) -> void:
	for k in 3:
		place(["grass_medium_01", "weed_plant_02", "grass_medium_02"][k], p + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)), rng.randf() * TAU, rng.randf_range(0.8, 1.2))
	_leaf_decal_at(p)


var _leaf_spots: Array = []
func _leaf_decal_at(p: Vector3) -> void:
	_leaf_spots.append(p)


func _green_areas() -> void:
	for a in d.areas:
		if not a.kind in ["grass", "forest"]:
			continue
		var poly := PackedVector2Array()
		for p in a.pts:
			poly.append(Vector2(p[0], p[1]))
		var r := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			r = r.expand(p)
		var area := r.get_area()
		var n_trees := int(area / (90.0 if a.kind == "forest" else 260.0))
		var n_small := int(area / 2.2)
		for i in min(n_trees, 60):
			var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			if Geometry2D.is_point_in_polygon(p, poly) and _free_spot(p, 2.5, 1.0):
				var tp := Vector3(p.x, 0, p.y)
				place(["tree:island_tree_02", "tree:tree_small_02"][rng.randi() % 2], tp, rng.randf() * TAU, rng.randf_range(1.2, 1.9), "cyl")
				_leaf_spots.append(tp)
		for i in min(n_small, 900):
			var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
			if Geometry2D.is_point_in_polygon(p, poly) and _free_spot(p, 0.3, 0.2):
				var kind: String = ["grass_medium_01", "grass_medium_02", "grass_medium_01", "weed_plant_02", "fern_02", "nettle_plant", "shrub_02", "shrub_03", "shrub_04"][rng.randi() % 9]
				var s := rng.randf_range(0.8, 1.3) if not kind.begins_with("shrub") else rng.randf_range(0.7, 1.1)
				place(kind, Vector3(p.x, 0, p.y), rng.randf() * TAU, s)


func _wall_weeds() -> void:
	# weeds and grass tufts in the cracks along building bases
	for poly in blocked:
		for i in poly.size() - 1:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[i + 1]
			var L := a.distance_to(b)
			var n := int(L / 6.0)
			for k in n:
				if rng.randf() > 0.45:
					continue
				var t := rng.randf()
				var mid := a.lerp(b, t)
				var out := Vector2(-(b - a).y, (b - a).x).normalized()
				for sgn in [1.0, -1.0]:
					var p: Vector2 = mid + out * 0.25 * sgn
					if _in_bounds(p) and not _in_building(p) and not _on_road(p, 0.0):
						place(["grass_medium_02", "weed_plant_02", "grass_medium_01"][rng.randi() % 3], Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.5, 0.9))
						break


# ------------------------------------------------------------------ street furniture
func _street_furniture() -> void:
	var bollard := _bollard_mesh()
	var bollard_xf: Array[Transform3D] = []
	for r in d.roads:
		if r.kind in ["tertiary", "residential"]:
			var hw: float = 3.5 if r.kind == "tertiary" else 2.75
			var acc := 6.0
			for i in r.pts.size() - 1:
				var a := Vector2(r.pts[i][0], r.pts[i][1])
				var b := Vector2(r.pts[i + 1][0], r.pts[i + 1][1])
				var L := a.distance_to(b)
				var dir := (b - a) / maxf(L, 0.01)
				var t := acc
				while t < L:
					var p := a + dir * t + Vector2(-dir.y, dir.x) * (hw + 0.7)
					if _free_spot(p, 0.8, 0.1):
						place("street_lamp_02", Vector3(p.x, 0, p.y), atan2(dir.x, dir.y), 1.15, "cyl")
					t += 26.0
				acc = t - L
		if r.kind in ["pedestrian", "footway"]:
			# Dutch bollards where foot paths meet the street
			for end in [0, r.pts.size() - 1]:
				var p := Vector2(r.pts[end][0], r.pts[end][1])
				var q := Vector2(r.pts[1 if end == 0 else end - 1][0], r.pts[1 if end == 0 else end - 1][1])
				var dir := (q - p).normalized()
				var side := Vector2(-dir.y, dir.x)
				for k in range(-2, 3):
					var bp := p + dir * 1.2 + side * k * 1.1
					if _in_bounds(bp) and not _in_building(bp, 0.3) and not _on_road(bp, 0.1):
						bollard_xf.append(Transform3D(Basis(), Vector3(bp.x, 0, bp.y)))
	if not bollard_xf.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bollard
		mm.instance_count = bollard_xf.size()
		for i in bollard_xf.size():
			mm.set_instance_transform(i, bollard_xf[i])
			var cs := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = 0.08
			cy.height = 0.9
			cs.shape = cy
			cs.position = bollard_xf[i].origin + Vector3(0, 0.45, 0)
			body.add_child(cs)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Mat.solid(Color(0.32, 0.1, 0.08), 0.45, 0.6)
		m.static_root.add_child(mmi)
	# benches and bins from OpenStreetMap, café terraces outside cafés/restaurants
	for p in d.street_pois:
		var v := Vector3(p.pos[0], 0, p.pos[1])
		if not _in_bounds(Vector2(v.x, v.z)):
			continue
		match p.kind:
			"bench":
				place("modular_street_seating", v, rng.randf() * TAU, 1.0, "box")
				place("metal_trash_can", v + Vector3(1.6, 0, 0.4), rng.randf() * TAU, 1.0, "box")
			"restaurant", "cafe", "fast_food", "bar", "pub":
				var spot := _nearest_free(Vector2(v.x, v.z), 3.0)
				if spot != Vector2.INF:
					for k in 3:
						var tp := Vector3(spot.x, 0, spot.y) + Vector3(cos(k * 2.1), 0, sin(k * 2.1)) * 1.8
						if _free_spot(Vector2(tp.x, tp.z), 0.6, 0.3):
							place("outdoor_table_chair_set_01", tp, rng.randf() * TAU, 1.0, "box")
	# around the mall entrances: planters, bins, benches
	for e in d.mall.entrances:
		var c := Vector2(d.mall.hall_center[0], d.mall.hall_center[1])
		var ev := Vector2(e[0], e[1])
		var out := (ev - c).normalized()
		var side := Vector2(-out.y, out.x)
		for s in [-1.0, 1.0]:
			var p: Vector2 = ev + out * 2.5 + side * 2.6 * s
			if _free_spot(p, 0.4, 0.3):
				place(["planter_box_01", "planter_box_02"][rng.randi() % 2], Vector3(p.x, 0, p.y), atan2(out.x, out.y), 1.0, "box")
		var bp := ev + out * 3.2 + side * 4.5
		if _free_spot(bp, 0.4, 0.3):
			place("metal_trash_can", Vector3(bp.x, 0, bp.y), rng.randf() * TAU, 1.0, "box")


func _nearest_free(p: Vector2, start: float) -> Vector2:
	for r in [start, start + 2.0, start + 4.0, start + 6.0]:
		for k in 12:
			var q: Vector2 = p + Vector2(cos(k * TAU / 12), sin(k * TAU / 12)) * r
			if _free_spot(q, 0.6, 0.4):
				return q
	return Vector2.INF


# ------------------------------------------------------------------ clutter
func _service_clutter() -> void:
	# along the outside of the mall (service yards, delivery doors): bags, boxes, crates, tyres, utility boxes
	var shell: Array = d.mall.shell
	var junk := ["trashbag", "trashbag", "cardboard_box_01", "plastic_crate_02", "wooden_crate_02", "cement_bag", "compost_bags", "old_tyre"]
	for s in shell:
		if not s.doors.is_empty():
			continue
		var a := Vector2(s.a[0], s.a[1])
		var b := Vector2(s.b[0], s.b[1])
		var L := a.distance_to(b)
		if L < 4.0:
			continue
		var dir := (b - a) / L
		var c := Vector2(d.mall.hall_center[0], d.mall.hall_center[1])
		var out := Vector2(-dir.y, dir.x)
		if out.dot(a - c) < 0:
			out = -out
		var face := atan2(out.x, out.y)
		if rng.randf() < 0.55 and L > 7.0:
			var dp := a + dir * L * rng.randf_range(0.3, 0.7) + out * 0.08
			place("rollershutter_door", Vector3(dp.x, 0, dp.y), face, 1.0)
		if rng.randf() < 0.4:
			var up := a + dir * L * rng.randf_range(0.1, 0.9) + out * 0.25
			place(["power_box_01", "utility_box_02"][rng.randi() % 2], Vector3(up.x, 0, up.y), face, 1.0, "box")
		var n := int(L / 5.0)
		for k in n:
			if rng.randf() > 0.5:
				continue
			var p := a + dir * L * rng.randf() + out * rng.randf_range(0.5, 1.6)
			if not _free_spot(p, 0.0, 0.3):
				continue
			var name: String = junk[rng.randi() % junk.size()]
			place(name, Vector3(p.x, 0, p.y), rng.randf() * TAU, rng.randf_range(0.9, 1.1), "box" if name in ["wooden_crate_02", "plastic_crate_02"] else "")
			if name == "trashbag":
				for j in rng.randi_range(1, 3):
					place("trashbag", Vector3(p.x + rng.randf_range(-0.6, 0.6), 0, p.y + rng.randf_range(-0.6, 0.6)), rng.randf() * TAU, rng.randf_range(0.8, 1.1))


func _mall_props() -> void:
	# potted plants and bins in the corridors
	for o in d.mall.open:
		if o.hall or rng.randf() > 0.08:
			continue
		var c := Vector3.ZERO
		for p in o.pts:
			c += Vector3(p[0], 0, p[1])
		c /= 4.0
		place(["potted_plant_02", "potted_plant_04"][rng.randi() % 2], c, rng.randf() * TAU, 1.3, "box")
	# the armory unit gets a generator and crates
	for st in m.stations:
		if st.cat == "equipment":
			var f: Vector3 = st.facing
			var side := Vector3(-f.z, 0, f.x)
			place("portable_generator", st.pos - f * 0.2 + side * 6.0, rng.randf() * TAU, 1.0, "box")
			place("wooden_crate_02", st.pos + side * -6.0 + f * 0.5, rng.randf() * TAU, 1.0, "box")


# ------------------------------------------------------------------ decals
func _tex(kind: String) -> ImageTexture:
	if decal_tex.has(kind):
		return decal_tex[kind]
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = kind.hash()
	noise.frequency = 0.03
	var r2 := RandomNumberGenerator.new()
	r2.seed = kind.hash()
	match kind:
		"leaves":
			img.fill(Color(0, 0, 0, 0))
			for k in 220:
				var c := Vector2(r2.randf() * n, r2.randf() * n)
				if c.distance_to(Vector2(n, n) / 2) > n * 0.48 * (0.7 + r2.randf() * 0.3):
					continue
				var col: Color = [Color(0.45, 0.3, 0.1), Color(0.55, 0.42, 0.15), Color(0.35, 0.22, 0.08), Color(0.4, 0.38, 0.12)][k % 4]
				var a := r2.randf() * TAU
				for y in range(-7, 8):
					for x in range(-7, 8):
						var lx := x * cos(a) + y * sin(a)
						var ly := -x * sin(a) + y * cos(a)
						if (lx * lx) / 49.0 + (ly * ly) / 9.0 < 1.0:
							var px := int(c.x) + x
							var py := int(c.y) + y
							if px >= 0 and py >= 0 and px < n and py < n:
								img.set_pixel(px, py, col * Color(1, 1, 1, 0.95))
		"litter":
			img.fill(Color(0, 0, 0, 0))
			for k in 14:
				var c := Vector2i(r2.randi_range(20, n - 40), r2.randi_range(20, n - 40))
				var col: Color = [Color(0.92, 0.92, 0.88), Color(0.85, 0.2, 0.15), Color(0.2, 0.4, 0.8), Color(0.8, 0.75, 0.6)][k % 4]
				img.fill_rect(Rect2i(c, Vector2i(r2.randi_range(6, 22), r2.randi_range(4, 14))), col)
		"oil", "crack", "puddle", "manhole":
			for y in n:
				for x in n:
					var u := Vector2(x, y) / n * 2.0 - Vector2.ONE
					var r := u.length()
					var nv := noise.get_noise_2d(x, y)
					var col := Color(0, 0, 0, 0)
					match kind:
						"oil":
							col = Color(0.03, 0.03, 0.03, clamp((0.8 - r + nv * 0.4) * 1.6, 0.0, 0.75))
						"puddle":
							col = Color(0.05, 0.06, 0.06, clamp((0.75 - r + nv * 0.35) * 3.0, 0.0, 0.85))
						"crack":
							var line: float = abs(u.y + sin(u.x * 5.0 + nv * 3.0) * 0.25 + nv * 0.2)
							col = Color(0.05, 0.05, 0.05, clamp(1.0 - line * 40.0, 0.0, 0.9) * clamp(1.0 - abs(u.x), 0.0, 1.0) * 1.5)
						"manhole":
							var ring: float = abs(r - 0.82)
							col = Color(0.12, 0.12, 0.12, 1.0 if r < 0.9 else 0.0)
							if ring < 0.05:
								col = Color(0.05, 0.05, 0.05, 1.0)
							elif r < 0.8 and (int(x / 12) + int(y / 12)) % 2 == 0:
								col = Color(0.18, 0.18, 0.17, 1.0)
					img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	decal_tex[kind] = t
	return t


func _decal(kind: String, pos: Vector3, size: float, yaw := 0.0, rough := -1.0) -> void:
	var dcl := Decal.new()
	dcl.texture_albedo = _tex(kind)
	dcl.size = Vector3(size, 0.6, size)
	dcl.position = pos + Vector3(0, 0.05, 0)
	dcl.rotation.y = yaw
	dcl.upper_fade = 0.3
	dcl.lower_fade = 0.3
	dcl.cull_mask = 1
	dcl.distance_fade_enabled = true
	dcl.distance_fade_begin = 60.0
	dcl.distance_fade_length = 15.0
	m.static_root.add_child(dcl)


func _decals() -> void:
	for p in _leaf_spots:
		_decal("leaves", p + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), rng.randf_range(2.5, 4.5), rng.randf() * TAU)
	for a in d.areas:
		if a.kind != "parking":
			continue
		for k in 6:
			var p = a.pts[rng.randi() % a.pts.size()]
			var c := Vector3.ZERO
			for q in a.pts:
				c += Vector3(q[0], 0, q[1])
			c /= a.pts.size()
			var v := c.lerp(Vector3(p[0], 0, p[1]), rng.randf() * 0.7)
			_decal("oil", v, rng.randf_range(0.8, 1.8), rng.randf() * TAU)
	var count := 0
	for s in road_segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if a.distance_to(b) < 6.0 or not _in_bounds(a.lerp(b, 0.5)):
			continue
		var p := a.lerp(b, rng.randf())
		var v := Vector3(p.x, 0, p.y)
		match rng.randi() % 4:
			0:
				_decal("crack", v, rng.randf_range(1.5, 3.0), rng.randf() * TAU)
			1:
				_decal("litter", v + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)), rng.randf_range(1.0, 2.0), rng.randf() * TAU)
			2:
				if s[3] in ["tertiary", "residential"]:
					_decal("manhole", v, 0.75)
			3:
				_decal("puddle", v, rng.randf_range(1.2, 2.5), rng.randf() * TAU)
		count += 1
		if count > 160:
			break
