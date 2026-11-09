class_name Mat
extends RefCounted
## Material factory. Loads CC0 PBR texture sets from res://assets/textures/<name>/
## (albedo / normal / roughness / ao / metallic). Falls back to plain colours if missing.

static var _cache := {}


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## World-space triplanar material for level geometry: no UVs needed, texture density is uniform.
## `scale` = texture repeats per metre.
static func world(name: String, tint := Color.WHITE, scale := 0.25, rough := 1.0, metal := 0.0) -> StandardMaterial3D:
	var key := "w:%s:%s:%s:%s:%s" % [name, tint.to_html(), scale, rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := pbr(name, tint, rough, metal)
	m = m.duplicate()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3.ONE * scale
	_cache[key] = m
	return m


## Regular UV-mapped PBR material.
static func pbr(name: String, tint := Color.WHITE, rough := 1.0, metal := 0.0, uv_scale := 1.0) -> StandardMaterial3D:
	var key := "p:%s:%s:%s:%s:%s" % [name, tint.to_html(), rough, metal, uv_scale]
	if _cache.has(key):
		return _cache[key]
	var base := "res://assets/textures/%s/" % name
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	var a := _tex(base + "albedo.jpg")
	if a:
		m.albedo_texture = a
	var n := _tex(base + "normal.jpg")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 1.0
	var r := _tex(base + "roughness.jpg")
	m.roughness = rough
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	var o := _tex(base + "ao.jpg")
	if o:
		m.ao_enabled = true
		m.ao_texture = o
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		m.ao_light_affect = 0.4
	var mt := _tex(base + "metallic.jpg")
	m.metallic = metal
	if mt and metal > 0.0:
		m.metallic_texture = mt
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if uv_scale != 1.0:
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	_cache[key] = m
	return m


static func solid(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var key := "s:%s:%s:%s" % [c.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m


static func emissive(c: Color, energy := 4.0) -> StandardMaterial3D:
	var key := "e:%s:%s" % [c.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


static func unshaded(c: Color, additive := false, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex:
		m.albedo_texture = tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
