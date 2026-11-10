class_name Hud
extends Control
## In-game HUD, shop panel and scoreboard. Built entirely in code.

var game: Game
var font: SystemFont
var font_bold: SystemFont

var wave_lbl: Label
var wave_sub: Label
var money_lbl: Label
var money_feed: VBoxContainer
var ann_box: VBoxContainer
var ann_title: Label
var ann_sub: Label
var ann_t := 0.0
var combo_lbl: Label
var combo_t := 0.0
var feed_box: VBoxContainer
var cross: Control
var hitm: Control
var hit_t := 0.0
var hit_kill := false
var hit_head := false
var scope: Control
var prompt: Label
var revive_bar: ProgressBar
var revive_lbl: Label
var downed_lbl: Label
var hp_bar: ProgressBar
var ar_bar: ProgressBar
var hp_num: Label
var ar_num: Label
var team_lbl: RichTextLabel
var weapon_lbl: Label
var ammo_lbl: Label
var reserve_lbl: Label
var equip_lbl: RichTextLabel
var markers: Control
var minimap: Control
var dmg_layer: Control
var dmg_dirs: Array = []
var vignette: ColorRect
var designate_lbl: Label

var shop: Panel
var shop_cat := ""
var shop_list: VBoxContainer
var shop_title: Label
var shop_money: Label
var shop_msg: Label
var shop_open := false
var score: Panel
var score_grid: GridContainer
var pause_open := false
var shown_money := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Roboto Condensed", "Arial Narrow", "DejaVu Sans Condensed", "Liberation Sans Narrow", "sans-serif"])
	font.font_weight = 500
	font_bold = font.duplicate()
	font_bold.font_weight = 700

	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = "shader_type canvas_item; uniform float amt = 0.0; void fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.3, 0.75, length(d) * (1.0 + amt * 0.5)); COLOR = vec4(0.45, 0.0, 0.0, v * amt * 0.9); }"
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vignette.material = vm
	add_child(vignette)

	dmg_layer = Control.new()
	dmg_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_layer.draw.connect(_draw_dmg)
	add_child(dmg_layer)

	scope = Control.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.draw.connect(_draw_scope)
	scope.visible = false
	add_child(scope)

	# top-left: wave
	wave_lbl = _label("WAVE 0", 40, Color(0.95, 0.9, 0.78), true)
	wave_lbl.position = Vector2(28, 18)
	wave_sub = _label("", 20, Color(0.82, 0.8, 0.74))
	wave_sub.position = Vector2(30, 66)
	minimap = Control.new()
	minimap.position = Vector2(28, 104)
	minimap.size = Vector2(200, 200)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	minimap.clip_contents = true
	add_child(minimap)

	# top-right: money
	money_lbl = _label("$500", 46, Color(0.5, 0.9, 0.5), true)
	money_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_lbl.offset_left = -400
	money_lbl.offset_right = -28
	money_lbl.offset_top = 14
	money_feed = VBoxContainer.new()
	money_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	money_feed.offset_left = -400
	money_feed.offset_right = -28
	money_feed.offset_top = 72
	money_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	money_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(money_feed)
	feed_box = VBoxContainer.new()
	feed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed_box.offset_left = -520
	feed_box.offset_right = -28
	feed_box.offset_top = 250
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed_box)

	# center: announce, combo, crosshair, hitmarker, prompts
	ann_box = VBoxContainer.new()
	ann_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	ann_box.offset_left = -700
	ann_box.offset_right = 700
	ann_box.offset_top = 170
	ann_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ann_box)
	ann_title = _label("", 66, Color(0.97, 0.91, 0.75), true, ann_box)
	ann_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann_sub = _label("", 24, Color(0.9, 0.87, 0.78), false, ann_box)
	ann_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ann_box.modulate.a = 0.0
	combo_lbl = _label("", 34, Color(1.0, 0.8, 0.3), true)
	combo_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	combo_lbl.offset_left = -400
	combo_lbl.offset_right = 400
	combo_lbl.offset_top = -170
	combo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_lbl.modulate.a = 0.0

	cross = Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross)
	add_child(cross)
	hitm = Control.new()
	hitm.set_anchors_preset(Control.PRESET_FULL_RECT)
	hitm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitm.draw.connect(_draw_hitmarker)
	add_child(hitm)

	prompt = _label("", 24, Color.WHITE)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.offset_left = -500
	prompt.offset_right = 500
	prompt.offset_top = 120
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	designate_lbl = _label("MARK TARGET\n[LMB] call in   ·   [RMB] cancel", 24, Color(1.0, 0.4, 0.3), true)
	designate_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	designate_lbl.offset_left = -400
	designate_lbl.offset_right = 400
	designate_lbl.offset_top = 70
	designate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	designate_lbl.visible = false
	revive_lbl = _label("REVIVING", 20, Color(0.6, 0.85, 1.0), true)
	revive_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	revive_lbl.offset_left = -150
	revive_lbl.offset_right = 150
	revive_lbl.offset_top = 60
	revive_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	revive_bar = _bar(Color(0.4, 0.75, 1.0))
	revive_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	revive_bar.offset_left = -150
	revive_bar.offset_right = 150
	revive_bar.offset_top = 92
	revive_bar.offset_bottom = 102
	revive_lbl.visible = false
	revive_bar.visible = false
	downed_lbl = _label("", 46, Color(1.0, 0.33, 0.25), true)
	downed_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	downed_lbl.offset_left = -600
	downed_lbl.offset_right = 600
	downed_lbl.offset_top = -260
	downed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# bottom-left: team + health/armor
	var bl := VBoxContainer.new()
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.offset_left = 28
	bl.offset_top = -190
	bl.offset_right = 380
	bl.offset_bottom = -24
	bl.alignment = BoxContainer.ALIGNMENT_END
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bl)
	team_lbl = RichTextLabel.new()
	team_lbl.bbcode_enabled = true
	team_lbl.fit_content = true
	team_lbl.scroll_active = false
	team_lbl.add_theme_font_override("normal_font", font)
	team_lbl.add_theme_font_size_override("normal_font_size", 18)
	team_lbl.add_theme_constant_override("outline_size", 4)
	team_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	team_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.add_child(team_lbl)
	var hp_row := _stat_row(bl, "HEALTH", Color(0.92, 0.92, 0.88))
	hp_bar = hp_row[0]
	hp_num = hp_row[1]
	var ar_row := _stat_row(bl, "ARMOR", Color(0.45, 0.68, 1.0))
	ar_bar = ar_row[0]
	ar_num = ar_row[1]

	# bottom-right: weapon + ammo + equipment
	var br := VBoxContainer.new()
	br.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	br.offset_left = -700
	br.offset_top = -200
	br.offset_right = -28
	br.offset_bottom = -24
	br.alignment = BoxContainer.ALIGNMENT_END
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(br)
	weapon_lbl = _label("", 20, Color(0.82, 0.8, 0.74), false, br)
	weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br.add_child(ammo_row)
	ammo_lbl = _label("15", 60, Color.WHITE, true, ammo_row)
	reserve_lbl = _label(" / ∞", 28, Color(0.75, 0.75, 0.75), false, ammo_row)
	reserve_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	equip_lbl = RichTextLabel.new()
	equip_lbl.bbcode_enabled = true
	equip_lbl.fit_content = true
	equip_lbl.scroll_active = false
	equip_lbl.add_theme_font_override("normal_font", font)
	equip_lbl.add_theme_font_size_override("normal_font_size", 15)
	equip_lbl.add_theme_constant_override("outline_size", 4)
	equip_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	equip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br.add_child(equip_lbl)

	markers = Control.new()
	markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	markers.draw.connect(_draw_markers)
	add_child(markers)

	_build_shop()
	_build_score()


