class_name LeekBackdrop
extends RefCounted
## Low-detail scenery of the town of Leek around the playable map, from res://assets/maps/leek_backdrop.json
## (tools/build_leek_backdrop.py: BAG footprints, 3D BAG roof heights, OpenStreetMap streets / water / land use).
## Real positions and heights, but cheap: untextured vertex-coloured meshes in 250 m chunks, no collision,
## shadows only near the play area. Everything sits just below the detailed map's ground so the two never fight.

const DATA := "res://assets/maps/leek_backdrop.json"
const CHUNK := 250.0
const SHADOW_DIST := 320.0

const WALLS := [Color(0.46, 0.27, 0.2), Color(0.52, 0.33, 0.24), Color(0.4, 0.24, 0.19), Color(0.62, 0.55, 0.47), Color(0.75, 0.72, 0.66), Color(0.35, 0.3, 0.28)]
const ROOF_SLANT := [Color(0.22, 0.2, 0.2), Color(0.38, 0.2, 0.15), Color(0.28, 0.27, 0.27)]
const ROOF_FLAT := Color(0.3, 0.3, 0.31)
const AREA_COL := {"grass": Color(0.22, 0.32, 0.14), "forest": Color(0.13, 0.21, 0.1), "farm": Color(0.33, 0.36, 0.2),
	"water": Color(0.11, 0.15, 0.16), "parking": Color(0.3, 0.3, 0.3)}
const GROUND := Color(0.25, 0.3, 0.2)
const ROAD := Color(0.2, 0.2, 0.21)

var d: Dictionary
var detail := Rect2()
var chunks := {}          # Vector2i -> SurfaceTool
var flat_chunks := {}     # Vector2i -> SurfaceTool (ground cover: areas + roads)
var rng := RandomNumberGenerator.new()


func build(parent: Node3D) -> void:
	if not FileAccess.file_exists(DATA):
		return
	d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if d == null:
		return
	var r: Array = d.detail_rect
	detail = Rect2(r[0], r[1], r[2], r[3])
	rng.seed = 7
	var half: float = d.half
	# open ground under everything
	_quad(_st(flat_chunks, Vector3.ZERO), Vector3(-half, -0.09, -half), Vector3(half, -0.09, -half), Vector3(half, -0.09, half), Vector3(-half, -0.09, half), GROUND, true)
	for a in d.areas:
		_area(a[0], a[1])
	for rd in d.roads:
		_road(float(rd[0]), rd[1], ROAD if rd.size() < 3 else AREA_COL.water, -0.05 if rd.size() < 3 else -0.07)
	for b in d.buildings:
		_building(float(b[0]), int(b[1]) == 1, b[2])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.92
	mat.metallic_specular = 0.25
	var root := Node3D.new()
	root.name = "LeekBackdrop"
	parent.add_child(root)
	for set in [chunks, flat_chunks]:
		for key in set:
			var st: SurfaceTool = set[key]
			st.generate_normals()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			var centre := Vector2((key.x + 0.5) * CHUNK, (key.y + 0.5) * CHUNK)
			var near := centre.distance_to(detail.get_center()) < SHADOW_DIST
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (near and set == chunks) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			root.add_child(mi)


func _st(set: Dictionary, p: Vector3) -> SurfaceTool:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	if not set.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		set[key] = st
	return set[key]


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, e: Vector3, col: Color, up := false) -> void:
	if up:                     # ground-level quads: wound to face +Y
		_tri(st, a, b, c, col)
		_tri(st, a, c, e, col)
		return
	_tri(st, a, c, b, col)
	_tri(st, a, e, c, col)


