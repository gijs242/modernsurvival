extends Node
## Entry point: menus, session start (singleplayer / host / join / dedicated), pause and game over.

var game: Game
var hud: Hud
var view_layer: CanvasLayer
var ui: CanvasLayer
var postfx: ColorRect
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
var best_lbl: Label
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
	# finishing pass (sharpen, grade, lens) between the 3D view and the HUD
	var post_layer := CanvasLayer.new()
	post_layer.name = "PostLayer"
	post_layer.layer = 1
	add_child(post_layer)
	postfx = ColorRect.new()
	postfx.set_anchors_preset(Control.PRESET_FULL_RECT)
	postfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://scripts/postfx.gdshader")
	postfx.material = pm
	postfx.visible = false
	post_layer.add_child(postfx)
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
	elif Net.args.has("autotest") or Net.args.has("shots") or Net.args.has("selftest") or Net.args.has("perfprobe") or Net.args.has("scopetest"):
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
	var q := int(Net.args.get("quality", Settings.get_val("quality", 2)))       # -1 Performance, 0 Low, 1 Medium, 2 High, 3 Ultra
	var vp := get_viewport()
	if q < 0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR       # FSR 1: far cheaper than FSR 2
		vp.scaling_3d_scale = 0.6
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if q <= 1 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 0.67 if q == 0 else 0.77 if q == 1 else 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED if q <= 1 else Viewport.MSAA_2X
	vp.use_taa = q == 3
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 4.0 if q < 0 else 1.0
	RenderingServer.directional_shadow_atlas_set_size(8192 if q >= 2 else (4096 if q >= 0 else 2048), true)


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
	map_opt.add_item("Mall")
	map_opt.add_item("Industrial Yard")
	map_opt.selected = 1 if Settings.get_val("map", "mall") == "yard" else 0
	map_opt.item_selected.connect(func(i): Settings.set_val("map", "mall" if i == 0 else "yard"))
	_row(v, "Map (host / solo)", map_opt)
	var diff_opt := OptionButton.new()
	var dkeys := Defs.DIFFICULTY.keys()
	for k in dkeys:
		diff_opt.add_item("%s  (enemy damage ×%.1f)" % [Defs.DIFFICULTY[k].name, Defs.DIFFICULTY[k].dmg])
	diff_opt.selected = max(0, dkeys.find(Settings.get_val("difficulty", "regular")))
	diff_opt.item_selected.connect(func(i): Settings.set_val("difficulty", dkeys[i]); _refresh_best())
	_row(v, "Difficulty (host / solo)", diff_opt)
	best_lbl = _lbl(v, "", 15, Color(0.95, 0.8, 0.45))
	_refresh_best()
	quality_opt = OptionButton.new()
	for q in ["Performance (weak PCs / laptops)", "Low", "Medium", "High", "Ultra"]:
		quality_opt.add_item(q)
	quality_opt.selected = int(Settings.get_val("quality", 2)) + 1
	quality_opt.item_selected.connect(func(i): Settings.set_val("quality", i - 1); _apply_window_settings())
	_row(v, "Graphics", quality_opt)
	var pfx := CheckBox.new()
	pfx.text = "Sharpening, colour grade and lens effects"
	pfx.button_pressed = bool(Settings.get_val("postfx", true))
	pfx.toggled.connect(func(on): Settings.set_val("postfx", on))
	_row(v, "Post-processing", pfx)
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
	var summ := _lbl(v, "", 18, Color(0.85, 0.83, 0.78))
	summ.name = "Summary"
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


## Map id from settings / command line; anything unknown (e.g. an id saved by an older version) is the Mall.
func _map_id(id: String) -> String:
	return "yard" if id == "yard" else "mall"


func _start_sp() -> void:
	Net.start_sp()
	Net.map_id = _map_id(str(Net.args.get("map", Settings.get_val("map", "mall"))))
	Net.difficulty = str(Net.args.get("difficulty", Settings.get_val("difficulty", "regular")))
	_start_game()
	game.send({"t": "join", "name": _player_name()})


func _host() -> void:
	var p := int(port_edit.text) if port_edit else Defs.DEFAULT_PORT
	Net.map_id = _map_id(str(Settings.get_val("map", "mall")))
	Net.difficulty = str(Settings.get_val("difficulty", "regular"))
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


## Best runs per map and difficulty (user://settings.cfg).
func _best_key(map: String, d: String) -> String:
	return "best_%s_%s" % [map, d]


