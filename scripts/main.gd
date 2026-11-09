extends Node
## Entry point: menus, session start (singleplayer / host / join / dedicated), pause and game over.

var game: Game
var hud: Hud
var view_layer: CanvasLayer
var ui: CanvasLayer
var menu: Control
var pause_menu: Control
var over_menu: Control
var loading: Control
var name_edit: LineEdit
var addr_edit: LineEdit
var port_edit: LineEdit
var status_lbl: Label
var quality_opt: OptionButton
var font: SystemFont
var font_bold: SystemFont
var autotest_t := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_inputs()
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Roboto Condensed", "Arial Narrow", "DejaVu Sans Condensed", "sans-serif"])
	font_bold = font.duplicate()
	font_bold.font_weight = 700
	view_layer = CanvasLayer.new()
	view_layer.name = "ViewLayer"
	view_layer.layer = 0
	add_child(view_layer)
	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	Sfx.set_volume(float(Settings.get_val("volume", 0.8)))
	_apply_window_settings()

	if Net.is_dedicated():
		_start_dedicated()
		return
	_build_menu()
	_build_pause()
	_build_over()
	Net.connected.connect(_on_connected)
	Net.failed.connect(func(msg): _set_status(msg, true); _show_menu())
	Net.disconnected.connect(func(): _end_session(); _set_status("Disconnected from server", true))
	if Net.args.has("autotest"):
		autotest_t = float(Net.args.get("autotest", 30)) if str(Net.args.autotest) != "true" else 30.0
	if Net.args.has("join"):
		name_edit.text = Net.player_name
		_join(str(Net.args.join), Net.port)
	elif Net.args.has("autotest") or Net.args.has("shots"):
		_start_sp()


func _register_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "reload": [KEY_R], "weapon1": [KEY_1], "weapon2": [KEY_2],
		"frag": [KEY_G], "melee": [KEY_V], "interact": [KEY_E], "ready": [KEY_F], "mine": [KEY_4], "turret": [KEY_5],
		"strike": [KEY_6], "drone": [KEY_7], "carpet": [KEY_8], "scoreboard": [KEY_TAB], "pause": [KEY_ESCAPE, KEY_P], "fullscreen": [KEY_F11],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var m := InputEventMouseButton.new()
		m.button_index = pair[1]
		InputMap.action_add_event(pair[0], m)


func _apply_window_settings() -> void:
	var q := int(Settings.get_val("quality", 2))
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if q <= 1 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 0.67 if q == 0 else 0.77 if q == 1 else 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED if q <= 1 else Viewport.MSAA_2X
	vp.use_taa = q == 3
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(8192 if q >= 2 else 4096, true)


# ======================================================================= UI building
func _style_btn(b: Button, primary := false) -> void:
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(0, 52)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(1.0, 0.54, 0.16) if primary else Color(0.14, 0.15, 0.17)
	n.border_color = Color(1.0, 0.54, 0.16) if primary else Color(0.25, 0.27, 0.3)
	n.set_border_width_all(1)
	var h := n.duplicate()
	h.bg_color = Color(1.0, 0.64, 0.32) if primary else Color(0.2, 0.21, 0.24)
	h.border_color = Color(1.0, 0.54, 0.16)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.07, 0.07, 0.07) if primary else Color(0.92, 0.9, 0.86))
	b.add_theme_color_override("font_hover_color", Color(0.07, 0.07, 0.07) if primary else Color.WHITE)


func _lbl(parent: Node, text: String, size: int, color := Color(0.85, 0.83, 0.8), bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _screen(dark := 0.85) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.035, 0.04, dark)
	root.add_child(bg)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.062, 0.07, 0.95)
	sb.border_color = Color(1.0, 0.54, 0.16)
	sb.border_width_top = 3
	sb.content_margin_left = 36
	sb.content_margin_right = 36
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 30
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	panel.resized.connect(func(): panel.position = (root.size - panel.size) / 2.0)
	root.resized.connect(func(): panel.position = (root.size - panel.size) / 2.0)
	ui.add_child(root)
	return [root, v]


