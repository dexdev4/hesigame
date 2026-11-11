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
var wheel: SteerWheel
var arrows: ArrowPad
var pause_btn: Button
var cam_btn: Button
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
var _set := {}
var _bottom := 0.0
var _play_on := false
var _editing := false
var _drag := {}
var _over := {}
var garage_tab := "cars"
var _solid: Array[Control] = []  # panels on sheet screens (drags elsewhere turn the garage camera)
var fps_label: Label
var _fuel_bar: ProgressBar
var _fuel_val: Label
var _fuel_next: Label
var _rf := {}
var mirror: RearMirror
var stick: FloatStick
var _feed: VBoxContainer


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
	_build_map()
	_build_boss()
	_build_pick()
	_build_pause()
	_build_over()
	_build_settings()
	_build_pedal_editor()
	_build_replay()
	_build_refuel()
	fps_label = _label("", 20, AMBER, mono_font)
	fps_label.position = Vector2(22, 0)
	fps_label.anchor_top = 0.15
	fps_label.anchor_bottom = 0.15
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fps_label)
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
	scroll.scroll_deadzone = 100000  # touch scrolling is handled in _input instead
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
	_bottom = bottom
	layout_pedals()
	_kmh.get_parent().offset_bottom = -(26 + bottom)
	# menu panels fill the width on phones and stay readable on wide screens
	for k in screens:
		if screens[k].has_meta("sheet"):
			_layout_sheet(screens[k], vp, top, bottom)
			continue
		var margin: MarginContainer = screens[k].get_child(1).get_child(0)
		var side := maxf(34.0, (vp.x - float(margin.get_meta("max_w"))) / 2.0)
		margin.add_theme_constant_override("margin_left", int(side))
		margin.add_theme_constant_override("margin_right", int(side))
		margin.add_theme_constant_override("margin_top", int(60 + top))
		margin.add_theme_constant_override("margin_bottom", int(60 + bottom))


func _layout_sheet(scr: Control, vp: Vector2, top: float, bottom: float) -> void:
	var portrait := vp.y > vp.x
	if scr.has_meta("panel"):
		var panel: PanelContainer = scr.get_meta("panel")
		var w := minf(vp.x - 24.0, float(panel.get_meta("max_w")))
		if not portrait:
			w = minf(w, vp.x * 0.5)
		panel.custom_minimum_size.x = w
		panel.offset_left = -w / 2.0
		panel.offset_right = w / 2.0
		panel.offset_bottom = -(12.0 + bottom)
		if not portrait:
			# landscape: the panel sits on the right, the car stays in view on the left
			panel.anchor_left = 1.0
			panel.anchor_right = 1.0
			panel.offset_left = -w - 16.0
			panel.offset_right = -16.0
		else:
			panel.anchor_left = 0.5
			panel.anchor_right = 0.5
	if scr == screens.get("garage"):
		(_garage.scroll as ScrollContainer).custom_minimum_size.y = clampf(vp.y * (0.27 if portrait else 0.42), 220.0, 620.0)
	if _map.has("map") and scr == screens.get("map"):
		# the map fills what the header and the panel leave free
		var wm: Control = _map.map
		var pnl: Control = scr.get_meta("panel")
		var ph := pnl.size.y if pnl.size.y > 10.0 else 430.0
		wm.offset_top = 120.0 + top
		if portrait:
			wm.offset_bottom = -(ph + 20.0 + bottom)
			wm.offset_right = 0.0
		else:
			wm.offset_bottom = -bottom
			wm.offset_right = -(pnl.custom_minimum_size.x + 30.0)
	if _map.has("head") and scr == screens.get("map"):
		var mh: MarginContainer = _map.head
		mh.add_theme_constant_override("margin_top", int(20 + top))
		mh.add_theme_constant_override("margin_left", 22)
		mh.add_theme_constant_override("margin_right", 22)
	if _menu.has("head") and scr == screens.get("menu"):
		var head: MarginContainer = _menu.head
		head.add_theme_constant_override("margin_top", int(20 + top))
		head.add_theme_constant_override("margin_left", 22)
		head.add_theme_constant_override("margin_right", 22)


## True when a touch at pos lands on one of the sheet panels (not the 3D view).
func ui_blocks(pos: Vector2) -> bool:
	for c in _solid:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	for k in screens:
		if screens[k].visible and not screens[k].has_meta("sheet"):
			return true  # a full-screen menu is open
	return false


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

	# One slim band along the top of the screen, so the road ahead stays clear:
	# lives and score on the left, the stage tracker in the middle, buttons right.
	top.add_theme_constant_override("separation", 12)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_BEGIN
	mid.add_theme_constant_override("separation", 0)
	mid.custom_minimum_size.x = 170
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(mid)
	_lives_ctrl = Control.new()
	_lives_ctrl.custom_minimum_size = Vector2(170, 24)
	_lives_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_ctrl.draw.connect(_draw_lives)
	mid.add_child(_lives_ctrl)
	_score = _label("0", 54, LINE, display_font)
	_score.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_score.add_theme_constant_override("shadow_offset_y", 3)
	mid.add_child(_score)
	var combo_row := _row(8)
	mid.add_child(combo_row)
	_mult_bg = PanelContainer.new()
	var msb := _flat(AMBER, 6)
	msb.content_margin_left = 10
	msb.content_margin_right = 10
	_mult_bg.add_theme_stylebox_override("panel", msb)
	_mult = _label("x1.0", 20, AMBER_INK, mono_font)
	_mult_bg.add_child(_mult)
	combo_row.add_child(_mult_bg)
	_combo = _bar(_fill_amber, 7)
	_combo.custom_minimum_size.x = 90
	combo_row.add_child(_combo)

	var right := HBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right)
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.custom_minimum_size = Vector2(60, 60)
	pause_btn.add_theme_font_override("font", display_font)
	pause_btn.add_theme_font_size_override("font_size", 28)
	var pst := _flat(Color(0.04, 0.05, 0.06, 0.45), 36, Color(LINE, 0.7), 3)
	pause_btn.add_theme_stylebox_override("normal", pst)
	pause_btn.add_theme_stylebox_override("hover", pst)
	pause_btn.add_theme_stylebox_override("pressed", pst)
	pause_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_btn.pressed.connect(func() -> void: act.emit("pause", ""))
	cam_btn = pause_btn.duplicate(0) as Button  # 0: copy looks, not the pause signal
	cam_btn.text = "CAM"
	cam_btn.add_theme_font_size_override("font_size", 22)
	cam_btn.pressed.connect(func() -> void: act.emit("cam_cycle", ""))
	right.add_theme_constant_override("separation", 8)
	right.add_child(cam_btn)
	right.add_child(pause_btn)
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	# goal sign
	_goal = PanelContainer.new()
	_goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gs := _flat(Color(SIGN, 0.88), 10, LINE, 2)
	gs.set_content_margin_all(6)
	gs.content_margin_left = 10
	gs.content_margin_right = 10
	_goal.add_theme_stylebox_override("panel", gs)
	_g["style"] = gs
	top.add_child(_goal)
	top.move_child(_goal, 1)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 1)
	_goal.add_child(gv)
	var head := _row(8)
	gv.add_child(head)
	_g["title"] = _label("STAGE 1", 24, LINE, display_font)
	_g["title"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_g["title"])
	_g["sub"] = _label("", 17, MUTED, display_font)
	_g["sub"].clip_text = true
	_g["sub"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_g["sub"].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_g["sub"].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_g["sub"])
	for i in [1, 2]:
		var r := _row(6)
		gv.add_child(r)
		var l := _label("DIST", 15, MUTED, mono_font)
		l.custom_minimum_size.x = 48
		r.add_child(l)
		var b := _bar(_fill_white, 8)
		r.add_child(b)
		var v := _label("0", 17, LINE, mono_font)
		v.custom_minimum_size.x = 128
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(v)
		_g["l%d" % i] = l
		_g["b%d" % i] = b
		_g["v%d" % i] = v

	# scoring messages: a short feed just under the score counter, out of the way of the road
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", -4)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_layer.add_child(_feed)
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
	speedo.offset_top = -196
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
	# fuel gauge, with the distance to the next fuel stop when it matters
	_fuel_next = _label("", 15, AMBER, mono_font)
	_fuel_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speedo.add_child(_fuel_next)
	var frow := _row(6)
	frow.alignment = BoxContainer.ALIGNMENT_CENTER
	frow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speedo.add_child(frow)
	frow.add_child(_label("FUEL", 14, MUTED, mono_font))
	_fuel_bar = _bar(_fill_white, 8)
	_fuel_bar.custom_minimum_size.x = 120
	_fuel_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_fuel_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frow.add_child(_fuel_bar)
	_fuel_val = _label("40 L", 14, LINE, mono_font)
	_fuel_val.custom_minimum_size.x = 44
	frow.add_child(_fuel_val)

	brake = Pedal.new()
	brake.kind = "brake"
	play_layer.add_child(brake)
	gas = Pedal.new()
	gas.kind = "gas"
	play_layer.add_child(gas)
	wheel = SteerWheel.new()
	play_layer.add_child(wheel)
	stick = FloatStick.new()
	play_layer.add_child(stick)
	arrows = ArrowPad.new()
	play_layer.add_child(arrows)
	mirror = RearMirror.new()
	play_layer.add_child(mirror)
	play_layer.move_child(mirror, 0)  # under the HUD band and pops
	play_layer.visible = false


