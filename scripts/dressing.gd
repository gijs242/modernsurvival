class_name Dressing
extends RefCounted
## Prop instancing for the Mall map: scanned CC0 models (res://assets/props/<name>/<name>.gltf) placed with
## place(), drawn with one MultiMesh per mesh part, plus optional box colliders. Also floor grime decals.

var m: GameMap
var body: StaticBody3D
var batches := {}              # prop name -> Array[Transform3D]
var colliders := {}            # prop name -> "box" / "cyl" / ""
var mesh_cache := {}           # prop name -> Array[[Mesh, Transform3D]]
var aabb_cache := {}           # prop name -> AABB of the whole model (unscaled)
var decal_tex := {}


func setup(map: GameMap, static_body: StaticBody3D) -> void:
	m = map
	body = static_body


static func has_prop(name: String) -> bool:
	return ResourceLoader.exists("res://assets/props/%s/%s.gltf" % [name, name])


func _meshes_of(name: String) -> Array:
	if mesh_cache.has(name):
		return mesh_cache[name]
	var out := []
	var path := "res://assets/props/%s/%s.gltf" % [name, name]
	var box := AABB()
	var first := true
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
			var a := xf * mm.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
		inst.free()
	mesh_cache[name] = out
	aabb_cache[name] = box
	return out


## Size of a prop model in metres (unscaled), e.g. to fit it on a table or line several up.
func size_of(name: String) -> Vector3:
	_meshes_of(name)
	return (aabb_cache.get(name, AABB()) as AABB).size


func _near_door(p: Vector2) -> bool:
	for dd in m.get_meta("doors", []):                # keep mall doorways clear (enemies need ~1 m to pass)
		if Vector2(p.x - dd[0].x, p.y - dd[0].z).length() < 3.0:
			return true
	return false


func place(name: String, pos: Vector3, yaw := 0.0, scale := 1.0, collider := "") -> void:
	if collider != "" and _near_door(Vector2(pos.x, pos.z)):
		return
	if not batches.has(name):
		batches[name] = []
	batches[name].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), pos))
	if collider != "":
		colliders[name] = collider


## One MultiMesh per prop part per CHUNK-sized square: lets the renderer frustum- and occlusion-cull the props
## and pick a mesh LOD per chunk (a single map-wide MultiMesh is always drawn in full, at full detail).
const CHUNK := 12.0

func flush() -> void:
	var stats := {}
	for name in batches:
		var parts := _meshes_of(name)
		var all: Array = batches[name]
		if parts.is_empty():
			continue
		var groups := {}
		for xf in all:
			var o: Vector3 = (xf as Transform3D).origin
			var cell := Vector2i(floori(o.x / CHUNK), floori(o.z / CHUNK))
			if not groups.has(cell):
				groups[cell] = []
			groups[cell].append(xf)
		var tris := 0
		for part in parts:
			var mesh: Mesh = part[0]
			var lxf: Transform3D = part[1]
			for i in mesh.get_surface_count():
				tris += mesh.surface_get_array_len(i) / 3 if mesh.surface_get_array_index_len(i) <= 0 else mesh.surface_get_array_index_len(i) / 3
			# only bigger props cast shadows below Ultra (shadow passes were a big GPU cost)
			var big := mesh.get_aabb().size.y * (all[0] as Transform3D).basis.get_scale().y > 0.9
			for cell in groups:
				var xfs: Array = groups[cell]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh
				mm.instance_count = xfs.size()
				for i in xfs.size():
					mm.set_instance_transform(i, xfs[i] * lxf)
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (big or m.quality >= 3) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.visibility_range_end = 70.0 if big else 35.0
				mmi.visibility_range_end_margin = 6.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				m.static_root.add_child(mmi)
		stats[name] = "%d x %d tris" % [all.size(), tris]
		var kind: String = colliders.get(name, "")
		if kind == "":
			continue
		var aabb: AABB = aabb_cache[name]
		for xf in all:
			var s: float = (xf as Transform3D).basis.get_scale().x
			var cs := CollisionShape3D.new()
			if kind == "cyl":
				var cy := CylinderShape3D.new()
				cy.radius = maxf(aabb.size.x, aabb.size.z) * 0.5 * s
				cy.height = aabb.size.y * s
				cs.shape = cy
				cs.transform = Transform3D(Basis(), (xf as Transform3D).origin + Vector3(0, aabb.size.y * 0.5 * s, 0))
			else:
				var bx := BoxShape3D.new()
				bx.size = aabb.size * s
				cs.shape = bx
				cs.transform = Transform3D((xf as Transform3D).basis.orthonormalized(), (xf as Transform3D) * aabb.get_center())
			body.add_child(cs)
	if Net.args.has("buildlog"):
		print("[dress] ", stats)


# ------------------------------------------------------------------ floor grime decals
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
		"litter":
			img.fill(Color(0, 0, 0, 0))
			for k in 14:
				var c := Vector2i(r2.randi_range(20, n - 40), r2.randi_range(20, n - 40))
				var col: Color = [Color(0.92, 0.92, 0.88), Color(0.85, 0.2, 0.15), Color(0.2, 0.4, 0.8), Color(0.8, 0.75, 0.6)][k % 4]
				img.fill_rect(Rect2i(c, Vector2i(r2.randi_range(6, 22), r2.randi_range(4, 14))), col)
		_:
			for y in n:
				for x in n:
					var u := Vector2(x, y) / n * 2.0 - Vector2.ONE
					var r := u.length()
					var nv := noise.get_noise_2d(x, y)
					var col := Color(0, 0, 0, 0)
					match kind:
						"stain":
							col = Color(0.12, 0.1, 0.08, clampf((0.8 - r + nv * 0.5) * 1.4, 0.0, 0.45))
						"puddle":
							col = Color(0.05, 0.06, 0.06, clampf((0.75 - r + nv * 0.35) * 3.0, 0.0, 0.7))
						"crack":
							var line: float = absf(u.y + sin(u.x * 5.0 + nv * 3.0) * 0.25 + nv * 0.2)
							col = Color(0.05, 0.05, 0.05, clampf(1.0 - line * 40.0, 0.0, 0.9) * clampf(1.0 - absf(u.x), 0.0, 1.0) * 1.5)
						"scuff":
							col = Color(0.15, 0.15, 0.15, clampf((0.6 - r) * 2.0, 0.0, 1.0) * clampf(noise.get_noise_2d(x * 3.0, y * 0.3) * 2.0, 0.0, 0.35))
					img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	decal_tex[kind] = t
	return t


func decal(kind: String, pos: Vector3, size: float, yaw := 0.0) -> void:
	var dcl := Decal.new()
	dcl.texture_albedo = _tex(kind)
	dcl.size = Vector3(size, 0.6, size)
	dcl.position = pos + Vector3(0, 0.05, 0)
	dcl.rotation.y = yaw
	dcl.upper_fade = 0.3
	dcl.lower_fade = 0.3
	dcl.cull_mask = 1
	dcl.distance_fade_enabled = true
	dcl.distance_fade_begin = 35.0
	dcl.distance_fade_length = 10.0
	m.static_root.add_child(dcl)
