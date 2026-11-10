extends Node
## Sound system (autoload `Sfx`). Gunshots, reloads, explosions and impacts are real recordings in
## res://assets/sounds/ (built by tools/make_sounds.py); everything else is synthesised at startup, and any
## missing recording falls back to its synthesised version. Drop <name>.wav|.ogg there to override a sound.

const RATE := 22050
var streams := {}
var pool2d: Array[AudioStreamPlayer] = []
var pool3d: Array[AudioStreamPlayer3D] = []
var i2 := 0
var i3 := 0
var ready_ok := false
var _ambience: AudioStreamPlayer
var _synth := {}   ## names that are synthesised (no recording found)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool2d.append(p)
	for i in 48:
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.unit_size = 6.0
		p.max_distance = 220.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		pool3d.append(p)
	_generate()
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "SFX"
	_ambience.stream = streams.get("ambience")
	_ambience.volume_db = -14.0
	add_child(_ambience)
	ready_ok = true


func start_ambience() -> void:
	if not _ambience.playing:
		_ambience.play()


func _setup_buses() -> void:
	if AudioServer.get_bus_index("SFX") != -1:
		return
	AudioServer.add_bus()
	var sfx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(sfx, "SFX")
	AudioServer.set_bus_send(sfx, "Master")
	AudioServer.add_bus()
	var world := AudioServer.bus_count - 1
	AudioServer.set_bus_name(world, "World")
	AudioServer.set_bus_send(world, "SFX")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.55
	rev.damping = 0.6
	rev.spread = 0.8
	rev.wet = 0.18
	rev.dry = 1.0
	rev.predelay_msec = 40.0
	AudioServer.add_bus_effect(world, rev)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 5.0
	comp.attack_us = 200.0
	comp.release_ms = 200.0
	AudioServer.add_bus_effect(sfx, comp)
	var lim := AudioEffectHardLimiter.new()
	AudioServer.add_bus_effect(sfx, lim)


func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(max(v, 0.0001)))


# ------------------------------------------------------------------ playback
func play(name: String, vol_db := 0.0, pitch := 1.0, var_pitch := 0.06) -> void:
	var s: AudioStream = streams.get(name)
	if s == null:
		return
	var p := pool2d[i2]
	i2 = (i2 + 1) % pool2d.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch * (1.0 + randf_range(-var_pitch, var_pitch))
	p.play()


## Weapon shot. Every gun has its own recording (assets/sounds/<id>.ogg, see tools/make_sounds.py);
## guns without one fall back to the closest synthesised voice at a different pitch. Shots further than
## FAR_DIST use the mid-distance recording (<id>_far) when there is one. Suppressed = quiet & thin.
const GUN_VOICE := {"m9": ["pistol", 1.05], "m1911": ["pistol", 0.82], "ak47": ["ar", 0.88], "l85": ["ar", 1.08],
	"g3a3": ["lmg", 0.92], "scar": ["ar", 0.9], "mosin": ["dmr", 0.9], "svd": ["dmr", 1.08], "mg250": ["lmg", 0.95]}
const FAR_DIST := 35.0

func play_gun(id: String, pos = null, quiet := false) -> void:
	var name := id
	var pitch := 1.0
	if not streams.has(id):
		var v: Array = GUN_VOICE.get(id, ["ar", 1.0])
		name = v[0]
		pitch = v[1]
	if pos != null and not quiet and streams.has(name + "_far"):
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(pos) > FAR_DIST:
			name += "_far"
	var vol := -16.0 if quiet else (0.0 if pos != null else -1.0)
	if quiet:
		pitch *= 1.6 if _synth.has(name) else 1.3
	if pos == null:
		play(name, vol, pitch, 0.04)
	else:
		play_at(name, pos, vol, pitch)