# ------------------------------------------------------------------ widgets
func _label(text: String, size: int, color: Color, bold := false, parent: Node = self) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.border_color = Color(1, 1, 1, 0.25)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	return b


func _stat_row(parent: Control, name: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var l := _label(name, 15, Color(0.78, 0.76, 0.7), true, row)
	l.custom_minimum_size.x = 70
	var b := _bar(color)
	remove_child(b)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	var n := _label("100", 18, Color.WHITE, true, row)
	n.custom_minimum_size.x = 44
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return [b, n]


func _panel_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.055, 0.062, 0.07, 0.94)
	s.border_color = accent
	s.border_width_top = 3
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 20
	return s


func _build_shop() -> void:
	shop = Panel.new()
	shop.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	shop.offset_left = -360
	shop.offset_right = 360
	shop.offset_top = -330
	shop.offset_bottom = 330
	shop.visible = false
	add_child(shop)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_right = -22
	v.offset_top = 16
	v.offset_bottom = -14
	shop.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	shop_title = _label("ARMORY", 32, Color.ORANGE, true, head)
	shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_money = _label("$0", 32, Color(0.5, 0.9, 0.5), true, head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	shop_list = VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 6)
	sc.add_child(shop_list)
	shop_msg = _label("", 18, Color(1.0, 0.45, 0.4), true, v)
	_label("Click to buy  ·  [E] / [Esc] to close  ·  New gear unlocks every few waves", 15, Color(0.6, 0.6, 0.6), false, v)