func _draw_lives() -> void:
	var c := _lives_ctrl
	c.draw_set_transform(Vector2(0, -6), 0.0, Vector2(0.62, 0.62))
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
	if c.has_meta("inf"):  # developer tools: infinite lives
		c.draw_string(display_font, Vector2(8.0 + _max_lives * 46.0, 34), "INF", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, AMBER)


func set_play_visible(on: bool) -> void:
	_play_on = on
	if not _editing:
		play_layer.visible = on


## Which on-screen control a touch at `pos` lands on: "gas", "brake", "ui" or "".
func role_at(pos: Vector2) -> String:
	if not play_layer.visible:
		return "ui"
	if gas.hit_rect().has_point(pos):
		return "gas"
	if brake.hit_rect().has_point(pos):
		return "brake"
	if wheel.visible and wheel.hit(pos):
		return "wheel"
	if arrows.visible:
		var side := arrows.side_at(pos)
		if side != "":
			return side
	if pause_btn.get_global_rect().grow(12).has_point(pos) or cam_btn.get_global_rect().grow(12).has_point(pos):
		return "ui"
	match Save.setting("steer_mode"):
		"swipe":
			return ""
		"stick":
			return "stick"  # the stick appears wherever the finger lands
	return "none"  # only the steering control steers in wheel and button modes


## The dashboard gauges show speed and gear in the cockpit, so the HUD speedo hides there.
func set_speedo_visible(on: bool) -> void:
	var spd: Control = _kmh.get_parent()
	if spd.visible != on:
		spd.visible = on


func set_pedals(g: bool, b: bool) -> void:
	gas.pressed = g
	brake.pressed = b


func update_play(d: Dictionary) -> void:
	_feed.position = Vector2(_mult_bg.global_position.x, _mult_bg.global_position.y + _mult_bg.size.y + 6.0) - play_layer.global_position
	_score.text = d.score
	_mult.text = d.mult
	_mult_bg.modulate = Color(1, 1, 1, 1) if d.combo_on else Color(1, 1, 1, 0.45)
	_combo.value = d.combo_frac
	if d.lives != _lives or d.max_lives != _max_lives or d.get("inf", false) != _lives_ctrl.has_meta("inf"):
		if d.get("inf", false):
			_lives_ctrl.set_meta("inf", true)
		else:
			_lives_ctrl.remove_meta("inf")
		_lives = d.lives
		_max_lives = d.max_lives
		_lives_ctrl.queue_redraw()
	_kmh.text = d.kmh
	_unit.text = "%s  ·  GEAR %d  ·  %s" % [d.unit, d.gear, d.get("clock", "")]
	_rpm.value = clampf(d.rpm, 0.0, 1.0)
	_rpm.add_theme_stylebox_override("fill", _fill_red if d.rpm > 0.9 else (_fill_amber if d.rpm > 0.75 else _fill_white))
	_kmh.add_theme_color_override("font_color", AMBER if d.fast else LINE)
	_sp_tag.text = "HIGH SPEED BONUS" if d.fast else ""
	if d.has("fuel"):
		var f: float = d.fuel
		_fuel_bar.value = clampf(f, 0.0, 1.0)
		var low := f < 0.25
		var blink := f < 0.1 and fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4
		_fuel_bar.add_theme_stylebox_override("fill", _fill_red if low else (_fill_amber if f < 0.4 else _fill_white))
		_fuel_bar.modulate.a = 0.35 if blink else 1.0
		_fuel_val.text = d.fuel_l
		_fuel_val.add_theme_color_override("font_color", TAIL if low else LINE)
		_fuel_next.text = d.fuel_next
	(_g["style"] as StyleBoxFlat).bg_color = Color("#173a6e", 0.92) if d.get("cop", false) else (RED_SIGN if d.boss else Color(SIGN, 0.88))
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
	elif kind == "small":
		size = 30
		col = MUTED
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


## A scoring message in the feed under the score counter: newest on top,
## a few at most, each fading out after a moment.
func pop_feed(text: String, kind := "") -> void:
	var col := LINE
	var size := 19
	if kind == "hot":
		col = AMBER
		size = 21
	elif kind == "bad":
		col = TAIL
	elif kind == "small":
		col = MUTED
	var l := _label(text, size, col, display_font)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	l.modulate.a = 0.0
	_feed.add_child(l)
	_feed.move_child(l, 0)
	while _feed.get_child_count() > 4:
		var old := _feed.get_child(_feed.get_child_count() - 1)
		_feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.08)
	tw.tween_interval(1.3)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


## Small floating message at a screen position (usually just above the car).
## It rises and fades; several in a row stack upwards instead of overlapping.
func pop_at(text: String, kind: String, pos: Vector2) -> void:
	var size := 24
	var col := LINE
	if kind == "hot":
		size = 28
		col = AMBER
	elif kind == "bad":
		col = TAIL
	elif kind == "small":
		col = MUTED
	var l := _label(text, size, col, display_font)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	l.modulate.a = 0.0
	play_layer.add_child(l)
	var live := 0
	for c in play_layer.get_children():
		if c.has_meta("float"):
			live += 1
	l.set_meta("float", true)
	var sz := l.get_minimum_size()
	var vp := get_viewport().get_visible_rect().size
	var start := Vector2(clampf(pos.x - sz.x / 2.0, 8.0, vp.x - sz.x - 8.0), pos.y - sz.y - live * (sz.y + 2.0))
	l.position = start
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.08)
	tw.tween_property(l, "position:y", start.y - 30.0, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(l.queue_free)


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
	_hint.text = {"wheel": "Turn the wheel to steer", "buttons": "Hold the arrow buttons to steer", "tilt": "Tilt the phone to steer",
		"stick": "Touch anywhere and push left or right to steer"}.get(Save.setting("steer_mode"), "Swipe left or right anywhere to steer")
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint, "modulate:a", 0.95, 0.3)
	_hint_tween.tween_interval(4.0)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.6)


# ---------------------------------------------------------------- menus

## A screen that leaves the 3D view clear: no scrim, nothing that blocks
## touches except its own panels (listed in _solid so dragging elsewhere
## turns the garage camera).
func _sheet_screen(name: String) -> Control:
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.set_meta("sheet", true)
	scr.visible = false
	root.add_child(scr)
	screens[name] = scr
	return scr