func _row(parent: Node, label: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := _lbl(h, label, 18)
	l.custom_minimum_size.x = 200
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)


func _slider(key: String, mn: float, mx: float, step: float, def: float, cb: Callable = Callable()) -> HSlider:
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.get_val(key, def))
	s.custom_minimum_size.y = 28
	s.value_changed.connect(func(v):
		Settings.set_val(key, v)
		if cb.is_valid(): cb.call(v))
	return s


func _build_menu() -> void:
	var r := _screen(1.0)
	menu = r[0]
	var v: VBoxContainer = r[1]
	var bg: ColorRect = menu.get_child(0)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item; void fragment(){ vec2 p = UV - vec2(0.3, 0.2); float g = 1.0 - smoothstep(0.0, 1.0, length(p)); COLOR = vec4(mix(vec3(0.03,0.035,0.04), vec3(0.28,0.22,0.14), g*0.6), 1.0); }"
	var m := ShaderMaterial.new()
	m.shader = sh
	bg.material = m
	_lbl(v, "MODERN", 64, Color(0.95, 0.9, 0.78), true)
	_lbl(v, "S U R V I V A L", 40, Color(1.0, 0.54, 0.16), true)
	_lbl(v, "Hold the yard. Survive the waves. Spend wisely.", 18, Color(0.6, 0.6, 0.6))
	name_edit = LineEdit.new()
	name_edit.text = str(Settings.get_val("name", "Soldier"))
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(t): Settings.set_val("name", t))
	_row(v, "Callsign", name_edit)
	var b1 := Button.new()
	b1.text = "SINGLEPLAYER"
	_style_btn(b1, true)
	b1.pressed.connect(_start_sp)
	v.add_child(b1)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	var b2 := Button.new()
	b2.text = "HOST CO-OP"
	_style_btn(b2)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b2.pressed.connect(_host)
	hb.add_child(b2)
	var b3 := Button.new()
	b3.text = "JOIN"
	_style_btn(b3)
	b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b3.pressed.connect(func(): _join(addr_edit.text.strip_edges(), int(port_edit.text)))
	hb.add_child(b3)
	addr_edit = LineEdit.new()
	addr_edit.text = str(Settings.get_val("addr", "127.0.0.1"))
	addr_edit.placeholder_text = "Server IP or hostname"
	addr_edit.text_changed.connect(func(t): Settings.set_val("addr", t))
	_row(v, "Server address", addr_edit)
	port_edit = LineEdit.new()
	port_edit.text = str(Settings.get_val("port", Defs.DEFAULT_PORT))
	port_edit.text_changed.connect(func(t): Settings.set_val("port", int(t)))
	_row(v, "Port", port_edit)
	quality_opt = OptionButton.new()
	for q in ["Low", "Medium", "High", "Ultra"]:
		quality_opt.add_item(q)
	quality_opt.selected = int(Settings.get_val("quality", 2))
	quality_opt.item_selected.connect(func(i): Settings.set_val("quality", i); _apply_window_settings())
	_row(v, "Graphics", quality_opt)
	_row(v, "Mouse sensitivity", _slider("sens", 0.2, 3.0, 0.05, 1.0))
	_row(v, "Field of view", _slider("fov", 60, 100, 1, 78))
	_row(v, "Volume", _slider("volume", 0, 1, 0.05, 0.8, func(x): Sfx.set_volume(x)))
	status_lbl = _lbl(v, "", 16, Color(0.6, 0.85, 0.6))
	var keys := _lbl(v, "WASD move · Shift sprint · Space jump · C crouch · LMB fire · RMB aim · R reload · 1/2 weapons\nG frag · V melee · E armory/revive · F ready · 4 claymore · 5 sentry · 6 airstrike · 7 gunship · 8 carpet · Tab squad", 14, Color(0.55, 0.55, 0.55))
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD
	var q := Button.new()
	q.text = "QUIT"
	_style_btn(q)
	q.pressed.connect(func(): get_tree().quit())
	v.add_child(q)