func _build_score() -> void:
	score = Panel.new()
	score.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	score.offset_left = -380
	score.offset_right = 380
	score.offset_top = -200
	score.offset_bottom = 200
	score.add_theme_stylebox_override("panel", _panel_style(Color(1.0, 0.55, 0.15)))
	score.visible = false
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 24
	v.offset_right = -24
	v.offset_top = 16
	score.add_child(v)
	_label("SQUAD", 30, Color(0.95, 0.9, 0.78), true, v)
	score_grid = GridContainer.new()
	score_grid.columns = 5
	score_grid.add_theme_constant_override("h_separation", 34)
	v.add_child(score_grid)


# ------------------------------------------------------------------ public API
func blocking() -> bool:
	return shop_open or pause_open


func feed(text: String) -> void:
	var l := _label(text, 18, Color(0.92, 0.9, 0.85), false, feed_box)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
	while feed_box.get_child_count() > 7:
		feed_box.get_child(0).free()


func announce(title: String, sub: String, dur: float) -> void:
	ann_title.text = title
	ann_sub.text = sub
	ann_t = dur
	ann_box.modulate.a = 0.0
	ann_box.scale = Vector2(1.08, 1.08)


func money_pop(amt: int, label: String) -> void:
	var l := _label("%s  +$%d" % [label, amt], 24, Color(0.62, 0.96, 0.62), true, money_feed)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.scale = Vector2(1.3, 1.3)
	l.pivot_offset = Vector2(360, 14)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12)
	tw.tween_interval(1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	while money_feed.get_child_count() > 5:
		money_feed.get_child(0).free()


func hitmarker(head: bool, kill: bool) -> void:
	hit_t = 0.32 if kill else 0.2
	hit_kill = kill
	hit_head = head
	hitm.queue_redraw()


func on_kill(e: Dictionary) -> void:
	hitmarker(e.head, true)
	Sfx.play("kill_head" if e.head else "kill", -1.0, 1.0, 0.03)
	var label := "HEADSHOT" if e.head else "MELEE" if e.melee else "KILL"
	money_pop(e.money, label)
	if e.bonus > 0:
		money_pop(e.bonus, "COMBO")
	if e.combo >= 2:
		combo_lbl.text = "%s  x%d" % [Defs.COMBO_NAMES[min(e.combo, Defs.COMBO_NAMES.size() - 1)], e.combo]
		combo_t = 1.4
		combo_lbl.scale = Vector2(1.6, 1.6)
		combo_lbl.pivot_offset = Vector2(400, 20)
	feed("You  ✕  %s%s" % [Defs.ENEMIES[e.et].name, "  (headshot)" if e.head else ""])


func on_buy(e: Dictionary) -> void:
	if e.ok:
		Sfx.play("buy", -4.0, 1.0, 0.0)
		shop_msg.add_theme_color_override("font_color", Color(0.5, 0.95, 0.5))
		shop_msg.text = "Purchased: %s" % e.name
	else:
		Sfx.play("deny", -6.0, 1.0, 0.0)
		shop_msg.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		shop_msg.text = e.why
	_refresh_shop()


func on_restart() -> void:
	announce("", "", 0.0)


func damage_dir(ang: float) -> void:
	dmg_dirs.append({"a": ang, "t": 1.2})


func open_shop(cat: String) -> void:
	shop_cat = cat
	shop_open = true
	shop.visible = true
	shop.add_theme_stylebox_override("panel", _panel_style(Defs.CAT_COLORS[cat]))
	shop_title.text = Defs.CAT_NAMES[cat]
	shop_title.add_theme_color_override("font_color", Defs.CAT_COLORS[cat])
	shop_msg.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sfx.play("ui", -4.0)
	_refresh_shop()


func close_shop() -> void:
	shop_open = false
	shop.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_shop() -> void:
	if not shop_open:
		return
	for c in shop_list.get_children():
		c.queue_free()
	var me := game.me
	var cleared: int = game.snap.get("cleared", 0)
	var money: int = me.get("m", 0)
	shop_money.text = "$%d" % money
	if shop_cat == "gunsmith":
		_refresh_gunsmith(me, cleared, money)
		return
	for it in Defs.SHOP:
		if it.cat != shop_cat:
			continue
		var locked: bool = cleared < it.after
		var owned: bool = it.has("weapon") and it.weapon in me.get("w", [])
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 62)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.04)
		sb.border_color = Defs.CAT_COLORS[shop_cat]
		sb.border_width_left = 0
		var sh := sb.duplicate()
		sh.bg_color = Color(1, 1, 1, 0.1)
		sh.border_width_left = 4
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.add_theme_stylebox_override("disabled", sb)
		var grid := HBoxContainer.new()
		grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		grid.offset_left = 14
		grid.offset_right = -14
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(grid)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.alignment = BoxContainer.ALIGNMENT_CENTER
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(left)
		_label(it.name, 22, Color(0.95, 0.94, 0.9), true, left)
		_label(it.desc, 15, Color(0.65, 0.65, 0.65), false, left)
		var right := VBoxContainer.new()
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(right)
		var price := _label("$%d" % it.price, 22, Color(0.5, 0.9, 0.5) if money >= it.price else Color(0.85, 0.4, 0.35), true, right)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var status := ""
		if locked:
			status = "UNLOCKS AFTER WAVE %d" % it.after
			price.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		elif owned:
			status = "OWNED"
		var st := _label(status, 14, Color(0.5, 0.75, 1.0) if owned else Color(0.6, 0.6, 0.6), true, right)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if locked:
			b.disabled = true
			b.modulate.a = 0.5
		var id: String = it.id
		b.pressed.connect(func(): game.send({"t": "buy", "item": id}))
		shop_list.add_child(b)