## A panel pinned to the bottom of a sheet screen, centred and width-capped.
func _bottom_panel(scr: Control, max_w := 720.0) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb := _sign_style(SIGN)
	sb.bg_color = Color(SIGN, 0.94)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.set_meta("max_w", max_w)
	scr.add_child(panel)
	_solid.append(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	scr.set_meta("panel", panel)
	return vb


func _build_menu() -> void:
	var scr := _sheet_screen("menu")
	# soft shading top and bottom so the text reads over the workshop
	for top in [true, false]:
		var g := TextureRect.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(0, 0, 0, 0.55))
		grad.set_color(1, Color(0, 0, 0, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
		gt.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
		g.texture = gt
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.anchor_right = 1.0
		if top:
			g.anchor_bottom = 0.22
		else:
			g.anchor_top = 0.6
			g.anchor_bottom = 1.0
		scr.add_child(g)
	# title and cash across the top
	var head := MarginContainer.new()
	head.anchor_right = 1.0
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(head)
	_menu["head"] = head
	var hr := _row(14)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(hr)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_theme_constant_override("separation", 0)
	tv.add_child(_eyebrow("Exit 12 · Service area · Your garage"))
	var title := _label("REDLINE RUSH", 64, LINE, display_font)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	tv.add_child(title)
	hr.add_child(tv)
	var chips := VBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hr.add_child(chips)
	var a := _stat("$0", "Cash", AMBER)
	var b := _stat("0", "Best run")
	for st in [a, b]:
		(st[0] as Control).custom_minimum_size.x = 150
		chips.add_child(st[0])
	_menu["cash"] = a[1]
	_menu["best"] = b[1]
	# the car and what to do with it, at the bottom
	var v := _bottom_panel(scr)
	var nr := _row(10)
	v.add_child(nr)
	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", 0)
	nv.add_child(_eyebrow("On the turntable"))
	_menu["car"] = _label("", 46, LINE, display_font)
	nv.add_child(_menu.car)
	nr.add_child(nv)
	_menu["fuel"] = _label("", 15, AMBER, mono_font)
	_menu.fuel.size_flags_vertical = Control.SIZE_SHRINK_END
	nr.add_child(_menu.fuel)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	v.add_child(grid)
	for k in ["accel", "top", "grip", "brake"]:
		var sv := VBoxContainer.new()
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_theme_constant_override("separation", 2)
		var lab := _label("", 14, MUTED, mono_font)
		sv.add_child(lab)
		var bar := _bar(_fill_amber, 8)
		sv.add_child(bar)
		grid.add_child(sv)
		_menu["l_" + k] = lab
		_menu["b_" + k] = bar
	v.add_child(_button("START RUN  →", "amber", "map"))
	var btns := GridContainer.new()
	btns.columns = 3
	btns.add_theme_constant_override("h_separation", 10)
	btns.add_theme_constant_override("v_separation", 10)
	v.add_child(btns)
	for bd in [["CARS", "garage", "cars"], ["WORKSHOP", "garage", "up"], ["SETTINGS", "settings", ""]]:
		var bt := _button(bd[0], "light", bd[1], bd[2])
		bt.add_theme_font_size_override("font_size", 28)
		btns.add_child(bt)
	var help := _button("HOW TO PLAY", "ghost", "help")
	help.add_theme_font_size_override("font_size", 22)
	v.add_child(help)
	v.add_child(_label("Drag to look around your car", 15, MUTED, mono_font))
	_build_help()


func _build_help() -> void:
	var v := _screen("help")
	v.add_child(_eyebrow("Driver's handbook"))
	v.add_child(_label("HOW TO PLAY", 72, LINE, display_font))
	var how := RichTextLabel.new()
	how.bbcode_enabled = true
	how.fit_content = true
	how.scroll_active = false
	how.mouse_filter = Control.MOUSE_FILTER_IGNORE
	how.add_theme_font_size_override("normal_font_size", 23)
	how.add_theme_font_size_override("bold_font_size", 23)
	how.add_theme_color_override("default_color", MUTED)
	how.text = ("• [b][color=#f3f5ef]Gas[/color][/b] pedal on the right, [b][color=#f3f5ef]brake[/color][/b] pedal on the left.\n\n"
		+ "• [b][color=#f3f5ef]Steer[/color][/b] like a real car: it keeps going the way it points, so straighten up yourself. Change the steering method in Settings › Controls.\n\n"
		+ "• Pass cars inside 1 m for a [b][color=#f3f5ef]near miss[/color][/b]. Change lanes right beside a car for a [b][color=#f3f5ef]close cut[/color][/b]. Chains build your multiplier.\n\n"
		+ "• Cover the distance or hit the points target and the [b][color=#f3f5ef]boss[/color][/b] (or the police) arrives 10 seconds later. Out-score the boss before the finish gantry.\n\n"
		+ "• Watch the [b][color=#f3f5ef]fuel[/color][/b] gauge and pull into the fuel stops on the right.\n\n"
		+ "• Spend your winnings in the [b][color=#f3f5ef]garage[/color][/b]: new cars, upgrades, paint and wheels.")
	v.add_child(how)
	v.add_child(_button("BACK", "light", "menu"))


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
	var c := Data.car_by_id(Save.data.selected)
	_menu.car.text = String(c.name).to_upper()
	_menu.fuel.text = "%s · %d L" % [String(Data.FUEL_GRADES[c.get("fuel", "regular")].name).to_upper(), int(c.get("tank", 45))]
	# with your permanent upgrades applied
	var accel: float = c.accel * (1.0 + 0.06 * Save.perm_level("accel"))
	var top: float = c.top * (1.0 + 0.04 * Save.perm_level("top"))
	var grip: float = c.grip * (1.0 + 0.06 * Save.perm_level("handling"))
	var brake: float = c.brake * (1.0 + 0.06 * Save.perm_level("brake"))
	var rows := {"accel": ["ACCEL %.1f" % accel, accel / 13.0], "top": ["TOP %d KM/H" % roundi(top * 3.6), top / 95.0],
		"grip": ["GRIP %.1f" % grip, grip / 16.0], "brake": ["BRAKES %.1f" % brake, brake / 16.0]}
	for k in rows:
		_menu["l_" + k].text = rows[k][0]
		_menu["b_" + k].value = clampf(rows[k][1], 0.0, 1.0)


var _map := {}


## World map: the drawn map fills the screen, the chosen highway's details
## and the Drive button sit in a panel at the bottom.
func _build_map() -> void:
	var scr := _sheet_screen("map")
	var bg := ColorRect.new()
	bg.color = WorldMap.WATER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.add_child(bg)
	_solid.append(bg)
	var wm := WorldMap.new()
	wm.set_anchors_preset(Control.PRESET_FULL_RECT)
	wm.picked.connect(func(i: int) -> void: act.emit("route", str(i)))
	scr.add_child(wm)
	_map["map"] = wm
	var head := MarginContainer.new()
	head.anchor_right = 1.0
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(head)
	_map["head"] = head
	var hv := VBoxContainer.new()
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	hv.add_child(_eyebrow("Interstate atlas · Tap a highway"))
	var t := _label("WORLD MAP", 58, LINE, display_font)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	t.add_theme_constant_override("shadow_offset_y", 3)
	hv.add_child(t)
	_map["progress"] = _label("", 17, AMBER, mono_font)
	hv.add_child(_map.progress)
	var v := _bottom_panel(scr)
	_map["route"] = _label("", 40, LINE, display_font)
	_map.route.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_map.route)
	_map["info"] = _wrap("", 19, MUTED)
	v.add_child(_map.info)
	var row := _row(12)
	v.add_child(row)
	var a := _stat("", "Country")
	var b := _stat("", "Best here")
	var c := _stat("", "Boss skill")
	for st in [a, b, c]:
		row.add_child(st[0])
	_map["land"] = a[1]
	_map["best"] = b[1]
	_map["skill"] = c[1]
	_map["drive"] = _button("DRIVE  →", "amber", "drive")
	v.add_child(_map.drive)
	v.add_child(_button("BACK TO GARAGE", "ghost", "menu"))


func render_map() -> void:
	var wm: WorldMap = _map.map
	wm.unlocked = int(Save.data.get("routes", 1))
	wm.selected = int(Save.data.get("route_sel", 0))
	wm.best = Save.data.get("route_best", {})
	wm.queue_redraw()
	var i: int = wm.selected
	var r := Data.route_info(i)
	_map.route.text = "%s  %s → %s" % [r.name, String(r.from).to_upper(), String(r.to).to_upper()]
	var nxt: String = Data.CITIES[i + 2].name if i + 2 < Data.CITIES.size() else ""
	var done: bool = wm.unlocked > i + 1 or (i == Data.ROUTES.size() - 1 and Save.data.get("route_done", false))
	if done:
		_map.info.text = "Cleared. Drive it again for a better score; it never ends."
	elif nxt != "":
		_map.info.text = "Beat the final boss, %s (boss 4), to open the highway on to %s." % [Data.BOSSES[3].name, nxt]
	else:
		_map.info.text = "The last highway. Beat %s here to conquer the map." % Data.BOSSES[3].name
	_map.land.text = String(r.land.title)
	_map.best.text = Fmt.num(int(wm.best.get(str(i), 0)))
	var keep := Data.route
	Data.route = i
	_map.skill.text = "+%d%%" % roundi((Data.route_scale() - 1.0) * 100.0)
	Data.route = keep
	_map.progress.text = "%d OF %d HIGHWAYS OPEN" % [wm.unlocked, Data.ROUTES.size()]


func map_note(text: String) -> void:
	_map.info.text = text


const GARAGE_TABS := [["cars", "CARS"], ["up", "UPGRADES"], ["paint", "PAINT"], ["wheels", "WHEELS"]]


func _build_garage() -> void:
	var scr := _sheet_screen("garage")
	var v := _bottom_panel(scr)
	var head := _row(10)
	v.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	_garage["eyebrow"] = _eyebrow("Exit 12 · Service area")
	tv.add_child(_garage.eyebrow)
	_garage["title"] = _label("GARAGE", 54, LINE, display_font)
	tv.add_child(_garage.title)
	head.add_child(tv)
	var cv := VBoxContainer.new()
	cv.alignment = BoxContainer.ALIGNMENT_END
	var ce := _eyebrow("Cash")
	ce.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cv.add_child(ce)
	_garage["cash"] = _label("$0", 34, AMBER, mono_font)
	cv.add_child(_garage.cash)
	head.add_child(cv)
	var tabs := GridContainer.new()
	tabs.columns = 4
	tabs.add_theme_constant_override("h_separation", 8)
	v.add_child(tabs)
	for t in GARAGE_TABS:
		var tb := _button(t[1], "light", "tab", t[0])
		tb.add_theme_font_size_override("font_size", 22)
		tabs.add_child(tb)
		_garage["tab_" + t[0]] = tb
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 100000  # touch scrolling is handled in _input instead
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	_garage["list"] = list
	_garage["scroll"] = scroll
	v.add_child(_button("DONE", "light", "menu"))


## A colour chip button for the paint and wheel tabs.
func _swatch(col: Color, caption: String, on: bool, action: String, arg: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 92)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := _flat(SIGN_DEEP, 12, AMBER if on else Color(LINE, 0.15), 4 if on else 2)
	for k in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(k, sb)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 10
	vb.offset_right = -10
	vb.offset_top = 10
	vb.offset_bottom = -8
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var chip := Panel.new()
	chip.custom_minimum_size.y = 40
	chip.add_theme_stylebox_override("panel", _flat(col, 8, Color(0, 0, 0, 0.4), 2))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(chip)
	var l := _label(caption, 15, LINE if on else MUTED, mono_font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	b.pressed.connect(func() -> void: act.emit(action, arg))
	return b


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
	for t in GARAGE_TABS:
		(_garage["tab_" + t[0]] as Button).modulate = Color(1, 1, 1, 1) if garage_tab == t[0] else Color(1, 1, 1, 0.5)
	var sel_car := Data.car_by_id(Save.data.selected)
	_garage.title.text = "GARAGE" if garage_tab == "cars" else "WORKSHOP"
	_garage.eyebrow.text = "EXIT 12 · SERVICE AREA" if garage_tab == "cars" else "WORKING ON · " + String(sel_car.name).to_upper()
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
			if not sel:
				var vw := _button("VIEW", "ghost", "preview", c.id)
				vw.size_flags_horizontal = Control.SIZE_SHRINK_END
				vw.add_theme_font_size_override("font_size", 22)
				top.add_child(vw)
			top.add_child(btn)
			var sub: String = c.blurb if not locked else "Beat %s to put this car up for sale." % Data.BOSSES[c.boss].name
			card[1].add_child(_wrap(sub, 20, MUTED))
			card[1].add_child(_label("%s FUEL  ·  %d L TANK" % [String(Data.FUEL_GRADES[c.get("fuel", "regular")].name).to_upper(), int(c.get("tank", 45))], 16, AMBER, mono_font))
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
	elif garage_tab == "paint":
		var lk: Dictionary = Save.data.get("looks", {}).get(sel_car.id, {})
		var cur: String = lk.get("color", "")
		list.add_child(_wrap("Paint for your %s. The colour shows on the car straight away and is free." % sel_car.name, 20, MUTED))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		list.add_child(grid)
		for pnt in Data.PAINTS:
			var hex: String = pnt[1]
			var col := Color(sel_car.color) if hex == "" else Color(hex)
			grid.add_child(_swatch(col, String(pnt[0]).to_upper(), hex == cur, "paint", hex))
	elif garage_tab == "wheels":
		var stl := Save.car_style(sel_car)
		var cur_rim: String = stl.get("rim", "5spoke")
		var cur_col: String = stl.get("rim_color", "#c3c8ce")
		list.add_child(_eyebrow("Wheel design"))
		var rg := GridContainer.new()
		rg.columns = 3
		rg.add_theme_constant_override("h_separation", 10)
		rg.add_theme_constant_override("v_separation", 10)
		list.add_child(rg)
		for rm in Data.RIMS:
			var on: bool = rm[0] == cur_rim
			var rb := _button(String(rm[1]).to_upper(), "amber" if on else "ghost", "rim", rm[0])
			rb.add_theme_font_size_override("font_size", 22)
			rg.add_child(rb)
		list.add_child(_eyebrow("Wheel finish"))
		var cg := GridContainer.new()
		cg.columns = 3
		cg.add_theme_constant_override("h_separation", 10)
		cg.add_theme_constant_override("v_separation", 10)
		list.add_child(cg)
		for rc in Data.RIM_COLORS:
			cg.add_child(_swatch(Color(rc[1]), String(rc[0]).to_upper(), String(rc[1]).to_lower() == cur_col.to_lower(), "rim_color", rc[1]))
		list.add_child(_button("FACTORY WHEELS", "ghost", "rim_reset"))
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
		list.add_child(_wrap("Upgrades are fitted to your %s only. Every car is upgraded separately." % sel_car.name, 20, MUTED))


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
	var a := _stat("—", "Rival skill", AMBER)
	var b := _stat("2.0 km", "Race length")
	var c := _stat("—", "Rival car")
	for s in [a, b, c]:
		stats.add_child(s[0])
	_boss["target"] = a[1]
	_boss["car"] = c[1]
	v.add_child(_wrap("The rival scores the same way you do: near misses, razor passes, close cuts and combos. Out-score them before the finish gantry. Lose and it costs a life, then you get a rematch.", 21, MUTED))
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
	v.add_child(_button("RESUME", "amber", "resume"))
	var btns := _row(14)
	v.add_child(btns)
	btns.add_child(_button("SETTINGS", "light", "settings"))
	btns.add_child(_button("REPLAY", "light", "replay"))
	v.add_child(_button("END RUN", "ghost", "quit"))


var _knob_tex: ImageTexture
var _cam_lock := false  # set while render_cam rewrites slider ranges


func _knob() -> ImageTexture:
	if _knob_tex == null:
		var img := Image.create(40, 40, false, Image.FORMAT_RGBA8)
		for y in 40:
			for x in 40:
				var d := Vector2(x - 19.5, y - 19.5).length()
				var a := clampf(18.0 - d, 0.0, 1.0)
				var c := LINE if d < 11.0 else AMBER
				img.set_pixel(x, y, Color(c, a))
		_knob_tex = ImageTexture.create_from_image(img)
	return _knob_tex


## Shows the current camera view's settings.
func render_cam() -> void:
	var mode: String = Save.data.cam.mode
	var cfg := Save.cam(mode)
	var rng: Dictionary = Data.CAM_RANGES[mode]
	for m in Data.CAM_MODES:
		(_set["mode_" + m] as Button).modulate = Color(1, 1, 1, 1) if m == mode else Color(1, 1, 1, 0.45)
	var names := {"fov": "Field of view", "height": "Height", "dist": "Distance" if mode == "chase" else "Forward",
		"angle": "Angle"}
	_cam_lock = true
	for key in ["fov", "height", "dist", "angle"]:
		var sl: HSlider = _set["s_" + key]
		sl.min_value = rng[key][0]
		sl.max_value = rng[key][1]
		sl.step = 1.0 if key == "fov" or key == "angle" else 0.05
		sl.set_value_no_signal(cfg[key])
		_set["n_" + key].text = names[key]
		var unit := "°" if key == "fov" or key == "angle" else " m"
		var fmt := "%d" if unit == "°" else "%.2f"
		_set["v_" + key].text = (fmt % cfg[key]) + unit
	_cam_lock = false


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
	v.add_child(_button("RUN AGAIN  →", "amber", "start"))
	var btns := _row(14)
	v.add_child(btns)
	btns.add_child(_button("GARAGE", "light", "garage"))
	btns.add_child(_button("WATCH REPLAY", "light", "replay"))
	v.add_child(_button("MAIN MENU", "ghost", "menu"))


func show_over(reason: String, score: String, dist: String, bosses: String, cash: String, note: String) -> void:
	_over.reason.text = reason.to_upper()
	_over.score.text = score
	_over.dist.text = dist
	_over.boss.text = bosses
	_over.cash.text = cash
	_over.note.text = note
	show_screen("over")



# ---------------------------------------------------------------- settings

func _slider_row(parent: Control, key: String, action: String, save_action: String) -> void:
	var r := _row(12)
	parent.add_child(r)
	var nm := _label("", 22, LINE)
	nm.custom_minimum_size.x = 165
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_child(nm)
	var sl := HSlider.new()
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size.y = 48
	var track := _flat(Color(0, 0, 0, 0.35), 6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", _flat(AMBER, 6))
	sl.add_theme_stylebox_override("grabber_area_highlight", _flat(AMBER, 6))
	sl.add_theme_icon_override("grabber", _knob())
	sl.add_theme_icon_override("grabber_highlight", _knob())
	sl.value_changed.connect(func(val: float) -> void:
		if not _cam_lock:
			act.emit(action, "%s=%s" % [key, val]))
	sl.drag_ended.connect(func(_changed: bool) -> void: act.emit(save_action, ""))
	r.add_child(sl)
	var val_l := _label("", 20, LINE, mono_font)
	val_l.custom_minimum_size.x = 96
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(val_l)
	_set["n_" + key] = nm
	_set["s_" + key] = sl
	_set["v_" + key] = val_l


const SETTINGS_TABS := [["controls", "CONTROLS"], ["camera", "CAMERA"], ["display", "DISPLAY & AUDIO"], ["dev", "DEVELOPER"]]
var settings_tab := "controls"


## One option: its name and a short explanation on the left, and its current
## value on the right (tap to change it).
func _option_row(parent: Control, key: String, title: String, hint: String) -> void:
	var r := _row(14)
	parent.add_child(r)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 2)
	tv.add_child(_label(title, 24, LINE))
	if hint != "":
		var h := _wrap(hint, 17, MUTED)
		tv.add_child(h)
	r.add_child(tv)
	var b := Button.new()
	b.add_theme_font_override("font", display_font)
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(220, 58)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := _flat(SIGN_DEEP, 12, Color(LINE, 0.25), 2)
	sb.set_content_margin_all(12)
	var sh := sb.duplicate() as StyleBoxFlat
	sh.bg_color = SIGN_DEEP.lightened(0.08)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sh)
	b.add_theme_stylebox_override("pressed", sh)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_stylebox_override("focus", _flat(Color.TRANSPARENT, 12, AMBER, 3))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, AMBER)
	b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.6))
	b.pressed.connect(func() -> void: act.emit("toggle", key))
	b.set_meta("row", true)
	r.add_child(b)
	_set["t_" + key] = b
	_set["r_" + key] = r