func _build_pause() -> void:
	var r := _screen(0.6)
	pause_menu = r[0]
	var v: VBoxContainer = r[1]
	v.custom_minimum_size.x = 420
	_lbl(v, "PAUSED", 40, Color(0.95, 0.9, 0.78), true)
	var b := Button.new()
	b.text = "RESUME"
	_style_btn(b, true)
	b.pressed.connect(_resume)
	v.add_child(b)
	_row(v, "Mouse sensitivity", _slider("sens", 0.2, 3.0, 0.05, 1.0, func(x): _live_setting("sens", x)))
	_row(v, "Field of view", _slider("fov", 60, 100, 1, 78, func(x): _live_setting("fov", x)))
	_row(v, "Volume", _slider("volume", 0, 1, 0.05, 0.8, func(x): Sfx.set_volume(x)))
	var q := Button.new()
	q.text = "QUIT TO MENU"
	_style_btn(q)
	q.pressed.connect(func(): _end_session(); _show_menu())
	v.add_child(q)
	pause_menu.visible = false


func _build_over() -> void:
	var r := _screen(0.65)
	over_menu = r[0]
	var v: VBoxContainer = r[1]
	_lbl(v, "MISSION FAILED", 56, Color(1.0, 0.3, 0.22), true)
	_lbl(v, "", 24, Color(0.9, 0.88, 0.84)).name = "Sub"
	var g := GridContainer.new()
	g.name = "Stats"
	g.columns = 5
	g.add_theme_constant_override("h_separation", 30)
	v.add_child(g)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	var b := Button.new()
	b.text = "PLAY AGAIN"
	_style_btn(b, true)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func():
		over_menu.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if game: game.send({"t": "restart"}))
	hb.add_child(b)
	var q := Button.new()
	q.text = "MENU"
	_style_btn(q)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.pressed.connect(func(): _end_session(); _show_menu())
	hb.add_child(q)
	over_menu.visible = false


func _live_setting(key: String, v: float) -> void:
	if game:
		var lp: Player = game.player_nodes.get(game.local_id)
		if lp and lp.is_local:
			if key == "sens":
				lp.sens = v
			else:
				lp.fov = v


func _set_status(msg: String, err := false) -> void:
	if status_lbl:
		status_lbl.text = msg
		status_lbl.add_theme_color_override("font_color", Color(1, 0.45, 0.4) if err else Color(0.6, 0.85, 0.6))


func _show_menu() -> void:
	menu.visible = true
	pause_menu.visible = false
	over_menu.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ======================================================================= sessions
func _player_name() -> String:
	var n := name_edit.text.strip_edges() if name_edit else Net.player_name
	return n if n != "" else "Soldier"


func _start_sp() -> void:
	Net.start_sp()
	_start_game()
	game.send({"t": "join", "name": _player_name()})


func _host() -> void:
	var p := int(port_edit.text) if port_edit else Defs.DEFAULT_PORT
	var err := Net.host(p)
	if err != OK:
		_set_status("Could not host on port %d (error %d)" % [p, err], true)
		return
	_start_game()
	game.send({"t": "join", "name": _player_name()})
	game.hud.feed("Hosting on port %d — friends join with your IP" % p)


func _join(addr: String, p: int) -> void:
	if addr == "":
		_set_status("Enter a server address", true)
		return
	var err := Net.join(addr, p)
	if err != OK:
		_set_status("Could not connect (error %d)" % err, true)
		return
	_set_status("Connecting to %s:%d…" % [addr, p])


func _on_connected() -> void:
	_start_game()
	game.send({"t": "join", "name": _player_name()})


