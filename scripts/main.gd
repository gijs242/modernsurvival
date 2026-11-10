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
var browser_list: VBoxContainer
var _browse_t := 0.0
var _query_t := 0.0
var _pending_join := ""


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
	elif Net.args.has("autotest") or Net.args.has("shots") or Net.args.has("selftest"):
		_start_sp()


func _register_inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "reload": [KEY_R], "weapon1": [KEY_1], "weapon2": [KEY_2],
		"frag": [KEY_G], "melee": [KEY_V], "interact": [KEY_E], "ready": [KEY_F], "mine": [KEY_4], "turret": [KEY_5],
		"strike": [KEY_6], "drone": [KEY_7], "carpet": [KEY_8], "scoreboard": [KEY_TAB], "pause": [KEY_ESCAPE, KEY_P], "fullscreen": [KEY_F11],
		"inspect": [KEY_T], "nvg": [KEY_N],
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
	var map_opt := OptionButton.new()
	map_opt.add_item("De Liekeblom (Leek)")
	map_opt.add_item("Industrial Yard")
	map_opt.selected = 0 if Settings.get_val("map", "liekeblom") == "liekeblom" else 1
	map_opt.item_selected.connect(func(i): Settings.set_val("map", "liekeblom" if i == 0 else "yard"))
	_row(v, "Map (host / solo)", map_opt)
	quality_opt = OptionButton.new()
	for q in ["Low", "Medium", "High", "Ultra"]:
		quality_opt.add_item(q)
	quality_opt.selected = int(Settings.get_val("quality", 2))
	quality_opt.item_selected.connect(func(i): Settings.set_val("quality", i); _apply_window_settings())
	_row(v, "Graphics", quality_opt)
	_row(v, "Mouse sensitivity", _slider("sens", 0.2, 3.0, 0.05, 1.0))
	_row(v, "Field of view", _slider("fov", 60, 100, 1, 78))
	_row(v, "Volume", _slider("volume", 0, 1, 0.05, 0.8, func(x): Sfx.set_volume(x)))
	# server browser: LAN games (broadcast) + recently joined servers (pinged)
	_lbl(v, "SERVERS  ·  LAN and recently joined", 15, Color(1.0, 0.54, 0.16), true)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 118)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	browser_list = VBoxContainer.new()
	browser_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(browser_list)
	_lbl(browser_list, "Searching the local network…", 15, Color(0.55, 0.55, 0.55))
	status_lbl = _lbl(v, "", 16, Color(0.6, 0.85, 0.6))
	var keys := _lbl(v, "WASD move · Shift sprint · Space jump · C crouch · LMB fire · RMB aim · R reload · 1/2 weapons\nG frag · V melee · E armory/revive · F ready · T inspect · N night vision · Shift (scoped) hold breath\n4 claymore · 5 sentry · 6 airstrike · 7 gunship · 8 carpet · Tab squad", 14, Color(0.55, 0.55, 0.55))
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
	Net.map_id = str(Net.args.get("map", Settings.get_val("map", "liekeblom")))
	_start_game()
	game.send({"t": "join", "name": _player_name()})


func _host() -> void:
	var p := int(port_edit.text) if port_edit else Defs.DEFAULT_PORT
	Net.map_id = str(Settings.get_val("map", "liekeblom"))
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
	_pending_join = "%s:%d" % [addr, p]
	_set_status("Connecting to %s:%d…" % [addr, p])


func _on_connected() -> void:
	if _pending_join != "":
		var recent: Array = Settings.get_val("recent", [])
		recent.erase(_pending_join)
		recent.push_front(_pending_join)
		Settings.set_val("recent", recent.slice(0, 6))
		_pending_join = ""
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
	game.setup(0, Net.map_id)
	multiplayer.peer_connected.connect(func(id): print("[+] peer %d connected (%d online)" % [id, multiplayer.get_peers().size()]))
	multiplayer.peer_disconnected.connect(func(id):
		print("[-] peer %d left" % id)
		if multiplayer.get_peers().is_empty():
			game.reset())
	print("Modern Survival dedicated server listening on UDP port %d (max %d players), map: %s" % [Net.port, Defs.MAX_PLAYERS, Net.map_id])
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
	game.setup(int(Net.args.get("quality", Settings.get_val("quality", 2))), Net.map_id)
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