func _shop_button(title: String, desc: String, price_text: String, price_ok: bool, status: String, status_col: Color, disabled: bool, on_press: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 62)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = Defs.CAT_COLORS[shop_cat]
	var sh := sb.duplicate()
	sh.bg_color = Color(1, 1, 1, 0.1)
	sh.border_width_left = 4
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.add_theme_stylebox_override("disabled", sb)
	var grid := HBoxContainer.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.offset_left = 14
	grid.offset_right = -14
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(grid)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(left)
	_label(title, 22, Color(0.95, 0.94, 0.9), true, left)
	_label(desc, 15, Color(0.65, 0.65, 0.65), false, left)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(right)
	var pr := _label(price_text, 22, Color(0.5, 0.9, 0.5) if price_ok else Color(0.85, 0.4, 0.35), true, right)
	pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var st := _label(status, 14, status_col, true, right)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if disabled:
		b.disabled = true
		b.modulate.a = 0.5
	b.pressed.connect(on_press)
	shop_list.add_child(b)


func _refresh_gunsmith(me: Dictionary, cleared: int, money: int) -> void:
	var lp: Player = game.player_nodes.get(game.local_id)
	if lp == null:
		return
	var wid: String = lp.cur
	var fitted: Dictionary = lp.atts_of(wid)
	_label("Modifying: %s   (switch weapons with 1 / 2 to modify the other)" % Defs.WEAPONS[wid].name.to_upper(), 17, Color(0.85, 0.75, 1.0), true, shop_list)
	var any := false
	for aid in Defs.ATTACH:
		if not Defs.attach_fits(wid, aid):
			continue
		any = true
		var a: Dictionary = Defs.ATTACH[aid]
		var locked: bool = cleared < a.after
		var on: bool = fitted.get(a.slot, "") == aid
		var status: String = ("UNLOCKS AFTER WAVE %d" % a.after) if locked else ("FITTED" if on else String(a.slot).to_upper())
		var id: String = aid
		_shop_button(a.name, a.desc, "$%d" % a.price, money >= a.price and not locked, status,
			Color(0.5, 0.75, 1.0) if on else Color(0.6, 0.6, 0.6), locked or on,
			func(): game.send({"t": "buy_att", "w": wid, "a": id}))
	if not any:
		_label("No attachments fit this weapon.", 18, Color(0.7, 0.7, 0.7), false, shop_list)


