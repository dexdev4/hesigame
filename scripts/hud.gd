class_name Hud
extends CanvasLayer
## All 2D UI, built in code: the driving HUD, the pedals and every menu screen.
## Menus are styled as green highway guide signs. Button presses are reported
## through the `act` signal; the game script owns all logic.

signal act(action: String, arg: String)

const SIGN := Color("#0d6a42")
const SIGN_DEEP := Color("#08482c")
const LINE := Color("#f3f5ef")
const AMBER := Color("#f5b52e")
const AMBER_INK := Color("#1d1503")
const TAIL := Color("#ff3b2a")
const MUTED := Color("#b5c4ba")
const RED_SIGN := Color("#5a1717")
const SCRIM := Color(0.03, 0.04, 0.05, 0.62)

var display_font: SystemFont
var mono_font: SystemFont
var body_font: SystemFont
var root: Control
var play_layer: Control
var screens := {}

var gas: Pedal
var brake: Pedal
var pause_btn: Button
var _top_margin: MarginContainer
var _score: Label
var _mult: Label
var _mult_bg: PanelContainer
var _combo: ProgressBar
var _lives_ctrl: Control
var _lives := 3
var _max_lives := 3
var _goal: PanelContainer
var _g := {}
var _kmh: Label
var _sp_tag: Label
var _unit: Label
var _rpm: ProgressBar
var _pops: VBoxContainer
var _banner: VBoxContainer
var _banner_t: Label
var _banner_s: Label
var _hint: Label
var _banner_tween: Tween
var _hint_tween: Tween
var _fill_white: StyleBoxFlat
var _fill_amber: StyleBoxFlat
var _fill_red: StyleBoxFlat

# menu widgets that get refreshed
var _menu := {}
var _garage := {}
var _boss := {}
var _pick := {}
var _pause := {}
var _over := {}
var garage_tab := "cars"


func _ready() -> void:
	layer = 1
	display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Impact", "Oswald", "Roboto Condensed", "Arial Narrow", "sans-serif"])
	display_font.font_weight = 800
	mono_font = SystemFont.new()
	mono_font.font_names = PackedStringArray(["Roboto Mono", "DejaVu Sans Mono", "Menlo", "monospace"])
	mono_font.font_weight = 700
	body_font = SystemFont.new()
	body_font.font_names = PackedStringArray(["Roboto", "Noto Sans", "Segoe UI", "DejaVu Sans", "sans-serif"])

	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = body_font
	th.default_font_size = 26
	root.theme = th
	add_child(root)

	_fill_white = _flat(LINE, 6)
	_fill_amber = _flat(AMBER, 6)
	_fill_red = _flat(TAIL, 6)

	_build_play()
	_build_menu()
	_build_garage()
	_build_boss()
	_build_pick()
	_build_pause()
	_build_over()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


# ---------------------------------------------------------------- helpers