func _refresh_best() -> void:
	if best_lbl == null:
		return
	var lines := []
	for m in ["mall", "yard"]:
		var b: Dictionary = Settings.get_val(_best_key(m, Settings.get_val("difficulty", "regular")), {})
		if not b.is_empty():
			lines.append("%s: wave %d, %s pts" % ["Mall" if m == "mall" else "Industrial Yard", int(b.wave), _thousands(int(b.score))])
	var dname: String = Defs.DIFFICULTY.get(Settings.get_val("difficulty", "regular"), Defs.DIFFICULTY.regular).name
	best_lbl.text = ("BEST (%s)   " % dname.to_upper()) + ("   ·   ".join(lines) if not lines.is_empty() else "no runs yet")


func _thousands(n: int) -> String:
	var t := str(n)
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return t + out


func _on_game_over(stats: Array, wave: int) -> void:
	over_menu.visible = true
	var survived: int = max(0, wave - 1)
	(over_menu.find_child("Sub", true, false) as Label).text = "You survived %d wave%s" % [survived, "" if survived == 1 else "s"]
	# personal summary + high score
	var me: Dictionary = {}
	for st in stats:
		if st.id == game.local_id:
			me = st
	var ls: Dictionary = game.local_stats
	var shots: int = ls.get("shots", 0)
	var acc: float = 100.0 * int(ls.get("hits", 0)) / max(1, shots)
	var fav := "—"
	var fav_n := 0
	for w in ls.get("kills_w", {}):
		if int(ls.kills_w[w]) > fav_n:
			fav_n = int(ls.kills_w[w])
			fav = Defs.WEAPONS[w].name if Defs.WEAPONS.has(w) else str(w).capitalize()
	var kills: int = me.get("kills", 0)
	var heads: int = me.get("heads", 0)
	var secs: int = (Time.get_ticks_msec() - int(ls.get("start", Time.get_ticks_msec()))) / 1000
	var score: int = roundi((kills * 100 + heads * 50 + survived * 500 + int(me.get("earned", 0)) * 0.1) * float(game.diff.score))
	var key := _best_key(Net.map_id, game.diff_id)
	var best: Dictionary = Settings.get_val(key, {})
	var record := best.is_empty() or score > int(best.get("score", 0))
	if record and not Net.args.has("autotest"):
		Settings.set_val(key, {"wave": survived, "score": score, "kills": kills})
	_refresh_best()
	(over_menu.find_child("Summary", true, false) as Label).text = "SCORE %s%s   ·   %s\nAccuracy %.0f%%   ·   Headshots %d%%   ·   Favourite weapon: %s (%d kills)\nBest kill streak %d   ·   Time %d:%02d" % [
		_thousands(score), "   — NEW BEST!" if record else "   (best %s)" % _thousands(int(best.get("score", 0))), game.diff.name,
		acc, roundi(100.0 * heads / max(1, kills)), fav, fav_n, int(ls.get("best_combo", 0)), secs / 60, secs % 60]
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
			"Mall" if info.get("map", "") == "mall" else "Industrial Yard", int(info.get("p", 0)), int(info.get("max", 4)), int(info.get("w", 0))], 16)
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


var _pf_sum := 0.0
var _pf_n := 0

# ======================================================================= render cost probe (dev tool)
## --perfprobe: stand in the mall hall and measure the GPU / CPU render time with each costly feature off in turn.
var _pp_t := 0.0
var _pp_i := -1
var _pp_acc := [0.0, 0.0, 0]
var _pp_base := {}
const PP_STEPS := ["baseline", "sdfgi", "volumetric_fog", "ssil", "ssao", "glow", "fog", "sun_shadows", "omni_lights", "backdrop", "dressing", "all_off"]