func play_at(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, max_dist := 220.0) -> void:
	var s: AudioStream = streams.get(name)
	if s == null:
		return
	var p := pool3d[i3]
	i3 = (i3 + 1) % pool3d.size()
	if not p.is_inside_tree():
		return
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.max_distance = max_dist
	p.pitch_scale = pitch * (1.0 + randf_range(-0.05, 0.05))
	p.play()


# ------------------------------------------------------------------ synthesis helpers
class Buf:
	var d: PackedFloat32Array
	func _init(seconds: float) -> void:
		d = PackedFloat32Array()
		d.resize(int(seconds * 22050))


func _noise_burst(b: Buf, t0: float, dur: float, gain: float, lp := 1.0, hp := 0.0, attack := 0.002, decay_pow := 1.0, brown := false) -> void:
	# One-pole filtered noise with an exponential-ish envelope.
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var y_lp := 0.0
	var y_hp := 0.0
	var prev := 0.0
	var br := 0.0
	var a_lp: float = clamp(lp, 0.0, 1.0)
	for i in n:
		var k := start + i
		if k >= b.d.size():
			break
		var t := float(i) / RATE
		var env: float = min(1.0, t / attack) * pow(1.0 - float(i) / n, decay_pow * 3.0)
		var x := randf() * 2.0 - 1.0
		if brown:
			br = (br + 0.02 * x) / 1.02
			x = br * 3.5
		y_lp += a_lp * (x - y_lp)
		var v := y_lp
		if hp > 0.0:
			y_hp = hp * (y_hp + v - prev)
			prev = v
			v = y_hp
		b.d[k] += v * env * gain


func _tone(b: Buf, t0: float, dur: float, f0: float, f1: float, gain: float, wave := "sine", attack := 0.003) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var ph := 0.0
	for i in n:
		var k := start + i
		if k >= b.d.size():
			break
		var t := float(i) / RATE
		var f := f0 * pow(f1 / f0, float(i) / n)
		ph += f / RATE
		var s := 0.0
		match wave:
			"sine": s = sin(ph * TAU)
			"square": s = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"tri": s = abs(fmod(ph, 1.0) * 4.0 - 2.0) - 1.0
			"saw": s = fmod(ph, 1.0) * 2.0 - 1.0
		var env: float = min(1.0, t / attack) * pow(1.0 - float(i) / n, 2.0)
		b.d[k] += s * env * gain