## A group heading inside a settings tab.
func _group(parent: Control, title: String) -> void:
	var sp := Control.new()
	sp.custom_minimum_size.y = 4
	parent.add_child(sp)
	parent.add_child(_eyebrow(title))
	var line := ColorRect.new()
	line.color = Color(LINE, 0.18)
	line.custom_minimum_size.y = 2
	parent.add_child(line)


func _build_settings() -> void:
	var v := _screen("settings", SIGN, 720)
	v.add_child(_eyebrow("Glovebox · Owner's manual"))
	v.add_child(_label("SETTINGS", 84, LINE, display_font))
	# tabs: one area of settings at a time instead of one long list
	var tabs := GridContainer.new()
	tabs.columns = 2
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	v.add_child(tabs)
	var pages := {}
	for t in SETTINGS_TABS:
		var tb := _button(t[1], "light", "")
		tb.add_theme_font_size_override("font_size", 26)
		var id: String = t[0]
		tb.pressed.connect(func() -> void:
			settings_tab = id
			render_settings())
		tabs.add_child(tb)
		_set["tab_" + id] = tb
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 14)
		page.custom_minimum_size.y = 640  # the same height on every tab, so Done stays put
		v.add_child(page)
		pages[id] = page
		_set["page_" + id] = page

	# --- controls
	var pc: VBoxContainer = pages.controls
	_group(pc, "Steering")
	_option_row(pc, "steer_mode", "Steering method", "Stick, swipe, on-screen wheel, left/right buttons or tilting the phone.")
	_slider_row(pc, "steer_sens", "set", "save")
	_option_row(pc, "assist", "Steering assist", "On: the car straightens up to the road when you let go. Off: it keeps its heading, like a real car.")
	_option_row(pc, "tilt_invert", "Tilt direction", "Flip tilt steering if it feels backwards (tilt only).")
	_group(pc, "Pedals and feel")
	_slider_row(pc, "pedal_scale", "set", "save")
	_option_row(pc, "haptics", "Vibration", "Buzz on near misses and crashes.")
	pc.add_child(_button("EDIT ON-SCREEN LAYOUT", "amber", "pedal_edit"))
	var pr := _row(12)
	pc.add_child(pr)
	for b in [_button("SWAP PEDALS", "ghost", "pedal_swap"), _button("RESET LAYOUT", "ghost", "pedal_reset")]:
		b.add_theme_font_size_override("font_size", 24)
		pr.add_child(b)

	# --- camera (the game keeps drawing underneath, so changes preview live)
	var pcam: VBoxContainer = pages.camera
	_group(pcam, "View")
	var modes := _row(8)
	pcam.add_child(modes)
	for m in Data.CAM_MODES:
		var mb := _button(String(Data.CAM_NAMES[m]).to_upper(), "light", "cam_mode", m)
		mb.add_theme_font_size_override("font_size", 24)
		modes.add_child(mb)
		_set["mode_" + m] = mb
	_group(pcam, "Adjust this view")
	for key in ["fov", "height", "dist", "angle"]:
		_slider_row(pcam, key, "cam_set", "cam_save")
	pcam.add_child(_button("RESET THIS VIEW", "ghost", "cam_reset"))
	_group(pcam, "Effects")
	_option_row(pcam, "shake", "Camera shake", "Shake on bumps, crashes and at top speed.")

	# --- display and audio
	var pd: VBoxContainer = pages.display
	_group(pd, "Screen")
	_option_row(pd, "orientation", "Orientation", "Portrait or landscape.")
	_option_row(pd, "gfx", "Graphics", "Lower it if the game stutters.")
	_option_row(pd, "units", "Speed units", "")
	_group(pd, "Rear-view mirror")
	_option_row(pd, "mirror", "Mirror", "Move it with Edit on-screen layout (Controls).")
	_slider_row(pd, "mirror_scale", "set", "save")
	_group(pd, "Audio")
	_option_row(pd, "sound", "Engine and effects", "")

	# --- developer tools
	var pdev: VBoxContainer = pages.dev
	_group(pdev, "Testing")
	pdev.add_child(_wrap("For testing. Unlocks change your saved progress.", 20, MUTED))
	_option_row(pdev, "dev_lives", "Infinite lives", "")
	_option_row(pdev, "dev_fps", "FPS counter", "")
	var dev := GridContainer.new()
	dev.columns = 2
	dev.add_theme_constant_override("h_separation", 12)
	dev.add_theme_constant_override("v_separation", 12)
	pdev.add_child(dev)
	for d in [["UNLOCK ALL CARS", "cars"], ["MAX ALL UPGRADES", "upgrades"], ["+$100,000 CASH", "cash"], ["RESET PROGRESS", "reset"]]:
		var b := _button(d[0], "ghost", "dev", d[1])
		b.add_theme_font_size_override("font_size", 22)
		dev.add_child(b)
		_set["dev_" + d[1]] = b
	_set["dev_note"] = _wrap("", 20, AMBER)
	pdev.add_child(_set.dev_note)

	var sp := Control.new()
	sp.custom_minimum_size.y = 6
	v.add_child(sp)
	v.add_child(_button("DONE", "light", "settings_back"))
	(screens.settings.get_child(0) as ColorRect).color = Color(0.03, 0.04, 0.05, 0.3)


