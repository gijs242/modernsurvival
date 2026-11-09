class_name Props
extends RefCounted
## Small procedural models for equipment and support: grenades, rockets, claymores, sentries, aircraft.


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


static func _cyl(r: float, h: float, r2 := -1.0, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0 else r2
	c.height = h
	c.radial_segments = seg
	return c


static func olive() -> StandardMaterial3D:
	return Mat.pbr("painted_metal", Color(0.27, 0.29, 0.2), 0.7, 0.3)


static func steel() -> StandardMaterial3D:
	return Mat.pbr("painted_metal", Color(0.14, 0.14, 0.15), 0.5, 0.7)


static func frag() -> Node3D:
	var g := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.05
	s.height = 0.12
	_mi(g, s, olive())
	_mi(g, _box(Vector3(0.03, 0.03, 0.03)), steel(), Vector3(0, 0.065, 0))
	_mi(g, _box(Vector3(0.012, 0.06, 0.02)), steel(), Vector3(0.025, 0.04, 0))
	return g


static func rocket() -> Node3D:
	var g := Node3D.new()
	_mi(g, _cyl(0.035, 0.5), olive(), Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_mi(g, _cyl(0.0, 0.14, 0.035), steel(), Vector3(0, 0, -0.32), Vector3(-PI / 2, 0, 0))
	var glow := Effects.make_flash_sprite(0.9)
	glow.position.z = 0.3
	g.add_child(glow)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.6, 0.3)
	l.light_energy = 2.0
	l.omni_range = 6.0
	g.add_child(l)
	g.set_meta("rocket", true)
	return g


static func claymore() -> Node3D:
	var g := Node3D.new()
	_mi(g, _box(Vector3(0.24, 0.13, 0.06)), olive(), Vector3(0, 0.12, 0), Vector3(-0.15, 0, 0))
	for x in [-0.08, 0.08]:
		_mi(g, _box(Vector3(0.015, 0.1, 0.015)), steel(), Vector3(x, 0.04, 0.02))
	var led := _mi(g, _box(Vector3(0.015, 0.015, 0.01)), Mat.emissive(Color(1, 0.1, 0.05), 8.0), Vector3(0.09, 0.17, -0.03))
	g.set_meta("led", led)
	return g


static func turret() -> Node3D:
	var g := Node3D.new()
	for k in 3:
		var p := Node3D.new()
		p.rotation.y = k * TAU / 3.0
		g.add_child(p)
		_mi(p, _box(Vector3(0.04, 0.9, 0.04)), steel(), Vector3(0, 0.42, 0.16), Vector3(-0.35, 0, 0))
	var head := Node3D.new()
	head.position.y = 0.95
	g.add_child(head)
	_mi(head, _box(Vector3(0.3, 0.22, 0.42)), olive(), Vector3(0, 0.08, 0))
	_mi(head, _box(Vector3(0.16, 0.16, 0.12)), olive(), Vector3(0.21, 0.06, -0.05))
	_mi(head, _cyl(0.025, 0.6), steel(), Vector3(0, 0.12, -0.45), Vector3(PI / 2, 0, 0))
	_mi(head, _box(Vector3(0.12, 0.08, 0.02)), Mat.solid(Color(0.05, 0.15, 0.2), 0.05, 1.0), Vector3(0, 0.2, -0.19))
	var flash := Effects.make_flash_sprite(0.5)
	flash.position = Vector3(0, 0.12, -0.8)
	flash.visible = false
	head.add_child(flash)
	g.set_meta("head", head)
	g.set_meta("flash", flash)
	return g


static func _aircraft(len_scale: float) -> Node3D:
	var g := Node3D.new()
	var m := Mat.pbr("painted_metal", Color(0.42, 0.45, 0.47), 0.5, 0.6)
	_mi(g, _cyl(0.7, 14.0 * len_scale, 0.9), m, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	_mi(g, _cyl(0.0, 3.0, 0.7), m, Vector3(0, 0, -8.5 * len_scale), Vector3(-PI / 2, 0, 0))
	_mi(g, _box(Vector3(13.0, 0.18, 3.2)), m, Vector3(0, -0.1, 0.5))
	_mi(g, _box(Vector3(5.0, 0.14, 1.6)), m, Vector3(0, 0.1, 5.8 * len_scale))
	_mi(g, _box(Vector3(0.15, 2.4, 2.4)), m, Vector3(0, 1.3, 5.6 * len_scale))
	var canopy := SphereMesh.new()
	canopy.radius = 0.6
	canopy.height = 1.0
	_mi(g, canopy, Mat.solid(Color(0.05, 0.08, 0.1), 0.05, 1.0), Vector3(0, 0.6, -4.5 * len_scale)).scale = Vector3(1, 0.8, 2.4)
	var burner := Effects.make_flash_sprite(3.5)
	burner.position.z = 7.6 * len_scale
	g.add_child(burner)
	return g


static func jet() -> Node3D:
	return _aircraft(1.0)


static func gunship() -> Node3D:
	var g := _aircraft(1.4)
	g.scale = Vector3.ONE * 1.3
	return g