func _flat(c: Color, radius := 10, border := Color.TRANSPARENT, bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	return sb


func _sign_style(bg: Color) -> StyleBoxFlat:
	var sb := _flat(bg, 26, LINE, 5)
	sb.expand_margin_left = 10
	sb.expand_margin_right = 10
	sb.expand_margin_top = 10
	sb.expand_margin_bottom = 10
	sb.set_content_margin_all(30)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	sb.shadow_offset = Vector2(0, 14)
	return sb


func _label(text: String, size: int, color := LINE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wrap(text: String, size: int, color := LINE) -> Label:
	var l := _label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


func _eyebrow(text: String) -> Label:
	var l := _label(text.to_upper(), 18, MUTED, mono_font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, kind: String, action: String, arg := "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", display_font)
	b.add_theme_font_size_override("font_size", 34)
	var bg := LINE
	var fg := SIGN_DEEP
	if kind == "amber":
		bg = AMBER
		fg = AMBER_INK
	var normal := _flat(bg, 12)
	if kind == "ghost":
		normal = _flat(Color.TRANSPARENT, 12, LINE, 3)
		fg = LINE
	normal.set_content_margin_all(16)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.12) if kind != "ghost" else Color(1, 1, 1, 0.08)
	var press := normal.duplicate() as StyleBoxFlat
	press.bg_color = bg.darkened(0.15) if kind != "ghost" else Color(1, 1, 1, 0.16)
	var dis := normal.duplicate() as StyleBoxFlat
	dis.bg_color = Color(bg, 0.35) if kind != "ghost" else Color.TRANSPARENT
	var focus := _flat(Color.TRANSPARENT, 14, AMBER, 4)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", press)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_stylebox_override("focus", focus)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.5))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if action != "":
		b.pressed.connect(func() -> void: act.emit(action, arg))
	return b


func _stat(value: String, caption: String, value_color := LINE) -> Array:
	var p := PanelContainer.new()
	var sb := _flat(SIGN_DEEP, 12)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var v := _label(value, 30, value_color, mono_font)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(v)
	vb.add_child(_label(caption.to_upper(), 15, MUTED, mono_font))
	return [p, v]


func _row(sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _bar(fill: StyleBoxFlat, height := 10) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.0
	pb.custom_minimum_size.y = height
	pb.add_theme_stylebox_override("background", _flat(Color(0, 0, 0, 0.35), 6))
	pb.add_theme_stylebox_override("fill", fill)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb


## A full-screen scrim with a centred highway-sign panel. Returns its VBox.
func _screen(name: String, bg := SIGN, width := 660.0) -> VBoxContainer:
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.add_child(scrim)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scr.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	margin.set_meta("max_w", width)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sign_style(bg))
	column.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	panel.add_child(vb)
	scr.visible = false
	root.add_child(scr)
	screens[name] = scr
	return vb


func show_screen(name: String) -> void:
	for k in screens:
		screens[k].visible = k == name


func _apply_safe_area() -> void:
	var vp := get_viewport().get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var top := 0.0
	var bottom := 0.0
	if win.x > 0 and win.y > 0 and safe.size.y > 0 and OS.has_feature("mobile"):
		var k := vp.y / win.y
		top = maxf(0.0, safe.position.y) * k
		bottom = maxf(0.0, win.y - safe.end.y) * k
	_top_margin.add_theme_constant_override("margin_top", int(18 + top))
	_goal.offset_top = 160 + top
	gas.offset_bottom = -(30 + bottom)
	gas.offset_top = gas.offset_bottom - 262
	brake.offset_bottom = -(30 + bottom)
	brake.offset_top = brake.offset_bottom - 176
	_kmh.get_parent().offset_bottom = -(26 + bottom)
	# menu panels fill the width on phones and stay readable on wide screens
	for k in screens:
		var margin: MarginContainer = screens[k].get_child(1).get_child(0)
		var side := maxf(34.0, (vp.x - float(margin.get_meta("max_w"))) / 2.0)
		margin.add_theme_constant_override("margin_left", int(side))
		margin.add_theme_constant_override("margin_right", int(side))
		margin.add_theme_constant_override("margin_top", int(60 + top))
		margin.add_theme_constant_override("margin_bottom", int(60 + bottom))


# ---------------------------------------------------------------- play HUD

func _build_play() -> void:
	play_layer = Control.new()
	play_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	play_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(play_layer)

	_top_margin = MarginContainer.new()
	_top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_margin.add_theme_constant_override("margin_left", 22)
	_top_margin.add_theme_constant_override("margin_right", 22)
	_top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_layer.add_child(_top_margin)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_margin.add_child(top)

	_lives_ctrl = Control.new()
	_lives_ctrl.custom_minimum_size = Vector2(150, 40)
	_lives_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lives_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_ctrl.draw.connect(_draw_lives)
	top.add_child(_lives_ctrl)

	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_BEGIN
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(mid)
	_score = _label("0", 84, LINE, display_font)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_score.add_theme_constant_override("shadow_offset_y", 4)
	mid.add_child(_score)
	var combo_row := _row(10)
	combo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(combo_row)
	_mult_bg = PanelContainer.new()
	var msb := _flat(AMBER, 6)
	msb.content_margin_left = 10
	msb.content_margin_right = 10
	_mult_bg.add_theme_stylebox_override("panel", msb)
	_mult = _label("x1.0", 24, AMBER_INK, mono_font)
	_mult_bg.add_child(_mult)
	combo_row.add_child(_mult_bg)
	_combo = _bar(_fill_amber, 9)
	_combo.custom_minimum_size.x = 110
	combo_row.add_child(_combo)

	var right := HBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right)
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.custom_minimum_size = Vector2(72, 72)
	pause_btn.add_theme_font_override("font", display_font)
	pause_btn.add_theme_font_size_override("font_size", 28)
	var pst := _flat(Color(0.04, 0.05, 0.06, 0.45), 36, Color(LINE, 0.7), 3)
	pause_btn.add_theme_stylebox_override("normal", pst)
	pause_btn.add_theme_stylebox_override("hover", pst)
	pause_btn.add_theme_stylebox_override("pressed", pst)
	pause_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_btn.pressed.connect(func() -> void: act.emit("pause", ""))
	right.add_child(pause_btn)

	# goal sign
	_goal = PanelContainer.new()
	_goal.anchor_left = 0.5
	_goal.anchor_right = 0.5
	_goal.offset_left = -250
	_goal.offset_right = 250
	_goal.offset_top = 160
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := _flat(SIGN, 14, LINE, 3)
	gs.set_content_margin_all(12)
	gs.content_margin_left = 18
	gs.content_margin_right = 18
	_goal.add_theme_stylebox_override("panel", gs)
	_g["style"] = gs
	play_layer.add_child(_goal)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 4)
	_goal.add_child(gv)
	var head := _row(8)
	gv.add_child(head)
	_g["title"] = _label("STAGE 1", 28, LINE, display_font)
	_g["title"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_g["title"])
	_g["sub"] = _label("", 18, MUTED, display_font)
	_g["sub"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_g["sub"])
	for i in [1, 2]:
		var r := _row(10)
		gv.add_child(r)
		var l := _label("DIST", 16, MUTED, mono_font)
		l.custom_minimum_size.x = 64
		r.add_child(l)
		var b := _bar(_fill_white, 10)
		r.add_child(b)
		var v := _label("0", 17, LINE, mono_font)
		v.custom_minimum_size.x = 150
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(v)
		_g["l%d" % i] = l
		_g["b%d" % i] = b
		_g["v%d" % i] = v

	_pops = VBoxContainer.new()
	_pops.anchor_left = 0.0
	_pops.anchor_right = 1.0
	_pops.anchor_top = 0.36
	_pops.anchor_bottom = 0.36
	_pops.alignment = BoxContainer.ALIGNMENT_BEGIN
	_pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_layer.add_child(_pops)

	_banner = VBoxContainer.new()
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.24
	_banner.anchor_bottom = 0.24
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	play_layer.add_child(_banner)
	_banner_t = _label("", 110, LINE, display_font)
	_banner_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_banner_t.add_theme_constant_override("shadow_offset_y", 5)
	_banner.add_child(_banner_t)
	_banner_s = _label("", 22, AMBER, mono_font)
	_banner_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_child(_banner_s)

	_hint = _label("Swipe left or right anywhere to steer", 24, LINE, mono_font)
	_hint.anchor_right = 1.0
	_hint.anchor_top = 0.56
	_hint.anchor_bottom = 0.56
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.modulate.a = 0.0
	play_layer.add_child(_hint)

	var speedo := VBoxContainer.new()
	speedo.anchor_left = 0.5
	speedo.anchor_right = 0.5
	speedo.anchor_top = 1.0
	speedo.anchor_bottom = 1.0
	speedo.offset_left = -140
	speedo.offset_right = 140
	speedo.offset_top = -150
	speedo.offset_bottom = -26
	speedo.alignment = BoxContainer.ALIGNMENT_END
	speedo.add_theme_constant_override("separation", 0)
	speedo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_layer.add_child(speedo)
	_sp_tag = _label("", 16, AMBER, mono_font)
	_sp_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speedo.add_child(_sp_tag)
	_kmh = _label("0", 64, LINE, mono_font)
	_kmh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kmh.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_kmh.add_theme_constant_override("shadow_offset_y", 3)
	speedo.add_child(_kmh)
	_unit = _label("KM/H", 18, MUTED, mono_font)
	_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speedo.add_child(_unit)
	_rpm = _bar(_fill_white, 8)
	_rpm.custom_minimum_size.x = 190
	_rpm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	speedo.add_child(_rpm)
	speedo.move_child(_rpm, 1)

	brake = Pedal.new()
	brake.kind = "brake"
	brake.anchor_top = 1.0
	brake.anchor_bottom = 1.0
	brake.offset_left = 26
	brake.offset_right = 26 + 210
	play_layer.add_child(brake)
	gas = Pedal.new()
	gas.kind = "gas"
	gas.anchor_left = 1.0
	gas.anchor_right = 1.0
	gas.anchor_top = 1.0
	gas.anchor_bottom = 1.0
	gas.offset_left = -26 - 140
	gas.offset_right = -26
	play_layer.add_child(gas)
	play_layer.visible = false