## Feedback line under the developer tools.
func dev_note(text: String) -> void:
	_set.dev_note.text = text
	_set.dev_reset.text = "TAP AGAIN TO RESET" if text.begins_with("Tap") else "RESET PROGRESS"


func render_settings() -> void:
	render_cam()
	_cam_lock = true
	var sliders := {"steer_sens": ["Sensitivity", 0.4, 2.0], "pedal_scale": ["Pedal size", 0.7, 1.4], "mirror_scale": ["Mirror size", 0.6, 1.8]}
	for key in sliders:
		var sl: HSlider = _set["s_" + key]
		sl.min_value = sliders[key][1]
		sl.max_value = sliders[key][2]
		sl.step = 0.05
		var val := float(Save.setting(key))
		sl.set_value_no_signal(val)
		_set["n_" + key].text = sliders[key][0]
		_set["v_" + key].text = "x%.2f" % val
	_cam_lock = false
	var states := {
		"assist": "ON" if Save.data.assist else "OFF (REAL)", "haptics": "ON" if Save.setting("haptics") else "OFF",
		"shake": "ON" if Save.setting("shake") else "OFF", "sound": "ON" if Save.data.sound else "OFF",
		"units": "MPH" if Save.setting("units") == "mph" else "KM/H",
		"steer_mode": {"swipe": "SWIPE", "wheel": "WHEEL", "buttons": "BUTTONS", "tilt": "TILT", "stick": "STICK"}.get(Save.setting("steer_mode"), "SWIPE"),
		"tilt_invert": "REVERSED" if Save.setting("tilt_invert") else "NORMAL",
		"orientation": "LANDSCAPE" if Save.setting("orientation") == "landscape" else "PORTRAIT",
		"gfx": String(Save.setting("gfx")).to_upper(),
		"mirror": "ON" if Save.setting("mirror") else "OFF",
		"dev_lives": "ON" if Save.setting("dev_lives") else "OFF", "dev_fps": "ON" if Save.setting("dev_fps") else "OFF",
	}
	for key in states:
		var b: Button = _set["t_" + key]
		if b.has_meta("row"):
			b.text = "%s  ›" % states[key]
		else:
			b.text = "%s:  %s" % [b.get_meta("base"), states[key]]
	# tilt direction only matters with tilt steering
	var tilt: bool = Save.setting("steer_mode") == "tilt"
	(_set.t_tilt_invert as Button).disabled = not tilt
	(_set.r_tilt_invert as Control).modulate = Color(1, 1, 1, 1.0 if tilt else 0.45)
	for t in SETTINGS_TABS:
		var on: bool = settings_tab == t[0]
		(_set["page_" + t[0]] as Control).visible = on
		(_set["tab_" + t[0]] as Button).modulate = Color(1, 1, 1, 1.0 if on else 0.5)