func on_snapshot(s: Dictionary, me: Dictionary) -> void:
	if shop_open and Engine.get_process_frames() % 10 == 0:
		_refresh_shop()


# ------------------------------------------------------------------ per frame
func _process(dt: float) -> void:
	if game == null:
		return
	var s := game.snap
	var me := game.me
	var lp: Player = game.player_nodes.get(game.local_id)
	# wave info
	var st: String = s.get("state", "inter")
	wave_lbl.text = "WAVE %d" % s.get("wave", 0)
	if st == "inter":
		var ready_n := 0
		var total: int = s.get("players", []).size()
		for p in s.get("players", []):
			if p.rd:
				ready_n += 1
		wave_sub.text = "Next wave in %ds  ·  [F] ready (%d/%d)" % [s.get("timer", 0), ready_n, total]
	elif st == "active":
		wave_sub.text = "Hostiles remaining: %d" % s.get("left", 0)
	else:
		wave_sub.text = "Mission failed"
	# money (counts up smoothly)
	var target := float(me.get("m", 0))
	shown_money = move_toward(shown_money, target, max(1.0, abs(target - shown_money)) * dt * 8.0)
	money_lbl.text = "$%d" % roundi(shown_money)
	# health
	hp_bar.value = me.get("hp", 100)
	hp_num.text = str(me.get("hp", 100))
	ar_bar.max_value = 250 if me.get("ar", 0) > 100 else 100
	ar_bar.value = me.get("ar", 0)
	ar_num.text = str(me.get("ar", 0))
	var hp: float = me.get("hp", 100)
	(vignette.material as ShaderMaterial).set_shader_parameter("amt", clamp((60.0 - hp) / 60.0, 0.0, 1.0) if not me.get("dn", false) else 0.8)
	# team
	var t := ""
	for p in s.get("players", []):
		if p.id == game.local_id:
			continue
		var c := "#ff6050" if p.dn else "#777777" if p.dd else "#cfe4ff"
		t += "[color=%s]%s[/color]  [color=#999]%s[/color]\n" % [c, p.n, "DOWN" if p.dn else "KIA" if p.dd else "%d HP" % p.hp]
	team_lbl.text = t
	# weapon
	if lp and lp.is_local:
		var w: Dictionary = lp.ws()
		var a: Dictionary = lp.ammo.get(lp.cur, {"mag": 0, "res": 0})
		weapon_lbl.text = w.name.to_upper() + ("   RELOADING" if lp.reloading else "")
		ammo_lbl.text = str(a.mag)
		ammo_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if a.mag <= int(w.mag * 0.25) else Color.WHITE)
		reserve_lbl.text = " / ∞" if a.res < 0 else " / %d" % a.res
		var eq := "[right]"
		eq += _eq("G", "Frag", me.get("fr", 0))
		eq += _eq("4", "Claymore", me.get("mi", 0))
		eq += _eq("5", "Sentry", me.get("tu", 0))
		eq += _eq("6", "Airstrike", me.get("as", 0))
		eq += _eq("7", "Gunship", me.get("dr", 0))
		eq += _eq("8", "Carpet", me.get("cb", 0))
		if me.get("sr", 0) > 0:
			eq += "  [color=#7cc0ff]SELF-REVIVE[/color]"
		equip_lbl.text = eq + "[/right]"
		prompt.text = lp.interact_prompt
		# incoming enemy grenade
		var nade := ""
		for pr in s.get("proj", []):
			if pr[1] == "efrag" and (pr[2] as Vector3).distance_to(lp.global_position) < 8.0:
				var to: Vector3 = pr[2] - lp.global_position
				var ang := wrapf(atan2(-to.x, -to.z) - lp.yaw, -PI, PI)
				nade = "⚠  GRENADE  " + ("↑" if abs(ang) < 0.6 else "↓" if abs(ang) > 2.5 else ("←" if ang > 0 else "→"))
		if nade != "":
			prompt.text = nade
			prompt.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
		else:
			prompt.add_theme_color_override("font_color", Color.WHITE)
		if int(me.get("nv", 0)) > 0:
			eq += "  [color=#7dff8a]N  NVG %s[/color]" % ("ON" if lp.nvg_on else "")
			equip_lbl.text = eq + "[/right]"
		designate_lbl.visible = lp.designating != ""
		scope.visible = lp.scope_view()
		cross.visible = lp.ads < 0.5 and not scope.visible
		cross.queue_redraw()
		# revive progress: either me reviving someone, or someone reviving me
		var rp := 0.0
		if lp.revive_target != 0:
			for p in s.get("players", []):
				if p.id == lp.revive_target:
					rp = p.rp
		elif me.get("dn", false):
			rp = me.get("rp", 0.0)
		revive_bar.visible = rp > 0.0
		revive_lbl.visible = rp > 0.0
		revive_lbl.text = "BEING REVIVED" if me.get("dn", false) else "REVIVING"
		revive_bar.value = rp * 100.0
		if me.get("dn", false):
			downed_lbl.text = "YOU ARE DOWN\n%s %ds" % ["Self-revive in" if me.get("sr", 0) > 0 else "Bleeding out —", ceili(me.get("dt", 0.0))]
		elif me.get("dd", false):
			downed_lbl.text = "KILLED IN ACTION — redeploying when the wave ends" + ("\nSpectating %s   ·   [LMB] / [RMB] switch" % lp.spec_name if lp.spec_name != "" else "")
		else:
			downed_lbl.text = ""
	# announce fade
	if ann_t > 0.0:
		ann_t -= dt
		ann_box.modulate.a = move_toward(ann_box.modulate.a, 1.0 if ann_t > 0.4 else 0.0, dt * 3.0)
	else:
		ann_box.modulate.a = move_toward(ann_box.modulate.a, 0.0, dt * 3.0)
	if combo_t > 0.0:
		combo_t -= dt
		combo_lbl.modulate.a = clamp(combo_t * 3.0, 0.0, 1.0)
		combo_lbl.scale = combo_lbl.scale.lerp(Vector2.ONE, min(1.0, dt * 14.0))
	else:
		combo_lbl.modulate.a = 0.0
	if hit_t > 0.0:
		hit_t -= dt
		hitm.queue_redraw()
	if not dmg_dirs.is_empty():
		for d in dmg_dirs:
			d.t -= dt
		dmg_dirs = dmg_dirs.filter(func(d): return d.t > 0.0)
		dmg_layer.queue_redraw()
	score.visible = Input.is_action_pressed("scoreboard") and not shop_open
	if score.visible and Engine.get_process_frames() % 15 == 0:
		_refresh_score()
	if Engine.get_process_frames() % 3 == 0:
		minimap.queue_redraw()
	markers.queue_redraw()


