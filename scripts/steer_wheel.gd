class_name SteerWheel
extends Control
## On-screen steering wheel. The game turns it from touch drags (multi-touch
## safe); this control only draws it and reports its hit area.

const MAX_ANGLE := 2.2  # about 126 degrees each way

var angle := 0.0:
	set(v):
		if v != angle:
			angle = v
			queue_redraw()
var held := false:
	set(v):
		if v != held:
			held = v
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func centre() -> Vector2:
	return global_position + size / 2.0


func radius() -> float:
	return minf(size.x, size.y) / 2.0


func hit(pos: Vector2) -> bool:
	return pos.distance_to(centre()) < radius() * 1.2


func _draw() -> void:
	var c := size / 2.0
	var r := radius() - 10.0
	if held:
		draw_circle(c, r + 12.0, Color(0.96, 0.71, 0.18, 0.18))
	draw_set_transform(c, angle, Vector2.ONE)
	var rim := Color("#1b1e22")
	var trim := Color("#555c64")
	draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(0, 0, 0, 0.35), 30.0, true)
	draw_arc(Vector2.ZERO, r, 0, TAU, 64, rim, 24.0, true)
	draw_arc(Vector2.ZERO, r + 10.0, 0, TAU, 64, trim, 3.0, true)
	draw_arc(Vector2.ZERO, r - 10.0, 0, TAU, 64, trim, 2.0, true)
	for a in [0.0, PI, PI * 0.5]:  # spokes: left, right, bottom
		var d := Vector2(cos(a), sin(a))
		draw_line(d * r * 0.28, d * (r - 8.0), trim, 16.0, true)
		draw_line(d * r * 0.28, d * (r - 8.0), rim, 10.0, true)
	draw_circle(Vector2.ZERO, r * 0.3, trim)
	draw_circle(Vector2.ZERO, r * 0.26, rim)
	draw_circle(Vector2.ZERO, r * 0.07, Color("#f5b52e"))
	draw_line(Vector2(0, -r - 11.0), Vector2(0, -r + 11.0), Color("#f5b52e"), 8.0, true)  # top-centre marker
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