func _stream(b: Buf, loop := false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in b.d:
		peak = max(peak, abs(v))
	var norm: float = min(1.0, 0.95 / peak)
	var bytes := PackedByteArray()
	bytes.resize(b.d.size() * 2)
	for i in b.d.size():
		bytes.encode_s16(i * 2, int(clamp(b.d[i] * norm, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = b.d.size()
	return w


func _gun(crack_lp: float, body_lp: float, boom: float, length: float, tail := 0.5) -> AudioStreamWAV:
	var b := Buf.new(length + tail)
	_noise_burst(b, 0.0, 0.035, 1.0, 1.0, 0.7)                   # supersonic crack
	_noise_burst(b, 0.0, length, 0.9, crack_lp)                    # muzzle blast
	_noise_burst(b, 0.0, length * 1.6, 0.8, body_lp, 0.0, 0.002, 0.6, true)
	_tone(b, 0.0, length * 0.8, boom * 2.0, boom * 0.55, 0.9)     # low thump
	_noise_burst(b, 0.04, length + tail - 0.05, 0.12, 0.08, 0.0, 0.02, 0.4, true)   # outdoor tail
	return _stream(b)


func _generate() -> void:
	var t0 := Time.get_ticks_msec()
	var defs := {
		"pistol": func(): return _gun(0.55, 0.15, 150, 0.16),
		"smg": func(): return _gun(0.6, 0.18, 140, 0.12),
		"shotgun": func(): return _gun(0.35, 0.08, 70, 0.4, 0.7),
		"ar": func(): return _gun(0.5, 0.12, 105, 0.2),
		"dmr": func(): return _gun(0.45, 0.09, 80, 0.42, 0.8),
		"lmg": func(): return _gun(0.48, 0.11, 92, 0.24),
		"launcher": func(): return _gun(0.2, 0.05, 55, 0.6, 0.6),
		"turret": func(): return _gun(0.6, 0.18, 130, 0.12),
		"gunship": func(): return _gun(0.25, 0.06, 50, 0.35, 0.8),
		"enemy_rifle": func(): return _gun(0.45, 0.12, 100, 0.2),
		"enemy_shotgun": func(): return _gun(0.32, 0.08, 72, 0.38, 0.6),
		"enemy_lmg": func(): return _gun(0.45, 0.1, 88, 0.24),
		"hit": func():
			var b := Buf.new(0.08)
			_noise_burst(b, 0, 0.035, 0.7, 0.9, 0.85)
			_tone(b, 0, 0.05, 1900, 1500, 0.35, "square")
			return _stream(b),
		"hit_head": func():
			var b := Buf.new(0.3)
			_noise_burst(b, 0, 0.035, 0.6, 0.9, 0.85)
			_tone(b, 0, 0.25, 3600, 3400, 0.4, "tri")
			_tone(b, 0, 0.18, 5400, 5300, 0.15)
			return _stream(b),
		"kill": func():
			var b := Buf.new(0.2)
			_noise_burst(b, 0, 0.05, 0.6, 0.7, 0.6)
			_tone(b, 0, 0.14, 180, 70, 0.9)
			_tone(b, 0.01, 0.06, 1400, 1100, 0.3, "square")
			return _stream(b),
		"kill_head": func():
			var b := Buf.new(0.45)
			_noise_burst(b, 0, 0.05, 0.6, 0.7, 0.6)
			_tone(b, 0, 0.14, 180, 70, 0.9)
			_tone(b, 0, 0.4, 3000, 2900, 0.35, "tri")
			_tone(b, 0.06, 0.35, 4500, 4400, 0.2, "tri")
			return _stream(b),
		"impact": func():
			var b := Buf.new(0.12)
			_noise_burst(b, 0, 0.06, 0.6, 0.8, 0.5)
			return _stream(b),
		"impact_metal": func():
			var b := Buf.new(0.35)
			_noise_burst(b, 0, 0.04, 0.5, 0.9, 0.6)
			_tone(b, 0, 0.3, 2600, 1900, 0.25, "sine")
			_tone(b, 0, 0.25, 4100, 3700, 0.12, "sine")
			return _stream(b),
		"impact_flesh": func():
			var b := Buf.new(0.12)
			_noise_burst(b, 0, 0.09, 0.8, 0.12)
			_tone(b, 0, 0.08, 160, 90, 0.4)
			return _stream(b),
		"whiz": func():
			var b := Buf.new(0.2)
			_noise_burst(b, 0, 0.18, 0.6, 0.5, 0.7, 0.05, 0.5)
			return _stream(b),
		"hurt": func():
			var b := Buf.new(0.25)
			_tone(b, 0, 0.2, 110, 50, 0.8)
			_noise_burst(b, 0, 0.15, 0.6, 0.08)
			return _stream(b),
		"heartbeat": func():
			var b := Buf.new(0.4)
			_tone(b, 0, 0.12, 60, 40, 0.8)
			_tone(b, 0.18, 0.12, 55, 38, 0.6)
			return _stream(b),
		"explosion": func():
			var b := Buf.new(2.6)
			_noise_burst(b, 0, 0.09, 1.0, 0.8, 0.3)
			_noise_burst(b, 0, 1.8, 1.0, 0.06, 0.0, 0.004, 0.5, true)
			_noise_burst(b, 0, 0.9, 0.6, 0.25)
			_tone(b, 0, 1.0, 70, 25, 1.0)
			for i in 8:
				_noise_burst(b, randf_range(0.3, 1.6), 0.04, 0.12, 0.7, 0.5)
			return _stream(b),
		"jet": func():
			var b := Buf.new(3.4)
			_noise_burst(b, 0, 3.3, 1.0, 0.12, 0.0, 0.6, 0.35, true)
			_noise_burst(b, 0, 3.0, 0.3, 0.6, 0.6, 0.8, 0.5)
			return _stream(b),
		"dry": func():
			var b := Buf.new(0.05)
			_noise_burst(b, 0, 0.03, 0.4, 0.9, 0.8)
			return _stream(b),
		"mag_out": func():
			var b := Buf.new(0.12)
			_noise_burst(b, 0, 0.06, 0.5, 0.6, 0.5)
			_tone(b, 0, 0.05, 400, 300, 0.2, "square")
			return _stream(b),
		"mag_in": func():
			var b := Buf.new(0.15)
			_noise_burst(b, 0, 0.05, 0.6, 0.8, 0.6)
			_noise_burst(b, 0.05, 0.04, 0.5, 0.5, 0.5)
			return _stream(b),
		"bolt": func():
			var b := Buf.new(0.18)
			_noise_burst(b, 0, 0.04, 0.6, 0.95, 0.7)
			_noise_burst(b, 0.08, 0.05, 0.7, 0.8, 0.6)
			return _stream(b),
		"pump": func():
			var b := Buf.new(0.25)
			_noise_burst(b, 0, 0.05, 0.6, 0.5, 0.4)
			_noise_burst(b, 0.12, 0.06, 0.7, 0.4, 0.4)
			return _stream(b),
		"swap": func():
			var b := Buf.new(0.18)
			_noise_burst(b, 0, 0.08, 0.3, 0.3)
			_noise_burst(b, 0.1, 0.03, 0.4, 0.9, 0.6)
			return _stream(b),
		"casing": func():
			var b := Buf.new(0.2)
			_tone(b, 0, 0.08, 5200, 4800, 0.15, "tri")
			_tone(b, 0.09, 0.06, 4900, 4500, 0.08, "tri")
			return _stream(b),
		"step": func():
			var b := Buf.new(0.1)
			_noise_burst(b, 0, 0.07, 0.6, 0.2)
			_noise_burst(b, 0.01, 0.05, 0.15, 0.8, 0.6)
			return _stream(b),
		"land": func():
			var b := Buf.new(0.15)
			_noise_burst(b, 0, 0.12, 0.8, 0.12)
			return _stream(b),
		"melee": func():
			var b := Buf.new(0.16)
			_noise_burst(b, 0, 0.15, 0.6, 0.4, 0.3, 0.03)
			return _stream(b),
		"stab": func():
			var b := Buf.new(0.12)
			_noise_burst(b, 0, 0.1, 0.9, 0.3)
			_tone(b, 0, 0.1, 150, 60, 0.5)
			return _stream(b),
		"money": func():
			var b := Buf.new(0.3)
			_tone(b, 0, 0.08, 1568, 1568, 0.3, "tri")
			_tone(b, 0.07, 0.2, 2093, 2093, 0.3, "tri")
			return _stream(b),
		"buy": func():
			var b := Buf.new(0.45)
			_noise_burst(b, 0, 0.06, 0.4, 0.7, 0.5)
			for i in 3:
				_tone(b, 0.05 + i * 0.06, 0.25, [1318.0, 1760.0, 2637.0][i], [1318.0, 1760.0, 2637.0][i], 0.25, "tri")
			return _stream(b),
		"deny": func():
			var b := Buf.new(0.4)
			_tone(b, 0, 0.15, 220, 200, 0.3, "square")
			_tone(b, 0.16, 0.2, 180, 160, 0.3, "square")
			return _stream(b),
		"ui": func():
			var b := Buf.new(0.05)
			_tone(b, 0, 0.04, 1200, 1100, 0.3, "tri")
			return _stream(b),
		"radio": func():
			var b := Buf.new(0.6)
			_noise_burst(b, 0, 0.25, 0.4, 0.5, 0.6)
			_tone(b, 0.25, 0.12, 1000, 1000, 0.25, "square")
			_tone(b, 0.4, 0.12, 1400, 1400, 0.25, "square")
			return _stream(b),
		"wave_start": func():
			var b := Buf.new(2.4)
			for f in [55.0, 82.4, 110.0]:
				_tone(b, 0, 2.2, f, f * 0.97, 0.25, "saw", 0.05)
			for i in 3:
				_tone(b, i * 0.35, 0.4, 90, 40, 0.8)
				_noise_burst(b, i * 0.35, 0.2, 0.5, 0.08, 0.0, 0.002, 1.0, true)
			return _stream(b),
		"wave_end": func():
			var b := Buf.new(1.6)
			var notes := [261.6, 329.6, 392.0, 523.2]
			for i in 4:
				_tone(b, i * 0.12, 1.2, notes[i], notes[i], 0.25, "tri", 0.01)
			return _stream(b),
		"unlock": func():
			var b := Buf.new(0.9)
			var notes := [659.0, 880.0, 1175.0, 1568.0]
			for i in 4:
				_tone(b, i * 0.08, 0.5, notes[i], notes[i], 0.2)
			return _stream(b),
		"beep": func():
			var b := Buf.new(0.1)
			_tone(b, 0, 0.08, 2400, 2400, 0.3, "square")
			return _stream(b),
		# ---- surface footsteps (step_<surface>)
		"step_tile": func():
			var b := Buf.new(0.09)
			_noise_burst(b, 0, 0.025, 0.7, 0.9, 0.5)
			_noise_burst(b, 0.005, 0.06, 0.4, 0.25)
			_tone(b, 0, 0.03, 1900, 1500, 0.08, "tri")
			return _stream(b),
		"step_grass": func():
			var b := Buf.new(0.16)
			_noise_burst(b, 0, 0.13, 0.5, 0.55, 0.3, 0.03, 0.6)
			_noise_burst(b, 0.02, 0.08, 0.3, 0.12)
			return _stream(b),
		"step_metal": func():
			var b := Buf.new(0.25)
			_noise_burst(b, 0, 0.03, 0.6, 0.8, 0.4)
			_tone(b, 0, 0.22, 420, 400, 0.25, "tri")
			_tone(b, 0, 0.18, 1130, 1100, 0.12)
			return _stream(b),
		"step_wood": func():
			var b := Buf.new(0.12)
			_noise_burst(b, 0, 0.05, 0.6, 0.3)
			_tone(b, 0, 0.08, 220, 160, 0.35)
			return _stream(b),
		"step_gravel": func():
			var b := Buf.new(0.16)
			for i in 9:
				_noise_burst(b, randf_range(0.0, 0.08), 0.02, randf_range(0.2, 0.5), 0.85, 0.5)
			_noise_burst(b, 0, 0.1, 0.4, 0.15)
			return _stream(b),
		"step_glass": func():
			var b := Buf.new(0.2)
			for i in 6:
				_tone(b, randf_range(0, 0.06), 0.06, randf_range(3500, 6500), 3000, 0.1, "tri")
			_noise_burst(b, 0, 0.06, 0.4, 0.3)
			return _stream(b),
		# ---- new threats & world
		"rotor": func():
			var b := Buf.new(2.0)
			for i in 40:                                             # 20 Hz blade slap
				_noise_burst(b, i * 0.05, 0.045, 1.0, 0.12, 0.0, 0.004, 0.8, true)
				_tone(b, i * 0.05, 0.04, 55, 40, 0.5)
			_noise_burst(b, 0, 2.0, 0.25, 0.5, 0.3, 0.2, 0.0)          # turbine hiss
			return _stream(b, true),
		"bite": func():
			var b := Buf.new(0.35)
			_tone(b, 0, 0.25, 180, 120, 0.6, "saw", 0.01)              # growl
			_noise_burst(b, 0, 0.25, 0.5, 0.3, 0.0, 0.02, 0.6)
			_noise_burst(b, 0.22, 0.05, 0.7, 0.9, 0.4)                  # snap
			return _stream(b),
		"laser": func():
			var b := Buf.new(0.5)
			for i in 3:
				_tone(b, i * 0.14, 0.09, 2400, 2400, 0.35, "square")
			return _stream(b),
		"engine": func():
			var b := Buf.new(3.2)
			_tone(b, 0, 3.1, 48, 36, 0.6, "saw", 0.4)
			_noise_burst(b, 0, 3.1, 0.6, 0.06, 0.0, 0.5, 0.3, true)
			_tone(b, 2.4, 0.6, 120, 60, 0.4, "saw")                      # brakes / idle down
			return _stream(b),
		"door": func():
			var b := Buf.new(0.35)
			_noise_burst(b, 0, 0.05, 1.0, 0.3)
			_tone(b, 0, 0.3, 90, 60, 0.8)
			_noise_burst(b, 0.01, 0.12, 0.3, 0.7, 0.5)
			return _stream(b),
		"power_down": func():
			var b := Buf.new(1.6)
			_tone(b, 0, 1.5, 240, 35, 0.6, "saw", 0.01)
			_noise_burst(b, 0, 0.08, 0.8, 0.9, 0.5)                      # breaker clunk
			_tone(b, 0, 0.12, 90, 50, 0.8)
			return _stream(b),
		"glass": func():
			var b := Buf.new(1.0)
			_noise_burst(b, 0, 0.06, 1.0, 0.95, 0.4)
			for i in 30:
				_tone(b, randf_range(0.0, 0.6), randf_range(0.05, 0.2), randf_range(2500, 7500), randf_range(2000, 6000), randf_range(0.05, 0.2), "tri")
			_noise_burst(b, 0.05, 0.7, 0.3, 0.8, 0.6, 0.02, 0.8)
			return _stream(b),
		"breath_in": func():
			var b := Buf.new(0.6)
			_noise_burst(b, 0, 0.55, 0.5, 0.35, 0.2, 0.25, 0.3)
			return _stream(b),
		"breath_out": func():
			var b := Buf.new(0.9)
			_noise_burst(b, 0, 0.85, 0.5, 0.25, 0.15, 0.02, 0.6)
			return _stream(b),
		"shield_ping": func():
			var b := Buf.new(0.3)
			_noise_burst(b, 0, 0.02, 0.8, 0.95, 0.6)
			_tone(b, 0, 0.25, 2100, 1900, 0.35, "tri")
			_tone(b, 0, 0.2, 3300, 3200, 0.15)
			return _stream(b),
		"ambience": func():
			var b := Buf.new(6.0)
			_noise_burst(b, 0, 6.0, 0.5, 0.05, 0.0, 1.5, 0.0, true)
			# fade loop seam
			var n := b.d.size()
			for i in 2000:
				var k := float(i) / 2000.0
				b.d[i] *= k
				b.d[n - 1 - i] *= k
			return _stream(b, true),
	}
	for name in defs:
		var custom := _custom(name)
		if custom:
			streams[name] = custom
		else:
			streams[name] = defs[name].call()
			_synth[name] = true
	# recordings with no synthesised counterpart: per-weapon shots and distant variants
	for name in GUN_VOICE.keys() + defs.keys():
		for n in [name, name + "_far"]:
			if not streams.has(n):
				var custom := _custom(n)
				if custom:
					streams[n] = custom
	print("[Sfx] generated %d sounds in %d ms" % [streams.size(), Time.get_ticks_msec() - t0])


func _custom(name: String) -> AudioStream:
	for ext in ["wav", "ogg", "mp3"]:
		var p := "res://assets/sounds/%s.%s" % [name, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null
