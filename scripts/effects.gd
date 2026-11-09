class_name Effects
extends Node3D
## Visual effects: pooled billboard particles (MultiMesh), tracers, decals, lights, casings, debris.

const SMOKE_CAP := 600
const GLOW_CAP := 600

static var tex := {}

var smoke_mm: MultiMesh
var glow_mm: MultiMesh
var smoke: Array = []     # particle dicts
var glow: Array = []
var tracers: Array = []
var ti := 0
var decals: Array = []
var di := 0
var lights: Array = []
var li := 0
var casings: Array = []
var ci := 0
var debris: Array = []
var dbi := 0
var shake := 0.0


# ------------------------------------------------------------------ procedural textures
static func _img_tex(size: int, f: Callable) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, f.call(float(x) / size * 2.0 - 1.0, float(y) / size * 2.0 - 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func textures() -> Dictionary:
	if not tex.is_empty():
		return tex
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	tex.glow = _img_tex(64, func(x, y):
		var d: float = clamp(1.0 - sqrt(x * x + y * y), 0.0, 1.0)
		return Color(1, 1, 1, d * d))
	tex.smoke = _img_tex(128, func(x, y):
		var d: float = clamp(1.0 - sqrt(x * x + y * y), 0.0, 1.0)
		var n: float = noise.get_noise_2d(x * 64.0, y * 64.0) * 0.5 + 0.5
		return Color(1, 1, 1, clamp(d * d * (0.4 + n * 1.1), 0.0, 1.0)))
	tex.flash = _img_tex(128, func(x, y):
		var r := sqrt(x * x + y * y)
		var a := atan2(y, x)
		var star: float = pow(abs(cos(a * 3.5)), 18.0) * clamp(1.0 - r, 0.0, 1.0)
		var core: float = clamp(1.0 - r * 2.6, 0.0, 1.0)
		var v: float = clamp(star * 1.4 + core, 0.0, 1.0)
		return Color(1.0, 0.85 + core * 0.15, 0.6 + core * 0.4, v))
	tex.hole = _img_tex(64, func(x, y):
		var r := sqrt(x * x + y * y)
		if r < 0.16:
			return Color(0.02, 0.02, 0.02, 1)
		if r < 0.32:
			return Color(0.08, 0.07, 0.06, 0.9)
		var n: float = noise.get_noise_2d(x * 40.0, y * 40.0)
		return Color(0.25, 0.23, 0.2, clamp((1.0 - r) * 0.7 + n * 0.3, 0.0, 1.0) * 0.6))
	tex.scorch = _img_tex(128, func(x, y):
		var r := sqrt(x * x + y * y)
		var n: float = noise.get_noise_2d(x * 30.0, y * 30.0)
		return Color(0.03, 0.025, 0.02, clamp((1.0 - r) * 1.4 + n * 0.5, 0.0, 0.92)))
	tex.blood = _img_tex(64, func(x, y):
		var r := sqrt(x * x + y * y)
		var n: float = noise.get_noise_2d(x * 22.0 + 5.0, y * 22.0)
		return Color(0.22, 0.01, 0.01, 1.0 if r + n * 0.7 < 0.55 else 0.0))
	return tex


static func make_flash_sprite(size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = textures().flash
	s.pixel_size = size / 128.0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.modulate = Color(1.6, 1.3, 0.9)
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.transparent = true
	s.no_depth_test = false
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = s.texture
	m.albedo_color = Color(1.6, 1.3, 0.9)
	s.material_override = m
	return s


# ------------------------------------------------------------------ setup
func _ready() -> void:
	textures()
	smoke_mm = _make_mm(SMOKE_CAP, tex.smoke, false)
	glow_mm = _make_mm(GLOW_CAP, tex.glow, true)
	var tm := BoxMesh.new()
	tm.size = Vector3(1, 1, 1)
	for i in 64:
		var t := MeshInstance3D.new()
		t.mesh = tm
		var m := Mat.unshaded(Color(1.0, 0.85, 0.55, 0.9), true)
		m.albedo_color = Color(4.0, 3.0, 1.6, 0.85)
		t.material_override = m
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		tracers.append({"n": t, "life": 0.0})
	for i in 160:
		var d := Decal.new()
		d.visible = false
		d.cull_mask = 1
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.normal_fade = 0.5
		add_child(d)
		decals.append(d)
	for i in 6:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.3)
		l.light_energy = 0.0
		l.omni_range = 18.0
		l.omni_attenuation = 1.4
		add_child(l)
		lights.append({"l": l, "life": 0.0, "e0": 0.0})
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0055
	cm.bottom_radius = 0.0055
	cm.height = 0.03
	cm.radial_segments = 6
	var brass := Mat.solid(Color(0.78, 0.6, 0.3), 0.3, 1.0)
	for i in 40:
		var c := MeshInstance3D.new()
		c.mesh = cm
		c.material_override = brass
		c.visible = false
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(c)
		casings.append({"n": c, "v": Vector3.ZERO, "spin": Vector3.ZERO, "life": 0.0})
	var dm := BoxMesh.new()
	dm.size = Vector3(0.09, 0.09, 0.09)
	var rock := Mat.world("concrete", Color(0.4, 0.38, 0.35), 1.0)
	for i in 60:
		var d := MeshInstance3D.new()
		d.mesh = dm
		d.material_override = rock
		d.visible = false
		add_child(d)
		debris.append({"n": d, "v": Vector3.ZERO, "life": 0.0})


func _make_mm(cap: int, t: Texture2D, additive: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.disable_receive_shadows = false
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 0.6
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-500, -50, -500), Vector3(1000, 300, 1000))
	add_child(mi)
	return mm