func _draw_lives() -> void:
	var c := _lives_ctrl
	for i in _max_lives:
		var x := 4.0 + i * 46.0
		var y := 10.0
		var on := i < _lives
		var col := AMBER if on else Color(LINE, 0.4)
		var body := PackedVector2Array([Vector2(x, y + 20), Vector2(x, y + 11), Vector2(x + 7, y + 3), Vector2(x + 30, y + 3),
			Vector2(x + 37, y + 11), Vector2(x + 40, y + 11), Vector2(x + 40, y + 20)])
		if on:
			c.draw_colored_polygon(body, col)
			c.draw_rect(Rect2(x + 9, y + 5, 9, 6), Color("#1b1e23", 0.55))
			c.draw_rect(Rect2(x + 21, y + 5, 9, 6), Color("#1b1e23", 0.55))
		else:
			body.append(body[0])
			c.draw_polyline(body, col, 2.0)
		c.draw_circle(Vector2(x + 9, y + 21), 4.5, col if on else Color(LINE, 0.25))
		c.draw_circle(Vector2(x + 31, y + 21), 4.5, col if on else Color(LINE, 0.25))


func set_play_visible(on: bool) -> void:
	play_layer.visible = on


## Which on-screen control a touch at `pos` lands on: "gas", "brake", "ui" or "".
func role_at(pos: Vector2) -> String:
	if not play_layer.visible:
		return "ui"
	if gas.hit_rect().has_point(pos):
		return "gas"
	if brake.hit_rect().has_point(pos):
		return "brake"
	if pause_btn.get_global_rect().grow(12).has_point(pos):
		return "ui"
	return ""