func _eq(key: String, name: String, n: int) -> String:
	var col := "#e8e6e1" if n > 0 else "#666666"
	return "  [color=#ffd36a]%s[/color] [color=%s]%s %d[/color]" % [key, col, name, n]


func _refresh_score() -> void:
	for c in score_grid.get_children():
		c.queue_free()
	for h in ["NAME", "KILLS", "HEADSHOTS", "EARNED", "STATUS"]:
		_label(h, 14, Color(0.6, 0.6, 0.6), true, score_grid)
	for p in game.snap.get("players", []):
		var col := Color(1.0, 0.83, 0.42) if p.id == game.local_id else Color(0.92, 0.9, 0.85)
		_label(p.n, 20, col, true, score_grid)
		_label(str(p.k), 20, col, false, score_grid)
		_label(str(p.h), 20, col, false, score_grid)
		_label("$%d" % p.e, 20, col, false, score_grid)
		_label("DOWN" if p.dn else "KIA" if p.dd else "OK", 20, col, false, score_grid)


# ------------------------------------------------------------------ drawing
func _draw_cross() -> void:
	var lp: Player = game.player_nodes.get(game.local_id) if game else null
	if lp == null or not lp.is_local:
		return
	var c := cross.size / 2.0
	var w: Dictionary = lp.ws()
	var moving := Vector2(lp.velocity.x, lp.velocity.z).length() > 1.0
	var spread: float = w.spread * (1.6 if moving else 1.0) + lp.bloom
	var gap: float = 6.0 + spread * 900.0 * (1.0 if not lp.sprinting else 1.8)
	var col := Color(1, 1, 1, 0.9)
	var sh := Color(0, 0, 0, 0.6)
	for d in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var a: Vector2 = c + d * gap
		var b: Vector2 = c + d * (gap + 10.0)
		cross.draw_line(a, b, sh, 4.0)
		cross.draw_line(a, b, col, 2.0)
	cross.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)