func _ring(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		pts.append(Vector2(flat[i], flat[i + 1]))
	return pts


func _area(kind: String, flat: Array) -> void:
	var pts := _ring(flat)
	if pts.size() >= 2 and pts[0].distance_to(pts[pts.size() - 1]) < 0.01:
		pts.remove_at(pts.size() - 1)
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	var y := -0.08 if kind == "water" else -0.06
	var col: Color = AREA_COL.get(kind, GROUND)
	var st := _st(flat_chunks, Vector3(pts[0].x, 0, pts[0].y))
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var c := pts[idx[i + 2]]
		var n := (b - a).cross(c - a)
		if n > 0:
			_tri(st, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), col)
		else:
			_tri(st, Vector3(a.x, y, a.y), Vector3(c.x, y, c.y), Vector3(b.x, y, b.y), col)
	# woods: a sprinkle of low-poly tree crowns so they read as woods from the play area
	if kind == "forest":
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		var n_trees := int(clamp(box.get_area() / 90.0, 3, 120))
		for k in n_trees:
			var p := box.position + Vector2(rng.randf() * box.size.x, rng.randf() * box.size.y)
			if Geometry2D.is_point_in_polygon(p, pts) and not detail.has_point(p):
				_tree(Vector3(p.x, 0, p.y), rng.randf_range(7.0, 13.0))


func _tree(p: Vector3, h: float) -> void:
	var st := _st(chunks, p)
	var r := h * 0.32
	var top := p + Vector3(0, h, 0)
	var base := p + Vector3(0, h * 0.3, 0)
	var col := Color(0.16, 0.25, 0.12) * rng.randf_range(0.85, 1.15)
	for k in 5:
		var a0 := TAU * k / 5.0
		var a1 := TAU * (k + 1) / 5.0
		_tri(st, base + Vector3(cos(a1), 0, sin(a1)) * r, base + Vector3(cos(a0), 0, sin(a0)) * r, top, col)


func _road(w: float, flat: Array, col: Color, y: float) -> void:
	var pts := _ring(flat)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := b - a
		if dir.length() < 0.05:
			continue
		var n := Vector2(-dir.y, dir.x).normalized() * w * 0.5
		var st := _st(flat_chunks, Vector3(a.x, 0, a.y))
		var ext := dir.normalized() * w * 0.5           # overlap the joints a little
		var a2 := a - ext
		var b2 := b + ext
		_quad(st, Vector3(a2.x - n.x, y, a2.y - n.y), Vector3(b2.x - n.x, y, b2.y - n.y), Vector3(b2.x + n.x, y, b2.y + n.y), Vector3(a2.x + n.x, y, a2.y + n.y), col, true)


func _building(h: float, slanted: bool, flat: Array) -> void:
	var pts := _ring(flat)
	if pts.size() < 3:
		return
	# counter-clockwise (seen from above, x east / z south) so walls face outward
	if _signed_area(pts) > 0.0:
		pts.reverse()
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	if detail.has_point(c):
		return
	var st := _st(chunks, Vector3(c.x, 0, c.y))
	var hash := int(abs(c.x * 7.0 + c.y * 13.0))
	var wall: Color = WALLS[hash % WALLS.size()]
	var area: float = abs(_signed_area(pts))
	var pitched := slanted and area < 450.0
	var eave := maxf(2.6, h * 0.6) if pitched else h
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		_quad(st, Vector3(a.x, -0.1, a.y), Vector3(b.x, -0.1, b.y), Vector3(b.x, eave, b.y), Vector3(a.x, eave, a.y), wall)
	if pitched:
		# hipped roof to the centre: reads as a Dutch pitched roof from a distance
		var roof: Color = ROOF_SLANT[hash % ROOF_SLANT.size()]
		var apex := Vector3(c.x, h, c.y)
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			_tri(st, Vector3(a.x, eave, a.y), apex, Vector3(b.x, eave, b.y), roof)
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	for i in range(0, idx.size(), 3):
		var a := pts[idx[i]]
		var b := pts[idx[i + 1]]
		var e := pts[idx[i + 2]]
		if (b - a).cross(e - a) > 0:
			_tri(st, Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(e.x, h, e.y), ROOF_FLAT)
		else:
			_tri(st, Vector3(a.x, h, a.y), Vector3(e.x, h, e.y), Vector3(b.x, h, b.y), ROOF_FLAT)


func _signed_area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5