func set_pedals(g: bool, b: bool) -> void:
	gas.pressed = g
	brake.pressed = b


func update_play(d: Dictionary) -> void:
	_score.text = d.score
	_mult.text = d.mult
	_mult_bg.modulate = Color(1, 1, 1, 1) if d.combo_on else Color(1, 1, 1, 0.45)
	_combo.value = d.combo_frac
	if d.lives != _lives or d.max_lives != _max_lives:
		_lives = d.lives
		_max_lives = d.max_lives
		_lives_ctrl.queue_redraw()
	_kmh.text = d.kmh
	_unit.text = "KM/H  ·  GEAR %d" % d.gear
	_rpm.value = clampf(d.rpm, 0.0, 1.0)
	_rpm.add_theme_stylebox_override("fill", _fill_red if d.rpm > 0.9 else (_fill_amber if d.rpm > 0.75 else _fill_white))
	_kmh.add_theme_color_override("font_color", AMBER if d.fast else LINE)
	_sp_tag.text = "HIGH SPEED BONUS" if d.fast else ""
	(_g["style"] as StyleBoxFlat).bg_color = RED_SIGN if d.boss else SIGN
	_g.title.text = d.title
	_g.sub.text = d.sub
	_g.l1.text = d.l1
	_g.l2.text = d.l2
	_g.b1.value = clampf(d.f1, 0.0, 1.0)
	_g.b2.value = clampf(d.f2, 0.0, 1.0)
	_g.v1.text = d.v1
	_g.v2.text = d.v2
	_g.b1.add_theme_stylebox_override("fill", _fill_amber if d.done1 else _fill_white)
	_g.b2.add_theme_stylebox_override("fill", _fill_red if d.boss else (_fill_amber if d.done2 else _fill_white))