# ---------------------------------------------------------------- pedal layout

func layout_pedals() -> void:
	if gas == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var k := float(Save.setting("pedal_scale"))
	var mode: String = Save.setting("steer_mode")
	var gsz := Vector2(140, 262) * k
	var bsz := Vector2(210, 176) * k
	var base_y := vp.y - _bottom - 30.0
	var gas_c := Vector2(vp.x - 26 - gsz.x / 2.0, base_y - gsz.y / 2.0)
	var brake_c := Vector2(26 + bsz.x / 2.0, base_y - bsz.y / 2.0)
	if mode == "wheel" or mode == "buttons":
		# steering control takes the bottom-left corner; the brake moves above the gas
		brake_c = Vector2(vp.x - 26 - bsz.x / 2.0, base_y - gsz.y - 24.0 - bsz.y / 2.0)
	_place_pedal(gas, gsz, Save.setting("gas_pos"), gas_c, vp)
	_place_pedal(brake, bsz, Save.setting("brake_pos"), brake_c, vp)
	wheel.visible = mode == "wheel"
	arrows.visible = mode == "buttons"
	var wd := 250.0 * k
	_place_pedal(wheel, Vector2(wd, wd), Save.setting("wheel_pos"), Vector2(26 + wd / 2.0, base_y - wd / 2.0), vp)
	var asz := Vector2(280, 130) * k
	_place_pedal(arrows, asz, Save.setting("arrows_pos"), Vector2(26 + asz.x / 2.0, base_y - asz.y / 2.0), vp)
	# rear-view mirror: top centre, just under the HUD band
	var msz := RearMirror.BASE * float(Save.setting("mirror_scale"))
	var band := float(_top_margin.get_theme_constant("margin_top")) + (78.0 if vp.x > vp.y else 104.0)
	_place_pedal(mirror, msz, Save.setting("mirror_pos"), Vector2(vp.x / 2.0, band + msz.y / 2.0), vp)
	mirror.visible = Save.setting("mirror")
	# keep the speedometer in the gap between the steering control and the pedals
	var spd: Control = _kmh.get_parent()
	var lft := 0.0
	var rgt := vp.x
	for c in [wheel, arrows]:
		if c.visible and c.position.y + c.size.y > vp.y * 0.7 and c.position.x < vp.x / 2.0:
			lft = maxf(lft, c.position.x + c.size.x + 8.0)
	for c in [gas, brake]:
		if c.position.y + c.size.y > vp.y - 220.0 and c.position.x > vp.x / 2.0:
			rgt = minf(rgt, c.position.x - 8.0)
	var mid := (lft + rgt) / 2.0 if lft > 0.0 else vp.x / 2.0
	if vp.x > vp.y:  # landscape: bottom middle, between the steering control and the pedals
		mid = vp.x / 2.0
	spd.anchor_left = 0.0
	spd.anchor_right = 0.0
	spd.offset_left = mid - 130.0
	spd.offset_right = mid + 130.0


