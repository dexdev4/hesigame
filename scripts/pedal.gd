class_name Pedal
extends Control
## Drawn accelerator or brake pedal. Touches are routed by the game script
## (multi-touch safe), this control only draws and reports its hit area.

@export_enum("gas", "brake") var kind := "gas"
var pressed := false:
	set(v):
		if v != pressed:
			pressed = v
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func hit_rect() -> Rect2:
	return get_global_rect().grow(18)


func _rounded(rect: Rect2, radius: int, fill: Color, border := Color.TRANSPARENT, bw := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	draw_style_box(sb, rect)


func _draw() -> void:
	var s := size
	var push := 8.0 if pressed else 0.0
	var glow := Color(0.47, 0.9, 0.55, 0.45) if kind == "gas" else Color(1.0, 0.3, 0.2, 0.5)
	var frame := Color("#555c64")
	var rubber := Color("#1b1e22")
	var groove := Color("#383e45")
	if kind == "gas":
		# tall accelerator pad with a floor hinge
		var pad := Rect2(s.x * 0.06, push, s.x * 0.88, s.y * 0.86 - push * 0.5)
		_rounded(Rect2(s.x * 0.41, s.y * 0.82, s.x * 0.18, s.y * 0.16), 6, Color("#24272b"))
		draw_circle(Vector2(s.x * 0.5, s.y * 0.95), s.x * 0.07, frame)
		if pressed:
			_rounded(pad.grow(10), 30, glow)
		_rounded(pad, 24, frame, Color("#9aa1a8"), 3)
		var inner := pad.grow(-s.x * 0.1)
		_rounded(inner, 16, rubber)
		var y := inner.position.y + 14.0
		while y < inner.end.y - 14.0:
			_rounded(Rect2(inner.position.x + 10, y, inner.size.x - 20, 6), 3, groove)
			y += 15.0
	else:
		# wide brake pad hanging from an arm
		_rounded(Rect2(s.x * 0.43, 0, s.x * 0.14, s.y * 0.26), 6, Color("#24272b"))
		var pad := Rect2(s.x * 0.03, s.y * 0.16 + push, s.x * 0.94, s.y * 0.8 - push * 0.5)
		if pressed:
			_rounded(pad.grow(10), 34, glow)
		_rounded(pad, 28, frame, Color("#9aa1a8"), 3)
		var inner := pad.grow(-s.y * 0.09)
		_rounded(inner, 18, rubber)
		var y := inner.position.y + 12.0
		while y < inner.end.y - 12.0:
			_rounded(Rect2(inner.position.x + 12, y, inner.size.x - 24, 6), 3, groove)
			y += 14.0
	var font := ThemeDB.fallback_font
	var label := "GAS" if kind == "gas" else "BRAKE"
	var fs := 18
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((s.x - tw) / 2.0, s.y + 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#b5c4ba"))