func pop(text: String, kind := "") -> void:
	var size := 44
	var col := LINE
	if kind == "hot":
		size = 54
		col = AMBER
	elif kind == "bad":
		col = TAIL
	var l := _label(text, size, col, display_font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.modulate.a = 0.0
	_pops.add_child(l)
	_pops.move_child(l, 0)
	while _pops.get_child_count() > 4:
		var old := _pops.get_child(_pops.get_child_count() - 1)
		_pops.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.tween_interval(0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


func banner(title: String, sub := "") -> void:
	_banner_t.text = title
	_banner_s.text = sub
	if _banner_tween:
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_interval(1.7)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


func show_hint() -> void:
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 0.95, 0.3)
	_hint_tween.tween_interval(4.0)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.6)


# ---------------------------------------------------------------- menus

func _build_menu() -> void:
	var v := _screen("menu")
	v.add_child(_eyebrow("Interstate 4 · Eastbound · All lanes open"))
	var title := _label("REDLINE\nRUSH", 112, LINE, display_font)
	title.add_theme_constant_override("line_spacing", -30)
	v.add_child(title)
	v.add_child(_wrap("Weave through four lanes of traffic. Close passes and late lane changes at speed pay the most. Three taps and the run is over.", 26))
	var stats := _row(12)
	v.add_child(stats)
	var a := _stat("$0", "Cash", AMBER)
	var b := _stat("0", "Best run")
	var c := _stat("Kestrel", "Your car")
	for s in [a, b, c]:
		stats.add_child(s[0])
	_menu["cash"] = a[1]
	_menu["best"] = b[1]
	_menu["car"] = c[1]
	var btns := _row(14)
	v.add_child(btns)
	btns.add_child(_button("START RUN  →", "amber", "start"))
	btns.add_child(_button("GARAGE", "light", "garage"))
	var tg := _row(12)
	v.add_child(tg)
	_menu["sound"] = _toggle("Engine sound", "sound")
	_menu["assist"] = _toggle("Lane assist", "assist")
	tg.add_child(_menu["sound"])
	tg.add_child(_menu["assist"])
	var how := RichTextLabel.new()
	how.bbcode_enabled = true
	how.fit_content = true
	how.scroll_active = false
	how.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how.add_theme_font_size_override("normal_font_size", 22)
	how.add_theme_font_size_override("bold_font_size", 22)
	how.add_theme_color_override("default_color", MUTED)
	how.text = ("• [b][color=#f3f5ef]Gas[/color][/b] pedal on the right, [b][color=#f3f5ef]brake[/color][/b] pedal on the left.\n"
		+ "• [b][color=#f3f5ef]Swipe[/color][/b] across the screen to steer. Lane assist settles you into the nearest lane when you lift.\n"
		+ "• Pass cars inside 1 m for a [b][color=#f3f5ef]near miss[/color][/b]. Change lanes right beside a car for a [b][color=#f3f5ef]close cut[/color][/b]. Chains build your multiplier.\n"
		+ "• Cover the distance and hit the points target to face the [b][color=#f3f5ef]boss[/color][/b]. Out-score it before the finish gantry.")
	v.add_child(how)