# ------------------------------------------------------------------ emitters
func particle(add: bool, pos: Vector3, vel: Vector3, size: float, grow: float, life: float, color: Color, grav := 0.0, drag := 1.5) -> void:
	var list := glow if add else smoke
	var cap := GLOW_CAP if add else SMOKE_CAP
	if list.size() >= cap:
		list.pop_front()
	list.append({"p": pos, "v": vel, "s0": size, "s1": grow, "life": life, "max": life, "c": color, "g": grav, "d": drag})


func tracer(from: Vector3, to: Vector3, color := Color(4.0, 3.0, 1.6, 0.85), width := 0.02, speed := 420.0) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var t: Dictionary = tracers[ti]
	ti = (ti + 1) % tracers.size()
	var n: MeshInstance3D = t.n
	(n.material_override as StandardMaterial3D).albedo_color = color
	t.from = from
	t.dir = (to - from) / len
	t.len = len
	t.seg = min(len, randf_range(3.0, 6.0))
	t.d = 0.0
	t.speed = speed
	t.w = width
	t.life = 1.0
	n.visible = true


func decal(pos: Vector3, normal: Vector3, kind := "hole", size := 0.1) -> void:
	var d: Decal = decals[di]
	di = (di + 1) % decals.size()
	d.texture_albedo = tex[kind]
	d.size = Vector3(size, 0.3, size)
	var up := normal.normalized()
	var ref := Vector3.RIGHT if abs(up.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	d.global_transform = Transform3D(Basis(x, up, z).rotated(up, randf() * TAU), pos)
	d.modulate = Color(1, 1, 1, 1)
	d.visible = true


func light(pos: Vector3, energy: float, life: float, color := Color(1.0, 0.6, 0.3), rng := 18.0) -> void:
	var l: Dictionary = lights[li]
	li = (li + 1) % lights.size()
	var o: OmniLight3D = l.l
	o.global_position = pos
	o.light_color = color
	o.omni_range = rng
	o.light_energy = energy
	l.life = life
	l.max = life
	l.e0 = energy


func impact(pos: Vector3, normal: Vector3, surface := "concrete") -> void:
	var dust: Color = {"metal": Color(0.45, 0.43, 0.4), "wood": Color(0.5, 0.4, 0.28), "ground": Color(0.5, 0.45, 0.38), "dirt": Color(0.5, 0.45, 0.35)}.get(surface, Color(0.62, 0.6, 0.56))
	for i in 3:
		particle(false, pos + normal * 0.05, normal * randf_range(0.6, 1.8) + Vector3(randf_range(-0.4, 0.4), randf_range(0, 0.6), randf_range(-0.4, 0.4)), 0.1, randf_range(0.5, 0.9), randf_range(0.6, 1.1), Color(dust, 0.55))
	var n := 7 if surface == "metal" else 3
	for i in n:
		particle(true, pos, normal * randf_range(2, 5) + Vector3(randf_range(-2.5, 2.5), randf_range(0, 3), randf_range(-2.5, 2.5)), 0.05, 0.01, randf_range(0.12, 0.3), Color(3.0, 1.6, 0.6, 1), 9.0, 0.5)
	decal(pos, normal, "hole", 0.13 if surface == "ground" else 0.09)


func blood(pos: Vector3, dir: Vector3, head: bool, space: PhysicsDirectSpaceState3D) -> void:
	for i in (7 if head else 4):
		particle(false, pos, dir * randf_range(0.8, 2.5) + Vector3(randf_range(-0.7, 0.7), randf_range(0, 1.2), randf_range(-0.7, 0.7)), 0.08, 0.45 if head else 0.32, randf_range(0.3, 0.6), Color(0.32, 0.02, 0.02, 0.9), 5.0)
	if space:
		var q := PhysicsRayQueryParameters3D.create(pos, pos + (dir + Vector3(0, -0.6, 0)).normalized() * 3.5, Defs.L_WORLD)
		var r := space.intersect_ray(q)
		if r:
			decal(r.position, r.normal, "blood", randf_range(0.5, 1.0))


func muzzle_smoke(pos: Vector3, dir: Vector3) -> void:
	particle(false, pos, dir * 1.0 + Vector3(0, 0.3, 0), 0.05, 0.3, 0.5, Color(0.8, 0.8, 0.8, 0.18))


func explosion(pos: Vector3, r := 6.0) -> void:
	var s := r / 6.0
	light(pos + Vector3.UP, 16.0 * s, 0.4, Color(1.0, 0.6, 0.3), 26.0 * s)
	particle(true, pos + Vector3(0, 0.6, 0), Vector3.ZERO, 2.0 * s, 8.0 * s, 0.18, Color(4.0, 3.2, 2.0, 1))
	for i in 18:
		var v := Vector3(randf_range(-1, 1) * 9, randf_range(1, 8), randf_range(-1, 1) * 9) * s
		particle(true, pos + Vector3(0, 0.5, 0), v, 1.0 * s, 3.4 * s, randf_range(0.35, 0.7), Color(3.5, 1.6, 0.5, 1) if i % 2 else Color(4.0, 2.4, 0.9, 1), 0.0, 3.5)
	for i in 22:
		var v := Vector3(randf_range(-1, 1) * 4, randf_range(1, 4), randf_range(-1, 1) * 4) * s
		var g := randf_range(0.16, 0.3)
		particle(false, pos + Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)), v, 2.0 * s, randf_range(6, 11) * s, randf_range(3.0, 6.0), Color(g, g * 0.95, g * 0.9, 0.85), 0.0, 1.2)
	for i in 14:
		var a := i / 14.0 * TAU
		particle(false, Vector3(pos.x, 0.4, pos.z), Vector3(cos(a), 0.05, sin(a)) * 10.0 * s, 1.2 * s, 4.5 * s, 1.6, Color(0.55, 0.5, 0.42, 0.55), 0.0, 2.5)
	for i in 22:
		particle(true, pos + Vector3(0, 0.5, 0), Vector3(randf_range(-11, 11), randf_range(2, 16), randf_range(-11, 11)), 0.1, 0.04, randf_range(0.6, 1.4), Color(3.0, 1.4, 0.4, 1), 14.0, 0.3)
	for i in 10:
		var d: Dictionary = debris[dbi]
		dbi = (dbi + 1) % debris.size()
		var n: MeshInstance3D = d.n
		n.global_position = pos + Vector3(0, 0.4, 0)
		n.scale = Vector3.ONE * randf_range(0.5, 2.0)
		d.v = Vector3(randf_range(-7, 7), randf_range(5, 15), randf_range(-7, 7))
		d.life = 3.0
		n.visible = true
	if pos.y < 1.2:
		decal(Vector3(pos.x, 0.0, pos.z), Vector3.UP, "scorch", r * 0.9)