func _perfprobe(dt: float) -> void:
	if game == null or game.map == null or game.map.env == null:
		return
	var lp: Player = game.player_nodes.get(game.local_id)
	if lp == null:
		return
	var p: Dictionary = game.P.get(game.local_id, {})
	p.hp = 100.0
	game.timer = 99.0
	lp.global_position = game.map.player_spawns[0]
	lp.yaw = -float(game.map.get_meta("theta", 0.0)) + 0.4
	lp.pitch = 0.05
	var vp := get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	_pp_t += dt
	if _pp_i < 0:
		if _pp_t > 6.0:
			_pp_i = 0
			_pp_t = 0.0
		return
	if _pp_t > 1.0:      # settle, then measure for 2 s
		_pp_acc[0] += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
		_pp_acc[1] += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
		_pp_acc[2] += 1
	if _pp_t > 3.0:
		var n: int = max(1, _pp_acc[2])
		print("[perf] %-15s gpu %.1f ms  cpu %.1f ms  draw calls %d" % [PP_STEPS[_pp_i], _pp_acc[0] / n, _pp_acc[1] / n,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		_pp_acc = [0.0, 0.0, 0]
		_pp_t = 0.0
		_pp_i += 1
		if _pp_i >= PP_STEPS.size():
			get_tree().quit()
			return
		_pp_apply(PP_STEPS[_pp_i])


func _pp_apply(step: String) -> void:
	var env: Environment = game.map.env
	match step:
		"sdfgi": env.sdfgi_enabled = false
		"volumetric_fog": env.volumetric_fog_enabled = false
		"ssil": env.ssil_enabled = false
		"ssao": env.ssao_enabled = false
		"glow": env.glow_enabled = false
		"fog": env.fog_enabled = false
		"sun_shadows": game.map.sun.shadow_enabled = false
		"omni_lights":
			for l in game.map.find_children("*", "OmniLight3D", true, false):
				(l as OmniLight3D).visible = false
		"dressing":
			for n in game.map.static_root.get_children():
				if n is MeshInstance3D or n is MultiMeshInstance3D:
					pass
			for n in game.map.find_children("*", "MultiMeshInstance3D", true, false):
				(n as Node3D).visible = false
		"all_off":
			for n in game.map.static_root.find_children("*", "GeometryInstance3D", true, false):
				(n as Node3D).visible = false


## FPS guard: if a game runs below ~25 FPS for 4 s, step the graphics preset down (live) and say so.
var _fg_t := 0.0
var _fg_frames := 0
var _fg_cool := 8.0

func _fps_guard(dt: float) -> void:
	if game == null or hud == null or Net.is_dedicated() or get_tree().paused:
		return
	if Net.args.has("perfprobe") or Net.args.has("shots") or Net.args.has("autotest") or Net.args.has("selftest"):
		return
	_fg_cool -= dt
	if _fg_cool > 0.0:                 # let the level settle (shader compiles, first spawns)
		_fg_t = 0.0
		_fg_frames = 0
		return
	_fg_t += dt
	_fg_frames += 1
	if _fg_t < 4.0:
		return
	var fps := _fg_frames / _fg_t
	_fg_t = 0.0
	_fg_frames = 0
	var q := int(Settings.get_val("quality", 2))
	if fps < 25.0 and q > -1:
		q -= 1
		Settings.set_val("quality", q)
		_apply_window_settings()
		game.map.apply_quality(q)
		game.quality = q
		if quality_opt:
			quality_opt.selected = q + 1
		hud.feed("Low frame rate (%d FPS): graphics lowered to %s" % [roundi(fps), ["Performance", "Low", "Medium", "High", "Ultra"][q + 1]])
		_fg_cool = 6.0


# ======================================================================= optic screenshots (dev tool)
## --scopetest <dir>: aim down sights with every weapon and every optic that fits it, one screenshot each.
var _sc_list: Array = []
var _sc_i := -1
var _sc_t := 0.0

func _scopetest(dt: float) -> void:
	if game == null:
		return
	var lp: Player = game.player_nodes.get(game.local_id)
	var p: Dictionary = game.P.get(game.local_id, {})
	if lp == null or p.is_empty():
		return
	p.hp = 100.0
	game.timer = 99.0
	game.cleared = 20
	p.money = 999999
	if _sc_list.is_empty():
		for w in Defs.WEAPONS:
			if w == "launcher" or (Net.args.has("scopeonly") and not w in str(Net.args.scopeonly).split(",")):
				continue
			_sc_list.append([w, ""])
			for o in ["reddot", "holo", "acog", "sniper_scope"]:
				if Defs.attach_fits(w, o):
					_sc_list.append([w, o])
	_sc_t += dt
	# look along the main corridor at a shop sign ~20 m away
	lp.global_position = game.map.player_spawns[0]
	lp.yaw = -float(game.map.get_meta("theta", 0.0)) + PI / 2
	lp.pitch = 0.0
	lp.velocity = Vector3.ZERO
	if _sc_i >= 0 and _sc_t > 1.2:
		var it: Array = _sc_list[_sc_i]
		_capture("%s_%s" % [it[0], it[1] if it[1] != "" else "iron"])
		print("[scope] %s + %s: scope_view=%s zoom=%.1f fov=%.1f vm_visible=%s" % [it[0], it[1], lp.scope_view(), lp.ws().zoom, lp.cam.fov, lp.vm.visible])
	if _sc_i < 0 or _sc_t > 1.2:
		_sc_i += 1
		_sc_t = 0.0
		if _sc_i >= _sc_list.size():
			get_tree().quit()
			return
		var it: Array = _sc_list[_sc_i]
		p.weapons = ["pistol", it[0]] if it[0] != "pistol" else ["pistol"]
		p.att = {}
		if it[1] != "":
			p.att[it[0]] = {"optic": it[1]}
		lp.state["w"] = p.weapons
		lp.state["at"] = p.att.duplicate(true)
		lp._sync_weapons(p.weapons)
		lp._equip(it[0], true)
		lp._set_viewmodel(it[0])
		lp.force_ads = 1.0


var _pf_sum_dummy := 0
func _process(dt: float) -> void:
	if postfx:
		postfx.visible = game != null and bool(Settings.get_val("postfx", true)) and int(Settings.get_val("quality", 2)) >= 0 and not Net.is_dedicated()
	if Net.args.has("scopetest"):
		_scopetest(dt)
	_fps_guard(dt)
	if Net.args.has("perfprobe"):
		_perfprobe(dt)
	if autotest_t > 0.0:
		_pf_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_pf_n += 1
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

func _mall_poses() -> Array:
	var th: float = game.map.get_meta("theta", 0.0)
	var sp: Vector3 = game.map.player_spawns[0]
	var st: Dictionary = game.map.stations[1]
	var f: Vector3 = st.facing
	var poses := [
		[1.0, sp, -th, 0.05, "hall", false, "ak47"],
		[1.5, sp, -th + 0.9, 0.12, "hall_roof", false, "scar"],
		[2.0, sp, -th + PI / 2, 0.0, "corridor", true, "ar"],
		[2.5, st.pos + f * 4.4, atan2(f.x, f.z), -0.05, "armory", false, "m1911"],
	]
	# looking out of each entrance into its loading bay, and from the bay back into the mall
	var t := 3.0
	var k := 0
	for dd in game.map.get_meta("doors", []):
		var door: Vector3 = dd[0]
		var out: Vector3 = dd[1]
		poses.append([t, door - out * 5.0, atan2(-out.x, -out.z), 0.02, "entrance_%d" % k, false, "g3a3"])
		poses.append([t + 0.5, door + out * 7.0, atan2(out.x, out.z), 0.02, "bay_%d" % k, false, "mg250"])
		t += 1.0
		k += 1
	# a look into every shop from its doorway
	for sh in game.map.get_meta("shop_views", []):
		poses.append([t, sh[0], atan2(-(sh[1] as Vector3).x, -(sh[1] as Vector3).z), -0.08, "shop_%d" % k, false, "pistol"])
		t += 0.5
		k += 1
	return poses


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
	var poses: Array = SHOT_POSES if game.map.map_id == "yard" else _mall_poses()
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
	elif game.map.map_id != "yard" and _shot_i < poses.size() + 5:
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
		elif k == 3:
			# pose lineup: low ready, aim, reload, grenade throw, crouched, staggered
			var right := Vector3(-fwd.z, 0, fwd.x)
			var lineup := [[0, 0.0], [1, 0.0], [5, 0.5], [6, -0.2], [3, 0.0], [7, -0.25]]
			for j in lineup.size():
				game._spawn_enemy("rifleman")
				var e: Enemy = game.enemies.values()[game.enemies.size() - 1]
				e.global_position = lp.global_position + fwd * 5.5 + right * (j - 2.5) * 1.25
				e.set_physics_process(false)
				e.rotation.y = lp.yaw + PI - 0.5
				e.st = lineup[j][0]
				e.model._act = lineup[j][0]
				e.model._act_t = lineup[j][1]
			_shot_mark = _shot_t
			_shot_i += 1
		elif k == 4 and _shot_t - _shot_mark > 0.5:
			_capture("poses")
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
	var dir := str(Net.args.get("shots", Net.args.get("scopetest", "user://shots")))
	DirAccess.make_dir_recursive_absolute(dir)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [dir, name])
	print("[shots] saved %s  (draw calls %d, objects %d, primitives %d)" % [name,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


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
	# --navcheck (dev): route length from every spawn to the hall, and through every mall door
	if f == 200 and Net.args.has("navcheck"):
		var nav := game.get_world_3d().navigation_map
		var goal: Vector3 = game.map.player_spawns[0]
		for sp in game.map.spawns:
			var path := NavigationServer3D.map_get_path(nav, sp, goal, true)
			var L := 0.0
			for i in range(1, path.size()):
				L += path[i].distance_to(path[i - 1])
			print("[nav] spawn %s straight %.0f m, route %.0f m, ends %.1f m from goal" % [sp, sp.distance_to(goal), L, path[path.size() - 1].distance_to(goal) if path.size() else -1.0])
		for dd in game.map.get_meta("doors", []):
			var ep: Vector3 = dd[0]
			var out: Vector3 = dd[1]
			var path := NavigationServer3D.map_get_path(nav, ep + out * 4.0, ep - out * 4.0, true)
			var L := 0.0
			for i in range(1, path.size()):
				L += path[i].distance_to(path[i - 1])
			var inside := NavigationServer3D.map_get_path(nav, ep - out * 4.0, goal, true)
			var end_d: float = inside[inside.size() - 1].distance_to(goal) if inside.size() else -1.0
			print("[nav] door %s width %.1f: through it %.0f m (8 straight); inside->hall ends %.1f m from goal; outside nav %s inside nav %s" % [ep, dd[2], L, end_d,
				NavigationServer3D.map_get_closest_point(nav, ep + out * 4.0).distance_to(ep + out * 4.0) < 1.0, NavigationServer3D.map_get_closest_point(nav, ep - out * 4.0).distance_to(ep - out * 4.0) < 1.0])
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
		print("[autotest] avg physics frame %.2f ms" % (_pf_sum / max(1, _pf_n) * 1000.0))
		_pf_sum = 0.0
		_pf_n = 0
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
					var sight: Vector3 = gun.get_meta("front_sight", Vector3(0, 0 if gun.has_meta("custom") else 0.11, -1.5))
					var pt := cam.unproject_position(gun.global_transform * sight)
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
				var ps: Dictionary = lp.pip_screen()
				var off := (ps.c as Vector2).distance_to(lp.vm_cam.get_viewport().get_visible_rect().size * 0.5) if not ps.is_empty() else -1.0
				_st_check("ACOG shows a magnified lens picture centred on the aim point", not ps.is_empty() and off < 3.0 and float(lp.ws().get("pip", 0.0)) >= 3.0,
					"lens radius=%.0f px, offset=%.1f px, magnification=%.1fx" % [float(ps.get("r", 0.0)), off, float(lp.ws().get("pip", 0.0))])
				lp.force_ads = -1.0
				_st_step = 16
				if game.map.has_meta("roof_stairs"):
					# walk a body with the player's capsule up the roof stairs (headless runs can't send movement input)
					var b: Vector3 = game.map.get_meta("roof_stairs")
					var t: Vector3 = game.map.get_meta("roof_top")
					var walker := CharacterBody3D.new()
					walker.collision_mask = Defs.L_WORLD
					walker.floor_snap_length = 0.35
					walker.floor_max_angle = deg_to_rad(50)
					var cs := CollisionShape3D.new()
					var cap := CapsuleShape3D.new()
					cap.radius = 0.36
					cap.height = 1.8
					cs.shape = cap
					cs.position.y = 0.9
					walker.add_child(cs)
					var gs := GDScript.new()
					gs.source_code = "extends CharacterBody3D\nvar dir := Vector3.ZERO\nvar max_y := 0.0\nfunc _physics_process(dt):\n\tmax_y = max(max_y, global_position.y)\n\tvelocity.x = dir.x * 4.0\n\tvelocity.z = dir.z * 4.0\n\tvelocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * dt\n\tmove_and_slide()\n"
					gs.reload()
					walker.set_script(gs)
					game.add_child(walker)
					var up := Vector3(t.x - b.x, 0, t.z - b.z).normalized()
					walker.global_position = b - up * 1.0 + Vector3(0, 0.05, 0)
					walker.set("dir", up)
					_st_body = null
					set_meta("walker", walker)
				_st_next = _st_t + 4.0
		16:
			if _st_t >= _st_next:
				if game.map.has_meta("roof_stairs"):
					var walker: CharacterBody3D = get_meta("walker")
					_st_check("player can climb the roof stairs", float(walker.get("max_y")) > 3.8, "highest y=%.2f" % float(walker.get("max_y")))
					var nav := game.get_world_3d().navigation_map
					var path := NavigationServer3D.map_get_path(nav, game.map.get_meta("roof_stairs"), game.map.get_meta("roof_nest"), true)
					var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
					_st_check("enemies can path up to the roof nest", path.size() > 0 and end.distance_to(game.map.get_meta("roof_nest")) < 2.0 and end.y > 3.0, "end=%s" % end)
				print("[selftest] DONE failures=%d" % _st_fail)
				get_tree().quit(_st_fail)