func _draw_hitmarker() -> void:
	if hit_t <= 0.0:
		return
	var c := hitm.size / 2.0
	var k: float = hit_t / (0.32 if hit_kill else 0.2)
	var col := Color(1.0, 0.22, 0.18, k) if hit_kill else Color(1.0, 0.85, 0.3, k) if hit_head else Color(1, 1, 1, k)
	var r0: float = (10.0 if hit_kill else 8.0) + (1.0 - k) * 4.0
	var r1 := r0 + (14.0 if hit_kill else 10.0)
	var width := 3.5 if hit_kill else 2.5
	for a in [PI / 4, 3 * PI / 4, 5 * PI / 4, 7 * PI / 4]:
		var d := Vector2(cos(a), sin(a))
		hitm.draw_line(c + d * r0, c + d * r1, Color(0, 0, 0, k * 0.6), width + 2.0)
		hitm.draw_line(c + d * r0, c + d * r1, col, width)


func _draw_scope() -> void:
	var c := scope.size / 2.0
	var r := scope.size.y * 0.42
	# black outside a circle
	var pts := PackedVector2Array()
	for i in 65:
		var a := i / 64.0 * TAU
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	scope.draw_rect(Rect2(Vector2.ZERO, Vector2(c.x - r, scope.size.y)), Color.BLACK)
	scope.draw_rect(Rect2(Vector2(c.x + r, 0), Vector2(scope.size.x - c.x - r, scope.size.y)), Color.BLACK)
	for i in 64:
		var a0 := i / 64.0 * TAU
		var a1 := (i + 1) / 64.0 * TAU
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var o0 := c + Vector2(cos(a0), sin(a0)) * r * 3.0
		var o1 := c + Vector2(cos(a1), sin(a1)) * r * 3.0
		scope.draw_colored_polygon(PackedVector2Array([p0, o0, o1, p1]), Color.BLACK)
	scope.draw_polyline(pts, Color(0, 0, 0), 6.0)
	scope.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.9), 1.5)
	scope.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.9), 1.5)
	scope.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - 40, c.y), Color.BLACK, 5.0)
	scope.draw_line(Vector2(c.x + 40, c.y), Vector2(c.x + r, c.y), Color.BLACK, 5.0)
	scope.draw_line(Vector2(c.x, c.y + 40), Vector2(c.x, c.y + r), Color.BLACK, 5.0)
	scope.draw_circle(c, 1.5, Color(1, 0.2, 0.1))


func _draw_dmg() -> void:
	var c := dmg_layer.size / 2.0
	for d in dmg_dirs:
		var a: float = d.a
		var k: float = d.t / 1.2
		var pts := PackedVector2Array()
		for i in 13:
			var t := a - 0.35 + 0.7 * i / 12.0
			pts.append(c + Vector2(sin(t), -cos(t)) * 150.0)
		dmg_layer.draw_polyline(pts, Color(0.9, 0.12, 0.08, 0.85 * k), 9.0)


func _world_to_map(rel: Vector3, yaw: float, scale: float, center: Vector2) -> Vector2:
	var x := rel.x * cos(yaw) - rel.z * sin(yaw)
	var z := rel.x * sin(yaw) + rel.z * cos(yaw)
	return center + Vector2(x, z) * scale


