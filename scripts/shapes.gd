class_name Shapes
extends RefCounted
## Procedural rounded shapes (instead of hard boxes). Meshes are cached by parameters.

static var _cache := {}


## Box with rounded edges and corners. `radius` is clamped to half the smallest side.
static func rounded_box(size: Vector3, radius := 0.02, seg := 3) -> ArrayMesh:
	var key := "rb:%s:%s:%s" % [size, radius, seg]
	if _cache.has(key):
		return _cache[key]
	var half := size * 0.5
	var r: float = min(radius, min(half.x, min(half.y, half.z)) * 0.999)
	var inner := half - Vector3.ONE * r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := seg * 2 + 2          # grid resolution per face
	# six faces: (normal axis, u axis, v axis)
	var faces := [[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var grid := []
		for j in n + 1:
			var row := []
			for i in n + 1:
				# non-uniform spacing: more vertices near the edges where the rounding happens
				var a := _edge_t(float(i) / n)
				var b := _edge_t(float(j) / n)
				var p := nrm * half + u * (a * 2.0 - 1.0) * half + v * (b * 2.0 - 1.0) * half
				p = Vector3(p.x * abs(nrm.x) + p.x * (1.0 - abs(nrm.x)), p.y, p.z)
				var c := p.clamp(-inner, inner)
				var d := p - c
				var q := c + (d.normalized() * r if d.length() > 1e-6 else nrm * r)
				var qn := (q - c).normalized() if (q - c).length() > 1e-6 else nrm
				row.append([q, qn, Vector2(a, b)])
			grid.append(row)
		for j in n:
			for i in n:
				var q00: Array = grid[j][i]
				var q10: Array = grid[j][i + 1]
				var q01: Array = grid[j + 1][i]
				var q11: Array = grid[j + 1][i + 1]
				for t in [q00, q11, q10, q00, q01, q11]:
					st.set_normal(t[1])
					st.set_uv(t[2])
					st.add_vertex(t[0])
	# make sure faces wind clockwise (Godot front faces) by checking the first triangle
	var mesh := st.commit()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var fn := (verts[1] - verts[0]).cross(verts[2] - verts[0])
	if fn.dot(norms[0]) > 0.0:     # counter-clockwise when seen from outside -> flip
		for k in range(0, verts.size(), 3):
			var tmp := verts[k + 1]
			verts[k + 1] = verts[k + 2]
			verts[k + 2] = tmp
			var tn := norms[k + 1]
			norms[k + 1] = norms[k + 2]
			norms[k + 2] = tn
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for k in range(0, uvs.size(), 3):
			var tu := uvs[k + 1]
			uvs[k + 1] = uvs[k + 2]
			uvs[k + 2] = tu
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache[key] = mesh
	return mesh


static func _edge_t(t: float) -> float:
	# cluster samples towards 0 and 1
	return 0.5 - 0.5 * cos(t * PI)


static func capsule(r: float, h: float, seg := 12) -> CapsuleMesh:
	var key := "cap:%s:%s:%s" % [r, h, seg]
	if _cache.has(key):
		return _cache[key]
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = max(h, r * 2.0)
	c.radial_segments = seg
	c.rings = 6
	_cache[key] = c
	return c


static func ellipsoid(size: Vector3, seg := 16) -> SphereMesh:
	var key := "el:%s:%s" % [size, seg]
	if _cache.has(key):
		return _cache[key]
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = seg
	s.rings = seg / 2
	_cache[key] = s
	return s


static func tube(r0: float, r1: float, h: float, seg := 14) -> CylinderMesh:
	var key := "tu:%s:%s:%s:%s" % [r0, r1, h, seg]
	if _cache.has(key):
		return _cache[key]
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	_cache[key] = c
	return c