func _toggle(text: String, action: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	var sb := _flat(SIGN_DEEP, 12)
	sb.set_content_margin_all(14)
	for k in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("focus", _flat(Color.TRANSPARENT, 12, AMBER, 3))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: act.emit(action, ""))
	b.set_meta("base", text)
	return b


func render_menu() -> void:
	_menu.cash.text = "$" + Fmt.num(Save.data.cash)
	_menu.best.text = Fmt.num(Save.data.best)
	_menu.car.text = Data.car_by_id(Save.data.selected).name
	_menu.sound.text = "%s:  %s" % [_menu.sound.get_meta("base"), "ON" if Save.data.sound else "OFF"]
	_menu.assist.text = "%s:  %s" % [_menu.assist.get_meta("base"), "ON" if Save.data.assist else "OFF"]


func _build_garage() -> void:
	var v := _screen("garage", SIGN, 720)
	var head := _row(10)
	v.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_eyebrow("Exit 12 · Service area"))
	tv.add_child(_label("GARAGE", 84, LINE, display_font))
	head.add_child(tv)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_END
	var ce := _eyebrow("Cash")
	ce.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(ce)
	_garage["cash"] = _label("$0", 38, AMBER, mono_font)
	cv.add_child(_garage.cash)
	head.add_child(cv)
	var tabs := _row(8)
	v.add_child(tabs)
	_garage["tab_cars"] = _button("CARS", "light", "tab", "cars")
	_garage["tab_up"] = _button("UPGRADES", "light", "tab", "up")
	tabs.add_child(_garage.tab_cars)
	tabs.add_child(_garage.tab_up)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 620
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	_garage["list"] = list
	_garage["scroll"] = scroll
	v.add_child(_button("BACK TO MENU", "ghost", "menu"))


func _card() -> Array:
	var p := PanelContainer.new()
	var sb := _flat(SIGN_DEEP, 14)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	return [p, vb]