func _place_pedal(p: Control, sz: Vector2, pos: Variant, fallback: Vector2, vp: Vector2) -> void:
	var c := fallback
	if pos is Array and pos.size() == 2:
		c = Vector2(float(pos[0]) * vp.x, float(pos[1]) * vp.y)
	p.size = sz
	p.position = (c - sz / 2.0).clamp(Vector2(4, 4), vp - sz - Vector2(4, 28))
	p.queue_redraw()


func _store_pedal(p: Control) -> void:
	var vp := get_viewport().get_visible_rect().size
	var c := p.position + p.size / 2.0
	var key: String = {gas: "gas_pos", brake: "brake_pos", wheel: "wheel_pos", arrows: "arrows_pos", mirror: "mirror_pos"}[p]
	Save.data.settings[key] = [c.x / vp.x, c.y / vp.y]


func swap_pedals() -> void:
	var vp := get_viewport().get_visible_rect().size
	var cg := gas.position + gas.size / 2.0
	var cb := brake.position + brake.size / 2.0
	Save.data.settings.gas_pos = [cb.x / vp.x, cb.y / vp.y]
	Save.data.settings.brake_pos = [cg.x / vp.x, cg.y / vp.y]
	layout_pedals()


func _build_pedal_editor() -> void:
	var v := _screen("pedals", SIGN, 620)
	v.add_child(_eyebrow("Pedal layout"))
	v.add_child(_wrap("Drag the pedals, the steering control and the mirror where you want them. Change pedal size in Settings.", 22))
	var r := _row(12)
	v.add_child(r)
	r.add_child(_button("DONE", "amber", "pedal_done"))
	r.add_child(_button("SWAP", "ghost", "pedal_swap"))
	r.add_child(_button("RESET", "ghost", "pedal_reset"))
	var r2 := _row(12)
	v.add_child(r2)
	for m in [["MIRROR −", "-"], ["MIRROR +", "+"]]:
		var b := _button(m[0], "ghost", "mirror_size", m[1])
		b.add_theme_font_size_override("font_size", 26)
		r2.add_child(b)
	var scr: Control = screens.pedals
	(scr.get_child(0) as ColorRect).color = Color(0, 0, 0, 0.15)
	var column := v.get_parent().get_parent() as VBoxContainer
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(scr.get_child(1) as ScrollContainer).mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin_pedal_edit() -> void:
	_editing = true
	play_layer.visible = true
	for c in play_layer.get_children():
		c.visible = c == gas or c == brake
	layout_pedals()  # shows the steering control and mirror as set
	set_pedals(false, false)
	show_screen("pedals")


func end_pedal_edit() -> void:
	_editing = false
	_drag = {}
	for c in play_layer.get_children():
		c.visible = true
	_hint.modulate.a = 0.0
	layout_pedals()
	play_layer.visible = _play_on


# ---------------------------------------------------------------- fuel stop

func _build_refuel() -> void:
	var v := _screen("refuel", Color("#123a5c"), 640)
	_rf["eyebrow"] = _eyebrow("Fuel stop")
	v.add_child(_rf.eyebrow)
	_rf["name"] = _label("SUNSET FUEL", 64, LINE, display_font)
	_rf.name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_rf.name)
	# price board: every grade, with yours picked out
	var board := VBoxContainer.new()
	board.add_theme_constant_override("separation", 4)
	v.add_child(board)
	for g in Data.FUEL_ORDER:
		var row := _row(10)
		board.add_child(row)
		var nm := _label(String(Data.FUEL_GRADES[g].name).to_upper(), 28, LINE, display_font)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var tag := _label("", 16, AMBER, mono_font)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
		var pr := _label("$0.00 /L", 30, AMBER, mono_font)
		row.add_child(pr)
		_rf["row_" + g] = [row, tag, pr]
	# the tank, and the pump's running total
	var tr := _row(10)
	v.add_child(tr)
	tr.add_child(_label("TANK", 18, MUTED, mono_font))
	_rf["tank"] = _bar(_fill_amber, 16)
	_rf.tank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(_rf.tank)
	_rf["tank_l"] = _label("", 20, LINE, mono_font)
	_rf.tank_l.custom_minimum_size.x = 120
	_rf.tank_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(_rf.tank_l)
	var readout := PanelContainer.new()
	var rs := _flat(Color(0, 0, 0, 0.45), 10)
	rs.set_content_margin_all(12)
	readout.add_theme_stylebox_override("panel", rs)
	v.add_child(readout)
	_rf["pump"] = _label("0.0 L      $0.00", 40, Color("#7dff9a"), mono_font)
	_rf.pump.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.add_child(_rf.pump)
	_rf["funds"] = _wrap("", 20, MUTED)
	v.add_child(_rf.funds)
	_rf["note"] = _wrap("", 20, AMBER)
	v.add_child(_rf.note)
	var r1 := _row(12)
	v.add_child(r1)
	var hold := _button("HOLD TO PUMP", "light", "")
	hold.button_down.connect(func() -> void: act.emit("pump", "on"))
	hold.button_up.connect(func() -> void: act.emit("pump", "off"))
	r1.add_child(hold)
	_rf["fill"] = _button("FILL UP", "amber", "fill")
	r1.add_child(_rf.fill)
	_rf["pay"] = _button("PAY & GO", "light", "pay")
	v.add_child(_rf.pay)


func show_refuel(d: Dictionary) -> void:
	update_refuel(d)
	show_screen("refuel")


func update_refuel(d: Dictionary) -> void:
	_rf.name.text = String(d.name).to_upper()
	var p: Dictionary = d.prices
	for g in Data.FUEL_ORDER:
		var row: Array = _rf["row_" + g]
		var mine: bool = g == d.grade
		(row[0] as Control).modulate = Color(1, 1, 1, 1.0 if mine else 0.4)
		(row[1] as Label).text = "YOUR CAR" if mine else ""
		(row[2] as Label).text = "$%.2f /L" % float(p[g])
	_rf.tank.value = clampf(float(d.fuel) / float(d.tank), 0.0, 1.0)
	_rf.tank_l.text = "%.1f / %d L" % [d.fuel, int(d.tank)]
	_rf.pump.text = "%5.1f L      $%s" % [d.litres, "%.2f" % float(d.bill)]
	_rf.funds.text = "You have $%s: $%s in the bank and $%s earned this run so far. Filling the tank costs about $%s." % [
		Fmt.num(d.total), Fmt.num(d.bank), Fmt.num(d.run), Fmt.num(ceili(float(d.to_fill)))]
	var note: String = d.msg
	if note == "" and float(d.to_fill) > float(d.total) - float(d.bill):
		note = "Not enough money for a full tank: you can pump $%s more." % Fmt.num(maxi(0, int(float(d.total) - float(d.bill))))
	_rf.note.text = note
	_rf.fill.text = "PUMPING..." if d.pumping else "FILL UP"
	_rf.pay.text = ("PAY $%s & GO" % Fmt.num(ceili(float(d.bill) - 0.0001))) if float(d.bill) > 0.0 else "LEAVE"


# ---------------------------------------------------------------- replay editor

var replay_ui: Control
var _rp := {}