func _draw_minimap() -> void:
	var lp: Player = game.player_nodes.get(game.local_id)
	if lp == null:
		return
	var sz := minimap.size
	var c := sz / 2.0
	var sc := 2.2
	var yaw := lp.yaw if lp.is_local else 0.0
	var me := lp.global_position
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.06, 0.06, 0.55))
	var view := Rect2(Vector2(-60, -60), sz + Vector2(120, 120))
	for item in game.map.minimap_polys:
		var pts := PackedVector2Array()
		var inside := false
		for k in item[0]:
			var p := _world_to_map(Vector3(k.x, 0, k.y) - me, yaw, sc, c)
			pts.append(p)
			inside = inside or view.has_point(p)
		if inside and pts.size() >= 3:
			minimap.draw_colored_polygon(pts, item[1])
	for ln in game.map.minimap_lines:
		var a := _world_to_map(Vector3(ln[0].x, 0, ln[0].y) - me, yaw, sc, c)
		var b := _world_to_map(Vector3(ln[1].x, 0, ln[1].y) - me, yaw, sc, c)
		if view.has_point(a) or view.has_point(b):
			minimap.draw_line(a, b, ln[2], 1.5)
	for st in game.map.stations:
		var p := _world_to_map(st.pos - me, yaw, sc, c)
		minimap.draw_circle(p, 4.0, Defs.CAT_COLORS[st.cat])
	for e in game.enemies.values():
		if not is_instance_valid(e):
			continue
		var p := _world_to_map(e.global_position - me, yaw, sc, c)
		if Rect2(Vector2.ZERO, sz).has_point(p):
			minimap.draw_circle(p, 5.0 if e.type == "heavy" else 3.0, Color(1.0, 0.25, 0.2))
	for pn in game.player_nodes.values():
		if pn == lp:
			continue
		var p := _world_to_map(pn.global_position - me, yaw, sc, c)
		minimap.draw_circle(p, 4.0, Color(1, 0.4, 0.3) if pn.state.get("dn", false) else Color(0.45, 0.75, 1.0))
	minimap.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(-6, 6)]), Color(1, 0.85, 0.3))
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.25), false, 1.0)


func _draw_markers() -> void:
	var lp: Player = game.player_nodes.get(game.local_id)
	if lp == null or not lp.is_local:
		return
	var cam := lp.cam
	var f := font_bold
	var armory := Vector3.ZERO
	for st in game.map.stations:
		armory += st.pos
	armory = armory / max(1, game.map.stations.size()) + Vector3(0, 3.2, 0)
	if lp.global_position.distance_to(armory) > 10.0 and not cam.is_position_behind(armory):
		var p := cam.unproject_position(armory)
		var d := lp.global_position.distance_to(armory)
		_marker(p, "ARMORY  %dm" % roundi(d), Color(1.0, 0.83, 0.42), f)
	for pn in game.player_nodes.values():
		if pn == lp or pn.state.get("dd", false):
			continue
		var wp: Vector3 = pn.global_position + Vector3(0, 2.3, 0)
		if not cam.is_position_behind(wp):
			var p := cam.unproject_position(wp)
			_marker(p, ("REVIVE  " if pn.state.get("dn", false) else "") + pn.state.get("n", ""), Color(1, 0.4, 0.3) if pn.state.get("dn", false) else Color(0.5, 0.78, 1.0), f)
	for e in game.enemies.values():
		if not is_instance_valid(e) or e.type != "heavy":
			continue
		var wp: Vector3 = e.global_position + Vector3(0, 2.6, 0)
		if not cam.is_position_behind(wp):
			var p := cam.unproject_position(wp)
			markers.draw_rect(Rect2(p - Vector2(40, 3), Vector2(80, 6)), Color(0, 0, 0, 0.6))
			markers.draw_rect(Rect2(p - Vector2(40, 3), Vector2(80.0 * e.hp_pct / 100.0, 6)), Color(1.0, 0.3, 0.2))


func _marker(p: Vector2, text: String, col: Color, f: Font) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
	markers.draw_string_outline(f, p + Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
	markers.draw_string(f, p + Vector2(-w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
	var d := p + Vector2(0, 10)
	markers.draw_colored_polygon(PackedVector2Array([d + Vector2(0, -5), d + Vector2(5, 0), d + Vector2(0, 5), d + Vector2(-5, 0)]), col)