func render_garage() -> void:
	_garage.cash.text = "$" + Fmt.num(Save.data.cash)
	_garage.tab_cars.modulate = Color(1, 1, 1, 1) if garage_tab == "cars" else Color(1, 1, 1, 0.5)
	_garage.tab_up.modulate = Color(1, 1, 1, 1) if garage_tab == "up" else Color(1, 1, 1, 0.5)
	var list: VBoxContainer = _garage.list
	for ch in list.get_children():
		list.remove_child(ch)
		ch.queue_free()
	if garage_tab == "cars":
		for c in Data.CARS:
			var owned := Save.owns(c.id)
			var sel: bool = Save.data.selected == c.id
			var locked: bool = c.boss >= 0 and not Save.is_unlocked(c.id)
			var card := _card()
			list.add_child(card[0])
			var top := _row(12)
			card[1].add_child(top)
			var sw := ColorRect.new()
			sw.color = Color(c.color)
			sw.custom_minimum_size = Vector2(22, 22)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			top.add_child(sw)
			var nm := _label(String(c.name).to_upper(), 34, LINE, display_font)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top.add_child(nm)
			var btn: Button
			if sel:
				btn = _button("DRIVING", "light", "")
				btn.disabled = true
			elif owned:
				btn = _button("SELECT", "light", "select", c.id)
			elif locked:
				btn = _button("LOCKED", "ghost", "")
				btn.disabled = true
			else:
				btn = _button("$" + Fmt.num(c.price), "amber", "buy", c.id)
				btn.disabled = Save.data.cash < c.price
			btn.size_flags_horizontal = Control.SIZE_SHRINK_END
			btn.add_theme_font_size_override("font_size", 26)
			top.add_child(btn)
			var sub: String = c.blurb if not locked else "Beat %s to put this car up for sale." % Data.BOSSES[c.boss].name
			card[1].add_child(_wrap(sub, 20, MUTED))
			var grid := GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 10)
			card[1].add_child(grid)
			var specs := [["ACCEL", c.accel / 12.0, "%.1f m/s²" % c.accel], ["TOP", c.top / 85.0, "%d km/h" % roundi(c.top * 3.6)],
				["GRIP", c.grip / 15.0, "%.1f" % c.grip], ["BRAKE", c.brake / 14.0, "%.1f" % c.brake]]
			for s in specs:
				var sv := VBoxContainer.new()
				sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sv.add_theme_constant_override("separation", 2)
				sv.add_child(_label(s[0], 13, MUTED, mono_font))
				sv.add_child(_label(s[2], 15, LINE, mono_font))
				var bar := _bar(_fill_white, 7)
				bar.value = clampf(s[1], 0.0, 1.0)
				sv.add_child(bar)
				grid.add_child(sv)
	else:
		for p in Data.PERM:
			var lv := Save.perm_level(p.id)
			var maxed: bool = lv >= p.max
			var cost := Data.perm_cost(p, lv)
			var card := _card()
			list.add_child(card[0])
			var top := _row(12)
			card[1].add_child(top)
			var nm := _label(String(p.name).to_upper(), 36, LINE, display_font)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top.add_child(nm)
			var btn: Button
			if maxed:
				btn = _button("MAXED", "light", "")
				btn.disabled = true
			else:
				btn = _button("$" + Fmt.num(cost), "amber", "perm", p.id)
				btn.disabled = Save.data.cash < cost
			btn.size_flags_horizontal = Control.SIZE_SHRINK_END
			btn.add_theme_font_size_override("font_size", 26)
			top.add_child(btn)
			card[1].add_child(_wrap(p.desc, 20, MUTED))
			var pips := _row(6)
			for i in p.max:
				var r := ColorRect.new()
				r.custom_minimum_size = Vector2(30, 10)
				r.color = AMBER if i < lv else Color(1, 1, 1, 0.18)
				pips.add_child(r)
			card[1].add_child(pips)
		list.add_child(_wrap("Upgrades apply to every car you own.", 20, MUTED))


func _build_boss() -> void:
	var v := _screen("boss", RED_SIGN)
	_boss["eyebrow"] = _eyebrow("Stage 1 boss")
	v.add_child(_boss.eyebrow)
	_boss["name"] = _label("COPPERHEAD", 84, LINE, display_font)
	_boss.name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_boss.name)
	_boss["line"] = _wrap("", 26)
	v.add_child(_boss.line)
	var stats := _row(12)
	v.add_child(stats)
	var a := _stat("0", "Points to beat", AMBER)
	var b := _stat("2.0 km", "Race length")
	var c := _stat("—", "Rival car")
	for s in [a, b, c]:
		stats.add_child(s[0])
	_boss["target"] = a[1]
	_boss["car"] = c[1]
	v.add_child(_wrap("Score more than the rival before the finish gantry. Lose and it costs a life, then you get a rematch.", 21, MUTED))
	v.add_child(_button("RACE  →", "amber", "race"))


func show_boss_intro(eyebrow: String, name: String, line: String, target: String, car: String) -> void:
	_boss.eyebrow.text = eyebrow.to_upper()
	_boss.name.text = name.to_upper()
	_boss.line.text = line
	_boss.target.text = target
	_boss.car.text = car
	show_screen("boss")


