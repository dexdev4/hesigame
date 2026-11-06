class_name ArrowPad
extends Control
## Left and right steering buttons, drawn side by side.

var left_on := false:
	set(v):
		if v != left_on:
			left_on = v
			queue_redraw()
var right_on := false:
	set(v):
		if v != right_on:
			right_on = v
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## "left", "right" or "" for a touch at a global position.
func side_at(pos: Vector2) -> String:
	var r := get_global_rect().grow(14)
	if not r.has_point(pos):
		return ""
	return "left" if pos.x < r.get_center().x else "right"


func _draw() -> void:
	var half := Vector2(size.x / 2.0 - 8.0, size.y)
	for i in 2:
		var on: bool = left_on if i == 0 else right_on
		var rect := Rect2(Vector2(i * (size.x / 2.0 + 8.0) - (8.0 if i == 1 else 0.0) + (8.0 if i == 1 else 0.0), 0), half)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1b1e22") if not on else Color("#2c3238")
		sb.set_corner_radius_all(22)
		sb.border_color = Color("#f5b52e") if on else Color("#9aa1a8")
		sb.set_border_width_all(3)
		draw_style_box(sb, rect)
		var c := rect.get_center()
		var s := minf(rect.size.x, rect.size.y) * 0.22
		var dir := -1.0 if i == 0 else 1.0
		var pts := PackedVector2Array([c + Vector2(dir * s, 0), c + Vector2(-dir * s * 0.6, -s), c + Vector2(-dir * s * 0.6, s)])
		draw_colored_polygon(pts, Color("#f5b52e") if on else Color("#f3f5ef"))