func _rp_button(text: String, arg: String, kind := "ghost") -> Button:
	var b := _button(text, kind, "rp", arg)
	b.add_theme_font_size_override("font_size", 23)
	b.custom_minimum_size.y = 62
	for k in ["normal", "hover", "pressed"]:
		var sb := (b.get_theme_stylebox(k) as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(k, sb)
	return b


func _build_replay() -> void:
	replay_ui = Control.new()
	replay_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	replay_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_ui.visible = false
	root.add_child(replay_ui)
	# top: title, clip time, done
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right"]:
		top.add_theme_constant_override("margin_" + side, 22)
	top.add_theme_constant_override("margin_top", 22)
	replay_ui.add_child(top)
	_rp["top"] = top
	var tr := _row(12)
	top.add_child(tr)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(tv)
	var title := _label("REPLAY", 46, LINE, display_font)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	tv.add_child(title)
	_rp["time"] = _label("0.0 s", 22, AMBER, mono_font)
	_rp.time.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	tv.add_child(_rp.time)
	var hide := _button("HIDE UI", "ghost", "rp", "hide")
	hide.add_theme_font_size_override("font_size", 24)
	hide.size_flags_horizontal = Control.SIZE_SHRINK_END
	hide.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tr.add_child(hide)
	var done := _button("DONE", "light", "rp", "done")
	done.add_theme_font_size_override("font_size", 28)
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tr.add_child(done)
	# bottom: timeline and controls
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var ps := _flat(Color(0.03, 0.04, 0.05, 0.72), 0)
	ps.set_content_margin_all(14)
	ps.content_margin_left = 20
	ps.content_margin_right = 20
	panel.add_theme_stylebox_override("panel", ps)
	replay_ui.add_child(panel)
	_rp["panel"] = panel
	_rp["panel_style"] = ps
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	panel.add_child(pv)
	var bar := ReplayBar.new()
	bar.scrub.connect(func(f: float) -> void: act.emit("rp_scrub", str(f)))
	pv.add_child(bar)
	_rp["bar"] = bar
	var r1 := _row(8)
	pv.add_child(r1)
	r1.add_child(_rp_button("<", "back"))
	_rp["play"] = _rp_button("PAUSE", "play", "amber")
	_rp.play.size_flags_stretch_ratio = 1.6
	r1.add_child(_rp.play)
	r1.add_child(_rp_button(">", "fwd"))
	_rp["speed"] = _rp_button("1x", "speed")
	r1.add_child(_rp.speed)
	_rp["cam"] = _rp_button("CHASE", "cam", "light")
	_rp.cam.size_flags_stretch_ratio = 2.0
	r1.add_child(_rp.cam)
	var r2 := _row(8)
	pv.add_child(r2)
	r2.add_child(_rp_button("SET IN", "in"))
	r2.add_child(_rp_button("SET OUT", "out"))
	r2.add_child(_rp_button("RESET CLIP", "clear"))

	var r3 := _row(8)
	pv.add_child(r3)
	var kadd := _rp_button("+ KEY", "key_add", "amber")
	kadd.size_flags_stretch_ratio = 1.3
	r3.add_child(kadd)
	r3.add_child(_rp_button("− KEY", "key_del"))
	r3.add_child(_rp_button("< KEY", "key_prev"))
	r3.add_child(_rp_button("KEY >", "key_next"))
	r3.add_child(_rp_button("CLEAR", "key_clear"))
	# with the controls hidden, only this faint button stays (a tap also works)
	var show := _button("SHOW UI", "ghost", "rp", "show")
	show.add_theme_font_size_override("font_size", 20)
	show.modulate.a = 0.45
	show.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	show.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	show.offset_left = -150
	show.offset_right = -18
	show.offset_top = 18
	show.size_flags_horizontal = Control.SIZE_SHRINK_END
	replay_ui.add_child(show)
	_rp["show"] = show
	_rp["help"] = _label("Drag the view to orbit the car  ·  clip %s", 18, MUTED, mono_font)
	_rp.help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rp.help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_rp.help)


func show_replay(on: bool) -> void:
	replay_ui.visible = on
	replay_ui_visible(true)
	if on:
		_rp.top.add_theme_constant_override("margin_top", _top_margin.get_theme_constant("margin_top"))
		(_rp.panel_style as StyleBoxFlat).content_margin_bottom = 14 + _bottom


## HIDE UI: the clip plays full screen until the next tap.
func replay_ui_visible(on: bool) -> void:
	for c in replay_ui.get_children():
		c.visible = on if c != _rp.show else not on
	if not on:
		(_rp.show as Control).offset_top = 18 + _top_margin.get_theme_constant("margin_top") - 18


## True if a touch at pos lands on the replay controls rather than the view.
func replay_ui_at(pos: Vector2) -> bool:
	for k in ["panel", "top", "show"]:
		var c: Control = _rp[k]
		if c.visible and c.get_global_rect().grow(8).has_point(pos):
			return true
	return false


func update_replay(d: Dictionary) -> void:
	(_rp.bar as ReplayBar).set_state(d.pos, d.a, d.b, d.len)
	(_rp.bar as ReplayBar).set_keys(d.keys)
	_rp.time.text = "%s  /  %s" % [d.time, d.clip]
	_rp.play.text = "PAUSE" if d.play else "PLAY"
	_rp.speed.text = d.speed
	_rp.cam.text = d.cam
	if d.nkeys == 0:
		_rp.help.text = "Drag to swing the camera, pinch to zoom, two fingers to pan. Then + KEY to keyframe the shot."
	else:
		_rp.help.text = "%d keyframe%s · move the playhead, set up the view and + KEY again · KEYFRAMES camera plays them" % [d.nkeys, "" if d.nkeys == 1 else "s"]


# ---------------------------------------------------------------- menu scrolling

var _scroll := {}            # the touch currently scrolling a menu
var _block_clicks_until := 0  # a scroll ends without pressing the button under the finger


## The scroll area under a touch on the visible menu: the garage list if the
## touch is inside it, otherwise the whole screen.
func _scroll_at(pos: Vector2) -> ScrollContainer:
	for k in screens:
		var scr: Control = screens[k]
		if scr.visible:
			if k == "garage" and (_garage.scroll as ScrollContainer).get_global_rect().has_point(pos):
				return _garage.scroll
			if scr.has_meta("sheet"):
				return null
			return scr.get_child(1) as ScrollContainer
	return null


func _over_slider(pos: Vector2) -> bool:
	for key in _set:
		var c: Variant = _set[key]
		if c is HSlider and (c as HSlider).is_visible_in_tree() and (c as HSlider).get_global_rect().grow_individual(0, 10, 0, 10).has_point(pos):
			return true
	return false


## Drag anywhere on a menu to scroll it, including over buttons. Drags that
## start on a slider move the slider instead.
func _menu_scroll(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			var sc := _scroll_at(e.position)
			if sc and not _over_slider(e.position):
				_scroll = {"i": e.index, "y": e.position.y, "start": e.position.y, "on": false, "sc": sc}
		elif not _scroll.is_empty() and e.index == _scroll.i:
			if _scroll.on:
				_block_clicks_until = Time.get_ticks_msec() + 150
			_scroll = {}
	elif event is InputEventScreenDrag and not _scroll.is_empty():
		var e := event as InputEventScreenDrag
		if e.index != _scroll.i:
			return
		if not _scroll.on and absf(e.position.y - _scroll.start) > 14.0:
			_scroll.on = true
		if _scroll.on:
			(_scroll.sc as ScrollContainer).scroll_vertical -= int(e.position.y - _scroll.y)
			get_viewport().set_input_as_handled()
		_scroll.y = e.position.y


## True just after a menu scroll, so the button under the finger is not pressed.
func clicks_blocked() -> bool:
	return not _scroll.is_empty() and _scroll.on or Time.get_ticks_msec() < _block_clicks_until


func _input(event: InputEvent) -> void:
	if not _editing:
		_menu_scroll(event)
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			for p in [gas, brake, wheel, arrows, mirror]:
				if (p as Control).visible and (p as Control).get_global_rect().has_point(e.position):
					_drag = {"p": p, "off": p.position - e.position, "i": e.index}
					if p is Pedal:
						p.pressed = true
					get_viewport().set_input_as_handled()
					return
		elif not _drag.is_empty() and e.index == _drag.i:
			if _drag.p is Pedal:
				_drag.p.pressed = false
			_store_pedal(_drag.p)
			_drag = {}
			act.emit("pedal_moved", "")
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and not _drag.is_empty():
		var e := event as InputEventScreenDrag
		if e.index == _drag.i:
			var vp := get_viewport().get_visible_rect().size
			var p: Control = _drag.p
			p.position = (e.position + _drag.off).clamp(Vector2(4, 4), vp - p.size - Vector2(4, 28))
			get_viewport().set_input_as_handled()