## Server browser: refresh the list once a second while the main menu is up.
func _update_browser(dt: float) -> void:
	if menu == null or not menu.visible or browser_list == null:
		Net.stop_browsing()
		return
	Net.start_browsing()
	_query_t -= dt
	if _query_t <= 0.0:
		_query_t = 3.0
		for r in Settings.get_val("recent", []):
			var parts := str(r).rsplit(":", true, 1)
			if parts.size() == 2:
				Net.query(parts[0], int(parts[1]))
	_browse_t -= dt
	if _browse_t > 0.0:
		return
	_browse_t = 1.0
	for c in browser_list.get_children():
		c.queue_free()
	var keys := Net.servers.keys()
	keys.sort()
	if keys.is_empty():
		var recent: Array = Settings.get_val("recent", [])
		_lbl(browser_list, "No games found on your network yet." + ("" if recent.is_empty() else "  Recent servers aren't answering."), 15, Color(0.55, 0.55, 0.55))
		return
	for k in keys:
		var info: Dictionary = Net.servers[k]
		var h := HBoxContainer.new()
		browser_list.add_child(h)
		var full: bool = int(info.get("p", 0)) >= int(info.get("max", 4))
		var l := _lbl(h, "%s   ·   %s   ·   %d/%d players   ·   wave %d" % [str(info.get("n", "?")).substr(0, 18),
			"De Liekeblom" if info.get("map", "") == "liekeblom" else "Industrial Yard", int(info.get("p", 0)), int(info.get("max", 4)), int(info.get("w", 0))], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = k
		var b := Button.new()
		b.text = "FULL" if full else "JOIN"
		b.disabled = full
		_style_btn(b, not full)
		b.custom_minimum_size = Vector2(90, 34)
		b.add_theme_font_size_override("font_size", 16)
		var ip: String = info.ip
		var gp := int(info.get("port", Defs.DEFAULT_PORT))
		b.pressed.connect(func(): _join(ip, gp))
		h.add_child(b)


func _process(dt: float) -> void:
	_update_browser(dt)
	if Net.args.has("selftest"):
		_selftest(dt)
	elif Net.args.has("shots"):
		_shots(dt)
	elif autotest_t > 0.0:
		_autotest(dt)


# ======================================================================= screenshot tour (dev tool)
var _shot_t := 0.0
var _soldiers: Array = []
var _shot_mark := 0.0
var _shot_i := 0
const SHOT_POSES := [
	# [time, pos, yaw, pitch, name, ads, weapon]
	[3.0, Vector3(0, 0, 6), 0.0, 0.02, "spawn_armory", false, "pistol"],
	[4.5, Vector3(-5, 0, 3), -2.3, 0.0, "ar_hip", false, "ar"],
	[6.0, Vector3(-5, 0, 3), -2.3, 0.0, "ar_ads", true, "ar"],
	[7.5, Vector3(-5, 0, 3), -2.3, 0.0, "smg_hip", false, "smg"],
	[9.0, Vector3(-5, 0, 3), -2.3, 0.0, "shotgun_hip", false, "shotgun"],
	[10.5, Vector3(-5, 0, 3), -2.3, 0.0, "lmg_hip", false, "lmg"],
	[12.0, Vector3(-5, 0, 3), -2.3, 0.0, "launcher_hip", false, "launcher"],
	[13.5, Vector3(-5, 0, 3), -2.3, 0.0, "dmr_hip", false, "dmr"],
	[15.0, Vector3(4.6, 0, -23.0), 0.0, -0.1, "station", false, "pistol"],
	[16.5, Vector3(20, 0, -3), 2.1, 0.0, "containers", false, "ar"],
]

func _liekeblom_poses() -> Array:
	var th: float = game.map.get_meta("theta", 0.0)
	var sp: Vector3 = game.map.player_spawns[0]
	var st: Dictionary = game.map.stations[1]
	var f: Vector3 = st.facing
	var e0: Array = (game.map.get_meta("entrances", []) as Array)
	var ext: Vector3 = game.map.spawns[0]
	if not e0.is_empty():
		var ent := Vector3(e0[0][0], 0, e0[0][1])
		var outward := (ent - sp).normalized()
		ext = ent + outward * 16.0
	var to_mall := ext - sp
	return [
		[1.0, sp, -th, 0.05, "hall", false, "ak47"],
		[1.5, sp, -th + 0.9, 0.12, "hall_roof", false, "scar"],
		[2.0, sp, -th + PI / 2, 0.0, "corridor", true, "ar"],
		[2.5, st.pos + f * 4.4, atan2(f.x, f.z), -0.05, "armory", false, "m1911"],
		[3.0, ext, atan2(to_mall.x, to_mall.z), 0.06, "street", false, "g3a3"],
		[3.5, ext, atan2(to_mall.x, to_mall.z) + 2.2, 0.03, "street2", false, "mg250"],
	]


func _shots(dt: float) -> void:
	_shot_t += dt
	if Engine.get_process_frames() % 15 == 0:
		print("[shots] frame %d t=%.2f wall=%ds" % [Engine.get_process_frames(), _shot_t, Time.get_ticks_msec() / 1000])
	if game == null:
		return
	var lp: Player = game.player_nodes.get(game.local_id)
	var p: Dictionary = game.P.get(game.local_id, {})
	if lp == null or p.is_empty():
		return
	p.hp = 100.0
	p.downed = false
	var poses: Array = SHOT_POSES if game.map.map_id == "yard" else _liekeblom_poses()
	if _shot_i < poses.size():
		var pose: Array = poses[_shot_i]
		game.timer = 60.0
		lp.global_position = pose[1]
		p.pos = pose[1]
		lp.yaw = pose[2]
		lp.pitch = pose[3]
		lp.ads = 1.0 if pose[5] else 0.0
		if lp.cur != pose[6]:
			p.weapons = ["pistol", pose[6]] if pose[6] != "pistol" else ["pistol"]
			lp._sync_weapons(p.weapons)
			lp._equip(pose[6], true)
		lp.swap_t = 0.0
		if _shot_t >= pose[0]:
			_capture(pose[4])
			_shot_i += 1
			if _shot_i == poses.size() and game.map.map_id == "yard":
				game.timer = 0.5
				autotest_t = 1e9
	elif game.map.map_id != "yard" and _shot_i < poses.size() + 3:
		var k := _shot_i - poses.size()
		var fwd := Vector3(-sin(lp.yaw), 0, -cos(lp.yaw))
		if k == 0 and _soldiers.is_empty():
			for j in 3:
				game._spawn_enemy(["rifleman", "grunt", "shotgunner"][j])
				var e: Enemy = game.enemies.values()[game.enemies.size() - 1]
				e.global_position = lp.global_position + fwd * (3.2 + j * 1.6) + Vector3(-fwd.z, 0, fwd.x) * (j - 1) * 1.3
				e.set_physics_process(false)
				e.rotation.y = lp.yaw + PI + (j - 1) * 0.5
				_soldiers.append(e)
			_shot_mark = _shot_t
		elif k == 0 and _shot_t - _shot_mark > 0.4:
			_capture("soldiers")
			_shot_i += 1
		elif k == 1:
			game._damage_enemy(_soldiers[0], 9999.0, p, {"head": true})
			game._damage_enemy(_soldiers[1], 9999.0, p, {"expl": true})
			_shot_mark = _shot_t
			_shot_i += 1
		elif k == 2 and _shot_t - _shot_mark > 1.2:
			_capture("ragdolls")
			_shot_i += 1
			if Net.args.has("shots_quit"):
				get_tree().quit(0)
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
	if best and not Net.args.has("pacifist"):
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
	var g := 1 if Net.args.has("pacifist") else f      # pacifist: no grenades / support either
	if g % 600 == 100: lp._throw()
	if g % 900 == 200: game.send({"t": "mine"})
	if g % 1200 == 300: game.send({"t": "turret"})
	if g % 1500 == 400: game.send({"t": "strike", "k": "strike", "pos": Vector3(0, 0, -30)})
	if g % 1800 == 500: game.send({"t": "drone"})
	if g % 2400 == 600: game.send({"t": "strike", "k": "carpet"})
	if f % 300 == 0 and game.is_server:
		var mix := {}
		for e in game.enemies.values():
			var k: String = e.type + ("/cover" if e.mode == Enemy.IN_COVER else "/tocover" if e.mode == Enemy.TO_COVER else "/flank" if e.role == "flank" else "")
			mix[k] = int(mix.get(k, 0)) + 1
			if Net.args.has("pacifist"):
				mix[k + "@"] = "%d%s/%s" % [e.global_position.distance_to(lp.global_position), "L" if e.los else "", e.st]
		var efr := 0
		for pr in game.projectiles.values():
			if pr.k == "efrag": efr += 1
		print("[autotest] enemy grenades thrown=%d in_air=%d camp=%.0f" % [game.nades_thrown, efr, game.P.get(game.local_id, {}).get("camp_t", 0.0)])
		print("[autotest] mix=%s helis=%d glass_broken=%d lights_out=%d power=%s special=%s" % [mix, game.helis.size(), game.glass_broken.size(), game.lights_out.size(), game.power, game.special])
	if f % 300 == 0:
		print("[autotest:%s] t=%.0fs wave=%d state=%s enemies=%d kills=%d money=%d shots=%d fps=%d" % [Net.mode, _at_elapsed, game.snap.get("wave", 0), game.snap.get("state", "?"), game.enemies.size(), p.get("kills", p.get("k", 0)), p.get("money", p.get("m", 0)), _at_fired, Engine.get_frames_per_second()])
	if _at_elapsed >= autotest_t:
		print("[autotest] DONE wave=%d kills=%d (%s)" % [game.snap.get("wave", 0), p.get("kills", p.get("k", 0)), Net.mode])
		get_tree().quit(0)


# ======================================================================= regression self-test (dev tool)
var _st_t := 0.0
var _st_step := 0
var _st_fail := 0
var _st_enemy: Enemy
var _st_body: Soldier
var _st_pitch := 0.0
var _st_weapons: Array = []
var _st_wi := 0
var _st_next := 0.0

func _st_check(name: String, ok: bool, detail := "") -> void:
	print("[selftest] %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_st_fail += 1

func _st_key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func _selftest(dt: float) -> void:
	_st_t += dt
	if game == null:
		return
	var lp: Player = game.player_nodes.get(game.local_id)
	var p: Dictionary = game.P.get(game.local_id, {})
	if lp == null or p.is_empty():
		return
	p.hp = 100.0
	game.timer = 99.0
	match _st_step:
		0:
			if _st_t > 1.0:
				var st0: Dictionary = game.map.stations[0]
				lp.global_position = st0.pos + (st0.facing as Vector3) * 1.6 + Vector3(0, 0.05, 0)
				lp.yaw = atan2((st0.facing as Vector3).x, (st0.facing as Vector3).z)
				_st_step = 1
		1:
			if _st_t > 1.5:
				_st_key(KEY_E, true)
				_st_step = 2
		2:
			if _st_t > 1.7:
				_st_key(KEY_E, false)
				_st_step = 3
		3:
			if _st_t > 2.2:
				_st_check("shop opens with E at the weapon station", hud.shop_open, "prompt='%s'" % lp.interact_prompt)
				_st_key(KEY_E, true)
				_st_step = 4
		4:
			if _st_t > 2.4:
				_st_key(KEY_E, false)
				_st_step = 5
		5:
			if _st_t > 2.8:
				_st_check("E closes the shop again", not hud.shop_open)
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				lp.global_position = game.map.player_spawns[0]
				_st_pitch = lp.pitch
				lp.fire_cd = 0.0
				lp._try_fire()
				_st_step = 6
		6:
			if _st_t > 2.85:
				var kick_deg := rad_to_deg(lp.recoil.y + lp.pitch - _st_pitch)
				_st_check("one pistol shot kicks the camera noticeably", kick_deg > 1.0, "kick=%.2f deg" % kick_deg)
				# spawn a hostile in front of the player and kill it
				game._spawn_enemy("rifleman")
				_st_enemy = game.enemies.values()[game.enemies.size() - 1]
				_st_enemy.global_position = lp.global_position + Vector3(-sin(lp.yaw), 0, -cos(lp.yaw)) * 4.0
				_st_step = 7
		7:
			if _st_t > 3.2:
				game._damage_enemy(_st_enemy, 9999.0, p, {"head": true})
				_st_step = 8
		8:
			if _st_t > 3.4:
				for c in game.enemies_root.get_children():
					if c is Soldier and c.dead:
						_st_body = c
				_st_check("killed enemy becomes a corpse", _st_body != null)
				_st_check("enemy removed from the live list", not game.enemies.has(_st_enemy.id) if is_instance_valid(_st_enemy) else true)
				_st_step = 9
		9:
			if _st_t > 4.6:
				var chest: RigidBody3D = null
				for c in game.enemies_root.get_children():
					if c is RigidBody3D and String(c.name).begins_with("RD_chest"):
						chest = c
				var up := chest.global_transform.basis.y.normalized().dot(Vector3.UP) if chest else 1.0
				_st_check("ragdoll falls over", chest != null and up < 0.6, "chest up-dot=%.2f, height=%.2f" % [up, chest.global_position.y if chest else -1.0])
				_st_step = 10
		10:
			if _st_t > 17.0:
				_st_check("corpse disappears after ~12 s", not is_instance_valid(_st_body))
				_st_weapons = Defs.WEAPONS.keys()
				_st_step = 11
				_st_next = _st_t
		11:
			# aim down sights with every weapon: the gun's sight line must hit the exact screen centre
			if _st_t >= _st_next:
				if _st_wi > 0:
					var gun: Node3D = lp.vm.get_meta("gun")
					var cam := lp.vm_cam
					var centre := cam.get_viewport().get_visible_rect().size * 0.5
					var pt := cam.unproject_position(gun.global_transform * Vector3(0, 0 if gun.has_meta("custom") else 0.11, -1.5))
					var err := pt.distance_to(centre)
					_st_check("sight line centred: %s" % _st_weapons[_st_wi - 1], err < 2.0 or lp.scope_view(), "error=%.2f px%s" % [err, " (scoped)" if lp.scope_view() else ""])
				if _st_wi >= _st_weapons.size():
					lp.force_ads = -1.0
					_st_step = 12
					return
				var w: String = _st_weapons[_st_wi]
				p.weapons = ["pistol", w] if w != "pistol" else ["pistol"]
				lp.state["w"] = p.weapons
				lp._sync_weapons(p.weapons)
				lp._equip(w, true)
				lp.force_ads = 1.0
				lp.velocity = Vector3.ZERO
				_st_wi += 1
				_st_next = _st_t + 0.8
		12:
			# gunsmith: buy a red dot for the AK, it must be fitted, centred and change stats
			game.cleared = 15
			p.money = 50000
			p.weapons = ["pistol", "ak47"]
			lp._sync_weapons(p.weapons)
			lp._equip("ak47", true)
			game.send({"t": "buy_att", "w": "ak47", "a": "reddot"})
			game.send({"t": "buy_att", "w": "ak47", "a": "foregrip"})
			_st_step = 13
			_st_next = _st_t + 1.0
		13:
			if _st_t >= _st_next:
				var att: Dictionary = p.att.get("ak47", {})
				_st_check("gunsmith fits a red dot + foregrip", att.get("optic", "") == "reddot" and att.get("under", "") == "foregrip", str(att))
				_st_check("foregrip lowers recoil", lp.ws("ak47").recoil < Defs.WEAPONS.ak47.recoil, "%.2f vs %.2f" % [lp.ws("ak47").recoil, Defs.WEAPONS.ak47.recoil])
				lp.force_ads = 1.0
				_st_step = 14
				_st_next = _st_t + 0.8
		14:
			if _st_t >= _st_next:
				var gun: Node3D = lp.vm.get_meta("gun")
				var dot := gun.find_child("Att_optic", true, false) as Node3D
				var cam := lp.vm_cam
				var centre := cam.get_viewport().get_visible_rect().size * 0.5
				var err := 999.0
				if dot:
					err = cam.unproject_position(dot.global_position + (gun.global_transform.basis * Vector3(0, 0, -0.01))).distance_to(centre)
				_st_check("red dot visible on the gun and centred when aiming", dot != null and err < 3.0, "error=%.2f px" % err)
				game.send({"t": "buy_att", "w": "ak47", "a": "acog"})
				_st_step = 15
				_st_next = _st_t + 1.0
		15:
			if _st_t >= _st_next:
				_st_check("ACOG switches to a magnified scope view", lp.scope_view(), "zoom=%.1f" % lp.ws().zoom)
				lp.force_ads = -1.0
				print("[selftest] DONE failures=%d" % _st_fail)
				get_tree().quit(_st_fail)