func _start_dedicated() -> void:
	var err := Net.dedicated(Net.port)
	if err != OK:
		printerr("Failed to start server on port %d (error %d)" % [Net.port, err])
		get_tree().quit(1)
		return
	game = Game.new()
	game.name = "Game"
	add_child(game)
	game.setup(0)
	multiplayer.peer_connected.connect(func(id): print("[+] peer %d connected (%d online)" % [id, multiplayer.get_peers().size()]))
	multiplayer.peer_disconnected.connect(func(id):
		print("[-] peer %d left" % id)
		if multiplayer.get_peers().is_empty():
			game.reset())
	print("Modern Survival dedicated server listening on UDP port %d (max %d players)" % [Net.port, Defs.MAX_PLAYERS])
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127."):
			print("  LAN address: %s:%d" % [a, Net.port])


func _start_game() -> void:
	if game:
		_end_session(false)
	menu.visible = false
	game = Game.new()
	game.name = "Game"
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(game)
	hud = Hud.new()
	hud.game = game
	game.hud = hud
	ui.add_child(hud)
	ui.move_child(hud, 0)
	game.setup(int(Settings.get_val("quality", 2)))
	game.game_over.connect(_on_game_over)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_session(leave := true) -> void:
	get_tree().paused = false
	if game:
		game.queue_free()
		game = null
	if hud:
		hud.queue_free()
		hud = null
	if leave:
		Net.leave()


func _on_game_over(stats: Array, wave: int) -> void:
	over_menu.visible = true
	(over_menu.find_child("Sub", true, false) as Label).text = "You survived %d wave%s" % [max(0, wave - 1), "" if wave - 1 == 1 else "s"]
	var g: GridContainer = over_menu.find_child("Stats", true, false)
	for c in g.get_children():
		c.queue_free()
	for h in ["NAME", "KILLS", "HEADSHOTS", "EARNED", "DOWNS"]:
		_lbl(g, h, 14, Color(0.6, 0.6, 0.6), true)
	for s in stats:
		for v in [s.name, str(s.kills), str(s.heads), "$%d" % s.earned, str(s.downs)]:
			_lbl(g, v, 20)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud and hud.shop_open:
		hud.close_shop()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ======================================================================= pause / input
func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if game == null or hud == null:
		return
	if ev.is_action_pressed("pause"):
		if hud.shop_open:
			hud.close_shop()
		elif pause_menu.visible:
			_resume()
		elif not over_menu.visible:
			_pause()
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("interact") and hud.shop_open:
		hud.close_shop()
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not hud.blocking() and not over_menu.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pause() -> void:
	pause_menu.visible = true
	hud.pause_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Net.mode == "sp":
		get_tree().paused = true


func _resume() -> void:
	pause_menu.visible = false
	hud.pause_open = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and game and hud and not pause_menu.visible and not over_menu.visible and not hud.shop_open:
		_pause()


func _process(dt: float) -> void:
	if Net.args.has("shots"):
		_shots(dt)
	elif autotest_t > 0.0:
		_autotest(dt)


# ======================================================================= screenshot tour (dev tool)
var _shot_t := 0.0
var _shot_i := 0
const SHOT_POSES := [
	# [time, pos, yaw, pitch, name, ads]
	[3.0, Vector3(0, 0, 6), 0.0, 0.02, "spawn_armory", false],
	[5.0, Vector3(-1.5, 0, -15.5), 0.08, 0.05, "armory", false],
	[7.0, Vector3(4.6, 0, -23.0), 0.0, -0.1, "station", false],
	[9.0, Vector3(-5, 0, 3), -2.3, 0.04, "yard", false],
	[11.0, Vector3(20, 0, -3), 2.1, 0.0, "containers", false],
	[13.0, Vector3(0, 0, -4), PI, 0.0, "ads", true],
]