func trail(pos: Vector3) -> void:
	particle(false, pos, Vector3(randf_range(-0.2, 0.2), randf_range(0.2, 0.6), randf_range(-0.2, 0.2)), 0.25, 1.4, 1.6, Color(0.7, 0.7, 0.7, 0.4), 0.0, 1.0)
	particle(true, pos, Vector3.ZERO, 0.4, 0.1, 0.06, Color(3.5, 2.0, 0.8, 1))


func casing(pos: Vector3, vel: Vector3) -> void:
	var c: Dictionary = casings[ci]
	ci = (ci + 1) % casings.size()
	var n: MeshInstance3D = c.n
	n.global_position = pos
	c.v = vel
	c.spin = Vector3(randf() * 30, randf() * 30, randf() * 30)
	c.life = 1.5
	n.visible = true


# ------------------------------------------------------------------ update
func _process(dt: float) -> void:
	_update_particles(smoke, smoke_mm, dt)
	_update_particles(glow, glow_mm, dt)
	for t in tracers:
		if t.life <= 0.0:
			continue
		var n: MeshInstance3D = t.n
		t.d += t.speed * dt
		if t.d > t.len:
			t.life = 0.0
			n.visible = false
			continue
		var tail: float = max(0.0, t.d - t.seg)
		var head: float = min(t.d, t.len)
		var mid: Vector3 = t.from + t.dir * (tail + head) * 0.5
		var length: float = max(0.01, head - tail)
		var up := Vector3.UP if abs(t.dir.y) < 0.99 else Vector3.RIGHT
		var basis := Basis.looking_at(t.dir, up)
		n.global_transform = Transform3D(basis.scaled(Vector3(t.w, t.w, length)), mid)
	for l in lights:
		if l.life > 0.0:
			l.life -= dt
			var o: OmniLight3D = l.l
			o.light_energy = max(0.0, l.e0 * (l.life / l.max))
	for c in casings:
		if c.life <= 0.0:
			continue
		var n: MeshInstance3D = c.n
		c.life -= dt
		if c.life <= 0.0:
			n.visible = false
			continue
		c.v.y -= 9.8 * dt
		n.global_position += c.v * dt
		if n.global_position.y < 0.01:
			n.global_position.y = 0.01
			c.v *= 0.4
			c.v.y = abs(c.v.y) * 0.5
			c.spin *= 0.5
		n.rotation += c.spin * dt
	for d in debris:
		if d.life <= 0.0:
			continue
		var n: MeshInstance3D = d.n
		d.life -= dt
		if d.life <= 0.0:
			n.visible = false
			continue
		d.v.y -= 15.0 * dt
		n.global_position += d.v * dt
		if n.global_position.y < 0.04:
			n.global_position.y = 0.04
			d.v *= 0.3
			d.v.y = abs(d.v.y) * 0.3
		n.rotation += Vector3(d.v.length(), d.v.x, 0) * dt
	shake = max(0.0, shake - dt * 2.2)


func _update_particles(list: Array, mm: MultiMesh, dt: float) -> void:
	var i := 0
	while i < list.size():
		var p: Dictionary = list[i]
		p.life -= dt
		if p.life <= 0.0:
			list.remove_at(i)
			continue
		p.v *= max(0.0, 1.0 - p.d * dt)
		p.v.y -= p.g * dt
		p.p += p.v * dt
		if p.p.y < 0.02:
			p.p.y = 0.02
			p.v.y *= -0.3
		i += 1
	var n: int = min(list.size(), mm.instance_count)
	for k in n:
		var p: Dictionary = list[k]
		var t: float = 1.0 - p.life / p.max
		var s: float = p.s0 + (p.s1 - p.s0) * (1.0 - (1.0 - t) * (1.0 - t))
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(s, s, s)), p.p))
		var c: Color = p.c
		c.a = p.c.a * (1.0 - t) * min(1.0, t * 20.0 + 0.2)
		mm.set_instance_color(k, c)
	mm.visible_instance_count = n