func _build_pick() -> void:
	var v := _screen("pick", SIGN, 720)
	_pick["eyebrow"] = _eyebrow("Boss beaten")
	v.add_child(_pick.eyebrow)
	v.add_child(_label("PICK AN UPGRADE", 68, LINE, display_font))
	_pick["line"] = _wrap("", 24)
	v.add_child(_pick.line)
	_pick["list"] = VBoxContainer.new()
	_pick.list.add_theme_constant_override("separation", 14)
	v.add_child(_pick.list)


func show_pick(eyebrow: String, line: String, boons: Array) -> void:
	_pick.eyebrow.text = eyebrow.to_upper()
	_pick.line.text = line
	for ch in _pick.list.get_children():
		_pick.list.remove_child(ch)
		ch.queue_free()
	for b in boons:
		var btn := Button.new()
		var sb := _flat(SIGN_DEEP, 14, Color.TRANSPARENT, 3)
		sb.set_content_margin_all(18)
		var hv := sb.duplicate() as StyleBoxFlat
		hv.border_color = AMBER
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", hv)
		btn.add_theme_stylebox_override("pressed", hv)
		btn.add_theme_stylebox_override("focus", hv)
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 20
		vb.offset_top = 14
		vb.offset_right = -20
		vb.offset_bottom = -14
		vb.add_child(_label(b.tag, 16, AMBER, mono_font))
		vb.add_child(_label(String(b.name).to_upper(), 40, LINE, display_font))
		vb.add_child(_label(b.desc, 21, MUTED))
		btn.add_child(vb)
		btn.custom_minimum_size = Vector2(0, 140)
		var id: String = b.id
		btn.pressed.connect(func() -> void: act.emit("boon", id))
		_pick.list.add_child(btn)
	show_screen("pick")


func _build_pause() -> void:
	var v := _screen("pause")
	v.add_child(_eyebrow("Hazards on"))
	v.add_child(_label("PAUSED", 84, LINE, display_font))
	var stats := _row(12)
	v.add_child(stats)
	var a := _stat("0", "Score")
	var b := _stat("0 km", "Distance")
	var c := _stat("1", "Stage")
	for s in [a, b, c]:
		stats.add_child(s[0])
	_pause["score"] = a[1]
	_pause["dist"] = b[1]
	_pause["stage"] = c[1]
	var btns := _row(14)
	v.add_child(btns)
	btns.add_child(_button("RESUME", "amber", "resume"))
	btns.add_child(_button("END RUN", "ghost", "quit"))


func show_pause(score: String, dist: String, stage: String) -> void:
	_pause.score.text = score
	_pause.dist.text = dist
	_pause.stage.text = stage
	show_screen("pause")


func _build_over() -> void:
	var v := _screen("over", RED_SIGN)
	_over["reason"] = _eyebrow("Run over")
	v.add_child(_over.reason)
	v.add_child(_label("RUN OVER", 84, LINE, display_font))
	var stats := _row(12)
	v.add_child(stats)
	var a := _stat("0", "Score")
	var b := _stat("0 km", "Distance")
	var c := _stat("0", "Bosses")
	for s in [a, b, c]:
		stats.add_child(s[0])
	_over["score"] = a[1]
	_over["dist"] = b[1]
	_over["boss"] = c[1]
	var pay := _stat("+$0", "Paid out", AMBER)
	v.add_child(pay[0])
	_over["cash"] = pay[1]
	_over["note"] = _wrap("", 21, MUTED)
	v.add_child(_over.note)
	var btns := _row(14)
	v.add_child(btns)
	btns.add_child(_button("RUN AGAIN", "amber", "start"))
	btns.add_child(_button("GARAGE", "light", "garage"))
	v.add_child(_button("MENU", "ghost", "menu"))


func show_over(reason: String, score: String, dist: String, bosses: String, cash: String, note: String) -> void:
	_over.reason.text = reason.to_upper()
	_over.score.text = score
	_over.dist.text = dist
	_over.boss.text = bosses
	_over.cash.text = cash
	_over.note.text = note
	show_screen("over")