func _shots(dt: float) -> void:
	_shot_t += dt
	if game == null:
		return
	var lp: Player = game.player_nodes.get(game.local_id)
	var p: Dictionary = game.P.get(game.local_id, {})
	if lp == null or p.is_empty():
		return
	p.hp = 100.0
	p.downed = false
	if _shot_i < SHOT_POSES.size():
		var pose: Array = SHOT_POSES[_shot_i]
		game.timer = 60.0
		lp.global_position = pose[1]
		p.pos = pose[1]
		lp.yaw = pose[2]
		lp.pitch = pose[3]
		lp.ads = 1.0 if pose[5] else 0.0
		if pose[5] and lp.cur != "ar":
			p.weapons = ["pistol", "ar"]
			lp._sync_weapons(p.weapons)
			lp._equip("ar", true)
		if _shot_t >= pose[0]:
			_capture(pose[4])
			_shot_i += 1
			if _shot_i == SHOT_POSES.size():
				game.timer = 0.5
				autotest_t = 1e9
	else:
		_autotest(dt)
		if game.enemies.size() >= 4 and _shot_t > 30.0 and _shot_i < 20 and fmod(_shot_t, 3.0) < dt:
			_capture("combat_%d" % _shot_i)
			_shot_i += 1
		if _shot_t > float(Net.args.get("shots_time", 70)):
			get_tree().quit(0)


func _capture(name: String) -> void:
	var dir := str(Net.args.shots)
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[shots] saved %s" % name)


# ======================================================================= headless self-test
var _at_elapsed := 0.0
var _at_fired := 0

func _autotest(dt: float) -> void:
	# Runs a scripted singleplayer session: buys, fires at enemies, throws grenades, calls support.
	_at_elapsed += dt
	if game == null:
		return
	var lp: Player = game.player_nodes.get(game.local_id)
	if lp == null:
		return
	var p: Dictionary = game.P.get(game.local_id, {})
	if p.is_empty():
		p = game.me
	elif true:
		p.hp = 100.0                      # god mode so the test runs to the end
		p.downed = false
		if int(_at_elapsed) % 7 == 0:
			p.money = max(p.money, 20000)
		game.cleared = max(game.cleared, 12)    # unlock everything
	if Engine.get_process_frames() % 90 == 0:
		for item in ["w_ar", "e_frag", "e_armor", "e_mine", "e_turret", "a_strike", "a_drone", "a_carpet", "w_launcher", "e_ammo"]:
			game.send({"t": "buy", "item": item})
		game.send({"t": "ready"})
	# aim at the nearest enemy and shoot
	var best: Enemy = null
	var bd := 1e9
	for e in game.enemies.values():
		var d: float = e.global_position.distance_to(lp.global_position)
		if d < bd:
			bd = d
			best = e
	if best:
		var to := best.global_position + Vector3(0, 1.3, 0) - lp.cam.global_position
		lp.yaw = atan2(-to.x, -to.z)
		lp.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		lp.recoil = Vector2.ZERO
		lp.fire_cd = min(lp.fire_cd, 0.0)
		lp.reloading = false
		lp.ammo[lp.cur].mag = max(1, lp.ammo[lp.cur].mag)
		lp._try_fire()
		_at_fired += 1
	var f := Engine.get_process_frames()
	if f % 600 == 100: lp._throw()
	if f % 900 == 200: game.send({"t": "mine"})
	if f % 1200 == 300: game.send({"t": "turret"})
	if f % 1500 == 400: game.send({"t": "strike", "k": "strike", "pos": Vector3(0, 0, -30)})
	if f % 1800 == 500: game.send({"t": "drone"})
	if f % 2400 == 600: game.send({"t": "strike", "k": "carpet"})
	if f % 300 == 0:
		print("[autotest:%s] t=%.0fs wave=%d state=%s enemies=%d kills=%d money=%d shots=%d fps=%d" % [Net.mode, _at_elapsed, game.snap.get("wave", 0), game.snap.get("state", "?"), game.enemies.size(), p.get("kills", p.get("k", 0)), p.get("money", p.get("m", 0)), _at_fired, Engine.get_frames_per_second()])
	if _at_elapsed >= autotest_t:
		print("[autotest] DONE wave=%d kills=%d (%s)" % [game.snap.get("wave", 0), p.get("kills", p.get("k", 0)), Net.mode])
		get_tree().quit(0)
